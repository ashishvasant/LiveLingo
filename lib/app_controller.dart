import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services/android_foreground_service.dart';
import 'services/android_live_audio_service.dart';
import 'services/audio_playback_service.dart';
import 'services/audio_playback_service_compat.dart';
import 'services/auth_service.dart';
import 'services/live_session_service.dart';
import 'services/local_database.dart';

class AppController extends ChangeNotifier {
  AppController._({
    required LocalDatabase database,
    required LiveSessionService liveSessionService,
    required AudioPlaybackService audioPlaybackService,
    required AuthService authService,
    required SharedPreferences? preferences,
    required bool testing,
  }) : _database = database,
       _liveSessionService = liveSessionService,
       _audioPlaybackService = audioPlaybackService,
       _authService = authService,
       _preferences = preferences,
       _testing = testing,
       _audioRecorder = testing ? null : AudioRecorder() {
    _authService.addListener(_handleAuthChanged);
  }

  final LocalDatabase _database;
  final LiveSessionService _liveSessionService;
  final AudioPlaybackService _audioPlaybackService;
  final AuthService _authService;
  final SharedPreferences? _preferences;
  final bool _testing;
  final AudioRecorder? _audioRecorder;
  final Uuid _uuid = const Uuid();

  bool initialized = false;
  bool isBusy = false;
  int selectedIndex = 0;
  AppSettings settings = AppSettings.defaults();
  List<HistoryEntry> history = <HistoryEntry>[];
  List<SessionSummary> sessionSummaries = <SessionSummary>[];
  List<DiagnosticEvent> diagnostics = <DiagnosticEvent>[];
  LiveLanguageState liveState = LiveLanguageState.initial(
    AppSettings.defaults(),
  );
  PhraseSuggestion? selectedSuggestion;
  CameraController? cameraController;

  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _cameraCaptureTimer;
  Timer? _nativeAudioRestartTimer;
  final List<int> _pendingAudioBytes = <int>[];

  static Future<AppController> bootstrap() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final LocalDatabase database = LocalDatabase();
    await database.open();
    final AuthService authService = await AuthService.bootstrap();
    final AppController controller = AppController._(
      database: database,
      liveSessionService: LiveSessionService(),
      audioPlaybackService: AudioPlaybackService(),
      authService: authService,
      preferences: preferences,
      testing: false,
    );
    await controller._load();
    return controller;
  }

  factory AppController.test({bool authenticated = false}) {
    return AppController._(
        database: LocalDatabase(),
        liveSessionService: LiveSessionService(),
        audioPlaybackService: AudioPlaybackService(),
        authService: AuthService.test(
          user: authenticated
              ? const AuthenticatedUser(
                  uid: 'test-user',
                  email: 'test@example.com',
                  displayName: 'Test User',
                  idToken: 'token',
                )
              : null,
        ),
        preferences: null,
        testing: true,
      )
      ..initialized = true
      ..settings = AppSettings.defaults()
      ..liveState = LiveLanguageState.initial(AppSettings.defaults());
  }

  bool get authConfigured => _authService.configured;
  bool get authBusy => _authService.busy;
  String? get authError => _authService.error;
  AuthenticatedUser? get authenticatedUser => _authService.currentUser;
  bool get isAuthenticated => authenticatedUser != null;
  bool get _usesNativeAndroidAudio =>
      !_testing && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _load() async {
    settings = await _database.loadSettings();
    if (settings.interactionMode != InteractionMode.autonomous ||
        settings.muteReplies ||
        !settings.audioInputEnabled) {
      settings = settings.copyWith(
        interactionMode: InteractionMode.autonomous,
        muteReplies: false,
        audioInputEnabled: true,
        updatedAt: DateTime.now().toUtc(),
      );
      if (!_testing) {
        await _database.saveSettings(settings);
      }
    }
    history = await _database.listHistory();
    diagnostics = await _database.listDiagnostics();
    sessionSummaries = await _database.listSessionSummaries();
    liveState = LiveLanguageState.initial(settings).copyWith(
      recentHistory: history,
      cameraEnabled: settings.includeCameraContext,
      currentGoal: settings.defaultAutonomousGoal,
      autonomousStatus: AutonomousStatus.initial(settings.defaultAutonomousGoal),
    );
    if (_preferences != null &&
        !_preferences.containsKey('did_bootstrap_language_assist')) {
      await _preferences.setBool('did_bootstrap_language_assist', true);
    }
    initialized = true;
    notifyListeners();
  }

  void _handleAuthChanged() {
    if (!isAuthenticated && liveState.liveConnected) {
      unawaited(stopLive());
    }
    final AuthenticatedUser? user = authenticatedUser;
    if (user != null && !_testing) {
      final AppSettings nextSettings = settings.copyWith(
        profileName: user.displayName,
        profileEmail: user.email,
        updatedAt: DateTime.now().toUtc(),
      );
      settings = nextSettings;
      unawaited(_database.saveSettings(nextSettings));
    }
    notifyListeners();
  }

  void selectTab(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    await _authService.signInWithGoogle();
  }

  Future<void> signOut() async {
    await stopLive();
    await _authService.signOut();
  }

  Future<void> saveSettings(AppSettings nextSettings) async {
    settings = nextSettings.copyWith(updatedAt: DateTime.now().toUtc());
    final bool desiredCameraEnabled = settings.includeCameraContext;
    if (!_testing) {
      await _database.saveSettings(settings);
      await _reloadCachedData();
    }
    liveState = liveState.copyWith(
      userLanguage: settings.userLanguage,
      targetLanguage: settings.targetLanguage,
      interactionMode: settings.interactionMode,
      muteReplies: settings.muteReplies,
      audioInputEnabled: settings.audioInputEnabled,
      cameraEnabled: _liveSessionService.isConnected
          ? liveState.cameraEnabled
          : desiredCameraEnabled,
      currentGoal: settings.defaultAutonomousGoal,
      autonomousStatus: AutonomousStatus.initial(settings.defaultAutonomousGoal),
    );
    if (_liveSessionService.isConnected &&
        liveState.cameraEnabled != desiredCameraEnabled) {
      await setCameraEnabled(desiredCameraEnabled);
    }
    if (_liveSessionService.isConnected && isAuthenticated) {
      _liveSessionService.sendSessionConfig(settings, liveState);
    }
    notifyListeners();
  }

  Future<void> _reloadCachedData() async {
    history = await _database.listHistory();
    diagnostics = await _database.listDiagnostics();
    sessionSummaries = await _database.listSessionSummaries();
    liveState = liveState.copyWith(recentHistory: history);
  }

  Future<void> clearDiagnostics() async {
    if (_testing) {
      diagnostics = <DiagnosticEvent>[];
      notifyListeners();
      return;
    }
    await _database.clearDiagnostics();
    diagnostics = <DiagnosticEvent>[];
    notifyListeners();
  }

  Future<void> setInteractionMode(InteractionMode mode) async {
    await _recordDiagnostic('interaction_mode_changed', <String, dynamic>{
      'mode': mode.wireValue,
    });
    await saveSettings(settings.copyWith(interactionMode: mode));
  }

  Future<void> setMuteReplies(bool muted) async {
    await _recordDiagnostic('mute_changed', <String, dynamic>{'muted': muted});
    await saveSettings(settings.copyWith(muteReplies: muted));
  }

  Future<void> setAudioInputEnabled(bool enabled) async {
    await _recordDiagnostic('audio_input_changed', <String, dynamic>{
      'enabled': enabled,
    });
    await saveSettings(settings.copyWith(audioInputEnabled: enabled));
    if (_liveSessionService.isConnected) {
      if (enabled) {
        await _startMicrophoneStream();
      } else {
        await _stopMicrophoneStream();
      }
    }
  }

  Future<void> updateAutonomousGoal(String goal) async {
    final String cleaned = goal.trim();
    await _recordDiagnostic('autonomous_goal_updated', <String, dynamic>{
      'goal': _previewText(cleaned),
    });
    liveState = liveState.copyWith(
      currentGoal: cleaned,
      autonomousStatus: AutonomousStatus.initial(cleaned),
    );
    notifyListeners();
    await saveSettings(settings.copyWith(defaultAutonomousGoal: cleaned));
  }

  Future<void> updateContextOverride(String text) async {
    final String cleaned = text.trim();
    await _recordDiagnostic('context_override_updated', <String, dynamic>{
      'text': _previewText(cleaned),
    });
    liveState = liveState.copyWith(contextOverride: cleaned);
    notifyListeners();
    if (_liveSessionService.isConnected) {
      _liveSessionService.sendContextOverride(cleaned);
    }
  }

  Future<void> setTargetLanguage(String language) async {
    final String cleaned = language.trim();
    if (cleaned.isEmpty) {
      return;
    }
    await _recordDiagnostic('target_language_set', <String, dynamic>{
      'language': cleaned,
    });
    await saveSettings(
      settings.copyWith(
        targetLanguage: cleaned,
        targetLanguageAutoInfer: false,
      ),
    );
    if (_liveSessionService.isConnected) {
      _liveSessionService.setTargetLanguage(cleaned);
    }
  }

  Future<void> initializeAutonomousHome() async {
    if (!isAuthenticated || isBusy) {
      return;
    }
    if (settings.interactionMode != InteractionMode.autonomous ||
        settings.muteReplies ||
        !settings.audioInputEnabled) {
      await saveSettings(
        settings.copyWith(
          interactionMode: InteractionMode.autonomous,
          muteReplies: false,
          audioInputEnabled: true,
        ),
      );
    }
    if (!_liveSessionService.isConnected) {
      await startLive(allowEmptyAutonomousGoal: true);
    }
    liveState = liveState.copyWith(
      awaitingGoalCapture: liveState.currentGoal.trim().isEmpty,
      awaitingLanguageCapture:
          liveState.currentGoal.trim().isNotEmpty &&
          (liveState.targetLanguage ?? '').trim().isEmpty,
      awaitingUserSpeechCapture: false,
    );
    notifyListeners();
  }

  Future<void> startGuideLive() async {
    if (liveState.interactionMode != InteractionMode.guide) {
      await setInteractionMode(InteractionMode.guide);
    }
    if (liveState.liveConnected) {
      return;
    }
    await startLive();
  }

  Future<void> startLive({bool allowEmptyAutonomousGoal = false}) async {
    if (!isAuthenticated || _liveSessionService.isConnected || isBusy) {
      return;
    }
    await _recordDiagnostic('start_live_requested', <String, dynamic>{
      'mode': liveState.interactionMode.wireValue,
      'muted': liveState.muteReplies,
      'camera_enabled': settings.includeCameraContext,
      'audio_input_enabled': settings.audioInputEnabled,
      'goal': _previewText(liveState.currentGoal),
    });
    if (!allowEmptyAutonomousGoal &&
        liveState.interactionMode == InteractionMode.autonomous &&
        liveState.currentGoal.trim().isEmpty) {
      await _recordDiagnostic(
        'missing_autonomous_goal',
        <String, dynamic>{'mode': liveState.interactionMode.wireValue},
      );
      notifyListeners();
      return;
    }
    isBusy = true;
    liveState = liveState.copyWith(
      connectionStatus: 'connecting',
      cameraEnabled: settings.includeCameraContext,
      heardMessages: const <HeardMessage>[],
      transcriptEvents: const <TranscriptEvent>[],
      autonomousConversation: const <ConversationMessage>[],
      clearAssistantReply: true,
      clearIntentAssist: true,
      clearQuickReply: true,
      clearAutonomousPrompt: true,
      awaitingGoalCapture: false,
      awaitingLanguageCapture: false,
      awaitingUserSpeechCapture: false,
      autonomousPaused: false,
      clearActiveQuickReplyMessageId: true,
    );
    notifyListeners();
    try {
      if (_testing) {
        liveState = liveState.copyWith(
          liveConnected: true,
          connectionStatus: 'connected',
          micStreaming: settings.audioInputEnabled,
        );
        await _recordDiagnostic('start_live_testing', <String, dynamic>{
          'connected': true,
        });
        return;
      }
      final String idToken = await _authService.getFreshIdToken();
      await _liveSessionService.connect(
        settings: settings,
        idToken: idToken,
        onMessage: _handleLiveMessage,
        onError: (Object error) async {
          await _recordDiagnostic(
            'socket_error',
            <String, dynamic>{'message': error.toString()},
          );
          liveState = liveState.copyWith(
            liveConnected: false,
            micStreaming: false,
            connectionStatus: 'disconnected',
            autonomousPaused: false,
            awaitingUserSpeechCapture: false,
          );
          notifyListeners();
        },
      );
      await _recordDiagnostic('live_socket_connected', <String, dynamic>{
        'backend_url': settings.backendUrl,
      });
      _liveSessionService.sendSessionConfig(settings, liveState);
      await _recordDiagnostic('session_config_sent', <String, dynamic>{
        'mode': liveState.interactionMode.wireValue,
        'muted': liveState.muteReplies,
        'target_language':
            liveState.targetLanguage ?? settings.targetLanguage,
      });
      if (settings.audioInputEnabled) {
        await _startMicrophoneStream();
      }
      if (liveState.cameraEnabled) {
        await setCameraEnabled(true);
      }
      if (!_testing) {
        await AndroidForegroundService.start(
          mode: liveState.interactionMode.label,
          muted: liveState.muteReplies,
        );
      }
    } catch (error) {
      await _recordDiagnostic(
        'start_live_failed',
        <String, dynamic>{'message': error.toString()},
      );
      liveState = liveState.copyWith(
        connectionStatus: 'error',
        liveConnected: false,
        micStreaming: false,
      );
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> stopLive() async {
    await _recordDiagnostic('stop_live_requested', <String, dynamic>{
      'connected': liveState.liveConnected,
    });
    final LiveLanguageState lastState = liveState;
    await _audioPlaybackService.stopActivePlayback();
    await _stopMicrophoneStream();
    await setCameraEnabled(false);
    await _liveSessionService.disconnect();
    if (!_testing) {
      await AndroidForegroundService.stop();
    }
    liveState = liveState.copyWith(
      liveConnected: false,
      micStreaming: false,
      connectionStatus: 'stopped',
      awaitingGoalCapture: false,
      awaitingLanguageCapture: false,
      awaitingUserSpeechCapture: false,
      autonomousPaused: false,
      clearActiveQuickReplyMessageId: true,
    );
    if (!_testing &&
        settings.saveLocalHistory &&
        (lastState.currentState != null || lastState.currentGoal.isNotEmpty)) {
      await _database.insertSessionSummary(
        SessionSummary(
          id: _uuid.v4(),
          createdAt: DateTime.now().toUtc(),
          interactionMode: lastState.interactionMode.wireValue,
          goal: lastState.currentGoal,
          contextSummary:
              lastState.currentState?.contextSummary ??
              lastState.autonomousStatus.summary,
          targetLanguage:
              lastState.currentState?.localLanguage ??
              lastState.targetLanguage ??
              settings.targetLanguage,
          outcome: lastState.autonomousStatus.status,
        ),
      );
      await _reloadCachedData();
    }
    notifyListeners();
  }

  Future<void> submitTextIntent(String text) async {
    final String cleaned = text.trim();
    if (cleaned.isEmpty ||
        !_liveSessionService.isConnected ||
        liveState.autonomousPaused) {
      return;
    }
    await _recordDiagnostic('user_text_sent', <String, dynamic>{
      'text': _previewText(cleaned),
    });
    if (liveState.interactionMode == InteractionMode.autonomous) {
      liveState = liveState.copyWith(
        clearAutonomousPrompt: true,
        awaitingUserSpeechCapture: false,
        autonomousConversation: _appendConversationMessage(
          ConversationMessage(
            id: _uuid.v4(),
            role: 'user',
            title: 'You',
            translatedText: cleaned,
            originalText: cleaned,
            language: liveState.userLanguage,
            timestamp: DateTime.now().toUtc(),
          ),
        ),
      );
      notifyListeners();
    }
    _liveSessionService.sendUserTextIntent(cleaned);
  }

  Future<void> startAutonomousWithDetails({
    required String goal,
    required String language,
  }) async {
    final String cleaned = goal.trim();
    final String cleanedLanguage = language.trim();
    if (cleaned.isEmpty || cleanedLanguage.isEmpty) {
      return;
    }
    if (liveState.interactionMode != InteractionMode.autonomous) {
      await setInteractionMode(InteractionMode.autonomous);
    }
    await saveSettings(
      settings.copyWith(
        interactionMode: InteractionMode.autonomous,
        muteReplies: false,
        audioInputEnabled: true,
      ),
    );
    await setTargetLanguage(cleanedLanguage);
    await updateAutonomousGoal(cleaned);
    liveState = liveState.copyWith(
      awaitingGoalCapture: false,
      awaitingLanguageCapture: false,
      awaitingUserSpeechCapture: false,
      clearAutonomousPrompt: true,
    );
    notifyListeners();
    if (!_liveSessionService.isConnected) {
      await startLive();
      return;
    }
    if (liveState.autonomousPaused) {
      await resumeAutonomous();
    }
    _liveSessionService.setTargetLanguage(cleanedLanguage);
    _liveSessionService.sendAutonomousGoal(cleaned);
    if (liveState.audioInputEnabled && !liveState.micStreaming) {
      await _startMicrophoneStream();
    }
  }

  Future<void> startAutonomousGoalCapture() async {
    if (liveState.interactionMode != InteractionMode.autonomous) {
      await setInteractionMode(InteractionMode.autonomous);
    }
    await saveSettings(
      settings.copyWith(
        interactionMode: InteractionMode.autonomous,
        muteReplies: false,
        audioInputEnabled: true,
      ),
    );
    liveState = liveState.copyWith(
      awaitingGoalCapture: true,
      awaitingLanguageCapture: false,
      awaitingUserSpeechCapture: false,
      clearAutonomousPrompt: true,
      clearActiveQuickReplyMessageId: true,
    );
    notifyListeners();
    if (!_liveSessionService.isConnected) {
      await startLive(allowEmptyAutonomousGoal: true);
    } else if (liveState.autonomousPaused) {
      await resumeAutonomous();
    }
    if (_liveSessionService.isConnected) {
      liveState = liveState.copyWith(awaitingGoalCapture: true);
      notifyListeners();
      _liveSessionService.startGoalCapture();
      await _recordDiagnostic(
        'goal_capture_started',
        <String, dynamic>{'mode': 'autonomous'},
      );
    }
  }

  Future<void> startAutonomousLanguageCapture() async {
    if (liveState.interactionMode != InteractionMode.autonomous) {
      await setInteractionMode(InteractionMode.autonomous);
    }
    await saveSettings(
      settings.copyWith(
        interactionMode: InteractionMode.autonomous,
        muteReplies: false,
        audioInputEnabled: true,
      ),
    );
    liveState = liveState.copyWith(
      awaitingGoalCapture: false,
      awaitingLanguageCapture: true,
      awaitingUserSpeechCapture: false,
      clearAutonomousPrompt: true,
    );
    notifyListeners();
    if (!_liveSessionService.isConnected) {
      await startLive(allowEmptyAutonomousGoal: true);
    } else if (liveState.autonomousPaused) {
      await resumeAutonomous();
    }
    if (_liveSessionService.isConnected) {
      liveState = liveState.copyWith(awaitingLanguageCapture: true);
      notifyListeners();
      _liveSessionService.startLanguageCapture();
      await _recordDiagnostic(
        'language_capture_started',
        <String, dynamic>{'mode': 'autonomous'},
      );
    }
  }

  Future<void> startAutonomousUserSpeechCapture() async {
    if (!_liveSessionService.isConnected || liveState.autonomousPaused) {
      return;
    }
    liveState = liveState.copyWith(
      awaitingUserSpeechCapture: true,
      clearAutonomousPrompt: true,
    );
    notifyListeners();
    _liveSessionService.startAutonomousUserSpeechCapture();
    await _recordDiagnostic(
      'autonomous_user_speech_capture_started',
      <String, dynamic>{'mode': 'autonomous'},
    );
  }

  Future<void> beginQuickSpeak(HeardMessage message) async {
    if (!_liveSessionService.isConnected) {
      return;
    }
    liveState = liveState.copyWith(
      activeQuickReplyMessageId: message.messageId,
      clearQuickReply: true,
    );
    notifyListeners();
    await _recordDiagnostic(
      'quick_speak_started',
      <String, dynamic>{
        'message_id': message.messageId,
        'language': message.sourceLanguage,
      },
    );
    _liveSessionService.beginQuickSpeak(
      sourceMessageId: message.messageId,
      language: message.sourceLanguage,
    );
  }

  Future<void> submitQuickReplyText({
    required HeardMessage message,
    required String text,
  }) async {
    final String cleaned = text.trim();
    if (cleaned.isEmpty || !_liveSessionService.isConnected) {
      return;
    }
    liveState = liveState.copyWith(
      activeQuickReplyMessageId: message.messageId,
      clearQuickReply: true,
    );
    notifyListeners();
    await _recordDiagnostic(
      'quick_reply_text_sent',
      <String, dynamic>{
        'message_id': message.messageId,
        'language': message.sourceLanguage,
        'text': _previewText(cleaned),
      },
    );
    _liveSessionService.submitQuickReplyText(
      sourceMessageId: message.messageId,
      text: cleaned,
      language: message.sourceLanguage,
    );
  }

  Future<void> clearQuickReply() async {
    liveState = liveState.copyWith(
      clearQuickReply: true,
      clearActiveQuickReplyMessageId: true,
    );
    notifyListeners();
  }

  Future<void> pauseAutonomous() async {
    if (!_liveSessionService.isConnected || liveState.autonomousPaused) {
      return;
    }
    await _audioPlaybackService.stopActivePlayback();
    await _stopMicrophoneStream();
    _liveSessionService.sendTaskControl('pause');
    liveState = liveState.copyWith(
      autonomousPaused: true,
      awaitingUserSpeechCapture: false,
      connectionStatus: 'paused',
      autonomousConversation: _appendConversationMessage(
        ConversationMessage(
          id: _uuid.v4(),
          role: 'system',
          title: 'Paused',
          translatedText: 'Autonomous mode is paused.',
          originalText: '',
          language: liveState.userLanguage,
          timestamp: DateTime.now().toUtc(),
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> resumeAutonomous() async {
    if (!_liveSessionService.isConnected || !liveState.autonomousPaused) {
      return;
    }
    _liveSessionService.sendTaskControl('resume');
    if (liveState.audioInputEnabled) {
      await _startMicrophoneStream();
    }
    liveState = liveState.copyWith(
      autonomousPaused: false,
      connectionStatus: 'listening',
      autonomousConversation: _appendConversationMessage(
        ConversationMessage(
          id: _uuid.v4(),
          role: 'system',
          title: 'Resumed',
          translatedText: 'Autonomous mode resumed.',
          originalText: '',
          language: liveState.userLanguage,
          timestamp: DateTime.now().toUtc(),
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> stopAutonomous() async {
    if (_liveSessionService.isConnected) {
      _liveSessionService.sendTaskControl('stop');
    }
  }

  Future<void> selectSuggestion(PhraseSuggestion suggestion) async {
    selectedSuggestion = suggestion;
    if (!_testing && settings.saveLocalHistory) {
      final HistoryEntry entry = HistoryEntry(
        id: _uuid.v4(),
        createdAt: DateTime.now().toUtc(),
        source: 'predicted',
        userLanguage: settings.userLanguage,
        targetLanguage:
            liveState.currentState?.localLanguage ?? settings.targetLanguage,
        suggestionId: suggestion.id,
        displayText: suggestion.displayText,
        targetText: suggestion.targetText,
        transliteration: suggestion.transliteration,
        pronunciationHint: suggestion.pronunciationHint,
        scenario: liveState.currentState?.scenario ?? '',
        locationGuess: liveState.currentState?.locationGuess ?? '',
        audioPlayed: false,
      );
      await _database.insertHistory(entry);
      await _reloadCachedData();
    }
    notifyListeners();
  }

  Future<void> playSuggestionAudio(PhraseSuggestion suggestion) async {
    if (liveState.muteReplies) {
      await _recordDiagnostic(
        'audio_request_blocked_by_mute',
        <String, dynamic>{'suggestion_id': suggestion.id},
      );
      return;
    }
    if (_liveSessionService.isConnected) {
      _liveSessionService.requestPhraseAudio(suggestion);
    }
  }

  Future<void> playReplySuggestionAudio({
    required HeardMessage message,
    required ReplySuggestionCard suggestion,
  }) async {
    if (liveState.muteReplies) {
      await _recordDiagnostic(
        'reply_audio_blocked_by_mute',
        <String, dynamic>{'suggestion_id': suggestion.id},
      );
      return;
    }
    if (!_liveSessionService.isConnected) {
      return;
    }
    await _recordDiagnostic(
      'reply_audio_requested',
      <String, dynamic>{
        'suggestion_id': suggestion.id,
        'source_language': message.sourceLanguage,
        'text': _previewText(suggestion.targetText),
      },
    );
    _liveSessionService.requestReplySuggestionAudio(
      suggestionId: suggestion.id,
      text: suggestion.targetText,
      language: message.sourceLanguage,
    );
  }

  Future<void> replayQuickReplyAudio(QuickReplyResult result) async {
    if (liveState.muteReplies) {
      return;
    }
    if ((result.audioBase64 ?? '').isNotEmpty && !_testing) {
      await _playReplyAudio(
        result.audioBase64!,
        result.mimeType ?? 'audio/mpeg',
        result.requestId,
      );
      return;
    }
    if (_liveSessionService.isConnected) {
      _liveSessionService.requestReplySuggestionAudio(
        suggestionId: result.requestId,
        text: result.targetText,
        language: result.targetLanguage,
      );
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    await _recordDiagnostic('camera_toggled', <String, dynamic>{
      'enabled': enabled,
    });
    if (_testing) {
      liveState = liveState.copyWith(cameraEnabled: enabled);
      notifyListeners();
      return;
    }
    if (!enabled) {
      _cameraCaptureTimer?.cancel();
      _cameraCaptureTimer = null;
      await cameraController?.dispose();
      cameraController = null;
      liveState = liveState.copyWith(cameraEnabled: false);
      notifyListeners();
      return;
    }

    try {
      final List<CameraDescription> cameras = await availableCameras();
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
      cameraController = controller;
      liveState = liveState.copyWith(cameraEnabled: true);
      notifyListeners();
      _cameraCaptureTimer?.cancel();
      _cameraCaptureTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) {},
      );
    } catch (error) {
      await _recordDiagnostic(
        'camera_init_failed',
        <String, dynamic>{'message': error.toString()},
      );
      liveState = liveState.copyWith(cameraEnabled: false);
      notifyListeners();
    }
  }

  Future<void> _startMicrophoneStream() async {
    if (_testing || _audioRecorder == null || !liveState.audioInputEnabled) {
      return;
    }
    if (liveState.micStreaming) {
      return;
    }
    final bool hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      await _recordDiagnostic(
        'microphone_permission_denied',
        <String, dynamic>{'granted': false},
      );
      return;
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (_usesNativeAndroidAudio) {
      _audioSubscription = AndroidLiveAudioService.pcmStream().listen(
        (Uint8List chunk) {
          _queueAudioChunk(chunk);
        },
        onError: (Object error, StackTrace stackTrace) async {
          await _recordDiagnostic(
            'android_audio_stream_error',
            <String, dynamic>{'message': error.toString()},
          );
          await _scheduleNativeAudioRestart();
        },
        cancelOnError: false,
      );
      await AndroidLiveAudioService.start();
    } else {
      final Stream<Uint8List> audioStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioSubscription = audioStream.listen((Uint8List chunk) {
        _queueAudioChunk(chunk);
      });
    }
    liveState = liveState.copyWith(micStreaming: true);
    await _recordDiagnostic(
      'microphone_stream_started',
      <String, dynamic>{
        'sample_rate': 16000,
        'channels': 1,
        'source': _usesNativeAndroidAudio ? 'android_native' : 'record_plugin',
      },
    );
    notifyListeners();
  }

  Future<void> _stopMicrophoneStream() async {
    _nativeAudioRestartTimer?.cancel();
    _nativeAudioRestartTimer = null;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _pendingAudioBytes.clear();
    if (_usesNativeAndroidAudio) {
      await AndroidLiveAudioService.stop();
    } else if (!_testing && _audioRecorder != null) {
      await _audioRecorder.stop();
    }
    liveState = liveState.copyWith(micStreaming: false);
    await _recordDiagnostic(
      'microphone_stream_stopped',
      <String, dynamic>{'connected': _liveSessionService.isConnected},
    );
  }

  Future<void> _playReplyAudio(
    String base64Audio,
    String mimeType,
    String requestId,
  ) async {
    if (_testing || base64Audio.isEmpty) {
      return;
    }
    final bool shouldResumeMic =
        _liveSessionService.isConnected &&
        liveState.micStreaming &&
        settings.audioInputEnabled;
    if (shouldResumeMic) {
      await _recordDiagnostic(
        'reply_audio_playback_started',
        <String, dynamic>{'request_id': requestId, 'holding_mic': true},
      );
      await _stopMicrophoneStream();
    }
    try {
      await _audioPlaybackService.playBase64Audio(
        base64Audio,
        mimeType,
        requestId,
      );
    } finally {
      if (shouldResumeMic &&
          _liveSessionService.isConnected &&
          settings.audioInputEnabled &&
          !liveState.autonomousPaused) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        await _startMicrophoneStream();
      }
    }
  }

  Future<void> _handleLiveMessage(Map<String, dynamic> payload) async {
    final String type = payload['type'] as String? ?? 'unknown';
    await _recordDiagnostic(
      'live_event_$type',
      _summarizeLivePayload(type, payload),
    );
    switch (type) {
      case 'session_ready':
        liveState = liveState.copyWith(
          liveConnected: true,
          connectionStatus: 'connected',
          autonomousPaused: false,
        );
        break;
      case 'user_message':
        final String translatedText = payload['translated_text'] as String? ?? '';
        final String originalText = payload['original_text'] as String? ?? '';
        liveState = liveState.copyWith(
          awaitingUserSpeechCapture: false,
          autonomousConversation: _appendConversationMessage(
            ConversationMessage(
              id: payload['message_id'] as String? ?? _uuid.v4(),
              role: 'user',
              title: 'You',
              translatedText: translatedText.isNotEmpty
                  ? translatedText
                  : originalText,
              originalText: originalText,
              language: payload['source_language'] as String? ?? liveState.userLanguage,
              timestamp:
                  DateTime.tryParse(payload['timestamp'] as String? ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
            ),
          ),
        );
        break;
      case 'heard_message':
        if (liveState.autonomousPaused) {
          break;
        }
        final HeardMessage heardMessage = HeardMessage.fromMap(payload);
        liveState = liveState.copyWith(
          heardMessages: _appendHeardMessage(heardMessage),
          autonomousConversation:
              liveState.interactionMode == InteractionMode.autonomous
              ? _appendConversationMessage(
                  ConversationMessage(
                    id: heardMessage.messageId,
                    role: 'other',
                    title: heardMessage.speakerLabel,
                    translatedText: heardMessage.translatedText,
                    originalText: heardMessage.originalText,
                    language: heardMessage.sourceLanguage,
                    timestamp: heardMessage.timestamp,
                  ),
                )
              : liveState.autonomousConversation,
        );
        break;
      case 'scenario_update':
        final ScenarioState state = ScenarioState.fromMap(
          payload['current_state'] as Map<String, dynamic>? ??
              <String, dynamic>{},
        );
        liveState = liveState.copyWith(
          currentState: state,
          lastScenarioUpdateAt: state.updatedAt,
          targetLanguage: state.localLanguage,
        );
        if (!_testing) {
          await _database.saveScenarioSnapshot(_uuid.v4(), state);
        }
        break;
      case 'phrase_suggestions':
        final List<PhraseSuggestion> suggestions =
            (payload['items'] as List<dynamic>? ?? <dynamic>[])
                .map(
                  (dynamic item) =>
                      PhraseSuggestion.fromMap(item as Map<String, dynamic>),
                )
                .toList();
        liveState = liveState.copyWith(suggestions: suggestions);
        if (!_testing) {
          await _database.cacheSuggestions(
            _uuid.v4(),
            liveState.currentState,
            suggestions,
          );
        }
        break;
      case 'intent_assist':
        final IntentAssist assist = IntentAssist.fromMap(payload);
        liveState = liveState.copyWith(currentIntentAssist: assist);
        if (!_testing) {
          await _database.saveIntentAssist(_uuid.v4(), assist);
        }
        break;
      case 'live_transcript':
        final TranscriptEvent event = TranscriptEvent.fromMap(payload);
        if (event.speaker == 'other' && !event.needsTranslation) {
          await _recordDiagnostic(
            'ambient_same_language_ignored',
            <String, dynamic>{
              'source_language': event.sourceLanguage,
              'text': _previewText(event.originalText),
            },
          );
          break;
        }
        liveState = liveState.copyWith(
          transcriptEvents: _appendTranscriptEvent(event),
        );
        break;
      case 'assistant_reply':
        if (liveState.autonomousPaused) {
          break;
        }
        final AssistantReply reply = AssistantReply.fromMap(payload);
        final List<TranscriptEvent> transcriptEvents =
            (reply.targetText.isNotEmpty || reply.translatedText.isNotEmpty)
            ? _appendTranscriptEvent(
                TranscriptEvent(
              speaker: 'assistant',
              originalText: reply.targetText,
              userLanguageText: reply.translatedText,
              targetLanguageText: reply.targetText,
              isFinal: true,
              timestamp: DateTime.now().toUtc(),
              sourceLanguage: liveState.targetLanguage ?? '',
              needsTranslation: true,
            ),
          )
            : liveState.transcriptEvents;
        liveState = liveState.copyWith(
          lastAssistantReply: reply,
          transcriptEvents: transcriptEvents,
          autonomousConversation:
              liveState.interactionMode == InteractionMode.autonomous &&
                  (reply.targetText.isNotEmpty || reply.translatedText.isNotEmpty)
              ? _appendConversationMessage(
                  ConversationMessage(
                    id: _uuid.v4(),
                    role: 'assistant',
                    title: 'AI said',
                    translatedText: reply.translatedText.isNotEmpty
                        ? reply.translatedText
                        : reply.targetText,
                    originalText: reply.targetText,
                    transliteration: reply.transliteration,
                    language: liveState.targetLanguage ?? '',
                    timestamp: DateTime.now().toUtc(),
                  ),
                )
              : liveState.autonomousConversation,
          clearAutonomousPrompt: true,
        );
        if (!_testing &&
            !liveState.muteReplies &&
            (reply.audioBase64 ?? '').isNotEmpty) {
          await _playReplyAudio(
            reply.audioBase64!,
            reply.mimeType ?? 'audio/mpeg',
            _uuid.v4(),
          );
        }
        break;
      case 'autonomous_status':
        final AutonomousStatus status = AutonomousStatus.fromMap(payload);
        liveState = liveState.copyWith(
          autonomousStatus: status,
          currentGoal: status.goal,
          autonomousPaused: status.status == 'paused'
              ? true
              : status.status == 'waiting_for_interaction' ||
                    status.status == 'in_progress' ||
                    status.status == 'active'
              ? false
              : liveState.autonomousPaused,
        );
        break;
      case 'autonomous_prompt':
        liveState = liveState.copyWith(
          autonomousPrompt: AutonomousPrompt.fromMap(payload),
          autonomousConversation: _appendConversationMessage(
            ConversationMessage(
              id: payload['prompt_id'] as String? ?? _uuid.v4(),
              role: 'prompt',
              title: 'AI needs your input',
              translatedText: payload['question'] as String? ?? '',
              originalText: '',
              language: liveState.userLanguage,
              timestamp: DateTime.now().toUtc(),
            ),
          ),
        );
        break;
      case 'quick_reply_result':
        final QuickReplyResult result = QuickReplyResult.fromMap(payload);
        liveState = liveState.copyWith(
          latestQuickReply: result,
          clearActiveQuickReplyMessageId: true,
        );
        if (!_testing &&
            !liveState.muteReplies &&
            (result.audioBase64 ?? '').isNotEmpty) {
          await _playReplyAudio(
            result.audioBase64!,
            result.mimeType ?? 'audio/mpeg',
            result.requestId,
          );
        }
        break;
      case 'goal_captured':
        final String goal = payload['goal'] as String? ?? '';
        liveState = liveState.copyWith(
          currentGoal: goal,
          awaitingGoalCapture: false,
          awaitingLanguageCapture:
              (liveState.targetLanguage ?? '').trim().isEmpty,
          autonomousConversation: _appendConversationMessage(
            ConversationMessage(
              id: _uuid.v4(),
              role: 'system',
              title: 'Task set',
              translatedText: goal,
              originalText: '',
              language: liveState.userLanguage,
              timestamp: DateTime.now().toUtc(),
            ),
          ),
        );
        settings = settings.copyWith(
          defaultAutonomousGoal: goal,
          interactionMode: InteractionMode.autonomous,
          updatedAt: DateTime.now().toUtc(),
        );
        if (!_testing) {
          await _database.saveSettings(settings);
        }
        break;
      case 'language_captured':
        final String language = payload['target_language'] as String? ?? '';
        if (language.isNotEmpty) {
          liveState = liveState.copyWith(
            targetLanguage: language,
            awaitingLanguageCapture: false,
            awaitingGoalCapture: false,
            autonomousConversation: _appendConversationMessage(
              ConversationMessage(
                id: _uuid.v4(),
                role: 'system',
                title: 'Language set',
                translatedText: 'AI will speak in $language.',
                originalText: '',
                language: liveState.userLanguage,
                timestamp: DateTime.now().toUtc(),
              ),
            ),
          );
          settings = settings.copyWith(
            targetLanguage: language,
            targetLanguageAutoInfer: false,
            updatedAt: DateTime.now().toUtc(),
          );
          if (!_testing) {
            await _database.saveSettings(settings);
          }
        }
        break;
      case 'live_status':
        final String message =
            payload['message'] as String? ?? 'waiting for speech';
        if (message.startsWith('Audio chunk ')) {
          break;
        }
        liveState = liveState.copyWith(
          connectionStatus: _compactConnectionStatus(message),
        );
        break;
      case 'model_debug':
        break;
      case 'language_selected':
        final String language = payload['target_language'] as String? ?? '';
        if (language.isNotEmpty) {
          settings = settings.copyWith(
            targetLanguage: language,
            targetLanguageAutoInfer: false,
            updatedAt: DateTime.now().toUtc(),
          );
          if (!_testing) {
            await _database.saveSettings(settings);
          }
          liveState = liveState.copyWith(targetLanguage: language);
        }
        break;
      case 'phrase_audio':
        if (!_testing && !liveState.muteReplies) {
          await _playReplyAudio(
            payload['audio_base64'] as String? ?? '',
            payload['mime_type'] as String? ?? 'audio/mpeg',
            payload['suggestion_id'] as String? ?? _uuid.v4(),
          );
          final String suggestionId = payload['suggestion_id'] as String? ?? '';
          if (suggestionId.isNotEmpty) {
            await _database.markHistoryAudioPlayed(suggestionId);
            await _reloadCachedData();
          }
        }
        break;
      case 'live_warning':
        await _recordDiagnostic(
          'live_warning',
          <String, dynamic>{'message': payload['message']},
        );
        liveState = liveState.copyWith(
          connectionStatus: _compactConnectionStatus(
            payload['message'] as String? ?? 'warning',
          ),
        );
        break;
      default:
        await _recordDiagnostic(type, payload);
    }
    notifyListeners();
  }

  Future<void> _recordDiagnostic(
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (_testing) {
      return;
    }
    final DiagnosticEvent event = DiagnosticEvent(
      id: _uuid.v4(),
      createdAt: DateTime.now().toUtc(),
      type: type,
      payload: payload,
    );
    await _database.insertDiagnostic(event);
    diagnostics = await _database.listDiagnostics();
  }

  Map<String, dynamic> _summarizeLivePayload(
    String type,
    Map<String, dynamic> payload,
  ) {
    switch (type) {
      case 'user_message':
        return <String, dynamic>{
          'translated_text': _previewText(
            payload['translated_text'] as String? ??
                payload['original_text'] as String? ??
                '',
          ),
        };
      case 'heard_message':
        return <String, dynamic>{
          'translated_text': _previewText(payload['translated_text'] as String? ?? ''),
          'source_language': payload['source_language'] ?? '',
          'reply_count':
              (payload['reply_suggestions'] as List<dynamic>? ?? <dynamic>[]).length,
        };
      case 'live_transcript':
        return <String, dynamic>{
          'speaker': payload['speaker'],
          'text': _previewText(
            payload['user_language_text'] as String? ??
                payload['original_text'] as String? ??
                '',
          ),
          'original_text': _previewText(payload['original_text'] as String? ?? ''),
          'source_language': payload['source_language'] ?? '',
          'needs_translation': payload['needs_translation'] ?? false,
          'is_final': payload['is_final'] ?? true,
        };
      case 'assistant_reply':
        return <String, dynamic>{
          'translated_text': _previewText(
            payload['translated_text'] as String? ?? '',
          ),
          'target_text': _previewText(payload['target_text'] as String? ?? ''),
          'spoken': payload['spoken'] ?? false,
          'audio_available': payload['audio_available'] ?? false,
        };
      case 'scenario_update':
        final Map<String, dynamic> state =
            payload['current_state'] as Map<String, dynamic>? ??
            <String, dynamic>{};
        return <String, dynamic>{
          'context_summary': _previewText(
            state['context_summary'] as String? ?? '',
          ),
          'local_language': state['local_language'] ?? '',
          'scenario': state['scenario'] ?? '',
          'manual_override_active': state['manual_override_active'] ?? false,
        };
      case 'autonomous_status':
        return <String, dynamic>{
          'goal': _previewText(payload['goal'] as String? ?? ''),
          'status': payload['status'] ?? '',
          'summary': _previewText(payload['summary'] as String? ?? ''),
        };
      case 'phrase_suggestions':
        return <String, dynamic>{
          'count': (payload['items'] as List<dynamic>? ?? <dynamic>[]).length,
        };
      case 'phrase_audio':
        return <String, dynamic>{
          'suggestion_id': payload['suggestion_id'] ?? '',
          'mime_type': payload['mime_type'] ?? 'audio/mpeg',
        };
      case 'quick_reply_result':
        return <String, dynamic>{
          'target_language': payload['target_language'] ?? '',
          'user_text': _previewText(payload['user_text'] as String? ?? ''),
          'target_text': _previewText(payload['target_text'] as String? ?? ''),
        };
      case 'autonomous_prompt':
        return <String, dynamic>{
          'question': _previewText(payload['question'] as String? ?? ''),
          'options':
              (payload['options'] as List<dynamic>? ?? <dynamic>[]).length,
        };
      case 'goal_captured':
        return <String, dynamic>{
          'goal': _previewText(payload['goal'] as String? ?? ''),
        };
      case 'language_captured':
        return <String, dynamic>{
          'target_language': payload['target_language'] ?? '',
        };
      default:
        final Map<String, dynamic> summary = <String, dynamic>{};
        for (final MapEntry<String, dynamic> entry in payload.entries) {
          if (entry.key == 'audio_base64' || entry.key == 'jpeg_base64') {
            summary[entry.key] = '[omitted]';
            continue;
          }
          if (entry.value is String) {
            summary[entry.key] = _previewText(entry.value as String);
            continue;
          }
          summary[entry.key] = entry.value;
        }
        return summary;
    }
  }

  String _previewText(String text, {int maxLength = 140}) {
    final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  String _compactConnectionStatus(String text) {
    final String normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'Waiting for speech';
    }
    if (normalized.startsWith('Live translation started')) {
      return 'Listening live';
    }
    if (normalized.startsWith('Session configured')) {
      return 'Ready';
    }
    if (normalized.startsWith('Listening for your autonomous task')) {
      return 'Listening for your task';
    }
    if (normalized.startsWith('Listening for the language')) {
      return 'Listening for the language';
    }
    if (normalized.startsWith('Listening for your answer')) {
      return 'Listening for your answer';
    }
    if (normalized.startsWith('TTS audio was unavailable')) {
      return 'Reply audio unavailable';
    }
    if (normalized.length <= 90) {
      return normalized;
    }
    return '${normalized.substring(0, 90)}...';
  }

  List<TranscriptEvent> _appendTranscriptEvent(TranscriptEvent event) {
    final List<TranscriptEvent> transcriptEvents = <TranscriptEvent>[
      ...liveState.transcriptEvents,
      event,
    ];
    if (transcriptEvents.length > 60) {
      transcriptEvents.removeRange(0, transcriptEvents.length - 60);
    }
    return transcriptEvents;
  }

  List<HeardMessage> _appendHeardMessage(HeardMessage message) {
    final List<HeardMessage> heardMessages = <HeardMessage>[
      ...liveState.heardMessages,
      message,
    ];
    if (heardMessages.length > 40) {
      heardMessages.removeRange(0, heardMessages.length - 40);
    }
    return heardMessages;
  }

  List<ConversationMessage> _appendConversationMessage(
    ConversationMessage message,
  ) {
    final List<ConversationMessage> items = <ConversationMessage>[
      ...liveState.autonomousConversation,
      message,
    ];
    if (items.length > 60) {
      items.removeRange(0, items.length - 60);
    }
    return items;
  }

  Future<void> _scheduleNativeAudioRestart() async {
    if (!_usesNativeAndroidAudio || !liveState.liveConnected) {
      return;
    }
    _nativeAudioRestartTimer?.cancel();
    _nativeAudioRestartTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        unawaited(_restartNativeAudioStream());
      },
    );
  }

  Future<void> _restartNativeAudioStream() async {
    if (!_usesNativeAndroidAudio || !liveState.liveConnected) {
      return;
    }
    await _recordDiagnostic(
      'android_audio_stream_restart',
      <String, dynamic>{'connected': liveState.liveConnected},
    );
    await _stopMicrophoneStream();
    if (liveState.audioInputEnabled && _liveSessionService.isConnected) {
      await _startMicrophoneStream();
    }
  }

  void _queueAudioChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _pendingAudioBytes.addAll(chunk);
    while (_pendingAudioBytes.length >= 3200) {
      final Uint8List frame = Uint8List.fromList(
        _pendingAudioBytes.sublist(0, 3200),
      );
      _pendingAudioBytes.removeRange(0, 3200);
      _liveSessionService.sendAudioChunk(frame);
    }
  }

  @override
  void dispose() {
    _nativeAudioRestartTimer?.cancel();
    _authService.removeListener(_handleAuthChanged);
    unawaited(stopLive());
    if (!_testing) {
      unawaited(_audioPlaybackService.dispose());
    }
    super.dispose();
  }
}
