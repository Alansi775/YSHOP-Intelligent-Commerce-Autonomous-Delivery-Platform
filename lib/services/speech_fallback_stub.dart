class WebSpeechFallback {
  Future<bool> speak(String text, {void Function()? onDone}) async {
    return false;
  }

  void stop() {}
}