import 'dart:html' as html;

class WebSpeechFallback {
  html.SpeechSynthesisUtterance? _utterance;

  Future<bool> speak(String text, {void Function()? onDone}) async {
    stop();

    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    final utterance = html.SpeechSynthesisUtterance(cleanText);
    _utterance = utterance;

    utterance.onEnd.listen((_) {
      onDone?.call();
      _utterance = null;
    });

    utterance.onError.listen((_) {
      onDone?.call();
      _utterance = null;
    });

    html.window.speechSynthesis?.speak(utterance);
    return true;
  }

  void stop() {
    html.window.speechSynthesis?.cancel();
    _utterance = null;
  }
}