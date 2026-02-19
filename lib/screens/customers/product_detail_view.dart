// lib/screens/customers/product_detail_view.dart
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/currency.dart';
import '../../state_management/cart_manager.dart';
import '../../state_management/auth_manager.dart';
import '../../state_management/theme_manager.dart';
import '../../services/api_service.dart';
import '../../widgets/centered_notification.dart';
import '../../widgets/store_admin_widgets.dart';
import '../stores/chat_view.dart';

// ─────────────────────────────────────────────────────────────
// 💰 Currency Helper
// ─────────────────────────────────────────────────────────────
String getCurrencySymbol(String? currencyCode) {
  if (currencyCode == null || currencyCode.isEmpty) return '';
  final currency = Currency.fromCode(currencyCode);
  return currency?.symbol ?? '';
}

// ═══════════════════════════════════════════════════════════════
// 🏬 PRODUCT DETAIL VIEW — DJI-Inspired Revolutionary Design
// ═══════════════════════════════════════════════════════════════
class ProductDetailView extends StatefulWidget {
  final Product product;
  const ProductDetailView({Key? key, required this.product}) : super(key: key);

  @override
  State<ProductDetailView> createState() => _ProductDetailViewState();
}

class _ProductDetailViewState extends State<ProductDetailView>
    with TickerProviderStateMixin {
  int _quantity = 1;
  final GlobalKey _cartIconKey = GlobalKey();
  final String fontTenor = 'TenorSans';

  // ── Animation Controllers ──
  late AnimationController _entryController;
  late AnimationController _pulseController;
  late Animation<double> _imageScale;
  late Animation<double> _contentSlide;
  late Animation<double> _contentFade;
  late Animation<double> _priceFade;
  late Animation<double> _actionsFade;
  late Animation<double> _pulseAnim;

  // ── Scroll ──
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();

    // Entry orchestration
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _imageScale = Tween<double>(begin: 1.08, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );

    _contentSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _contentFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );

    _priceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );

    _actionsFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // Pulse for add-to-cart button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scrollController.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollController.offset);
    });

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Style Helper ──
  TextStyle _ts(BuildContext context, double size,
      {FontWeight weight = FontWeight.normal, Color? color}) {
    return TextStyle(
      fontFamily: fontTenor,
      fontSize: size,
      fontWeight: weight,
      color: color ?? Theme.of(context).colorScheme.onBackground,
    );
  }

  // ── Responsive helpers ──
  bool _isWide(BuildContext context) =>
      MediaQuery.of(context).size.width > 800;

  // ═══════════════════════════════════════════════════════════
  //  🖼️ FULLSCREEN IMAGE VIEWER
  // ═══════════════════════════════════════════════════════════
  void _showImageFullScreen(bool isDark) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullScreenImageViewer(
              imageUrl: widget.product.imageUrl,
              heroTag: 'product_${widget.product.id}',
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  💬 CHAT ACTION
  // ═══════════════════════════════════════════════════════════
  void _startChat() {
    if (widget.product.storeOwnerEmail == null ||
        widget.product.storeOwnerEmail!.isEmpty) {
      CenteredNotification.show(context, 'Store owner email not available.',
          success: false);
      return;
    }

    final authManager = Provider.of<AuthManager>(context, listen: false);
    if (!authManager.isAuthenticated) {
      CenteredNotification.show(context, 'Please login to start a chat.',
          success: false);
      return;
    }

    final String currentUserID = authManager.userProfile?['email'] ??
        authManager.userProfile?['uid'] ??
        '';
    if (currentUserID.isEmpty) {
      CenteredNotification.show(context, 'Unable to identify user.',
          success: false);
      return;
    }

    final String storeOwnerEmail = widget.product.storeOwnerEmail ?? 'N/A';
    final String chatID =
        '${currentUserID}_${storeOwnerEmail}_${widget.product.id}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatView(
          chatID: chatID,
          product: ProductS.fromProduct(widget.product),
          currentUserID: currentUserID,
          isStoreOwner: false,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  🛒 ADD TO CART + OVERLAY
  // ═══════════════════════════════════════════════════════════
  void _showAddedToCartNotification(BuildContext context) {
    final RenderBox? renderBox =
        _cartIconKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset iconPosition = renderBox.localToGlobal(Offset.zero);
    final Size iconSize = renderBox.size;
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FocusTransitionOverlay(
        productName: widget.product.name,
        startPosition: iconPosition,
        startSize: iconSize,
        endPosition: Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        ),
        onDismiss: () {
          overlayEntry?.remove();
          overlayEntry = null;
        },
        getTenorSansStyle: (ctx, size, {FontWeight weight = FontWeight.normal, Color? color}) =>
            _ts(ctx, size, weight: weight, color: color),
      ),
    );
    Overlay.of(context).insert(overlayEntry!);
  }

  Future<void> _handleAddToCart() async {
    final int stock = widget.product.stock;
    if (_quantity > stock) {
      CenteredNotification.show(
          context, 'Sorry, only $stock items available in stock.',
          success: false);
      return;
    }
    _showAddedToCartNotification(context);
    try {
      await Provider.of<CartManager>(context, listen: false)
          .addToCart(product: widget.product, quantity: _quantity);
    } catch (e) {
      if (mounted) {
        CenteredNotification.show(
            context, e?.toString() ?? 'An error occurred, please try again.',
            success: false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  //   BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, _, __) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final wide = _isWide(context);
        final screenW = MediaQuery.of(context).size.width;
        final screenH = MediaQuery.of(context).size.height;

        // Parallax factor for image
        final double parallax = (_scrollOffset * 0.3).clamp(0, 120);
        final double imageOpacity =
            (1.0 - (_scrollOffset / (screenH * 0.45)).clamp(0, 1)).clamp(0.3, 1.0);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: wide
                ? _buildWideLayout(context, theme, isDark, screenW, screenH)
                : _buildMobileLayout(
                    context, theme, isDark, screenW, screenH, parallax, imageOpacity),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  📱 MOBILE / NARROW LAYOUT
  // ═══════════════════════════════════════════════════════════
  Widget _buildMobileLayout(BuildContext context, ThemeData theme, bool isDark,
      double screenW, double screenH, double parallax, double imageOpacity) {
    final topPad = MediaQuery.of(context).padding.top;
    final imageHeight = screenH * 0.52;

    return Stack(
      children: [
        // ── Scrollable Content ──
        CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ╔══════════════════════════════╗
            // ║   HERO IMAGE SECTION         ║
            // ╚══════════════════════════════╝
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _entryController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _imageScale.value,
                    child: Opacity(
                      opacity: imageOpacity,
                      child: SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Blurred background fill
                            Positioned.fill(
                              child: Transform.translate(
                                offset: Offset(0, -parallax),
                                child: CachedNetworkImage(
                                  imageUrl: widget.product.imageUrl,
                                  fit: BoxFit.cover,
                                  color: isDark
                                      ? Colors.black.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.15),
                                  colorBlendMode: BlendMode.darken,
                                ),
                              ),
                            ),
                            // Blur overlay
                            Positioned.fill(
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 35, sigmaY: 35),
                                child: Container(
                                  color: isDark
                                      ? Colors.black.withOpacity(0.4)
                                      : Colors.white.withOpacity(0.2),
                                ),
                              ),
                            ),
                            // Main product image – clickable
                            Center(
                              child: GestureDetector(
                                onTap: () => _showImageFullScreen(isDark),
                                child: Hero(
                                  tag: 'product_${widget.product.id}',
                                  child: Transform.translate(
                                    offset: Offset(0, -parallax * 0.5),
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxHeight: imageHeight * 0.82,
                                        maxWidth: screenW * 0.85,
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: widget.product.imageUrl,
                                        fit: BoxFit.contain,
                                        placeholder: (_, __) => const Center(
                                          child: CircularProgressIndicator(
                                              strokeWidth: 1.5),
                                        ),
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.broken_image,
                                                size: 48),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Gradient fade at bottom
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      theme.scaffoldBackgroundColor
                                          .withOpacity(0.8),
                                      theme.scaffoldBackgroundColor,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Tap-to-expand hint
                            Positioned(
                              bottom: 28,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: _scrollOffset < 20 ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_out_map_rounded,
                                          size: 14,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black38),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap image to expand',
                                        style: TextStyle(
                                          fontFamily: fontTenor,
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black38,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ╔══════════════════════════════╗
            // ║   PRODUCT CONTENT            ║
            // ╚══════════════════════════════╝
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _entryController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _contentSlide.value),
                    child: Opacity(
                      opacity: _contentFade.value,
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Product Name ──
                          Text(
                            widget.product.name,
                            style: _ts(context, 28, weight: FontWeight.w700)
                                .copyWith(
                              letterSpacing: -0.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Price + Stock row ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                              opacity: _priceFade.value,
                              child: child,
                            ),
                            child: _buildPriceStockRow(theme, isDark),
                          ),

                          const SizedBox(height: 28),

                          // ── Description ──
                          _buildDescriptionSection(theme, isDark),

                          const SizedBox(height: 28),

                          // ── Quantity Selector ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                              opacity: _actionsFade.value,
                              child: child,
                            ),
                            child: _buildQuantitySelector(theme, isDark),
                          ),

                          const SizedBox(height: 24),

                          // ── Store Card ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                              opacity: _actionsFade.value,
                              child: child,
                            ),
                            child: _buildStoreCard(theme, isDark),
                          ),

                          // Bottom padding for floating bar
                          const SizedBox(height: 140),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // ── Top Navigation Bar (Floating) ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(theme, isDark, topPad),
        ),

        // ── Bottom Action Bar ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _entryController,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 80 * (1 - _actionsFade.value)),
              child: Opacity(opacity: _actionsFade.value, child: child),
            ),
            child: _buildBottomBar(theme, isDark),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  🖥️ WIDE / DESKTOP LAYOUT
  // ═══════════════════════════════════════════════════════════
  Widget _buildWideLayout(BuildContext context, ThemeData theme, bool isDark,
      double screenW, double screenH) {
    final topPad = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Row(
          children: [
            // ── LEFT: Image Panel (50%) ──
            Expanded(
              flex: 5,
              child: AnimatedBuilder(
                animation: _entryController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _imageScale.value,
                    child: child,
                  );
                },
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.grey.shade100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Blurred background
                      CachedNetworkImage(
                        imageUrl: widget.product.imageUrl,
                        fit: BoxFit.cover,
                      ),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(
                          color: isDark
                              ? Colors.black.withOpacity(0.5)
                              : Colors.white.withOpacity(0.3),
                        ),
                      ),
                      // Product image centered
                      Center(
                        child: GestureDetector(
                          onTap: () => _showImageFullScreen(isDark),
                          child: Hero(
                            tag: 'product_${widget.product.id}',
                            child: Padding(
                              padding: const EdgeInsets.all(48),
                              child: CachedNetworkImage(
                                imageUrl: widget.product.imageUrl,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5)),
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.broken_image, size: 64),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Expand hint
                      Positioned(
                        bottom: 32,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_out_map_rounded,
                                    size: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black38),
                                const SizedBox(width: 5),
                                Text(
                                  'Click to expand',
                                  style: TextStyle(
                                    fontFamily: fontTenor,
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black38,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── RIGHT: Details Panel (50%) ──
            Expanded(
              flex: 5,
              child: AnimatedBuilder(
                animation: _entryController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_contentSlide.value * 0.5, 0),
                    child: Opacity(
                      opacity: _contentFade.value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        48, topPad + 72, 48, 48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Product Name ──
                          Text(
                            widget.product.name,
                            style:
                                _ts(context, 36, weight: FontWeight.w700)
                                    .copyWith(
                              letterSpacing: -0.8,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Price + Stock ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                                opacity: _priceFade.value, child: child),
                            child: _buildPriceStockRow(theme, isDark),
                          ),

                          const SizedBox(height: 36),

                          // ── Divider ──
                          Container(
                            height: 1,
                            color: (isDark ? Colors.white : Colors.black)
                                .withOpacity(0.06),
                          ),

                          const SizedBox(height: 32),

                          // ── Description ──
                          _buildDescriptionSection(theme, isDark),

                          const SizedBox(height: 36),

                          // ── Quantity ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                                opacity: _actionsFade.value, child: child),
                            child: _buildQuantitySelector(theme, isDark),
                          ),

                          const SizedBox(height: 28),

                          // ── Add to Cart (Desktop) ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                                opacity: _actionsFade.value, child: child),
                            child: _buildDesktopAddToCart(theme, isDark),
                          ),

                          const SizedBox(height: 32),

                          // ── Divider ──
                          Container(
                            height: 1,
                            color: (isDark ? Colors.white : Colors.black)
                                .withOpacity(0.06),
                          ),

                          const SizedBox(height: 28),

                          // ── Store Card ──
                          AnimatedBuilder(
                            animation: _entryController,
                            builder: (context, child) => Opacity(
                                opacity: _actionsFade.value, child: child),
                            child: _buildStoreCard(theme, isDark),
                          ),

                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // ── Back Button (Desktop) ──
        Positioned(
          top: topPad + 16,
          left: 20,
          child: _buildBackButton(theme, isDark),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  🧩 SHARED COMPONENTS
  // ═══════════════════════════════════════════════════════════

  // ── Top Bar (Mobile) ──
  Widget _buildTopBar(ThemeData theme, bool isDark, double topPad) {
    final double opacity =
        (_scrollOffset / 200).clamp(0, 1).toDouble();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: opacity * 20,
          sigmaY: opacity * 20,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, topPad + 8, 8, 10),
          color: theme.scaffoldBackgroundColor.withOpacity(opacity * 0.85),
          child: Row(
            children: [
              _buildBackButton(theme, isDark),
              const Spacer(),
              // Product name fades in as you scroll
              AnimatedOpacity(
                opacity: opacity,
                duration: Duration.zero,
                child: Text(
                  widget.product.name,
                  style: _ts(context, 15, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              // Placeholder for symmetry
              const SizedBox(width: 44),
            ],
          ),
        ),
      ),
    );
  }

  // ── Back Button ──
  Widget _buildBackButton(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  // ── Price + Stock Row ──
  Widget _buildPriceStockRow(ThemeData theme, bool isDark) {
    final sym = getCurrencySymbol(widget.product.currency);
    final inStock = widget.product.stock > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Price
        Text(
          '$sym${widget.product.price.toStringAsFixed(2)}',
          style: _ts(context, 26, weight: FontWeight.w800).copyWith(
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 14),
        // Stock indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: inStock
                ? const Color(0xFF8BC34A).withOpacity(0.12)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inStock ? const Color(0xFF8BC34A) : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                inStock ? '${widget.product.stock} in stock' : 'Out of stock',
                style: TextStyle(
                  fontFamily: fontTenor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: inStock ? const Color(0xFF689F38) : Colors.red,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Description Section ──
  Widget _buildDescriptionSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About this product',
          style: _ts(context, 13, weight: FontWeight.w600).copyWith(
            letterSpacing: 1.5,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.product.description,
          style: _ts(context, 15, color: isDark ? Colors.white70 : Colors.black54)
              .copyWith(height: 1.65, letterSpacing: 0.1),
        ),
      ],
    );
  }

  // ── Quantity Selector ──
  Widget _buildQuantitySelector(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Text(
          'Quantity',
          style: _ts(context, 13, weight: FontWeight.w600).copyWith(
            letterSpacing: 1.5,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(width: 20),
        Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _quantityButton(
                icon: Icons.remove_rounded,
                onTap: () {
                  if (_quantity > 1) setState(() => _quantity--);
                },
                isDark: isDark,
                theme: theme,
              ),
              Container(
                width: 48,
                alignment: Alignment.center,
                child: Text(
                  '$_quantity',
                  style: _ts(context, 17, weight: FontWeight.w700),
                ),
              ),
              _quantityButton(
                icon: Icons.add_rounded,
                onTap: () {
                  if (_quantity >= widget.product.stock) {
                    CenteredNotification.show(
                      context,
                      'Sorry, only ${widget.product.stock} items available.',
                      success: false,
                    );
                    return;
                  }
                  setState(() => _quantity++);
                },
                isDark: isDark,
                theme: theme,
                isAdd: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    required ThemeData theme,
    bool isAdd = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: isAdd
                ? theme.primaryColor
                : (isDark ? Colors.white54 : Colors.black45),
          ),
        ),
      ),
    );
  }

  // ── Store Card ──
  Widget _buildStoreCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          // Store icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.storefront_rounded,
                color: theme.primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Store info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.storeName ?? 'Store',
                  style: _ts(context, 14, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Verified Seller',
                  style: TextStyle(
                    fontFamily: fontTenor,
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Chat button
          GestureDetector(
            onTap: _startChat,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 15, color: theme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    'Chat',
                    style: TextStyle(
                      fontFamily: fontTenor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Desktop Add to Cart ──
  Widget _buildDesktopAddToCart(ThemeData theme, bool isDark) {
    final sym = getCurrencySymbol(widget.product.currency);
    final total = widget.product.price * _quantity;

    return Row(
      children: [
        // Total
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontFamily: fontTenor,
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$sym${total.toStringAsFixed(2)}',
              style: _ts(context, 22, weight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(width: 28),
        // Add to Cart button
        Expanded(
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return child!;
            },
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _handleAddToCart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? theme.colorScheme.primary
                      : theme.primaryColor,
                  foregroundColor: isDark
                      ? theme.colorScheme.onPrimary
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Add to Cart',
                      style: _ts(context, 15,
                          weight: FontWeight.w700,
                          color: isDark
                              ? theme.colorScheme.onPrimary
                              : Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.shopping_bag_outlined,
                      key: _isWide(context) ? _cartIconKey : null,
                      size: 20,
                      color: isDark
                          ? theme.colorScheme.onPrimary
                          : Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Bottom Bar (Mobile) ──
  Widget _buildBottomBar(ThemeData theme, bool isDark) {
    final sym = getCurrencySymbol(widget.product.currency);
    final total = widget.product.price * _quantity;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + 16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.75)
                : Colors.white.withOpacity(0.8),
            border: Border(
              top: BorderSide(
                color:
                    (isDark ? Colors.white : Colors.black).withOpacity(0.06),
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Row(
                children: [
                  // Total price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontFamily: fontTenor,
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sym${total.toStringAsFixed(2)}',
                        style: _ts(context, 22,
                            weight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Add to Cart button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _handleAddToCart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? theme.colorScheme.primary
                            : theme.primaryColor,
                        foregroundColor: isDark
                            ? theme.colorScheme.onPrimary
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Add to Cart',
                            style: _ts(context, 15,
                                weight: FontWeight.w700,
                                color: isDark
                                    ? theme.colorScheme.onPrimary
                                    : Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.shopping_bag_outlined,
                            key: _isWide(context) ? null : _cartIconKey,
                            size: 20,
                            color: isDark
                                ? theme.colorScheme.onPrimary
                                : Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 🖼️ FULLSCREEN IMAGE VIEWER (Immersive)
// ═══════════════════════════════════════════════════════════════
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  final bool isDark;

  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.heroTag,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              color: isDark
                  ? Colors.black.withOpacity(0.7)
                  : Colors.white.withOpacity(0.7),
            ),
          ),
          // Interactive image
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: GestureDetector(
                  onTap: () {}, // prevent dismiss on image tap
                  child: Hero(
                    tag: heroTag,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white : Colors.black,
                      size: 22,
                    ),
                  ),
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
// ✨ CART NOTIFICATION OVERLAY (Refined Animation)
// ═══════════════════════════════════════════════════════════════
class FocusTransitionOverlay extends StatefulWidget {
  final String productName;
  final Offset startPosition;
  final Size startSize;
  final Offset endPosition;
  final VoidCallback onDismiss;
  final TextStyle Function(BuildContext, double,
      {FontWeight weight, Color? color}) getTenorSansStyle;

  const FocusTransitionOverlay({
    Key? key,
    required this.productName,
    required this.startPosition,
    required this.startSize,
    required this.endPosition,
    required this.onDismiss,
    required this.getTenorSansStyle,
  }) : super(key: key);

  @override
  State<FocusTransitionOverlay> createState() =>
      _FocusTransitionOverlayState();
}

class _FocusTransitionOverlayState extends State<FocusTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _textOpacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    const double finalW = 260;
    const double finalH = 54;

    final Offset startOffset = widget.startPosition +
        Offset(widget.startSize.width / 2, widget.startSize.height / 2);
    final Offset endOffset =
        widget.endPosition - Offset(finalW / 2, finalH / 2);

    const double entryEnd = 0.3;

    _positionAnimation = Tween<Offset>(
      begin: startOffset,
      end: endOffset,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, entryEnd, curve: Curves.easeOutCubic),
    ));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.8, end: 1.05), weight: 60),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.05, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, entryEnd, curve: Curves.decelerate),
    ));

    _textOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, entryEnd, curve: Curves.easeIn),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color accentGreen = Color(0xFF8BC34A);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx,
          top: _positionAnimation.value.dy,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Builder(builder: (ctx) {
                final t = Theme.of(ctx);
                final bool dk = t.brightness == Brightness.dark;
                final Color bg =
                    dk ? Colors.white.withOpacity(0.95) : Colors.black87;
                final Color txt = dk ? Colors.black87 : Colors.white;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accentGreen.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller.value < 0.3
                              ? Icons.shopping_cart_rounded
                              : Icons.check_circle_rounded,
                          color: accentGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Opacity(
                        opacity: _textOpacityAnimation.value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 200,
                              child: Text(
                                widget.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: widget
                                    .getTenorSansStyle(ctx, 14)
                                    .copyWith(
                                  color: accentGreen,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Added to cart',
                              style:
                                  widget.getTenorSansStyle(ctx, 12).copyWith(
                                color: txt.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}