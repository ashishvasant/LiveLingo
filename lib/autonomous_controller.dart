import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'autonomous_models.dart';
import 'models.dart';
import 'services/android_foreground_service.dart';
import 'services/android_live_audio_service.dart';
import 'services/audio_playback_service.dart';
import 'services/audio_playback_service_compat.dart';
import 'services/auth_service.dart';
import 'services/autonomous_session_service.dart';
import 'services/local_database.dart';

class AutonomousController extends ChangeNotifier {
  AutonomousController._({
    required LocalDatabase database,
    required AuthService authService,
    required AudioPlaybackService audioPlaybackService,
    required AutonomousSessionService sessionService,
    required SharedPreferences? preferences,
    required bool testing,
  }) : _database = database,
       _authService = authService,
       _audioPlaybackService = audioPlaybackService,
       _sessionService = sessionService,
       _preferences = preferences,
       _testing = testing,
       _audioRecorder = testing ? null : AudioRecorder() {
    _authService.addListener(_handleAuthChanged);
  }

  final LocalDatabase _database;
  final AuthService _authService;
  final AudioPlaybackService _audioPlaybackService;
  final AutonomousSessionService _sessionService;
  final SharedPreferences? _preferences;
  final bool _testing;
  final AudioRecorder? _audioRecorder;
  final Uuid _uuid = const Uuid();

  bool initialized = false;
  bool sessionStarting = false;
  bool sessionStopping = false;
  bool liveConnected = false;
  bool paused = false;
  bool micStreaming = false;
  String connectionStatus = 'Idle';
  String currentTask = '';
  String currentPlaceLanguage = '';
  AppSettings settings = AppSettings.defaults();
  List<AutonomousConversationMessage> messages =
      <AutonomousConversationMessage>[];
  AutonomousPromptState? activePrompt;
  AutonomousStatusState status = AutonomousStatusState.initial();
  List<DiagnosticEvent> diagnostics = <DiagnosticEvent>[];
  List<SessionSummary> sessionSummaries = <SessionSummary>[];
  List<Map<String, dynamic>> backendRecentEvents = <Map<String, dynamic>>[];
  int nativeMicChunkCount = 0;
  int uploadedAudioFrameCount = 0;
  int websocketMessageCount = 0;
  String lastSocketMessage = '';
  String? disconnectMessage;

  StreamSubscription<Uint8List>? _audioSubscription;
  final List<int> _pendingAudioBytes = <int>[];
  bool _assistantAudioPlaying = false;
  final List<int> _streamingAudioBytes = <int>[];
  Timer? _streamingPlaybackTimer;
  bool _streamingAudioPlaying = false;
  final Map<String, _AssistantAudioClip> _assistantAudioByMessageId =
      <String, _AssistantAudioClip>{};
  final List<_AssistantAudioClip> _pendingAssistantAudioClips =
      <_AssistantAudioClip>[];
  CameraController? _cameraController;
  Timer? _cameraCaptureTimer;
  bool _videoFrameInFlight = false;
  int _videoFrameSequence = 0;

  static Future<AutonomousController> bootstrap() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final LocalDatabase database = LocalDatabase();
    await database.open();
    final AuthService authService = await AuthService.bootstrap();
    final AutonomousController controller = AutonomousController._(
      database: database,
      authService: authService,
      audioPlaybackService: AudioPlaybackService(),
      sessionService: AutonomousSessionService(),
      preferences: preferences,
      testing: false,
    );
    await controller._load();
    return controller;
  }

  bool get authConfigured => _authService.configured;
  bool get authBusy => _authService.busy;
  String? get authError => _authService.error;
  AuthenticatedUser? get authenticatedUser => _authService.currentUser;
  bool get isAuthenticated => authenticatedUser != null;
  bool get _usesNativeAndroidAudio =>
      !_testing && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _load() async {
    settings = (await _database.loadSettings()).copyWith(
      interactionMode: InteractionMode.autonomous,
      muteReplies: false,
      updatedAt: DateTime.now().toUtc(),
    );
    diagnostics = await _database.listDiagnostics();
    sessionSummaries = await _database.listSessionSummaries();
    currentTask = settings.defaultAutonomousGoal;
    currentPlaceLanguage = settings.targetLanguage;
    if (_preferences != null &&
        !_preferences.containsKey('did_bootstrap_language_assist')) {
      await _preferences.setBool('did_bootstrap_language_assist', true);
    }
    if (!_testing) {
      await _database.saveSettings(settings);
    }
    initialized = true;
    notifyListeners();
  }

  void _handleAuthChanged() {
    if (!isAuthenticated && liveConnected) {
      unawaited(stopSession());
    }
    final AuthenticatedUser? user = authenticatedUser;
    if (user != null && !_testing) {
      settings = settings.copyWith(
        profileName: user.displayName,
        profileEmail: user.email,
        updatedAt: DateTime.now().toUtc(),
      );
      unawaited(_database.saveSettings(settings));
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    await _authService.signInWithGoogle();
  }

  Future<void> signOut() async {
    await stopSession();
    await _authService.signOut();
  }

  Future<void> saveSettings(AppSettings nextSettings) async {
    settings = nextSettings.copyWith(
      interactionMode: InteractionMode.autonomous,
      muteReplies: false,
      updatedAt: DateTime.now().toUtc(),
    );
    currentPlaceLanguage = settings.targetLanguage;
    currentTask = settings.defaultAutonomousGoal;
    if (!_testing) {
      await _database.saveSettings(settings);
    }
    if (liveConnected) {
      await _syncVideoContextStreaming();
    }
    notifyListeners();
  }

  Future<void> clearDiagnostics() async {
    diagnostics = <DiagnosticEvent>[];
    if (!_testing) {
      await _database.clearDiagnostics();
    }
    notifyListeners();
  }

  Future<void> startSession({
    required String task,
    required String placeLanguage,
  }) async {
    final String cleanedTask = task.trim();
    final String cleanedPlaceLanguage = placeLanguage.trim();
    if (cleanedTask.isEmpty || cleanedPlaceLanguage.isEmpty) {
      throw StateError('Task and place language are required.');
    }
    if (!isAuthenticated) {
      throw StateError('You must sign in before starting live mode.');
    }
    sessionStarting = true;
    connectionStatus = 'Connecting';
    currentTask = cleanedTask;
    currentPlaceLanguage = cleanedPlaceLanguage;
    activePrompt = null;
    disconnectMessage = null;
    if (connectionStatus != 'Disconnected') {
      messages = <AutonomousConversationMessage>[];
      _assistantAudioByMessageId.clear();
    }
    _pendingAssistantAudioClips.clear();
    _streamingAudioBytes.clear();
    _streamingPlaybackTimer?.cancel();
    _streamingPlaybackTimer = null;
    _streamingAudioPlaying = false;
    backendRecentEvents = <Map<String, dynamic>>[];
    nativeMicChunkCount = 0;
    uploadedAudioFrameCount = 0;
    websocketMessageCount = 0;
    lastSocketMessage = '';
    status = AutonomousStatusState.initial().copyWith(
      task: cleanedTask,
      placeLanguage: cleanedPlaceLanguage,
      summary: 'Connecting live autonomous session.',
    );
    notifyListeners();

    await saveSettings(
      settings.copyWith(
        targetLanguage: cleanedPlaceLanguage,
        defaultAutonomousGoal: cleanedTask,
      ),
    );

    final String idToken = await _authService.getFreshIdToken();
    await _sessionService.connect(
      settings: settings,
      idToken: idToken,
      onMessage: _handleMessage,
      onError: _handleSocketError,
    );
    final bool configSent = _sessionService.sendSessionConfig(
      settings: settings,
      task: cleanedTask,
      placeLanguage: cleanedPlaceLanguage,
    );
    await _recordDiagnostic('session_config_sent', <String, dynamic>{
      'sent': configSent,
      'task': cleanedTask,
      'place_language': cleanedPlaceLanguage,
    });
    await _startMicrophoneStream();
    if (!_testing) {
      await AndroidForegroundService.start(mode: 'autonomous', muted: false);
    }
    liveConnected = true;
    paused = false;
    sessionStarting = false;
    connectionStatus = 'Live';
    await _recordDiagnostic('autonomous_session_started', <String, dynamic>{
      'task': cleanedTask,
      'place_language': cleanedPlaceLanguage,
    });
    await _syncVideoContextStreaming();
    unawaited(refreshBackendDebugEvents());
    notifyListeners();
  }

  Future<void> pauseSession() async {
    if (!_sessionService.isConnected || paused) {
      return;
    }
    final String previousStatus = connectionStatus;
    connectionStatus = 'Pausing';
    notifyListeners();
    try {
      await _audioPlaybackService.stopActivePlayback();
      await _stopMicrophoneStream();
      _sessionService.sendTaskControl('pause');
      paused = true;
      connectionStatus = 'Paused';
      await _recordDiagnostic('autonomous_session_paused', <String, dynamic>{});
    } catch (error) {
      paused = false;
      connectionStatus = previousStatus;
      await _recordDiagnostic(
        'autonomous_session_pause_error',
        <String, dynamic>{'message': error.toString()},
      );
    }
    notifyListeners();
  }

  Future<void> resumeSession() async {
    if (!_sessionService.isConnected || !paused) {
      return;
    }
    connectionStatus = 'Resuming';
    notifyListeners();
    try {
      _sessionService.sendTaskControl('resume');
      await _startMicrophoneStream();
      paused = false;
      connectionStatus = 'Live';
      await _recordDiagnostic(
        'autonomous_session_resumed',
        <String, dynamic>{},
      );
    } catch (error) {
      paused = true;
      connectionStatus = 'Paused';
      await _recordDiagnostic(
        'autonomous_session_resume_error',
        <String, dynamic>{'message': error.toString()},
      );
    }
    notifyListeners();
  }

  Future<void> stopSession() async {
    if (sessionStopping) {
      return;
    }
    sessionStopping = true;
    try {
      if (_sessionService.isConnected) {
        _sessionService.sendTaskControl('stop');
      }
      await _audioPlaybackService.stopActivePlayback();
      await _stopMicrophoneStream();
      await _stopVideoContextStreaming();
      await _sessionService.disconnect();
      if (!_testing) {
        await AndroidForegroundService.stop();
      }
      if (liveConnected && !_testing) {
        final SessionSummary summary = SessionSummary(
          id: _uuid.v4(),
          createdAt: DateTime.now().toUtc(),
          interactionMode: 'autonomous',
          goal: currentTask,
          contextSummary: messages.isNotEmpty
              ? messages.last.translatedText
              : status.summary,
          targetLanguage: currentPlaceLanguage,
          outcome: status.status,
        );
        await _database.insertSessionSummary(summary);
        sessionSummaries = await _database.listSessionSummaries();
      }
    } finally {
      _pendingAssistantAudioClips.clear();
      _streamingAudioBytes.clear();
      _streamingPlaybackTimer?.cancel();
      _streamingPlaybackTimer = null;
      _streamingAudioPlaying = false;
      liveConnected = false;
      paused = false;
      micStreaming = false;
      connectionStatus = 'Stopped';
      disconnectMessage = null;
      activePrompt = null;
      sessionStopping = false;
      notifyListeners();
    }
  }

  Future<void> submitUserResponse(
    String text, {
    String? selectedOption,
    String? selectedOptionLabel,
  }) async {
    final String cleaned = text.trim();
    if (cleaned.isEmpty || !_sessionService.isConnected) {
      return;
    }
    final AutonomousPromptState? prompt = activePrompt;
    if (prompt != null && prompt.toolCallId.isNotEmpty) {
      _sessionService.sendToolResponse(
        toolCallId: prompt.toolCallId,
        responseText: cleaned,
        selectedOption: selectedOption,
        selectedOptionLabel: selectedOptionLabel,
      );
      activePrompt = null;
    } else {
      _sessionService.sendUserTextResponse(cleaned);
    }
    notifyListeners();
  }

  Future<void> _handleSocketError(Object error) async {
    liveConnected = false;
    paused = false;
    connectionStatus = 'Disconnected';
    disconnectMessage = error.toString();
    activePrompt = null;
    _pendingAssistantAudioClips.clear();
    await _stopMicrophoneStream();
    await _stopVideoContextStreaming();
    await _recordDiagnostic('socket_error', <String, dynamic>{
      'message': error.toString(),
    });
    unawaited(refreshBackendDebugEvents());
    notifyListeners();
  }

  Future<void> _handleMessage(Map<String, dynamic> payload) async {
    final String type = payload['type'] as String? ?? '';
    websocketMessageCount += 1;
    lastSocketMessage = type;
    switch (type) {
      case 'session_ready':
        connectionStatus = 'Live';
        disconnectMessage = null;
        break;
      case 'autonomous_status':
        status = AutonomousStatusState.fromMap(
          payload,
        ).copyWith(task: currentTask, placeLanguage: currentPlaceLanguage);
        paused = status.status == 'paused';
        connectionStatus = paused ? 'Paused' : 'Live';
        if (status.status == 'active') {
          disconnectMessage = null;
        }
        break;
      case 'conversation_message':
        final AutonomousConversationMessage message =
            AutonomousConversationMessage.fromMap(payload);
        messages = _upsertConversationMessage(message);
        _attachPendingAssistantAudio(message);
        break;
      case 'autonomous_prompt':
        activePrompt = AutonomousPromptState.fromMap(payload);
        break;
      case 'autonomous_prompt_translation':
        final AutonomousPromptState translatedPrompt =
            AutonomousPromptState.fromMap(payload);
        final AutonomousPromptState? currentPrompt = activePrompt;
        if (currentPrompt != null &&
            currentPrompt.toolCallId.isNotEmpty &&
            currentPrompt.toolCallId == translatedPrompt.toolCallId) {
          activePrompt = currentPrompt.copyWith(
            question: translatedPrompt.question,
            options: translatedPrompt.options,
            allowFreeText: translatedPrompt.allowFreeText,
            context: translatedPrompt.context,
          );
        }
        break;
      case 'assistant_audio_chunk':
        final String chunkBase64 = payload['audio_base64'] as String? ?? '';
        if (chunkBase64.isNotEmpty && !paused) {
          final Uint8List pcmBytes = base64Decode(chunkBase64);
          _streamingAudioBytes.addAll(pcmBytes);
          // Start playback after accumulating ~0.3s of audio (24kHz, 16-bit mono = 48000 bytes/s)
          if (!_streamingAudioPlaying && _streamingAudioBytes.length >= 14400) {
            _triggerStreamingPlayback();
          }
          // Fallback timer: if chunks arrive slowly, play after 200ms
          _streamingPlaybackTimer?.cancel();
          if (!_streamingAudioPlaying) {
            _streamingPlaybackTimer = Timer(
              const Duration(milliseconds: 200),
              _triggerStreamingPlayback,
            );
          }
        }
        break;
      case 'assistant_audio_end':
        _streamingPlaybackTimer?.cancel();
        _streamingPlaybackTimer = null;
        // If streaming playback hasn't started yet, play whatever we have
        if (!_streamingAudioPlaying && _streamingAudioBytes.isNotEmpty) {
          _triggerStreamingPlayback();
        }
        // Don't clear _streamingAudioBytes here; let playback finish, then clear
        break;
      case 'assistant_audio':
        final String audioBase64 = payload['audio_base64'] as String? ?? '';
        final String mimeType = payload['mime_type'] as String? ?? 'audio/wav';
        final String linkedMessageId =
            payload['for_message_id'] as String? ?? '';
        final bool isReplay = payload['is_replay'] as bool? ?? false;
        if (audioBase64.isNotEmpty) {
          final _AssistantAudioClip clip = _AssistantAudioClip(
            audioBase64: audioBase64,
            mimeType: mimeType,
          );
          final String fallbackMessageId = _latestReplayTargetMessageId() ?? '';
          final String targetMessageId = linkedMessageId.trim().isNotEmpty
              ? linkedMessageId.trim()
              : fallbackMessageId;
          if (targetMessageId.isNotEmpty) {
            _storeAssistantAudioClip(targetMessageId, clip);
          } else {
            _pendingAssistantAudioClips.add(clip);
            if (_pendingAssistantAudioClips.length > 24) {
              _pendingAssistantAudioClips.removeRange(
                0,
                _pendingAssistantAudioClips.length - 24,
              );
            }
          }
        }
        // Only auto-play if NOT a replay-only message (streaming handled by assistant_audio_chunk)
        if (audioBase64.isNotEmpty && !paused && !isReplay) {
          unawaited(
            _playAssistantAudio(
              audioBase64: audioBase64,
              mimeType: mimeType,
              messageId: payload['message_id'] as String? ?? _uuid.v4(),
            ),
          );
        }
        break;
      case 'live_warning':
        await _recordDiagnostic('live_warning', <String, dynamic>{
          'message': payload['message'] as String? ?? '',
        });
        final String warningText = payload['message'] as String? ?? '';
        if (warningText.isNotEmpty) {
          messages = _upsertConversationMessage(
            AutonomousConversationMessage(
              id: _uuid.v4(),
              role: 'system_event',
              translatedText: warningText,
              originalText: warningText,
              sourceLanguage: 'system',
              timestamp: DateTime.now().toUtc(),
            ),
          );
        }
        break;
    }
    if (websocketMessageCount == 1 || websocketMessageCount % 10 == 0) {
      await _recordDiagnostic('websocket_message_progress', <String, dynamic>{
        'count': websocketMessageCount,
        'last_type': type,
      });
    }
    notifyListeners();
  }

  Future<void> refreshBackendDebugEvents() async {
    if (!isAuthenticated || _testing) {
      return;
    }
    try {
      final String idToken = await _authService.getFreshIdToken();
      final HttpClient client = HttpClient();
      try {
        final Uri uri = Uri.parse(
          '${settings.backendUrl.trim().replaceAll(RegExp(r'/$'), '')}/v1/session/debug/recent?limit=30',
        );
        final HttpClientRequest request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
        final HttpClientResponse response = await request.close();
        final String body = await utf8.decodeStream(response);
        if (response.statusCode >= 400) {
          await _recordDiagnostic(
            'backend_debug_fetch_failed',
            <String, dynamic>{'status': response.statusCode, 'body': body},
          );
          return;
        }
        final Map<String, dynamic> decoded =
            jsonDecode(body) as Map<String, dynamic>;
        final List<dynamic> items =
            decoded['items'] as List<dynamic>? ?? <dynamic>[];
        backendRecentEvents = items
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (Map<dynamic, dynamic> item) => item.map(
                (dynamic key, dynamic value) => MapEntry(key.toString(), value),
              ),
            )
            .toList();
        await _recordDiagnostic('backend_debug_fetched', <String, dynamic>{
          'count': backendRecentEvents.length,
        });
        notifyListeners();
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      await _recordDiagnostic('backend_debug_fetch_error', <String, dynamic>{
        'message': error.toString(),
      });
    }
  }

  Future<void> _recordDiagnostic(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final DiagnosticEvent event = DiagnosticEvent(
      id: _uuid.v4(),
      createdAt: DateTime.now().toUtc(),
      type: type,
      payload: payload,
    );
    diagnostics = <DiagnosticEvent>[event, ...diagnostics].take(100).toList();
    if (!_testing) {
      await _database.insertDiagnostic(event);
    }
  }

  void _triggerStreamingPlayback() {
    if (_streamingAudioPlaying || _streamingAudioBytes.isEmpty) return;
    _streamingAudioPlaying = true;
    _streamingPlaybackTimer?.cancel();
    _streamingPlaybackTimer = null;
    final Uint8List pcmBytes = Uint8List.fromList(_streamingAudioBytes);
    _streamingAudioBytes.clear();
    unawaited(_playStreamingAudio(pcmBytes));
  }

  Future<void> _playStreamingAudio(Uint8List pcmBytes) async {
    try {
      // Stop any file-based playback that might be running
      if (_assistantAudioPlaying) {
        await _audioPlaybackService.stopActivePlayback();
        _assistantAudioPlaying = false;
      }
      await _audioPlaybackService.playPcmBytes(pcmBytes);
      // If more bytes accumulated while we were playing, play them too
      if (_streamingAudioBytes.isNotEmpty) {
        final Uint8List nextChunk = Uint8List.fromList(_streamingAudioBytes);
        _streamingAudioBytes.clear();
        await _audioPlaybackService.playPcmBytes(nextChunk);
      }
    } catch (error) {
      await _recordDiagnostic(
        'streaming_audio_playback_error',
        <String, dynamic>{'message': error.toString()},
      );
    } finally {
      _streamingAudioPlaying = false;
    }
  }

  Future<void> _playAssistantAudio({
    required String audioBase64,
    required String mimeType,
    required String messageId,
  }) async {
    if (_assistantAudioPlaying) {
      await _audioPlaybackService.stopActivePlayback();
    }
    _assistantAudioPlaying = true;
    try {
      await _recordDiagnostic(
        'assistant_audio_playback_started',
        <String, dynamic>{'message_id': messageId, 'mime_type': mimeType},
      );
      await _audioPlaybackService.playBase64Audio(
        audioBase64,
        mimeType,
        messageId,
      );
      await _recordDiagnostic(
        'assistant_audio_playback_completed',
        <String, dynamic>{'message_id': messageId},
      );
    } catch (error) {
      await _recordDiagnostic(
        'assistant_audio_playback_error',
        <String, dynamic>{'message_id': messageId, 'message': error.toString()},
      );
    } finally {
      _assistantAudioPlaying = false;
    }
  }

  Future<void> _startMicrophoneStream() async {
    if (_testing || !settings.audioInputEnabled || paused) {
      return;
    }
    if (micStreaming) {
      return;
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (_usesNativeAndroidAudio) {
      _audioSubscription = AndroidLiveAudioService.pcmStream().listen(
        _queueAudioChunk,
        onError: (Object error, StackTrace stackTrace) async {
          await _recordDiagnostic(
            'android_audio_stream_error',
            <String, dynamic>{'message': error.toString()},
          );
        },
        cancelOnError: false,
      );
      await AndroidLiveAudioService.start();
    } else {
      final AudioRecorder? recorder = _audioRecorder;
      if (recorder == null) {
        return;
      }
      final bool hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        await _recordDiagnostic(
          'microphone_permission_denied',
          <String, dynamic>{'granted': false},
        );
        return;
      }
      final Stream<Uint8List> audioStream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioSubscription = audioStream.listen(_queueAudioChunk);
    }
    micStreaming = true;
    await _recordDiagnostic('microphone_stream_started', <String, dynamic>{
      'source': _usesNativeAndroidAudio ? 'android_native' : 'record_plugin',
    });
    notifyListeners();
  }

  Future<void> _stopMicrophoneStream() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _pendingAudioBytes.clear();
    if (_usesNativeAndroidAudio) {
      await AndroidLiveAudioService.stop();
    } else if (!_testing && _audioRecorder != null) {
      await _audioRecorder.stop();
    }
    micStreaming = false;
    await _recordDiagnostic('microphone_stream_stopped', <String, dynamic>{});
  }

  Future<void> _syncVideoContextStreaming() async {
    if (_testing) {
      return;
    }
    if (!liveConnected ||
        !_sessionService.isConnected ||
        !settings.includeCameraContext) {
      await _stopVideoContextStreaming();
      return;
    }
    await _startVideoContextStreaming();
  }

  Future<void> _startVideoContextStreaming() async {
    if (_testing || !settings.includeCameraContext) {
      return;
    }
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _cameraCaptureTimer ??= Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(sendVideoContextFrame(manual: false)),
      );
      return;
    }
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _recordDiagnostic(
          'video_context_camera_unavailable',
          <String, dynamic>{'reason': 'no_cameras'},
        );
        return;
      }
      final CameraDescription selectedCamera = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      _cameraController = controller;
      _videoFrameSequence = 0;
      _cameraCaptureTimer?.cancel();
      _cameraCaptureTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(sendVideoContextFrame(manual: false)),
      );
      await _recordDiagnostic('video_context_camera_started', <String, dynamic>{
        'lens': selectedCamera.lensDirection.name,
      });
    } catch (error) {
      await _recordDiagnostic(
        'video_context_camera_start_error',
        <String, dynamic>{'message': error.toString()},
      );
      await _stopVideoContextStreaming();
    }
  }

  Future<void> _stopVideoContextStreaming() async {
    _cameraCaptureTimer?.cancel();
    _cameraCaptureTimer = null;
    _videoFrameInFlight = false;
    final CameraController? controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<bool> sendVideoContextFrame({bool manual = true}) async {
    if (_testing ||
        !_sessionService.isConnected ||
        !liveConnected ||
        paused ||
        !settings.includeCameraContext) {
      return false;
    }
    if (_videoFrameInFlight) {
      return false;
    }
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _startVideoContextStreaming();
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return false;
      }
    }
    _videoFrameInFlight = true;
    try {
      final XFile frame = await _cameraController!.takePicture();
      final List<int> bytes = await frame.readAsBytes();
      if (bytes.isEmpty) {
        return false;
      }
      _videoFrameSequence += 1;
      final bool sent = _sessionService.sendCameraFrame(
        base64Jpeg: base64Encode(bytes),
        frameSeq: _videoFrameSequence,
        caption: 'Live surroundings context frame',
      );
      if (manual || _videoFrameSequence == 1 || _videoFrameSequence % 5 == 0) {
        await _recordDiagnostic('video_context_frame', <String, dynamic>{
          'sent': sent,
          'frame_seq': _videoFrameSequence,
          'manual': manual,
          'bytes': bytes.length,
        });
      }
      return sent;
    } catch (error) {
      await _recordDiagnostic('video_context_frame_error', <String, dynamic>{
        'message': error.toString(),
        'manual': manual,
      });
      return false;
    } finally {
      _videoFrameInFlight = false;
    }
  }

  void _queueAudioChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }
    nativeMicChunkCount += 1;
    if (nativeMicChunkCount == 1 || nativeMicChunkCount % 50 == 0) {
      unawaited(
        _recordDiagnostic('native_mic_chunk_progress', <String, dynamic>{
          'native_chunks': nativeMicChunkCount,
          'connected': _sessionService.isConnected,
          'paused': paused,
          'chunk_size': chunk.length,
        }),
      );
      notifyListeners();
    }
    if (!_sessionService.isConnected || paused) {
      return;
    }
    _pendingAudioBytes.addAll(chunk);
    while (_pendingAudioBytes.length >= 1600) {
      final Uint8List frame = Uint8List.fromList(
        _pendingAudioBytes.sublist(0, 1600),
      );
      _pendingAudioBytes.removeRange(0, 1600);
      final bool sent = _sessionService.sendAudioChunk(frame);
      if (sent) {
        uploadedAudioFrameCount += 1;
        if (uploadedAudioFrameCount == 1 || uploadedAudioFrameCount % 50 == 0) {
          unawaited(
            _recordDiagnostic(
              'websocket_audio_upload_progress',
              <String, dynamic>{
                'uploaded_frames': uploadedAudioFrameCount,
                'native_chunks': nativeMicChunkCount,
                'pending_bytes': _pendingAudioBytes.length,
              },
            ),
          );
          notifyListeners();
        }
      } else {
        unawaited(
          _recordDiagnostic('websocket_audio_upload_failed', <String, dynamic>{
            'native_chunks': nativeMicChunkCount,
            'uploaded_frames': uploadedAudioFrameCount,
          }),
        );
      }
    }
  }

  List<AutonomousConversationMessage> _upsertConversationMessage(
    AutonomousConversationMessage message,
  ) {
    final List<AutonomousConversationMessage> updated =
        <AutonomousConversationMessage>[...messages];
    final int existingIndex = updated.indexWhere(
      (AutonomousConversationMessage item) => item.id == message.id,
    );
    if (existingIndex >= 0) {
      updated[existingIndex] = message;
      return updated.take(80).toList();
    }
    return <AutonomousConversationMessage>[
      message,
      ...updated,
    ].take(80).toList();
  }

  bool canReplayMessageAudio(String messageId) {
    return _assistantAudioByMessageId.containsKey(messageId);
  }

  Future<void> replayMessageAudio(String messageId) async {
    final _AssistantAudioClip? clip = _assistantAudioByMessageId[messageId];
    if (clip == null) {
      return;
    }
    await _playAssistantAudio(
      audioBase64: clip.audioBase64,
      mimeType: clip.mimeType,
      messageId: 'replay-$messageId',
    );
  }

  String? _latestReplayTargetMessageId() {
    const Set<String> replayableRoles = <String>{
      'assistant_translation',
      'assistant_raw',
      'assistant',
      'assistant_output_text',
    };
    for (final AutonomousConversationMessage message in messages) {
      if (replayableRoles.contains(message.role)) {
        return message.id;
      }
    }
    return null;
  }

  void _storeAssistantAudioClip(String messageId, _AssistantAudioClip clip) {
    _assistantAudioByMessageId[messageId] = clip;
    if (_assistantAudioByMessageId.length > 160) {
      final String oldestKey = _assistantAudioByMessageId.keys.first;
      _assistantAudioByMessageId.remove(oldestKey);
    }
  }

  void _attachPendingAssistantAudio(AutonomousConversationMessage message) {
    if (_pendingAssistantAudioClips.isEmpty ||
        !_isReplayableRole(message.role) ||
        _assistantAudioByMessageId.containsKey(message.id)) {
      return;
    }
    final _AssistantAudioClip clip = _pendingAssistantAudioClips.removeAt(0);
    _storeAssistantAudioClip(message.id, clip);
  }

  bool _isReplayableRole(String role) {
    return switch (role) {
      'assistant_translation' ||
      'assistant_raw' ||
      'assistant_output_text' ||
      'assistant' => true,
      _ => false,
    };
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    unawaited(stopSession());
    if (!_testing) {
      unawaited(_audioPlaybackService.dispose());
    }
    super.dispose();
  }
}

class _AssistantAudioClip {
  const _AssistantAudioClip({
    required this.audioBase64,
    required this.mimeType,
  });

  final String audioBase64;
  final String mimeType;
}
