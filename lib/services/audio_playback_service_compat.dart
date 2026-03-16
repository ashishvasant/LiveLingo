import 'audio_playback_service.dart';

extension AudioPlaybackServiceCompat on AudioPlaybackService {
  Future<void> stopActivePlayback() async {
    final dynamic service = this;

    try {
      final dynamic result = service.stop();
      if (result is Future<void>) {
        await result;
      } else if (result is Future) {
        await result;
      }
      return;
    } on NoSuchMethodError {
      final dynamic fallback = service.stopPlayback();
      if (fallback is Future<void>) {
        await fallback;
      } else if (fallback is Future) {
        await fallback;
      }
    }
  }
}
