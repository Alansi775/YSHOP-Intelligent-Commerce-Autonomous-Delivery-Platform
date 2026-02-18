// lib/services/tts_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'tts_player_stub.dart'
    if (dart.library.html) 'tts_player_web.dart'
    if (dart.library.io) 'tts_player_mobile.dart';

class TTSService {
  // Read API key from environment (.env). Load .env in main.dart before runApp().
  static final String _apiKey = dotenv.env['YSHOP_TTS_API_KEY'] ?? '';

  // "George" — deep, warm, professional male
  static const String _voiceId = 'JBFqnCBsd6RMkjVDRZzb';
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final TTSPlayer _player = TTSPlayer();
  final Map<String, Uint8List> _cache = {};
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentHash;

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  String _hash(String t) =>
      md5.convert(utf8.encode(t.trim().toLowerCase())).toString().substring(0, 12);

  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    final t = text.length > 250 ? '${text.substring(0, 247)}...' : text;
    final h = _hash(t);

    if (_isPlaying && _currentHash == h) { await stop(); return false; }
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
        if (bytes != null) _cache[h] = bytes;
      }

      if (bytes == null) { _isLoading = false; _currentHash = null; return false; }

      _isLoading = false;
      _isPlaying = true;

      _player.play(bytes, onDone: () {
        _isPlaying = false;
        _currentHash = null;
      });

      return true;
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      _isLoading = false; _isPlaying = false; _currentHash = null;
      return false;
    }
  }

  Future<Uint8List?> _callAPI(String text) async {
    try {
      if (_apiKey.isEmpty) {
        debugPrint('[TTS] No API key provided. Set YSHOP_TTS_API_KEY in .env');
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
            'stability': 0.5,
            'similarity_boost': 0.75,
            'style': 0.0,
            'use_speaker_boost': true,
          },
        }),
      );
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
      debugPrint('[TTS] API ${r.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[TTS] API fail: $e');
      return null;
    }
  }

  Future<void> stop() async {
    if (_isPlaying) { _player.stop(); _isPlaying = false; _currentHash = null; }
  }

  void clearCache() => _cache.clear();
}