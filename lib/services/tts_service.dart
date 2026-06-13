// lib/services/tts_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'speech_fallback_stub.dart'
  if (dart.library.html) 'speech_fallback_web.dart';
import 'tts_player_stub.dart'
    if (dart.library.html) 'tts_player_web.dart'
    if (dart.library.io) 'tts_player_mobile.dart';

/// A distinct AI voice personality from the ElevenLabs pre-made library.
class VoicePersonality {
  final String voiceId;
  final String name;   // shown in overlay ("Aria", "George", …)
  final String gender; // "female" | "male"
  final String age;    // "young" | "mid" | "mature"

  const VoicePersonality({
    required this.voiceId,
    required this.name,
    required this.gender,
    required this.age,
  });
}

class TTSService {
  static String get _apiKey => dotenv.env['YSHOP_TTS_API_KEY'] ?? '';
  static bool get _allowBrowserFallback =>
      (dotenv.env['YSHOP_TTS_ALLOW_BROWSER_FALLBACK'] ?? 'false').toLowerCase() == 'true';

  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  // ── Voice personality pool ────────────────────────────────────────────────
  // ElevenLabs pre-made voice IDs paired with international character names.
  // Only confirmed free-tier ElevenLabs voices — others return 402.
  static const List<VoicePersonality> personalities = [
    VoicePersonality(voiceId: 'JBFqnCBsd6RMkjVDRZzb', name: 'Karim', gender: 'male',   age: 'mature'),
    VoicePersonality(voiceId: 'EXAVITQu4vr4xnSDxMaL', name: 'Sara',  gender: 'female', age: 'young'),
    VoicePersonality(voiceId: 'pNInz6obpgDQGcFmaJgB', name: 'Rami',  gender: 'male',   age: 'mid'),
  ];

  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal() {
    debugPrint('[TTS] API Key loaded at init: ${_apiKey.isEmpty ? "EMPTY" : "EXISTS (${_apiKey.substring(0,5)}...)"}');
  }

  final TTSPlayer _player = TTSPlayer();
  final WebSpeechFallback _webSpeech = WebSpeechFallback();
  final Map<String, Uint8List> _cache = {};
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _currentHash;
  Completer<void>? _playbackCompleter;

  // Active personality — defaults to George; randomized per voice session
  VoicePersonality _activePersonality = personalities[0];

  // Voice IDs that returned 402 on this account — filtered out of random pool
  final Set<String> _failedVoiceIds = <String>{};

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  /// Returns the currently active voice personality.
  VoicePersonality get currentPersonality => _activePersonality;

  /// Pick a random voice from the pool for the next session.
  /// Voices that previously returned 402 are excluded automatically.
  VoicePersonality selectRandomPersonality() {
    final available = personalities.where((p) => !_failedVoiceIds.contains(p.voiceId)).toList();
    final pool = available.isNotEmpty ? available : personalities; // fallback to full pool if all failed
    final next = pool[Random().nextInt(pool.length)];
    _activePersonality = next;
    _cache.clear();
    debugPrint('[TTS] Voice → ${next.name} (${next.gender}, ${next.age}) | id=${next.voiceId}');
    return next;
  }

  static String _normalizeVoiceMood(String? mood) {
    switch ((mood ?? 'neutral').toLowerCase()) {
      case 'calm':
      case 'neutral':
      case 'excited':
      case 'playful':
      case 'curious':
      case 'caring':
      case 'whisper':
      case 'disappointed':
      case 'apologetic':
      case 'warm':
      case 'laugh':
      case 'laughing':
      case 'sad':
      case 'crazy':
        return switch ((mood ?? 'neutral').toLowerCase()) {
          'calm' => 'neutral',
          'laugh' => 'playful',
          'laughing' => 'playful',
          'sad' => 'disappointed',
          'crazy' => 'excited',
          _ => (mood ?? 'neutral').toLowerCase(),
        };
      default:
        return 'neutral';
    }
  }

  static double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static ({double stability, double similarityBoost, double style}) _voiceProfile(String mood, double intensity) {
    final t = _clamp(intensity, 0.0, 1.0);
    double blend(double low, double high) => low + (high - low) * t;

    switch (mood) {
      // Natural, slightly dynamic — not robotic
      case 'neutral':
        return (stability: blend(0.55, 0.35), similarityBoost: 0.78, style: blend(0.15, 0.35));

      // Warm, invested — sounds like someone who genuinely cares
      case 'warm':
      case 'caring':
        return (stability: blend(0.48, 0.28), similarityBoost: 0.84, style: blend(0.28, 0.62));

      // Very expressive — almost unhinged excitement
      case 'excited':
        return (stability: blend(0.28, 0.06), similarityBoost: 0.88, style: blend(0.75, 1.0));

      // Light, bouncy, teasing
      case 'playful':
        return (stability: blend(0.38, 0.10), similarityBoost: 0.85, style: blend(0.58, 0.96));

      // Slightly raised, inquisitive
      case 'curious':
        return (stability: blend(0.48, 0.22), similarityBoost: 0.82, style: blend(0.32, 0.68));

      // Near-chaotic — maximum laughter feel
      case 'laugh':
        return (stability: blend(0.22, 0.04), similarityBoost: 0.86, style: blend(0.68, 1.0));

      // Barely audible, intimate
      case 'whisper':
        return (stability: blend(0.94, 0.80), similarityBoost: 0.70, style: blend(0.01, 0.06));

      // Slow, heavy, sincere
      case 'disappointed':
      case 'sad':
      case 'apologetic':
        return (stability: blend(0.75, 0.52), similarityBoost: 0.76, style: blend(0.14, 0.32));

      // Full chaos mode
      case 'crazy':
        return (stability: blend(0.18, 0.03), similarityBoost: 0.88, style: blend(0.85, 1.0));

      default:
        return (stability: blend(0.55, 0.32), similarityBoost: 0.78, style: blend(0.15, 0.38));
    }
  }

  static String _normalizePause(String? pause) {
    switch ((pause ?? 'normal').toLowerCase()) {
      case 'short':
      case 'long':
      case 'normal':
        return (pause ?? 'normal').toLowerCase();
      default:
        return 'normal';
    }
  }

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
  /// ElevenLabs does NOT support SSML — we drive emotion through text cues and punctuation.
  static String _prepareForTTS(String text, {String voiceCue = '', String pause = 'normal', double pace = 1.0, String mood = 'neutral', double energy = 0.65}) {
    var t = text;

    // ── Step 1: Clean parenthetical stage directions from body text ─────────
    // eleven_turbo_v2_5 reads these literally — convert to natural language or em-dash pause.
    // NOTE: We use em-dashes (—) for pauses instead of SSML <break> tags because
    // eleven_turbo_v2_5 sometimes reads SSML angle brackets aloud as "less than" or "break".
    t = t.replaceAll(RegExp(r'\(hmm+\)', caseSensitive: false), 'Hmm...');
    t = t.replaceAll(RegExp(r'\(hm\)', caseSensitive: false), 'Hm...');
    t = t.replaceAll(RegExp(r'\(sighs?\)', caseSensitive: false), '—');
    t = t.replaceAll(RegExp(r'\(laughs?\)', caseSensitive: false), 'Ha!');
    t = t.replaceAll(RegExp(r'\(chuckles?\)', caseSensitive: false), 'Heh,');
    t = t.replaceAll(RegExp(r'\(ha!\)', caseSensitive: false), 'Ha!');
    t = t.replaceAll(RegExp(r'\(deep[\s-]breath\)', caseSensitive: false), '—');
    t = t.replaceAll(RegExp(r'\(whispering\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\(whispers?\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\(exhales?\)', caseSensitive: false), '—');
    // Strip any leftover SSML break tags from prior code paths
    t = t.replaceAll(RegExp(r'<break\s[^>]*/?>', caseSensitive: false), '—');

    // ── Step 2: Apply cue prefix ─────────────────────────────────────────────
    // Em-dash (—) = natural pause recognized by eleven_turbo_v2_5
    final normalizedPause = _normalizePause(pause);
    final cue = voiceCue.trim();
    if (cue.isNotEmpty) {
      final lowered = cue.toLowerCase();
      if (lowered == 'laugh') {
        t = 'Ha! $t';
      } else if (lowered == 'laugh_soft' || lowered == 'chuckle') {
        t = 'Heh, $t';
      } else if (lowered == 'laugh_big') {
        t = 'Haha! $t';
      } else if (lowered == 'deep_breath') {
        t = '— $t';
      } else if (lowered == 'pause') {
        t = '— $t';
      } else if (lowered == 'thinking' || lowered == 'hmm') {
        t = 'Hmm... $t';
      } else if (lowered == 'sigh') {
        t = '— $t';
      } else if (lowered == 'whisper') {
        // No text prefix — whisper is driven by voice stability settings alone
      } else {
        final disallowed = const {'hey', 'hello', 'hi', 'يا هلا', 'مرحبا', 'اهلا', 'أهلا'};
        if (!disallowed.contains(lowered)) t = '$cue. $t';
      }
    } else if (normalizedPause == 'long') {
      t = '— $t';
    }

    // ── Step 3: Pace shaping ──────────────────────────────────────────────────
    if (pace <= 0.84 && !t.startsWith('—') && !t.startsWith('...')) {
      t = t.replaceAll(RegExp(r',\s+'), ', ... ');
    } else if (pace >= 1.15) {
      t = t.replaceAll(RegExp(r'\.\.\.\s*'), ' ');
    }

    // ── Step 4: Excitement emphasis ───────────────────────────────────────────
    if ((mood == 'excited' || mood == 'laugh') && energy >= 0.82 && !t.endsWith('!') && !t.endsWith('?')) {
      t = '$t!';
    }

    // ── Step 5: Final cleanup ─────────────────────────────────────────────────
    // Keep <break> SSML tags — eleven_turbo_v2_5 interprets them as real pauses
    // Only strip <prosody> (not supported) and collapse whitespace
    t = t.replaceAllMapped(
      RegExp(r'<prosody[^>]*>(.*?)</prosody>', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'\.{4,}'), '...');
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    t = t.replaceAll(RegExp(r',\s*,'), ',');
    return t.trim();
  }

  Future<bool> speak(String text, {String? voiceMood, double voiceIntensity = 0.65, String voiceCue = '', Map<String, dynamic>? voiceProfile}) async {
    final profileMood = voiceProfile?['emotion'] as String?;
    final mood = _normalizeVoiceMood(profileMood ?? voiceMood);
    final intensity = _clamp((voiceProfile?['energy'] as num?)?.toDouble() ?? voiceIntensity, 0.0, 1.0);
    final cue = (voiceProfile?['cue'] as String? ?? voiceCue).trim();
    final pause = _normalizePause(voiceProfile?['pause'] as String?);
    debugPrint('[TTS] API Key loaded: ${_apiKey.isEmpty ? "EMPTY" : "EXISTS (${_apiKey.substring(0, 5)}...)"} | mood=$mood | intensity=${intensity.toStringAsFixed(2)} | pause=$pause | cue=${cue.isEmpty ? "none" : cue} | rawText="${text.substring(0, text.length.clamp(0, 140))}"');
    if (text.trim().isEmpty) return false;

    final pace = _clamp((voiceProfile?['pace'] as num?)?.toDouble() ?? 1.0, 0.75, 1.35);
    final ttsText = _prepareForTTS(text, voiceCue: cue, pause: pause, pace: pace, mood: mood, energy: intensity);
    debugPrint('[TTS] Prepared | mood=$mood | intensity=${intensity.toStringAsFixed(2)} | pace=${pace.toStringAsFixed(2)} | cue=${cue.isEmpty ? "none" : cue} | text="${ttsText.substring(0, ttsText.length.clamp(0, 180))}"');
    if (ttsText.isEmpty) return false;

    final t = ttsText.length > 300 ? '${ttsText.substring(0, 297)}...' : ttsText;
    final pitch = (voiceProfile?['pitch'] as num?)?.toDouble() ?? 1.0;
    final volume = (voiceProfile?['volume'] as num?)?.toDouble() ?? 1.0;
    final h = _hash(
      '$mood|${intensity.toStringAsFixed(2)}|${pace.toStringAsFixed(2)}|${pitch.toStringAsFixed(2)}|${volume.toStringAsFixed(2)}|$t',
    );

    if (_isPlaying && _currentHash == h) {
      await stop();
      return false;
    }
    await stop();

    try {
      _isLoading = true;
      _currentHash = h;

      if (_apiKey.isEmpty) {
        debugPrint('[TTS] Missing YSHOP_TTS_API_KEY - ElevenLabs is disabled');
        if (_allowBrowserFallback && kIsWeb) {
          debugPrint('[TTS] Browser fallback is enabled explicitly');
          _isLoading = false;
          _isPlaying = true;
          _playbackCompleter = Completer<void>();
          final started = await _webSpeech.speak(ttsText, onDone: () {
            debugPrint('[TTS] Browser speech complete');
            _isPlaying = false;
            _currentHash = null;
            if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
              _playbackCompleter!.complete();
            }
          });

          if (started) return true;
        }

        _isLoading = false;
        _isPlaying = false;
        _currentHash = null;
        return false;
      }

      Uint8List? bytes;
      if (_cache.containsKey(h)) {
        debugPrint('[TTS] Cache hit: $h');
        bytes = _cache[h];
      } else {
        debugPrint('[TTS] Calling ElevenLabs...');
        bytes = await _callAPI(t, voiceMood: mood, voiceIntensity: intensity, voiceProfile: voiceProfile);
        if (bytes != null && bytes.length > 1000) {
          debugPrint('[TTS] Audio received | bytes=${bytes.length} | hash=$h');
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

  Future<Uint8List?> _callAPI(String text, {String voiceMood = 'neutral', double voiceIntensity = 0.65, Map<String, dynamic>? voiceProfile}) async {
    try {
      if (_apiKey.isEmpty) {
        debugPrint('[TTS] No API key');
        return null;
      }

      final profileMood = _normalizeVoiceMood((voiceProfile?['emotion'] as String?) ?? voiceMood);
      final profile = _voiceProfile(profileMood, _clamp((voiceProfile?['energy'] as num?)?.toDouble() ?? voiceIntensity, 0.0, 1.0));
      final pace = (voiceProfile?['pace'] as num?)?.toDouble();
      final volume = (voiceProfile?['volume'] as num?)?.toDouble();
      final pitch = (voiceProfile?['pitch'] as num?)?.toDouble();

      // Free-plan fallback voice (George) — used when selected voice returns 402
      const String _freeVoiceId = 'JBFqnCBsd6RMkjVDRZzb';

      Future<http.Response> _doRequest(String voiceId) => http.post(
        Uri.parse('$_baseUrl/text-to-speech/$voiceId'),
        headers: {
          'xi-api-key': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_turbo_v2_5',
          'voice_settings': {
            'stability': profile.stability,
            'similarity_boost': profile.similarityBoost,
            'style': profile.style,
            'use_speaker_boost': true,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[TTS] ElevenLabs profile | mood=$profileMood | pace=${pace?.toStringAsFixed(2) ?? "default"} | volume=${volume?.toStringAsFixed(2) ?? "default"} | pitch=${pitch?.toStringAsFixed(2) ?? "default"}');

      var r = await _doRequest(_activePersonality.voiceId);

      // 402 = library voice needs paid plan → retry with free fallback voice
      if (r.statusCode == 402 && _activePersonality.voiceId != _freeVoiceId) {
        final failedId = _activePersonality.voiceId;
        final failedName = _activePersonality.name;
        // Remember this voice as unavailable so it won't be picked again
        _failedVoiceIds.add(failedId);
        // Switch active personality to the fallback so name matches voice
        _activePersonality = personalities.firstWhere(
          (p) => p.voiceId == _freeVoiceId,
          orElse: () => personalities[0],
        );
        debugPrint('[TTS] 402 for $failedName ($failedId) — switched to ${_activePersonality.name}, retrying');
        r = await _doRequest(_freeVoiceId);
      }

      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        debugPrint('[TTS] Got ${r.bodyBytes.length} bytes');
        return r.bodyBytes;
      }
      debugPrint('[TTS] API ${r.statusCode} | body=${r.body.substring(0, r.body.length.clamp(0, 300))}');
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
      _webSpeech.stop();
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