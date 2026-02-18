// lib/services/tts_player_web.dart
// Web implementation — uses HTML5 Audio via Blob URL
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js' as js;

class TTSPlayer {
  html.AudioElement? _audio;
  String? _blobUrl;

  void play(Uint8List bytes, {void Function()? onDone}) {
    stop(); // clean up previous

    // Create a Blob from the audio bytes
    final blob = html.Blob([bytes], 'audio/mpeg');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    _audio = html.AudioElement(_blobUrl!);
    _audio!.onEnded.listen((_) {
      onDone?.call();
      _cleanup();
    });
    _audio!.onError.listen((_) {
      onDone?.call();
      _cleanup();
    });
    _audio!.play();
  }

  void stop() {
    if (_audio != null) {
      _audio!.pause();
      _audio!.currentTime = 0;
    }
    _cleanup();
  }

  void _cleanup() {
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
    _audio = null;
  }
}