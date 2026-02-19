// lib/widgets/ai_voice_call_overlay.dart
//
//  AI VOICE CALL V2 — Consistent with app design
//
// Features:
//   - Ferrofluid orb (black/white) as centerpiece
//   - Mute button (pause listening, stay in call)
//   - Replay button (repeat last AI response from cache)
//   - End button (DJI style)
//   - Dark gradient background matching conversation box
//   - Auto loop: listen → think → speak → listen
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/api_service.dart';
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
  String _lastAiResponse = ''; // for replay
  double _audioLevel = 0.0;
  List<Map<String, dynamic>>? _products;
  bool _isActive = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
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
    _tts.stop();
    _stt.stopListening();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  CALL LOOP
  // ═══════════════════════════════════════════
  void _startCall() { _isActive = true; _listen(); }

  void _endCall() {
    _isActive = false;
    _tts.stop();
    _stt.stopListening();
    _entryCtrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Mute toggle ──
  void _toggleMute() {
    if (_isMuted) {
      // Unmute — resume listening
      setState(() { _isMuted = false; _phase = _Phase.idle; });
      _listen();
    } else {
      // Mute — stop everything but stay in call
      _tts.stop();
      _stt.stopListening();
      setState(() {
        _isMuted = true;
        _phase = _Phase.muted;
        _audioLevel = 0.0;
      });
    }
  }

  // ── Replay last response (from TTS cache) ──
  void _replayLast() {
    if (_lastAiResponse.isEmpty) return;
    _tts.stop();
    _stt.stopListening();
    setState(() {
      _phase = _Phase.speaking;
      _transcript = '';
    });
    _speak(_lastAiResponse);
  }

  // ── LISTEN ──
  Future<void> _listen() async {
    if (!_isActive || !mounted || _isMuted) return;
    setState(() {
      _phase = _Phase.listening;
      _transcript = '';
      _audioLevel = 0.0;
    });

    final ok = await _stt.initialize();
    if (!ok || !_isActive) return;

    bool sent = false;
    await _stt.startListening(onResult: (text, isFinal) {
      if (!mounted || !_isActive || _isMuted) return;
      setState(() {
        _transcript = text;
        _audioLevel = text.isNotEmpty ? (text.length % 7) / 7.0 * 0.6 + 0.3 : 0.1;
      });
      if (isFinal && text.trim().isNotEmpty && !sent) {
        sent = true;
        _process(text.trim());
      }
    });
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
        final msg = data['message'] as String? ?? '';
        final prods = data['products'] as List?;
        if (prods != null && prods.isNotEmpty) {
          setState(() => _products = prods.cast<Map<String, dynamic>>());
        }
        _lastAiResponse = msg;
        _speak(msg);
      } else {
        _speak("Sorry, please try again.");
      }
    } catch (_) {
      if (mounted && _isActive) _speak("Connection error.");
    }
  }

  // ── SPEAK ──
  Future<void> _speak(String text) async {
    if (!_isActive || !mounted) return;
    setState(() { _phase = _Phase.speaking; _audioLevel = 0.4; });

    final ok = await _tts.speak(text);
    if (ok) {
      _animateSpeech();
      while (_tts.isPlaying && _isActive && mounted && !_isMuted) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    if (_isActive && mounted && !_isMuted) {
      setState(() => _audioLevel = 0.0);
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isActive && mounted && !_isMuted) _listen();
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background (matches conversation box dark theme) ──
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0A0F1E),
                      Color(0xFF0E1525),
                      Color(0xFF080D18),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    const Spacer(flex: 3),
                    // ── THE ORB ──
                    LiquidOrbVisualizer(
                      size: 220,
                      phase: _mapPhase(),
                      audioLevel: _audioLevel,
                    ),
                    const SizedBox(height: 28),
                    _statusText(),
                    const SizedBox(height: 10),
                    _liveText(),
                    const Spacer(flex: 1),
                    if (_products != null && _products!.isNotEmpty) _productStrip(),
                    const Spacer(flex: 1),
                    _controlButtons(),
                    const SizedBox(height: 44),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  VoicePhase _mapPhase() {
    switch (_phase) {
      case _Phase.listening: return VoicePhase.listening;
      case _Phase.thinking: return VoicePhase.thinking;
      case _Phase.speaking: return VoicePhase.speaking;
      case _Phase.idle: return VoicePhase.idle;
      case _Phase.muted: return VoicePhase.idle;
    }
  }

  // ── Top bar ──
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          Text('YSHOP AI', style: TextStyle(
            fontFamily: 'CinzelDecorative', fontSize: 13, fontWeight: FontWeight.w600,
            letterSpacing: 2, color: Colors.white.withOpacity(0.5),
          )),
          const Spacer(),
          _pillBadge(),
        ],
      ),
    );
  }

  Widget _pillBadge() {
    final color = _isMuted ? Colors.orange : _phaseColor();
    final label = _isMuted ? 'MUTED' :
        _phase == _Phase.listening ? 'LIVE' : _phase.name.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          letterSpacing: 1, color: color)),
      ]),
    );
  }

  Color _phaseColor() {
    switch (_phase) {
      case _Phase.listening: return const Color(0xFF2563EB);
      case _Phase.thinking: return const Color(0xFF8B5CF6);
      case _Phase.speaking: return const Color(0xFF10B981);
      default: return Colors.white.withOpacity(0.4);
    }
  }

  // ── Status ──
  Widget _statusText() {
    String s;
    switch (_phase) {
      case _Phase.listening: s = 'Listening...'; break;
      case _Phase.thinking: s = 'Thinking...'; break;
      case _Phase.speaking: s = 'Speaking...'; break;
      case _Phase.muted: s = 'Muted'; break;
      case _Phase.idle: s = 'Starting...'; break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(s, key: ValueKey(s), style: TextStyle(
        fontFamily: 'TenorSans', fontSize: 15,
        color: Colors.white.withOpacity(0.5), letterSpacing: 0.5)),
    );
  }

  Widget _liveText() {
    final t = _phase == _Phase.listening ? _transcript :
              _phase == _Phase.speaking ? _lastAiResponse : '';
    if (t.isEmpty) return const SizedBox(height: 20);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(t, textAlign: TextAlign.center, maxLines: 3,
        overflow: TextOverflow.ellipsis, style: TextStyle(
          fontSize: 13, height: 1.5,
          color: _phase == _Phase.listening
              ? Colors.white.withOpacity(0.85)
              : Colors.white.withOpacity(0.4),
          fontStyle: _phase == _Phase.speaking ? FontStyle.italic : FontStyle.normal,
        )),
    );
  }

  // ── Products ──
  Widget _productStrip() {
    return SizedBox(
      height: 86,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _products!.length,
        itemBuilder: (_, i) => _productChip(_products![i]),
      ),
    );
  }

  Widget _productChip(Map<String, dynamic> p) {
    final name = p['name'] ?? '';
    final price = p['price']?.toString() ?? '0';
    final currency = p['currency'] ?? 'TRY';
    final img = p['image_url'] ?? p['image'];
    final stock = (p['stock'] as int?) ?? 0;

    return GestureDetector(
      onTap: () {
        _tts.stop(); _stt.stopListening(); _isActive = false;
        final m = Product(
          id: p['id']?.toString() ?? '', storeId: p['store_id']?.toString() ?? '',
          name: name, description: p['description'] ?? '',
          price: double.tryParse(price) ?? 0.0, currency: currency,
          imageUrl: img ?? '', stock: stock,
          categoryId: p['category_id']?.toString(),
          storeName: p['store_name'] ?? p['storeName'],
          storeOwnerEmail: p['store_owner_email'] ?? p['storeOwnerEmail'],
          status: 'approved', isActive: true,
        );
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ProductDetailView(product: m),
        )).then((_) { if (mounted) { _isActive = true; _listen(); } });
      },
      child: Container(
        width: 185, margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 50, height: 50, color: Colors.white.withOpacity(0.04),
              child: img != null ? Image.network(img, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ph()) : _ph(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('$price $currency', style: const TextStyle(
                color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          )),
          if (stock > 0)
            GestureDetector(
              onTap: () => _addToCart(p),
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Icon(Icons.add_rounded, color: Colors.white.withOpacity(0.6), size: 14),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _ph() => Icon(Icons.shopping_bag_outlined, color: Colors.white.withOpacity(0.15), size: 18);

  // ═══════════════════════════════════════════
  //  CONTROL BUTTONS
  // ═══════════════════════════════════════════
  Widget _controlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Replay button
        _glassButton(
          icon: Icons.replay_rounded,
          label: 'Replay',
          onTap: _lastAiResponse.isNotEmpty ? _replayLast : null,
          enabled: _lastAiResponse.isNotEmpty,
        ),
        const SizedBox(width: 20),
        // End button (center, bigger)
        _endButton(),
        const SizedBox(width: 20),
        // Mute button
        _glassButton(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? 'Unmute' : 'Mute',
          onTap: _toggleMute,
          isActive: _isMuted,
        ),
      ],
    );
  }

  Widget _glassButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
    bool isActive = false,
  }) {
    final opacity = enabled ? 1.0 : 0.3;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.orange.withOpacity(0.15)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isActive
                          ? Colors.orange.withOpacity(0.3)
                          : Colors.white.withOpacity(0.1)),
                  ),
                  child: Icon(icon,
                    color: isActive
                        ? Colors.orange.withOpacity(0.9)
                        : Colors.white.withOpacity(0.6),
                    size: 22),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
              fontSize: 10, color: Colors.white.withOpacity(0.4),
              letterSpacing: 0.3,
            )),
          ],
        ),
      ),
    );
  }

  Widget _endButton() {
    return GestureDetector(
      onTap: _endCall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.35)),
                ),
                child: const Icon(Icons.call_end_rounded,
                    color: Color(0xFFFCA5A5), size: 24),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('End', style: TextStyle(
            fontSize: 10, color: Colors.white.withOpacity(0.4),
            letterSpacing: 0.3)),
        ],
      ),
    );
  }
}