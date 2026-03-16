import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({
    required this.configured,
    required this.initialized,
    this.message,
  });

  final bool configured;
  final bool initialized;
  final String? message;
}

class FirebaseBootstrap {
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const String androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const String iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );

  static bool get isConfigured {
    if (projectId.isEmpty || senderId.isEmpty) {
      return false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return androidApiKey.isNotEmpty && androidAppId.isNotEmpty;
      case TargetPlatform.iOS:
        return iosApiKey.isNotEmpty &&
            iosAppId.isNotEmpty &&
            iosBundleId.isNotEmpty;
      default:
        return false;
    }
  }

  static String get missingConfigMessage {
    return 'Firebase is not configured. Either add native Firebase config '
        '(Android google-services.json / iOS GoogleService-Info.plist) or '
        'supply the Firebase dart-defines for this build.';
  }

  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: androidApiKey,
          appId: androidAppId,
          messagingSenderId: senderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: iosApiKey,
          appId: iosAppId,
          messagingSenderId: senderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
          iosBundleId: iosBundleId,
        );
      default:
        throw UnsupportedError(
          'Firebase bootstrap is only configured for Android and iOS.',
        );
    }
  }

  static Future<FirebaseBootstrapResult> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        if (isConfigured) {
          await Firebase.initializeApp(options: currentPlatform);
        } else {
          await Firebase.initializeApp();
        }
      }
      return FirebaseBootstrapResult(
        configured: true,
        initialized: true,
        message: isConfigured
            ? null
            : 'Firebase initialized from native platform config.',
      );
    } catch (error) {
      if (!isConfigured) {
        return FirebaseBootstrapResult(
          configured: false,
          initialized: false,
          message: '$missingConfigMessage Native initialization error: $error',
        );
      }
      return FirebaseBootstrapResult(
        configured: true,
        initialized: false,
        message: 'Firebase initialization failed: $error',
      );
    }
  }
}
