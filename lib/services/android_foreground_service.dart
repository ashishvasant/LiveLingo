import 'dart:io';

import 'package:flutter/services.dart';

class AndroidForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'talking_learning/foreground_service',
  );

  static Future<void> start({
    required String mode,
    required bool muted,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('startForeground', <String, dynamic>{
      'mode': mode,
      'muted': muted,
    });
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stopForeground');
  }
}
