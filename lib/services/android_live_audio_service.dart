import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidLiveAudioService {
  static const MethodChannel _methodChannel = MethodChannel(
    'talking_learning/audio_stream',
  );
  static const EventChannel _eventChannel = EventChannel(
    'talking_learning/audio_stream/events',
  );

  static Stream<Uint8List> pcmStream() {
    if (!Platform.isAndroid) {
      return const Stream<Uint8List>.empty();
    }
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event is Uint8List) {
        return event;
      }
      if (event is List<int>) {
        return Uint8List.fromList(event);
      }
      return Uint8List(0);
    }).where((Uint8List chunk) => chunk.isNotEmpty);
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _methodChannel.invokeMethod<void>('startRecording');
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _methodChannel.invokeMethod<void>('stopRecording');
  }
}
