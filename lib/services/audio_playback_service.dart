import 'dart:convert';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playBase64Audio(
    String base64Audio,
    String mimeType,
    String fileName,
  ) async {
    final Directory directory = await getTemporaryDirectory();
    final String extension = mimeType.contains('mpeg') ? 'mp3' : 'wav';
    final File file = File(p.join(directory.path, '$fileName.$extension'));
    await file.writeAsBytes(base64Decode(base64Audio), flush: true);
    await _player.setFilePath(file.path);
    await _player.play();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> stopPlayback() async {
    await stop();
  }
}
