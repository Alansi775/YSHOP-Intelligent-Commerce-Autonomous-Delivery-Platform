// lib/services/tts_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'tts_player_stub.dart'
    if (dart.library.html) 'tts_player_web.dart'
    if (dart.library.io) 'tts_player_mobile.dart';

class TTSService {
  static final String _apiKey = dotenv.env['YSHOP_TTS_API_KEY'] ?? '';

  // "George" — deep, warm, professional male
  static const String _voiceId = 'JBFqnCBsd6RMkjVDRZzb';
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal() {
    // Log presence of API key at construction (do not print full key)
    debugPrint('[TTS] API Key loaded at init: ${_apiKey.isEmpty ? "EMPTY" : "EXISTS (${_apiKey.substring(0,5)}...)"}');
  }

  final TTSPlayer _player = TTSPlayer();
  final Map<String, Uint8List> _cache = {};
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentHash;
  Completer<void>? _playbackCompleter;

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  String _hash(String t) =>
      md5.convert(utf8.encode(t.trim().toLowerCase())).toString().substring(0, 12);

  /// Clean for UI display — no tags visible
  static String cleanForDisplay(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(RegExp(r'<break\s*time="[^"]*"\s*/?>'), '')
        .replaceAll(RegExp(r'</?prosody[^>]*>'), '')
        .replaceAll(RegExp(r'\(haha\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(hehe\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(hmm\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Convert AI expression tags to natural text for ElevenLabs.
  /// ElevenLabs text-to-speech does NOT support SSML tags.
  /// We convert them to punctuation/words that ElevenLabs handles naturally.
  static String _prepareForTTS(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'<break\s*time="[^"]*"\s*/?>'), '...');
    t = t.replaceAllMapped(
      RegExp(r'<prosody[^>]*>(.*?)</prosody>', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'\(haha\)', caseSensitive: false), 'ha ha,');
    t = t.replaceAll(RegExp(r'\(hehe\)', caseSensitive: false), 'heh,');
    t = t.replaceAll(RegExp(r'\(hmm\)', caseSensitive: false), 'hmm...');
    t = t.replaceAll(RegExp(r'\.{4,}'), '...');
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    t = t.replaceAll(RegExp(r',\s*,'), ',');
    return t.trim();
  }

  Future<bool> speak(String text) async {
    debugPrint('[TTS] API Key loaded: ${_apiKey.isEmpty ? "EMPTY" : "EXISTS (${_apiKey.substring(0, 5)}...)"}');
    if (text.trim().isEmpty) return false;

    final ttsText = _prepareForTTS(text);
    if (ttsText.isEmpty) return false;

    final t = ttsText.length > 300 ? '${ttsText.substring(0, 297)}...' : ttsText;
    final h = _hash(t);

    if (_isPlaying && _currentHash == h) {
      await stop();
      return false;
    }
    await stop();

    try {
      _isLoading = true;
      _currentHash = h;

      Uint8List? bytes;
      if (_cache.containsKey(h)) {
        debugPrint('[TTS] Cache hit: $h');
        bytes = _cache[h];
      } else {
        debugPrint('[TTS] Calling ElevenLabs...');
        bytes = await _callAPI(t);
        if (bytes != null && bytes.length > 1000) {
          _cache[h] = bytes;
        } else if (bytes != null && bytes.length <= 1000) {
          debugPrint('[TTS] Audio too small (${bytes.length}b), discarding');
          bytes = null;
        }
      }

      if (bytes == null) {
        debugPrint('[TTS] No valid audio');
        _isLoading = false;
        _currentHash = null;
        return false;
      }

      _isLoading = false;
      _isPlaying = true;
      _playbackCompleter = Completer<void>();

      _player.play(bytes, onDone: () {
        debugPrint('[TTS] Playback complete');
        _isPlaying = false;
        _currentHash = null;
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      _isLoading = false;
      _isPlaying = false;
      _currentHash = null;
      return false;
    }
  }

  /// Await until playback finishes (or 30s timeout)
  Future<void> waitForCompletion() async {
    if (!_isPlaying || _playbackCompleter == null) return;
    try {
      await _playbackCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[TTS] Timeout');
          _isPlaying = false;
          _currentHash = null;
        },
      );
    } catch (_) {}
  }

  Future<Uint8List?> _callAPI(String text) async {
    try {
      if (_apiKey.isEmpty) {
        debugPrint('[TTS] No API key');
        return null;
      }

      final r = await http.post(
        Uri.parse('$_baseUrl/text-to-speech/$_voiceId'),
        headers: {
          'xi-api-key': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': 0.40,
            'similarity_boost': 0.75,
            'style': 0.10,
            'use_speaker_boost': true,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        debugPrint('[TTS] Got ${r.bodyBytes.length} bytes');
        return r.bodyBytes;
      }
      debugPrint('[TTS] API ${r.statusCode}');
      return null;
    } on TimeoutException {
      debugPrint('[TTS] API timeout');
      return null;
    } catch (e) {
      debugPrint('[TTS] API fail: $e');
      return null;
    }
  }

  Future<void> stop() async {
    if (_isPlaying) {
      _player.stop();
      _isPlaying = false;
      _currentHash = null;
      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }
      _playbackCompleter = null;
    }
  }

  void clearCache() => _cache.clear();
}