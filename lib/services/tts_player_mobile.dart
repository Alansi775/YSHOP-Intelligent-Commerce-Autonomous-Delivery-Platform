// lib/services/tts_player_mobile.dart
// Mobile implementation — uses just_audio
import 'dart:typed_data';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class TTSPlayer {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(Uint8List bytes, {void Function()? onDone}) async {
    try {
      // Write to temp file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes);

      await _player.setFilePath(file.path);
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          onDone?.call();
          // Clean up temp file
          file.delete().catchError((_) {});
        }
      });
      _player.play();
    } catch (e) {
      onDone?.call();
    }
  }

  void stop() {
    _player.stop();
  }
}