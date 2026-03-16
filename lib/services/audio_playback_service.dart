import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _streamPlayer = AudioPlayer();

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

  /// Play raw PCM bytes in memory by wrapping with a WAV header.
  /// [sampleRate] defaults to 24000 to match Gemini Live output.
  Future<void> playPcmBytes(
    Uint8List pcmBytes, {
    int sampleRate = 24000,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) async {
    final Uint8List wavBytes = _buildWav(
      pcmBytes,
      sampleRate: sampleRate,
      numChannels: numChannels,
      bitsPerSample: bitsPerSample,
    );
    await _streamPlayer.stop();
    final source = _InMemoryAudioSource(wavBytes);
    await _streamPlayer.setAudioSource(source);
    await _streamPlayer.play();
  }

  /// Stop only the streaming player (used when new streaming audio arrives).
  Future<void> stopStreaming() async {
    await _streamPlayer.stop();
  }

  bool get isStreamPlaying =>
      _streamPlayer.playing &&
      _streamPlayer.processingState != ProcessingState.completed;

  static Uint8List _buildWav(
    Uint8List pcmData, {
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
  }) {
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmData);
    return wav;
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _streamPlayer.dispose();
  }

  Future<void> stop() async {
    await _player.stop();
    await _streamPlayer.stop();
  }

  Future<void> stopPlayback() async {
    await stop();
  }
}

/// In-memory audio source for just_audio that serves WAV bytes directly.
class _InMemoryAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _InMemoryAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final int effectiveStart = start ?? 0;
    final int effectiveEnd = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: effectiveEnd - effectiveStart,
      offset: effectiveStart,
      stream: Stream.value(
        _bytes.sublist(effectiveStart, effectiveEnd),
      ),
      contentType: 'audio/wav',
    );
  }
}
