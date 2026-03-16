import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../models.dart';

typedef AutonomousMessageHandler =
    Future<void> Function(Map<String, dynamic> payload);

class AutonomousSessionService {
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _closing = false;

  bool get isConnected => _channel != null && !_closing;

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
    required AutonomousMessageHandler onMessage,
    required Future<void> Function(Object error) onError,
  }) async {
    await disconnect();
    _closing = false;
    final Uri uri = Uri.parse(
      '${_toWebSocketUrl(settings.backendUrl)}/v1/autonomous/ws',
    );
    final WebSocket socket = await WebSocket.connect(
      uri.toString(),
      headers: <String, dynamic>{'Authorization': 'Bearer $idToken'},
    );
    socket.pingInterval = const Duration(seconds: 30);
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
        _closing = true;
        _subscription = null;
        _channel = null;
        await onError(error);
      },
      onDone: () async {
        final int? closeCode = socket.closeCode;
        final String? closeReason = socket.closeReason;
        final List<String> details = <String>[
          if (closeCode != null) 'code: $closeCode',
          if (closeReason != null && closeReason.isNotEmpty)
            'reason: $closeReason',
        ];
        _closing = true;
        _subscription = null;
        _channel = null;
        await onError(
          StateError(
            details.isEmpty
                ? 'Live session disconnected'
                : 'Live session disconnected (${details.join(', ')})',
          ),
        );
      },
      cancelOnError: false,
    );
  }

  Future<void> disconnect() async {
    _closing = true;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _closing = false;
  }

  bool sendAudioChunk(Uint8List bytes) {
    if (!isConnected) {
      return false;
    }
    try {
      _channel?.sink.add(bytes);
      return true;
    } catch (_) {
      _closing = true;
      _channel = null;
      _subscription = null;
      return false;
    }
  }

  bool sendSessionConfig({
    required AppSettings settings,
    required String task,
    required String placeLanguage,
  }) {
    return _sendJson(<String, Object?>{
      'type': 'session_config',
      'task': task.trim(),
      'place_language': placeLanguage.trim(),
      'user_language': settings.userLanguage,
      'voice_name': settings.liveVoiceName,
      'audio_input_enabled': settings.audioInputEnabled,
      'video_input_enabled': settings.includeCameraContext,
      'enable_camera_context': settings.includeCameraContext,
    });
  }

  bool sendTaskControl(String action) {
    return _sendJson(<String, Object?>{
      'type': 'task_control',
      'action': action,
    });
  }

  bool sendUserTextResponse(String text) {
    return _sendJson(<String, Object?>{
      'type': 'user_text_response',
      'text': text.trim(),
    });
  }

  bool sendToolResponse({
    required String toolCallId,
    required String responseText,
    String? selectedOption,
    String? selectedOptionLabel,
  }) {
    return _sendJson(<String, Object?>{
      'type': 'tool_response_submit',
      'tool_call_id': toolCallId,
      'response_text': responseText.trim(),
      'selected_option': selectedOption?.trim(),
      'selected_option_label': selectedOptionLabel?.trim(),
    });
  }

  bool sendCameraFrame({
    required String base64Jpeg,
    required int frameSeq,
    String? caption,
  }) {
    return _sendJson(<String, Object?>{
      'type': 'camera_frame',
      'jpeg_base64': base64Jpeg,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'frame_seq': frameSeq,
      'caption': caption?.trim(),
    });
  }

  bool _sendJson(Map<String, Object?> payload) {
    if (!isConnected) {
      return false;
    }
    try {
      _channel?.sink.add(jsonEncode(payload));
      return true;
    } catch (_) {
      _closing = true;
      _channel = null;
      _subscription = null;
      return false;
    }
  }
}
