// lib/widgets/ai_voice_call_overlay.dart
//
//  AI VOICE CALL V2 — Smoke Orb Edition
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/api_service.dart';
import '../services/image_cache_manager.dart';
import '../state_management/auth_manager.dart';
import '../state_management/cart_manager.dart';
import '../models/product.dart';
import '../widgets/liquid_orb_visualizer.dart';
import '../widgets/centered_notification.dart';
import '../screens/customers/product_detail_view.dart';

class AIVoiceCallOverlay {
  static void show(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: const _CallScreen(),
      ),
    ));
  }
}

enum _Phase { listening, thinking, speaking, idle, muted }

class _CallScreen extends StatefulWidget {
  const _CallScreen();
  @override
  State<_CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<_CallScreen> with TickerProviderStateMixin {
  final TTSService _tts = TTSService();
  final STTService _stt = STTService();

  late AnimationController _entryCtrl;

  _Phase _phase = _Phase.idle;
  String _transcript = '';
  String _lastAiResponse = '';      // raw → TTS engine
  String _lastAiDisplayText = '';   // clean → screen
  String _lastAiVoiceMood = 'neutral';
  double _lastAiVoiceIntensity = 0.65;
  String _lastAiVoiceCue = '';
  Map<String, dynamic>? _lastAiVoiceProfile;
  String _lastConversationStage = 'browsing';
  double _audioLevel = 0.0;
  List<Map<String, dynamic>>? _products;
  bool _isActive = false;
  bool _isMuted = false;
  bool _isProcessing = false;       // prevents double-send from STT

  // Silence detection — prompt user if they stay quiet too long
  Timer? _silenceTimer;
  int _silenceStreak = 0;

  // Interruption — user speaks while AI is talking
  bool _interrupted = false;

  late VoicePersonality _voicePersonality;

  @override
  void initState() {
    super.initState();
    // Pick a fresh random voice every time the overlay opens
    _voicePersonality = _tts.selectRandomPersonality();
    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    )..forward();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _startCall();
    });
  }

  @override
  void dispose() {
    _isActive = false;
    _silenceTimer?.cancel();
    _tts.stop();
    _stt.stopListening();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  CALL LOOP
  // ═══════════════════════════════════════════
  void _startCall() {
    _isActive = true;
    _greetAndListen();
  }

  // Speaks the greeting and retries with the correct name if 402 switches the voice.
  // This prevents a male voice from saying a female name (or vice versa).
  Future<void> _greetAndListen() async {
    String name = _voicePersonality.name;
    for (int attempt = 0; attempt < 2; attempt++) {
      final greeting = "Hey! I'm $name, your YSHOP assistant. What can I help you find today?";
      if (mounted) setState(() { _lastAiDisplayText = greeting; _lastAiResponse = greeting; });
      // autoListen: false — we control the listen transition ourselves
      await _speak(greeting, voiceMood: 'warm', voiceIntensity: 0.72, autoListen: false);
      final actual = _tts.currentPersonality;
      if (actual.voiceId != _voicePersonality.voiceId && mounted) {
        // 402 fallback switched voice — re-greet with the new name
        setState(() => _voicePersonality = actual);
        name = actual.name;
        debugPrint('[Overlay] Voice switched to ${actual.name} (${actual.gender}) — re-greeting');
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        break; // Voice stayed the same — greeting is correct
      }
    }
    if (_isActive && mounted && !_interrupted) _transitionToListening();
  }

  void _endCall() {
    _isActive = false;
    _silenceTimer?.cancel();
    _tts.stop();
    _stt.stopListening();
    _entryCtrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _toggleMute() {
    if (_isMuted) {
      setState(() { _isMuted = false; _phase = _Phase.idle; });
      _listen();
    } else {
      _tts.stop();
      _stt.stopListening();
      setState(() {
        _isMuted = true;
        _phase = _Phase.muted;
        _audioLevel = 0.0;
      });
    }
  }

  void _replayLast() {
    if (_lastAiResponse.isEmpty) return;
    _tts.stop();
    _stt.stopListening();
    setState(() {
      _phase = _Phase.speaking;
      _transcript = '';
    });
    _speak(
      _lastAiResponse,
      voiceMood: _lastAiVoiceMood,
      voiceIntensity: _lastAiVoiceIntensity,
      voiceCue: _lastAiVoiceCue,
    );
  }

  // ── LISTEN ──
  Future<void> _listen() async {
    if (!_isActive || !mounted || _isMuted) return;

    _isProcessing = false;
    _cancelSilenceTimer();

    setState(() {
      _phase = _Phase.listening;
      _transcript = '';
      _audioLevel = 0.0;
    });

    final ok = await _stt.initialize();
    if (!ok || !_isActive) return;

    // Start silence detection — fire after 9s of no speech
    _silenceTimer = Timer(const Duration(seconds: 9), _onSilence);

    await _stt.startListening(onResult: (text, isFinal) {
      if (!mounted || !_isActive || _isMuted) return;
      if (_isProcessing) return;

      // User spoke — cancel silence timer
      if (text.isNotEmpty) _cancelSilenceTimer();

      setState(() {
        _transcript = text;
        _audioLevel = text.isNotEmpty ? (text.length % 7) / 7.0 * 0.6 + 0.3 : 0.1;
      });

      if (isFinal && text.trim().isNotEmpty) {
        _isProcessing = true;
        _silenceStreak = 0; // reset streak when user actually speaks
        _process(text.trim());
      }
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  Future<void> _onSilence() async {
    if (!_isActive || !mounted || _isMuted || _phase != _Phase.listening) return;

    _silenceStreak++;
    await _stt.stopListening();

    final String msg;
    if (_silenceStreak == 1) {
      msg = "Still there? I'm here whenever you're ready.";
    } else if (_silenceStreak == 2) {
      msg = "No rush at all — just say something whenever you like.";
    } else {
      msg = "I'll be here if you need me. Feel free to speak up anytime!";
      _silenceStreak = 0;
    }

    setState(() { _lastAiDisplayText = msg; });
    _lastAiResponse = msg;
    await _speak(msg, voiceMood: 'warm', voiceIntensity: 0.50);
    // _speak → _transitionToListening → _listen() automatically
  }

  // ── THINK ──
  Future<void> _process(String text) async {
    if (!_isActive || !mounted) return;
    await _stt.stopListening();
    setState(() { _phase = _Phase.thinking; _audioLevel = 0.15; });

    try {
      final auth = Provider.of<AuthManager>(context, listen: false);
      final userId = auth.userProfile?['id'] ?? 'guest';
      final resp = await ApiService.postRequest(
        '/ai/chat', {'message': text, 'userId': userId, 'language': 'auto'},
      );
      if (!mounted || !_isActive) return;

      if (resp['success'] == true && resp['data'] != null) {
        final data = resp['data'];
        final meta = resp['meta'] as Map?;
        final traceId = meta?['traceId']?.toString() ?? 'unknown';
        final msg = data['message'] as String? ?? '';
        final voiceProfile = data['voiceProfile'] is Map ? Map<String, dynamic>.from(data['voiceProfile'] as Map) : null;
        final stage = data['conversationStage'] as String? ?? 'browsing';
        final mood = data['voiceMood'] as String? ?? 'neutral';
        final intensity = (data['voiceIntensity'] as num?)?.toDouble() ?? 0.65;
        final cue = data['voiceCue'] as String? ?? '';
        final prods = data['products'] as List?;

        debugPrint(
          '[Overlay] Backend | trace=$traceId | messageLen=${msg.length} | products=${prods?.length ?? 0} | stage=$stage | mood=$mood | intensity=${intensity.toStringAsFixed(2)} | cue=${cue.isEmpty ? "none" : cue}'
        );

        // Only update products when AI sends new ones
        if (prods != null && prods.isNotEmpty) {
          setState(() => _products = prods.cast<Map<String, dynamic>>());
        }

        _lastAiResponse = msg;
        _lastAiDisplayText = TTSService.cleanForDisplay(msg);
        _lastAiVoiceMood = mood;
        _lastAiVoiceIntensity = intensity;
        _lastAiVoiceCue = cue;
        _lastAiVoiceProfile = voiceProfile;
        _lastConversationStage = stage;

        final refined = _refineVoiceMetadata(
          text: msg,
          mood: mood,
          intensity: intensity,
          cue: cue,
          voiceProfile: voiceProfile,
        );

        debugPrint(
          '[Overlay] Speak | trace=$traceId | refinedMood=${refined.mood} | refinedIntensity=${refined.intensity.toStringAsFixed(2)} | refinedCue=${refined.cue.isEmpty ? "none" : refined.cue} | stage=$_lastConversationStage'
        );

        if (msg.isNotEmpty) {
          await _speak(
            msg,
            voiceMood: mood,
            voiceIntensity: intensity,
            voiceCue: cue,
            voiceProfile: voiceProfile,
          );
        } else {
          _transitionToListening();
        }

        // Farewell detected — show rating then close
        if (stage == 'farewell') {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) _showRatingAndEnd();
        }
      } else {
        _setResponse("Sorry, please try again.");
        await _speak(_lastAiResponse);
      }
    } catch (_) {
      if (mounted && _isActive) {
        _setResponse("Connection error.");
        await _speak(_lastAiResponse);
      }
    }
  }

  void _setResponse(String text) {
    _lastAiResponse = text;
    _lastAiDisplayText = TTSService.cleanForDisplay(text);
  }

  ({String mood, double intensity, String cue}) _refineVoiceMetadata({
    required String text,
    required String mood,
    required double intensity,
    required String cue,
    Map<String, dynamic>? voiceProfile,
  }) {
    var resolvedMood = (voiceProfile?['emotion'] as String? ?? mood).trim().toLowerCase();
    var resolvedIntensity = ((voiceProfile?['energy'] as num?)?.toDouble() ?? intensity).clamp(0.0, 1.0).toDouble();
    var resolvedCue = (voiceProfile?['cue'] as String? ?? cue).trim();

    final disallowedCuePrefixes = [
      'hey', 'hello', 'hi', 'ya hla', 'يا هلا', 'مرحبا', 'اهلا', 'أهلا',
    ];
    final loweredCue = resolvedCue.toLowerCase();
    if (disallowedCuePrefixes.any((prefix) => loweredCue == prefix || loweredCue.startsWith('$prefix '))) {
      resolvedCue = '';
    }

    if (resolvedMood == 'whisper' && resolvedCue.isEmpty) {
      resolvedCue = 'psst';
    }

    if (resolvedMood.isEmpty) {
      resolvedMood = 'neutral';
    }

    return (
      mood: resolvedMood,
      intensity: resolvedIntensity,
      cue: resolvedCue,
    );
  }

  // ── SPEAK ──
  // autoListen: false → caller handles transition (used by _greetAndListen)
  Future<void> _speak(String text, {String? voiceMood, double voiceIntensity = 0.65, String voiceCue = '', Map<String, dynamic>? voiceProfile, bool autoListen = true}) async {
    if (!_isActive || !mounted) return;

    _interrupted = false;

    final refined = _refineVoiceMetadata(
      text: text,
      mood: voiceMood ?? 'neutral',
      intensity: voiceIntensity,
      cue: voiceCue,
      voiceProfile: voiceProfile,
    );

    setState(() { _phase = _Phase.speaking; _audioLevel = 0.4; });

    final ok = await _tts.speak(
      text,
      voiceMood: refined.mood,
      voiceIntensity: refined.intensity,
      voiceCue: refined.cue,
      voiceProfile: voiceProfile,
    );

    if (ok) {
      _animateSpeech();
      // Open mic concurrently so user can interrupt — like real-time voice AI
      if (autoListen) _openInterruptMic();
      await _tts.waitForCompletion();
      await _stt.stopListening();
      debugPrint('[Overlay] TTS playback done | interrupted=$_interrupted');
    } else {
      debugPrint('[Overlay] TTS failed — keeping text visible');
      final readTime = (_lastAiDisplayText.length / 3 * 100).clamp(2000, 6000).toInt();
      await Future.delayed(Duration(milliseconds: readTime));
    }

    // Only transition normally if auto-listen mode and user didn't interrupt
    if (autoListen && !_interrupted && _isActive && mounted) {
      _transitionToListening();
    }
  }

  // ── Open mic during TTS playback (interruption detection) ──
  void _openInterruptMic() {
    if (_isMuted || !_isActive) return;
    // Initialize + listen in background — do not await
    _stt.initialize().then((ok) {
      if (!ok || !_isActive || !mounted || _isMuted) return;
      _stt.startListening(onResult: (text, isFinal) {
        if (!mounted || !_isActive || _isMuted || _interrupted) return;
        // Show live transcript while AI is speaking
        if (text.isNotEmpty) {
          setState(() { _transcript = text; });
        }
        // User said something substantial → interrupt AI
        if (isFinal && text.trim().length > 2 && _tts.isPlaying) {
          debugPrint('[Overlay] Interrupted! user="$text"');
          _interrupted = true;
          _isProcessing = true;
          _tts.stop(); // stops audio + unblocks waitForCompletion
          _process(text.trim());
        }
      });
    });
  }

  /// Smooth transition from speaking → listening with a natural pause
  void _transitionToListening() async {
    if (!_isActive || !mounted || _isMuted) return;

    // Brief pause — text stays visible during this
    // Phase stays as speaking so text remains on screen
    await Future.delayed(const Duration(milliseconds: 800));

    if (_isActive && mounted && !_isMuted) {
      _listen();
    }
  }

  void _animateSpeech() {
    if (!_isActive || !mounted || _phase != _Phase.speaking) return;
    setState(() => _audioLevel = 0.25 + math.Random().nextDouble() * 0.55);
    Future.delayed(const Duration(milliseconds: 130), _animateSpeech);
  }

  void _addToCart(Map<String, dynamic> p) {
    try {
      final cart = Provider.of<CartManager>(context, listen: false);
      final id = p['id'] as int?;
      if (id != null) {
        cart.addToCart(productId: id.toString(), product: p, quantity: 1);
        CenteredNotification.show(context, '"${p['name']}" added', success: true);
      }
    } catch (_) {}
  }

  // ── Rating sheet after farewell ──────────────────────────────────────────
  void _showRatingAndEnd() {
    _isActive = false;
    _silenceTimer?.cancel();
    _tts.stop();
    _stt.stopListening();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => _RatingSheet(
        voiceName: _voicePersonality.name,
        onDone: () {
          Navigator.of(context).pop(); // close sheet
          _entryCtrl.reverse().then((_) {
            if (mounted) Navigator.of(context).pop(); // close overlay
          });
        },
      ),
    );
  }

  // ── YSHOP Brand colors — single blue accent, black/white identity ─────────
  static const Color _yBlue   = Color(0xFF2196F3); // YSHOP primary blue
  static const Color _yBlueLt = Color(0xFF4FA8F5); // lighter tint for text
  static const Color _yMuted  = Color(0xFFF97316); // mute/warning orange

  // ═══════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _entryCtrl,
          builder: (_, child) => Opacity(opacity: _entryCtrl.value, child: child),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildBackground(),
                  SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isWide ? 500 : double.infinity),
                        child: Column(
                          children: [
                            _topBar(),
                            Spacer(flex: isWide ? 3 : 2),
                            _orbSection(isWide),
                            const SizedBox(height: 28),
                            _liveText(),
                            const Spacer(flex: 1),
                            if (_products != null && _products!.isNotEmpty) _productSection(),
                            const Spacer(flex: 1),
                            _controlRow(),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  VoicePhase _mapPhase() {
    switch (_phase) {
      case _Phase.listening: return VoicePhase.listening;
      case _Phase.thinking:  return VoicePhase.thinking;
      case _Phase.speaking:  return VoicePhase.speaking;
      case _Phase.idle:      return VoicePhase.idle;
      case _Phase.muted:     return VoicePhase.idle;
    }
  }

  // Single accent logic — YSHOP uses one blue, not a rainbow
  Color _phaseColor() => _isMuted ? _yMuted : _yBlue;

  // Opacity for the active indicator dot — pulses when active
  double _dotOpacity() {
    switch (_phase) {
      case _Phase.listening: return 1.0;
      case _Phase.thinking:  return 0.75;
      case _Phase.speaking:  return 0.90;
      default:               return 0.35;
    }
  }

  // ── Background — pure YSHOP dark ─────────────────────────────────────────
  Widget _buildBackground() {
    final isActive = _phase == _Phase.listening ||
        _phase == _Phase.speaking || _phase == _Phase.thinking;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid very-dark base — clean, not sci-fi
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0A0A), Color(0xFF050505)],
            ),
          ),
        ),
        // Single subtle YSHOP-blue glow at top — only when active
        if (isActive)
          Positioned(
            top: -80, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 320,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x0D2196F3), Color(0x002196F3)],
                    radius: 1.2,
                  ),
                ),
              ),
            ),
          ),
        // Bottom fade
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: IgnorePointer(
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Top bar — YSHOP brand identity ───────────────────────────────────────
  Widget _topBar() {
    final isActive = _phase == _Phase.listening ||
        _phase == _Phase.speaking || _phase == _Phase.thinking;
    final statusLabel = _isMuted ? 'MUTED'
        : _phase == _Phase.listening ? 'LIVE'
        : _phase == _Phase.thinking  ? 'THINKING'
        : _phase == _Phase.speaking  ? 'SPEAKING'
        : 'READY';
    final dotColor = _phaseColor();

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Brand mark — always black/white, never colored
          Text.rich(TextSpan(children: [
            const TextSpan(
              text: 'Y',
              style: TextStyle(
                fontFamily: 'CinzelDecorative', fontSize: 18,
                fontWeight: FontWeight.w700, color: Colors.white,
              ),
            ),
            TextSpan(
              text: 'SHOP',
              style: TextStyle(
                fontFamily: 'CinzelDecorative', fontSize: 12,
                fontWeight: FontWeight.w300, letterSpacing: 4,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
          ])),
          // Thin separator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 1, height: 16,
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          Text(
            'AI',
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 2.5, color: _yBlue.withOpacity(0.80),
            ),
          ),
          const SizedBox(width: 8),
          // Voice personality label — changes every session
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _voicePersonality.name,
              style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
          ),
          const Spacer(),
          // Status indicator — minimal dot + label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withOpacity(_dotOpacity()),
                  boxShadow: isActive || _isMuted
                      ? [BoxShadow(color: dotColor.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  statusLabel,
                  key: ValueKey(statusLabel),
                  style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    color: dotColor.withOpacity(_dotOpacity() * 0.85),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Orb section — grayscale smoke (YSHOP style) ───────────────────────────
  Widget _orbSection(bool isWide) {
    final orbSize = isWide ? 240.0 : 220.0;
    final ringSize = orbSize + 28;
    final isActive = _phase == _Phase.listening ||
        _phase == _Phase.speaking || _phase == _Phase.thinking;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring — subtle, elegant
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: ringSize, height: ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? Colors.white.withOpacity(0.06)
                      : Colors.white.withOpacity(0.03),
                  width: 1,
                ),
              ),
            ),
            // The orb — ALWAYS grayscale, no color modes
            LiquidOrbVisualizer(
              size: orbSize,
              phase: _mapPhase(),
              audioLevel: _audioLevel,
              colorful: false, // YSHOP: elegant grayscale smoke always
            ),
          ],
        ),
        const SizedBox(height: 20),
        _statusLabel(),
      ],
    );
  }

  Widget _statusLabel() {
    String label;
    switch (_phase) {
      case _Phase.listening: label = 'Listening'; break;
      case _Phase.thinking:  label = 'Thinking';  break;
      case _Phase.speaking:  label = 'Speaking';  break;
      case _Phase.muted:     label = 'Muted';     break;
      case _Phase.idle:      label = 'Starting';  break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        label,
        key: ValueKey(label),
        style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w300,
          letterSpacing: 1.5,
          color: Colors.white.withOpacity(0.38),
        ),
      ),
    );
  }

  // ── Live text ─────────────────────────────────────────────────────────────
  Widget _liveText() {
    String t;
    bool isUser;
    if (_phase == _Phase.listening && _transcript.isNotEmpty) {
      t = _transcript;
      isUser = true;
    } else if (_lastAiDisplayText.isNotEmpty &&
        (_phase == _Phase.speaking || _phase == _Phase.thinking ||
            (_phase == _Phase.listening && _transcript.isEmpty))) {
      t = _lastAiDisplayText;
      isUser = false;
    } else {
      return const SizedBox(height: 52);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: ClipRRect(
          key: ValueKey(t.hashCode),
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.white.withOpacity(0.06)
                    : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUser
                      ? Colors.white.withOpacity(0.09)
                      : _yBlue.withOpacity(0.10),
                  width: 1,
                ),
              ),
              child: Text(
                t,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14, height: 1.6,
                  fontWeight: isUser ? FontWeight.w500 : FontWeight.w300,
                  color: isUser
                      ? Colors.white.withOpacity(0.85)
                      : Colors.white.withOpacity(0.55),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Product section ───────────────────────────────────────────────────────
  Widget _productSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 12),
          child: Row(
            children: [
              Container(width: 16, height: 1, color: _yBlue.withOpacity(0.5)),
              const SizedBox(width: 8),
              Text(
                'FOR YOU',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  letterSpacing: 2.5, color: Colors.white.withOpacity(0.35),
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 16, height: 1, color: Colors.white.withOpacity(0.08)),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 24, right: 12),
            itemCount: _products!.length,
            itemBuilder: (_, i) => _productCard(_products![i]),
          ),
        ),
      ],
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final name = p['name'] ?? '';
    final price = p['price']?.toString() ?? '0';
    final currency = p['currency'] ?? 'TRY';
    final rawImg = p['image_url'] ?? p['image'];
    final img = Product.getFullImageUrl(rawImg?.toString());
    final stock = (p['stock'] as int?) ?? 0;
    final reason = (p['reason'] as String? ?? '').trim();

    return GestureDetector(
      onTap: () {
        _tts.stop(); _stt.stopListening(); _isActive = false;
        final m = Product(
          id: p['id']?.toString() ?? '',
          storeId: p['store_id']?.toString() ?? '',
          name: name, description: p['description'] ?? '',
          price: double.tryParse(price) ?? 0.0, currency: currency,
          imageUrl: img, stock: stock,
          categoryId: p['category_id']?.toString(),
          storeName: p['store_name'] ?? p['storeName'],
          storeOwnerEmail: p['store_owner_email'] ?? p['storeOwnerEmail'],
          status: 'approved', isActive: true,
        );
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProductDetailView(product: m)),
        ).then((_) { if (mounted) { _isActive = true; _listen(); } });
      },
      child: Container(
        width: 230,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
        ),
        child: Row(
          children: [
            // Image — full height left
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17), bottomLeft: Radius.circular(17),
              ),
              child: SizedBox(
                width: 90, height: double.infinity,
                child: img.isNotEmpty
                    ? CachedNetworkImage(
                        cacheManager: ImageCacheManager.instance,
                        imageUrl: img, fit: BoxFit.cover,
                        placeholder: (_, __) => _imagePlaceholder(),
                        errorWidget: (_, __, ___) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600, height: 1.3,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        if (reason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(reason,
                            style: TextStyle(
                              fontSize: 9.5, height: 1.3,
                              color: Colors.white.withOpacity(0.28),
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text('$price $currency',
                            style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: _yBlueLt, letterSpacing: -0.2,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (stock > 0)
                          GestureDetector(
                            onTap: () => _addToCart(p),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _yBlue.withOpacity(0.12),
                                border: Border.all(color: _yBlue.withOpacity(0.28)),
                              ),
                              child: const Icon(Icons.add_rounded, color: _yBlueLt, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
    color: Colors.white.withOpacity(0.03),
    child: Center(
      child: Icon(Icons.image_outlined, color: Colors.white.withOpacity(0.12), size: 24),
    ),
  );

  // ── Control row ───────────────────────────────────────────────────────────
  Widget _controlRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleBtn(
          icon: Icons.replay_rounded,
          label: 'Replay',
          onTap: _lastAiResponse.isNotEmpty ? _replayLast : null,
          enabled: _lastAiResponse.isNotEmpty,
        ),
        const SizedBox(width: 24),
        _endCallBtn(),
        const SizedBox(width: 24),
        _circleBtn(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? 'Unmute' : 'Mute',
          onTap: _toggleMute,
          active: _isMuted,
          activeColor: _yMuted,
        ),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
    bool active = false,
    Color? activeColor,
  }) {
    final color = active ? (activeColor ?? Colors.white) : Colors.white;
    return Opacity(
      opacity: enabled ? 1.0 : 0.20,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? color.withOpacity(0.12)
                        : Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: active
                          ? color.withOpacity(0.30)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Icon(icon, color: color.withOpacity(active ? 0.90 : 0.45), size: 22),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(label, style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w400, letterSpacing: 0.5,
              color: active ? color.withOpacity(0.60) : Colors.white.withOpacity(0.25),
            )),
          ],
        ),
      ),
    );
  }

  Widget _endCallBtn() {
    return GestureDetector(
      onTap: _endCall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 66, height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935).withOpacity(0.14),
                  border: Border.all(
                    color: const Color(0xFFE53935).withOpacity(0.28),
                  ),
                ),
                child: const Icon(Icons.call_end_rounded, color: Color(0xFFEF9A9A), size: 26),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text('End', style: TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w400, letterSpacing: 0.5,
            color: const Color(0xFFEF9A9A).withOpacity(0.40),
          )),
        ],
      ),
    );
  }
}

// ─── Rating Sheet — shown after farewell ────────────────────────────────────
class _RatingSheet extends StatefulWidget {
  final String voiceName;
  final VoidCallback onDone;
  const _RatingSheet({required this.voiceName, required this.onDone});
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 28),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3).withOpacity(0.12),
                border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.25)),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2196F3), size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              'How was ${widget.voiceName}?',
              style: const TextStyle(
                color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w600, letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Rate your YSHOP AI experience',
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return GestureDetector(
                  onTap: () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        key: ValueKey(filled),
                        size: 40,
                        color: filled ? const Color(0xFFFFC107) : Colors.white.withOpacity(0.25),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: widget.onDone,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: _stars > 0
                        ? const Color(0xFF2196F3)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _stars > 0 ? 'Submit Rating' : 'Skip',
                    style: TextStyle(
                      color: _stars > 0 ? Colors.white : Colors.white.withOpacity(0.45),
                      fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
