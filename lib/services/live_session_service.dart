import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../models.dart';

typedef LiveMessageHandler = Future<void> Function(Map<String, dynamic> payload);

class LiveSessionService {
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  bool get isConnected => _channel != null;

  String _toWebSocketUrl(String backendUrl) {
    final String trimmed = backendUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (trimmed.startsWith('https://')) {
      return trimmed.replaceFirst('https://', 'wss://');
    }
    if (trimmed.startsWith('http://')) {
      return trimmed.replaceFirst('http://', 'ws://');
    }
    return trimmed;
  }

  Future<void> connect({
    required AppSettings settings,
    required String idToken,
    required LiveMessageHandler onMessage,
    required Future<void> Function(Object error) onError,
  }) async {
    await disconnect();
    final Uri uri = Uri.parse('${_toWebSocketUrl(settings.backendUrl)}/v1/live/ws');
    final WebSocket socket = await WebSocket.connect(
      uri.toString(),
      headers: <String, dynamic>{'Authorization': 'Bearer $idToken'},
    );
    socket.pingInterval = const Duration(seconds: 15);
    _channel = IOWebSocketChannel(socket);
    _subscription = _channel!.stream.listen(
      (dynamic event) async {
        if (event is String) {
          final Map<String, dynamic> payload =
              jsonDecode(event) as Map<String, dynamic>;
          await onMessage(payload);
        }
      },
      onError: (Object error) async {
        await onError(error);
      },
      onDone: () async {
        await onError(StateError('Live session disconnected'));
      },
      cancelOnError: false,
    );
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void sendJson(Map<String, Object?> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void sendAudioChunk(Uint8List bytes) {
    _channel?.sink.add(bytes);
  }

  void sendSessionConfig(AppSettings settings, LiveLanguageState state) {
    sendJson(
      settings.toSessionConfig(
        cameraEnabled: state.cameraEnabled,
        autonomousGoal: state.currentGoal,
        contextOverride: state.contextOverride,
      ),
    );
  }

  void sendUserTextIntent(String text) {
    sendJson(<String, Object?>{'type': 'user_text_intent', 'text': text});
  }

  void sendContextOverride(String text) {
    sendJson(<String, Object?>{'type': 'context_override', 'text': text});
  }

  void sendAutonomousGoal(String goal) {
    sendJson(<String, Object?>{'type': 'autonomous_goal_set', 'goal': goal});
  }

  void sendTaskControl(String action) {
    sendJson(<String, Object?>{'type': 'task_control', 'action': action});
  }

  void setTargetLanguage(String language) {
    sendJson(<String, Object?>{
      'type': 'set_target_language',
      'language': language,
    });
  }

  void sendCameraFrame({required String base64Jpeg, required int frameSeq}) {
    sendJson(<String, Object?>{
      'type': 'camera_frame',
      'jpeg_base64': base64Jpeg,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'frame_seq': frameSeq,
    });
  }

  void requestPhraseAudio(PhraseSuggestion suggestion) {
    sendJson(<String, Object?>{
      'type': 'phrase_audio_request',
      'suggestion_id': suggestion.id,
      'text': suggestion.targetText,
    });
  }

  void requestReplySuggestionAudio({
    required String suggestionId,
    required String text,
    required String language,
  }) {
    sendJson(<String, Object?>{
      'type': 'phrase_audio_request',
      'suggestion_id': suggestionId,
      'text': text,
      'language': language,
    });
  }

  void beginQuickSpeak({
    required String sourceMessageId,
    required String language,
  }) {
    sendJson(<String, Object?>{
      'type': 'quick_speak_start',
      'source_message_id': sourceMessageId,
      'language': language,
    });
  }

  void submitQuickReplyText({
    required String sourceMessageId,
    required String text,
    required String language,
  }) {
    sendJson(<String, Object?>{
      'type': 'quick_reply_text',
      'source_message_id': sourceMessageId,
      'text': text,
      'language': language,
    });
  }

  void startGoalCapture() {
    sendJson(<String, Object?>{'type': 'goal_capture_start'});
  }

  void startLanguageCapture() {
    sendJson(<String, Object?>{'type': 'language_capture_start'});
  }

  void startAutonomousUserSpeechCapture() {
    sendJson(<String, Object?>{'type': 'autonomous_user_capture_start'});
  }
}
