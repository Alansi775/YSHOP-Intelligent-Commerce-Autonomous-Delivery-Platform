// lib/services/stt_service.dart
//
// Speech-to-Text Service — Platform-aware
//
// On WEB: Uses browser's Web Speech API directly via JS interop
// On MOBILE: Uses speech_to_text package (native Siri/Google)
//
// REQUIRED PACKAGES (pubspec.yaml):
//   speech_to_text: ^6.6.0
//
// iOS Info.plist:
//   NSSpeechRecognitionUsageDescription
//   NSMicrophoneUsageDescription
//
// Android AndroidManifest.xml:
//   <uses-permission android:name="android.permission.RECORD_AUDIO"/>

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// ═══════════════════════════════════════════════════════════════
/// 🎙️ STT SERVICE
/// ═══════════════════════════════════════════════════════════════
class STTService {
  static final STTService _instance = STTService._internal();
  factory STTService() => _instance;
  STTService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastResult = '';
  void Function(String text, bool isFinal)? _onResultCallback;

  bool get isListening => _isListening;
  String get lastResult => _lastResult;

  /// Initialize
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          debugPrint('[STT] Error: ${error.errorMsg}');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('[STT] Status: $status');
          if (status == 'done' || status == 'notListening') {
            // On web, 'done' fires quickly. Only mark not listening
            // if we actually got a final result or user stopped.
            if (_isListening && _lastResult.isNotEmpty) {
              _isListening = false;
              // Deliver final result if we haven't already
              _onResultCallback?.call(_lastResult, true);
            }
          }
        },
      );
      debugPrint('[STT] Initialized: $_isInitialized');
      debugPrint('[STT] Available locales: ${(await _speech.locales()).map((l) => l.localeId).take(5).toList()}');
      return _isInitialized;
    } catch (e) {
      debugPrint('[STT] Init failed: $e');
      return false;
    }
  }

  /// Start listening
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    String localeId = '',
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    // If already listening, stop first
    if (_isListening) {
      await stopListening();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    try {
      _isListening = true;
      _lastResult = '';
      _onResultCallback = onResult;

      debugPrint('[STT] Starting listen...');

      await _speech.listen(
        onResult: (result) {
          debugPrint('[STT] Result: "${result.recognizedWords}" final=${result.finalResult}');
          _lastResult = result.recognizedWords;
          onResult(result.recognizedWords, result.finalResult);

          if (result.finalResult) {
            _isListening = false;
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        localeId: localeId.isNotEmpty ? localeId : null,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      );

      debugPrint('[STT] Listen started successfully');
      return true;
    } catch (e) {
      debugPrint('[STT] Listen failed: $e');
      _isListening = false;
      return false;
    }
  }

  /// Stop
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      // If we have partial results, deliver them as final
      if (_lastResult.isNotEmpty) {
        _onResultCallback?.call(_lastResult, true);
      }
    }
  }

  /// Cancel
  Future<void> cancel() async {
    await _speech.cancel();
    _isListening = false;
    _lastResult = '';
  }

  void dispose() {
    _speech.stop();
  }
}