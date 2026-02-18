// lib/screens/customers/ai_shopping_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../state_management/theme_manager.dart';
import '../../state_management/auth_manager.dart';
import '../../state_management/cart_manager.dart';
import '../../services/api_service.dart';
import '../../widgets/liquid_ai_icon.dart';
import '../../widgets/centered_notification.dart';
import '../../providers/ai_conversation_provider.dart';
import '../../models/product.dart';
import '../../models/currency.dart';
import 'product_detail_view.dart';

// ═══════════════════════════════════════════════════════════════
// 🤖 AI SHOPPING VIEW — Immersive Conversational Commerce
// A revolutionary full-screen AI shopping assistant
// ═══════════════════════════════════════════════════════════════
class AIShoppingView extends StatefulWidget {
  const AIShoppingView({Key? key}) : super(key: key);

  @override
  State<AIShoppingView> createState() => _AIShoppingViewState();
}

class _AIShoppingViewState extends State<AIShoppingView>
    with TickerProviderStateMixin {
  late TextEditingController _searchController;
  late TextEditingController _replyController;
  late FocusNode _searchFocusNode;
  late FocusNode _replyFocusNode;
  late ScrollController _scrollController;

  late AnimationController _entryAnimation;
  late AnimationController _productAnimation;
  late AnimationController _pulseAnimation;
  late AnimationController _orbFloatAnimation;

  bool _isSearchActive = false;
  bool _isSearching = false;
  bool _hasResults = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _replyController = TextEditingController();
    _searchFocusNode = FocusNode();
    _replyFocusNode = FocusNode();
    _scrollController = ScrollController();

    _entryAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _productAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _orbFloatAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _entryAnimation.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replyController.dispose();
    _searchFocusNode.dispose();
    _replyFocusNode.dispose();
    _scrollController.dispose();
    _entryAnimation.dispose();
    _productAnimation.dispose();
    _pulseAnimation.dispose();
    _orbFloatAnimation.dispose();
    super.dispose();
  }

  // ── Actions ──
  void _handleClose() {
    _entryAnimation.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _handleSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _isSearchActive = false;
    });
    _performAISearch(query);
  }

  void _handleReply() {
    final reply = _replyController.text.trim();
    if (reply.isEmpty) return;
    _replyController.clear();
    setState(() => _isSearching = true);
    _performAISearch(reply);
  }

  void _startNewConversation() {
    final provider =
        Provider.of<AIConversationProvider>(context, listen: false);
    provider.startNewConversation();
    _searchController.clear();
    _replyController.clear();
    setState(() {
      _isSearching = false;
      _isSearchActive = false;
      _hasResults = false;
    });
  }

  Future<void> _performAISearch(String query) async {
    try {
      final conversationProvider =
          Provider.of<AIConversationProvider>(context, listen: false);
      final authManager = Provider.of<AuthManager>(context, listen: false);
      final userId = authManager.userProfile?['id'] ?? 'guest';

      conversationProvider.addMessage(role: 'user', message: query);

      final response = await ApiService.postRequest(
        '/ai/chat',
        {'message': query, 'userId': userId, 'language': 'auto'},
      );

      if (!mounted) return;

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        final products = data['products'] as List?;
        final message = data['message'] as String? ?? '';

        conversationProvider.addMessage(
          role: 'ai',
          message: message,
          products: products?.cast<Map<String, dynamic>>(),
        );

        if (products != null && products.isNotEmpty) {
          conversationProvider.setProducts(
            products.cast<Map<String, dynamic>>(),
            message,
          );
          _productAnimation.forward(from: 0);
          setState(() {
            _isSearching = false;
            _hasResults = true;
          });
        } else {
          conversationProvider.setProducts(
            null,
            message.isNotEmpty ? message : 'No products found',
          );
          setState(() {
            _isSearching = false;
            _hasResults = true;
          });
        }
      } else {
        conversationProvider.addMessage(
            role: 'ai', message: 'Something went wrong. Please try again.');
        setState(() => _isSearching = false);
      }

      // Scroll to bottom after new message
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      final conversationProvider =
          Provider.of<AIConversationProvider>(context, listen: false);
      conversationProvider.addMessage(
          role: 'ai', message: 'Connection error. Please try again.');
      setState(() => _isSearching = false);
    }
  }

  void _handleAddToCart(Map<String, dynamic> product) {
    try {
      final cartProvider = Provider.of<CartManager>(context, listen: false);
      final productId = product['id'] as int?;
      final name = product['name'] ?? 'Product';

      if (productId != null) {
        cartProvider.addToCart(
          productId: productId.toString(),
          product: product,
          quantity: 1,
        );
        CenteredNotification.show(context, '"$name" added to cart',
            success: true);
      }
    } catch (e) {
      CenteredNotification.show(context, 'Error adding to cart',
          success: false);
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: WillPopScope(
        onWillPop: () async {
          _handleClose();
          return false;
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: FadeTransition(
            opacity: _entryAnimation,
            child: Consumer<AIConversationProvider>(
              builder: (context, provider, _) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0A0F1E),
                        Color(0xFF111827),
                        Color(0xFF0A0F1E),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // ── Ambient background particles ──
                      ..._buildAmbientLights(),

                      // ── Main Content ──
                      SafeArea(
                        child: Column(
                          children: [
                            _buildHeader(provider),
                            Expanded(
                              child: _buildBody(provider),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Ambient light orbs in background ──
  List<Widget> _buildAmbientLights() {
    return [
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (_, __) => Positioned(
          top: -80 + _pulseAnimation.value * 20,
          right: -60,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF2563EB).withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (_, __) => Positioned(
          bottom: -100 + (1 - _pulseAnimation.value) * 30,
          left: -80,
          child: Container(
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF7C3AED).withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ═══════════════════════════════════════════
  // 🔝 HEADER
  // ═══════════════════════════════════════════
  Widget _buildHeader(AIConversationProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          // Close
          _glassButton(
            icon: Icons.close_rounded,
            onTap: _handleClose,
          ),
          const Spacer(),
          // Title
          Text(
            'YSHOP AI',
            style: TextStyle(
              fontFamily: 'CinzelDecorative',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.5,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const Spacer(),
          // New conversation
          if (provider.hasActiveConversation)
            _glassButton(
              icon: Icons.refresh_rounded,
              onTap: _startNewConversation,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 📄 BODY — switches between welcome & conversation
  // ═══════════════════════════════════════════
  Widget _buildBody(AIConversationProvider provider) {
    if (_isSearching && !_hasResults) {
      return _buildThinkingState();
    }

    final hasConversation = provider.hasActiveConversation;

    if (hasConversation) {
      return _buildConversationView(provider);
    }

    return _buildWelcomeView(provider);
  }

  // ═══════════════════════════════════════════
  // 🌟 WELCOME VIEW — first-time or fresh start
  // ═══════════════════════════════════════════
  Widget _buildWelcomeView(AIConversationProvider provider) {
    return Column(
      children: [
        const Spacer(flex: 3),
        // Floating orb
        AnimatedBuilder(
          animation: _orbFloatAnimation,
          builder: (_, __) {
            final float = math.sin(_orbFloatAnimation.value * math.pi) * 8;
            return Transform.translate(
              offset: Offset(0, float),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 15,
                    ),
                  ],
                ),
                child: const LiquidAIIcon(size: 72),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        // Welcome text
        Text(
          'What are you looking for?',
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: Colors.white.withOpacity(0.9),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'I\'ll find the perfect products for you',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.35),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 48),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _buildSearchInput(),
        ),
        const SizedBox(height: 20),
        // Quick suggestions
        _buildQuickSuggestions(),
        const Spacer(flex: 4),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 💬 CONVERSATION VIEW — chat + products
  // ═══════════════════════════════════════════
  Widget _buildConversationView(AIConversationProvider provider) {
    return Column(
      children: [
        // Messages list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: provider.conversation.length + (_isSearching ? 1 : 0),
            itemBuilder: (context, index) {
              // Show thinking indicator at the end
              if (_isSearching && index == provider.conversation.length) {
                return _buildTypingBubble();
              }

              final msg = provider.conversation[index];
              final isUser = msg['role'] == 'user';
              final text = msg['message'] ?? '';
              final products =
                  msg['products'] as List<Map<String, dynamic>>?;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessageBubble(text, isUser),
                  if (products != null && products.isNotEmpty)
                    _buildProductCards(products),
                ],
              );
            },
          ),
        ),

        // Reply input
        _buildReplyInput(),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // 🔍 SEARCH INPUT (Welcome screen)
  // ═══════════════════════════════════════════
  Widget _buildSearchInput() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              LiquidAIIcon(size: 26, isActive: _isSearchActive),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  cursorColor: Colors.white70,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything...',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _handleSearch(),
                  onChanged: (v) =>
                      setState(() => _isSearchActive = v.isNotEmpty),
                ),
              ),
              if (_isSearchActive) ...[
                GestureDetector(
                  onTap: _handleSearch,
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ] else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 💡 QUICK SUGGESTIONS
  // ═══════════════════════════════════════════
  Widget _buildQuickSuggestions() {
    final suggestions = ['I\'m hungry 🍔', 'Fashion finds 👗', 'Health essentials 💊'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions.map((s) {
        return GestureDetector(
          onTap: () {
            _searchController.text = s;
            setState(() => _isSearchActive = true);
            _handleSearch();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: Text(
              s,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════
  // 🤔 THINKING STATE
  // ═══════════════════════════════════════════
  Widget _buildThinkingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiquidAIIcon(size: 64, isThinking: true),
          const SizedBox(height: 24),
          Text(
            'Finding the best for you...',
            style: TextStyle(
              fontFamily: 'TenorSans',
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 💬 MESSAGE BUBBLE
  // ═══════════════════════════════════════════
  Widget _buildMessageBubble(String text, bool isUser) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: isUser ? _userBubble(text) : _aiBubble(text),
      ),
    );
  }

  Widget _userBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _aiBubble(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 10),
          child: LiquidAIIcon(size: 22),
        ),
        Flexible(
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // ⏳ TYPING INDICATOR
  // ═══════════════════════════════════════════
  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 10),
            child: LiquidAIIcon(size: 22, isThinking: true),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: const _ThinkingDots(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 🛍️ PRODUCT CARDS
  // ═══════════════════════════════════════════
  Widget _buildProductCards(List<Map<String, dynamic>> products) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 16),
      child: Column(
        children: products.asMap().entries.map((entry) {
          final i = entry.key;
          final product = entry.value;
          return _ProductCard(
            product: product,
            index: i,
            animation: _productAnimation,
            onAddToCart: () => _handleAddToCart(product),
            onTap: () => _navigateToProduct(product),
          );
        }).toList(),
      ),
    );
  }

  void _navigateToProduct(Map<String, dynamic> product) {
    final productModel = Product(
      id: product['id']?.toString() ?? '',
      storeId: product['store_id']?.toString() ?? '',
      name: product['name'] ?? '',
      description: product['description'] ?? '',
      price: double.tryParse(product['price']?.toString() ?? '0') ?? 0.0,
      currency: product['currency'] ?? 'TRY',
      imageUrl: product['image_url'] ?? product['image'] ?? '',
      stock: (product['stock'] as int?) ?? 0,
      categoryId: product['category_id']?.toString(),
      storeName: product['store_name'] ?? product['storeName'],
      storeOwnerEmail:
          product['store_owner_email'] ?? product['storeOwnerEmail'],
      status: 'approved',
      isActive: true,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProductDetailView(product: productModel)),
    );
  }

  // ═══════════════════════════════════════════
  // ✍️ REPLY INPUT (Conversation mode)
  // ═══════════════════════════════════════════
  Widget _buildReplyInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 18),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    focusNode: _replyFocusNode,
                    cursorColor: Colors.white70,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Reply or ask more...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _handleReply(),
                  ),
                ),
                GestureDetector(
                  onTap: _handleReply,
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 🃏 PRODUCT CARD — Premium glassmorphic card
// ═══════════════════════════════════════════════════════════════
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final int index;
  final AnimationController animation;
  final VoidCallback onAddToCart;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.index,
    required this.animation,
    required this.onAddToCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = product['name'] ?? 'Product';
    final price = product['price']?.toString() ?? '0';
    final currency = product['currency'] ?? 'TRY';
    final storeName = product['store_name'] ?? product['storeName'] ?? '';
    final imageUrl = product['image_url'] ?? product['image'];
    final stock = (product['stock'] as int?) ?? 0;
    final reason = product['reason'] ?? '';

    final intervalStart = (index * 0.12).clamp(0.0, 0.6);
    final intervalEnd = (0.5 + index * 0.12).clamp(0.5, 1.0);

    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: animation,
          curve: Interval(intervalStart, intervalEnd, curve: Curves.easeOut),
        ),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Interval(intervalStart, intervalEnd, curve: Curves.easeOutCubic),
        )),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: Colors.white.withOpacity(0.05),
                          child: imageUrl != null &&
                                  imageUrl.toString().isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Center(
                                    child: Icon(Icons.shopping_bag_outlined,
                                        color: Colors.white.withOpacity(0.2),
                                        size: 24),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Icon(Icons.shopping_bag_outlined,
                                        color: Colors.white.withOpacity(0.2),
                                        size: 24),
                                  ),
                                )
                              : Center(
                                  child: Icon(Icons.shopping_bag_outlined,
                                      color: Colors.white.withOpacity(0.2),
                                      size: 24),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                reason,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            // Price + Add
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                // Price badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$price $currency',
                                    style: const TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                // Add to cart
                                if (stock > 0)
                                  GestureDetector(
                                    onTap: onAddToCart,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color:
                                              Colors.white.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.add_rounded,
                                        color: Colors.white.withOpacity(0.8),
                                        size: 16,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'Out of stock',
                                    style: TextStyle(
                                      color: Colors.red.withOpacity(0.6),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Chevron
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.15),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ⏳ THINKING DOTS — Smooth animated dots
// ═══════════════════════════════════════════════════════════════
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_controller.value + delay) % 1.0);
            final scale = 0.5 + 0.5 * math.sin(t * math.pi);
            final opacity = 0.3 + 0.7 * math.sin(t * math.pi);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}