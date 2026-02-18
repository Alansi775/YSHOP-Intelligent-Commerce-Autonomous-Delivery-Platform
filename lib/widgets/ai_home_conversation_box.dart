// lib/widgets/ai_home_conversation_box.dart
//
// FIXES: RenderFlex overflow during expand animation
// NEW: Voice button with STT + ElevenLabs TTS
//
// Usage in category_home_view.dart — replace the old _buildAISearchBar() Positioned with:
//
//   Positioned(
//     top: 140,
//     left: MediaQuery.of(context).size.width * 0.15,
//     right: MediaQuery.of(context).size.width * 0.15,
//     child: AIHomeConversationBox(
//       onSearch: _performAISearch,
//       onAddToCart: _handleAddToCart,
//       messages: _aiMessages,
//       isExpanded: _isAIExpanded,
//       onToggleExpand: (val) {
//         setState(() => _isAIExpanded = val);
//         if (val) _aiExpandAnimation.forward();
//       },
//       onCollapse: _handleCollapseConversation,
//       onNewConversation: _startNewConversation,
//       aiSearchController: _aiSearchController,
//       aiSearchFocusNode: _aiSearchFocusNode,
//       sendButtonAnimation: _sendButtonAnimation,
//     ),
//   ),
//
// Then DELETE from category_home_view.dart these old methods:
//   _buildAISearchBar, _buildCollapsedSearchBar, _buildExpandedConversation,
//   _buildEmptyState, _buildMessagesList, _buildMessageBubble,
//   _buildUserBubble, _buildAIBubble, _buildLoadingAnimation,
//   _buildDot, _buildProductMessage, _buildMessageInput

import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/liquid_ai_icon.dart';
import '../models/product.dart';
import '../screens/customers/product_detail_view.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../widgets/ai_voice_call_overlay.dart';

class AIHomeConversationBox extends StatefulWidget {
  final Future<void> Function(String) onSearch;
  final void Function(dynamic) onAddToCart;
  final List<Map<String, dynamic>> messages;
  final bool isExpanded;
  final void Function(bool) onToggleExpand;
  final VoidCallback onCollapse;
  final VoidCallback onNewConversation;
  final TextEditingController aiSearchController;
  final FocusNode aiSearchFocusNode;
  final AnimationController sendButtonAnimation;

  const AIHomeConversationBox({
    Key? key,
    required this.onSearch,
    required this.onAddToCart,
    required this.messages,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCollapse,
    required this.onNewConversation,
    required this.aiSearchController,
    required this.aiSearchFocusNode,
    required this.sendButtonAnimation,
  }) : super(key: key);

  @override
  State<AIHomeConversationBox> createState() => _AIHomeConversationBoxState();
}

class _AIHomeConversationBoxState extends State<AIHomeConversationBox>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TTSService _tts = TTSService();
  final STTService _stt = STTService();

  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  bool _isListening = false;
  String _partialSpeech = '';
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeInOutCubic,
    );
    if (widget.isExpanded) _expandCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(AIHomeConversationBox old) {
    super.didUpdateWidget(old);
    if (widget.isExpanded && !old.isExpanded) _expandCtrl.forward();
    if (!widget.isExpanded && old.isExpanded) _expandCtrl.reverse();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _expandCtrl.dispose();
    super.dispose();
  }

  void _handleSend() {
    final q = widget.aiSearchController.text.trim();
    if (q.isEmpty) return;
    widget.aiSearchController.clear();
    widget.onSearch(q);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ── Voice STT ──
  bool _voiceSent = false; // guard against double-send

  Future<void> _startVoice() async {
    final ok = await _stt.initialize();
    if (!ok) return;

    _voiceSent = false;
    setState(() { _isListening = true; _partialSpeech = ''; });

    await _stt.startListening(onResult: (text, isFinal) {
      if (!mounted) return;
      setState(() => _partialSpeech = text);

      if (isFinal && text.trim().isNotEmpty && !_voiceSent) {
        _voiceSent = true;
        setState(() => _isListening = false);
        widget.aiSearchController.text = text;
        Future.delayed(const Duration(milliseconds: 200), _handleSend);
      }
    });
  }

  Future<void> _stopVoice() async {
    // Stop listening — the STT service will deliver partial as final
    final hadPartial = _partialSpeech.trim().isNotEmpty;
    await _stt.stopListening();

    if (!mounted) return;
    setState(() => _isListening = false);

    // If STT didn't auto-send but we have text, send it now
    if (hadPartial && !_voiceSent) {
      _voiceSent = true;
      widget.aiSearchController.text = _partialSpeech.trim();
      Future.delayed(const Duration(milliseconds: 200), _handleSend);
    }
  }

  // ── Voice TTS ──
  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    final ok = await _tts.speak(text);
    if (!ok && mounted) {
      setState(() => _isSpeaking = false);
    }
    // The TTS service calls onDone internally which sets isPlaying = false.
    // We poll briefly to detect when playback ends.
    if (ok) {
      _pollPlaybackEnd();
    }
  }

  void _pollPlaybackEnd() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (!_tts.isPlaying) {
        setState(() => _isSpeaking = false);
      } else {
        _pollPlaybackEnd();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD — uses AnimatedBuilder to smoothly transition
  //  height from 56→480, content fades in/out to prevent
  //  overflow during transition.
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isExpanded ? null : () {
        widget.onToggleExpand(true);
        widget.aiSearchFocusNode.requestFocus();
      },
      child: AnimatedBuilder(
        animation: _expandAnim,
        builder: (context, _) {
          final t = _expandAnim.value;
          final h = 56.0 + 424.0 * t;
          final r = 28.0 - 6.0 * t;

          return Container(
            height: h,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(
                color: Colors.white.withOpacity(0.12 + 0.03 * t),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2 + 0.2 * t),
                  blurRadius: 25 + 25 * t,
                  spreadRadius: 5 * t,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 15 + 15 * t,
                  sigmaY: 15 + 15 * t,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.10 - 0.02 * t),
                        Colors.white.withOpacity(0.05 - 0.02 * t),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // COLLAPSED (fades out fast)
                      Opacity(
                        opacity: (1 - t * 3).clamp(0.0, 1.0),
                        child: IgnorePointer(
                          ignoring: t > 0.3,
                          child: _collapsed(),
                        ),
                      ),
                      // EXPANDED (fades in after collapsed is gone)
                      Opacity(
                        opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0),
                        child: IgnorePointer(
                          ignoring: t < 0.5,
                          child: SizedBox.expand(child: _expanded()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  Widget _collapsed() {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const LiquidAIIcon(size: 26),
            const SizedBox(width: 12),
            Text('What would you like today?',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
            const Spacer(),
            // Voice call button
            GestureDetector(
              onTap: () => AIVoiceCallOverlay.show(context),
              child: Icon(Icons.mic_none_rounded, color: Colors.white.withOpacity(0.35), size: 18),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.2), size: 14),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  Widget _expanded() {
    return Column(
      children: [
        _header(),
        Container(height: 0.5, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: widget.messages.isEmpty ? _empty() : _messagesList(),
        ),
        if (_isListening) _listeningBar(),
        _inputBar(),
      ],
    );
  }

  // ── Header ──
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        children: [
          const LiquidAIIcon(size: 24),
          const SizedBox(width: 10),
          Text('YSHOP AI', style: TextStyle(
            fontFamily: 'CinzelDecorative', color: Colors.white.withOpacity(0.9),
            fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.5,
          )),
          const Spacer(),
          if (widget.messages.isNotEmpty)
            GestureDetector(
              onTap: widget.onNewConversation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.3), size: 18),
              ),
            ),
          GestureDetector(
            onTap: widget.onCollapse,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06), shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty ──
  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LiquidAIIcon(size: 44),
          const SizedBox(height: 14),
          Text('How can I help?', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 14)),
          const SizedBox(height: 6),
          Text('Type or tap the mic icon down to speak', style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11)),
        ],
      ),
    );
  }

  // ── Messages ──
  Widget _messagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      itemCount: widget.messages.length,
      itemBuilder: (_, i) {
        final m = widget.messages[i];
        if (m['type'] == 'loading') return _loadingDots();
        if (m['type'] == 'product' && m['products'] != null) return _productList(m['products']);
        return _bubble(m);
      },
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isUser = m['role'] == 'user';
    final text = m['text'] ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: 10, left: isUser ? 40 : 0, right: isUser ? 0 : 40),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: isUser ? _userBubble(text) : _aiBubble(text),
      ),
    );
  }

  Widget _userBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18), topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(text, style: const TextStyle(
        color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500, height: 1.4,
      )),
    );
  }

  Widget _aiBubble(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3, right: 8),
          child: LiquidAIIcon(size: 18),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Text(text, style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.45,
                )),
              ),
              // 🔊 Listen button
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: GestureDetector(
                    onTap: () => _speakText(text),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                          color: Colors.white.withOpacity(0.25), size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isSpeaking ? 'Stop' : 'Listen',
                          style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _loadingDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 3, right: 8), child: LiquidAIIcon(size: 18, isThinking: true)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4), topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: const _ThinkDots(),
          ),
        ],
      ),
    );
  }

  // ── Listening bar ──
  Widget _listeningBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF2563EB).withOpacity(0.15),
          const Color(0xFF7C3AED).withOpacity(0.1),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Animated AI orb while listening
          const LiquidAIIcon(size: 32, isThinking: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Listening...', style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600,
                )),
                if (_partialSpeech.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(_partialSpeech, style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 11, fontStyle: FontStyle.italic,
                  ), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: _stopVoice,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.stop_rounded, color: Colors.redAccent.withOpacity(0.8), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Products ──
  Widget _productList(List<dynamic> products) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 10),
      child: Column(
        children: products.map<Widget>((p) {
          final name = p['name'] ?? 'Product';
          final price = p['price']?.toString() ?? '0';
          final currency = p['currency'] ?? 'TRY';
          final imageUrl = p['image'] ?? p['image_url'];
          final stock = (p['stock'] as int?) ?? 10;
          final reason = p['reason'] ?? '';

          final model = Product(
            id: p['id']?.toString() ?? '', storeId: p['store_id']?.toString() ?? '',
            name: name, description: p['description'] ?? '',
            price: double.tryParse(price) ?? 0.0, currency: currency,
            imageUrl: imageUrl ?? '', stock: stock,
            categoryId: p['category_id']?.toString(),
            storeName: p['store_name'] ?? p['storeName'],
            storeOwnerEmail: p['store_owner_email'] ?? p['storeOwnerEmail'],
            status: 'approved', isActive: true,
          );

          return GestureDetector(
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProductDetailView(product: model))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.03),
                ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 56, height: 56,
                      color: Colors.white.withOpacity(0.04),
                      child: imageUrl != null && imageUrl.toString().isNotEmpty
                          ? Image.network(imageUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder())
                          : _placeholder(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (reason.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(reason, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$price $currency', style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w700)),
                            if (stock > 0)
                              GestureDetector(
                                onTap: () => widget.onAddToCart(p),
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1), shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: Icon(Icons.add_rounded, color: Colors.white.withOpacity(0.7), size: 14),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.12), size: 18),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: Icon(Icons.shopping_bag_outlined, color: Colors.white.withOpacity(0.15), size: 22),
  );

  // ── Input bar ──
  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          // 🎙️ Voice call button
          GestureDetector(
            onTap: () => AIVoiceCallOverlay.show(context),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Icon(
                Icons.mic_none_rounded,
                color: Colors.white.withOpacity(0.35),
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.aiSearchController,
              focusNode: widget.aiSearchFocusNode,
              cursorColor: Colors.white70,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              onChanged: (v) {
                if (v.isNotEmpty && !widget.sendButtonAnimation.isCompleted) widget.sendButtonAnimation.forward();
                else if (v.isEmpty && widget.sendButtonAnimation.isCompleted) widget.sendButtonAnimation.reverse();
              },
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          FadeTransition(
            opacity: widget.sendButtonAnimation,
            child: ScaleTransition(
              scale: widget.sendButtonAnimation,
              child: GestureDetector(
                onTap: _handleSend,
                child: Container(
                  width: 34, height: 34,
                  decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
class _PulsingMic extends StatefulWidget {
  const _PulsingMic();
  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Transform.scale(
          scale: 1.0 + _c.value * 0.15,
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.25),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(_c.value * 0.3), blurRadius: 12, spreadRadius: 2)],
            ),
            child: Icon(Icons.mic_rounded, color: Colors.white.withOpacity(0.9), size: 14),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
class _ThinkDots extends StatefulWidget {
  const _ThinkDots();
  @override
  State<_ThinkDots> createState() => _ThinkDotsState();
}

class _ThinkDotsState extends State<_ThinkDots> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_c.value + i * 0.2) % 1.0);
            final s = 0.5 + 0.5 * math.sin(t * math.pi);
            final o = 0.3 + 0.7 * math.sin(t * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.scale(scale: s, child: Opacity(
                opacity: o.clamp(0.0, 1.0),
                child: Container(width: 5, height: 5, decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withOpacity(0.6),
                )),
              )),
            );
          }),
        );
      },
    );
  }
}