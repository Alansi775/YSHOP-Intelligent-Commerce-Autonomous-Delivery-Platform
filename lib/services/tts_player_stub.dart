// lib/services/tts_player_stub.dart
// Stub — should never actually be used at runtime
import 'dart:typed_data';

class TTSPlayer {
  void play(Uint8List bytes, {void Function()? onDone}) {
    throw UnsupportedError('TTSPlayer stub — platform not supported');
  }

  void stop() {}
}