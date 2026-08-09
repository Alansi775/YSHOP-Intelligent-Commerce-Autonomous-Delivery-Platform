// lib/screens/customers/category_home_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/side_menu_view_contents.dart';
import '../../widgets/side_cart_view_contents.dart';
import '../../widgets/cart_icon_with_badge.dart';
import '../../widgets/liquid_ai_icon.dart';
import '../../widgets/ai_home_conversation_box.dart';
import '../../screens/auth/sign_in_ui.dart';
import '../../state_management/cart_manager.dart';
import '../../state_management/theme_manager.dart';
import '../../state_management/auth_manager.dart';
import '../../constants/store_categories.dart';
import '../../services/api_service.dart';
import '../../models/product.dart';
import 'product_detail_view.dart';
import 'stores_list_view.dart';
import '../../main.dart';


class CategoryHomeView extends StatefulWidget {
  const CategoryHomeView({Key? key}) : super(key: key);

  @override
  State<CategoryHomeView> createState() => _CategoryHomeViewState();
}

class _CategoryHomeViewState extends State<CategoryHomeView>
    with TickerProviderStateMixin {
  
  // Hero Products Data
  final List<HeroProduct> heroProducts = [
    HeroProduct(
      name: 'PREMIUM FOOD',
      subtitle: 'Gourmet Excellence',
      imagePath: '9.png',
      gradientColors: [Color(0xFF2A1810), Color(0xFF0D0806)],
      category: 'Food',
      icon: Icons.restaurant_rounded,
    ),
    HeroProduct(
      name: 'HEALTHCARE',
      subtitle: 'Wellness Essentials',
      imagePath: 'Hero.png',
      gradientColors: [Color(0xFF1A2530), Color(0xFF000000)],
      category: 'Pharmacy',
      icon: Icons.medical_services_rounded,
    ),
    HeroProduct(
      name: 'FASHION',
      subtitle: 'Curated Style',
      imagePath: '0.png',
      gradientColors: [Color(0xFF25283A), Color(0xFF0A0B12)],
      category: 'Clothes',
      icon: Icons.checkroom_rounded,
    ),
    HeroProduct(
      name: 'FRESH MARKET',
      subtitle: 'Farm to Table',
      imagePath: '1.png',
      gradientColors: [Color(0xFF2D2418), Color(0xFF0F0A06)],
      category: 'Market',
      icon: Icons.shopping_basket_rounded,
    ),
  ];

  // State
  late final List<String> categories;
  final ScrollController _scrollController = ScrollController();
  int _currentProductIndex = 0;
  late AnimationController _fadeController;
  Timer? _autoRotateTimer;

  // AI Expandable Conversation State
  bool _isAIExpanded = false;
  List<Map<String, dynamic>> _aiMessages = [];
  List<Map<String, dynamic>>? _aiProducts;
  final TextEditingController _aiSearchController = TextEditingController();
  final FocusNode _aiSearchFocusNode = FocusNode();
  late AnimationController _aiExpandAnimation;
  late AnimationController _sendButtonAnimation;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onOpenCartSignal() {
    if (mounted) _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  void initState() {
    super.initState();
    ApiService.clearCache();
    categories = StoreCategories.all;
    openCartDrawerSignal.addListener(_onOpenCartSignal);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _aiExpandAnimation = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
    );

    _sendButtonAnimation = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadImages();
    });

    _startAutoRotate();
  }

  void _onScroll() {
    final screenHeight = MediaQuery.of(context).size.height;
    final isAboveHero = _scrollController.offset < screenHeight - 100;

    if (isAboveHero != isAboveHeroNotifier.value) {
      isAboveHeroNotifier.value = isAboveHero;
    }
  }

  void _preloadImages() {
    for (var product in heroProducts) {
      precacheImage(
        AssetImage('assets/images/${product.imagePath}'),
        context,
      );
    }
  }

  void _startAutoRotate() {
    _autoRotateTimer?.cancel();

    _autoRotateTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        final nextIndex = (_currentProductIndex + 1) % heroProducts.length;
        _changeProduct(nextIndex);
      }
    });
  }

  void _changeProduct(int newIndex) {
    if (_currentProductIndex != newIndex && mounted) {
      setState(() {
        _currentProductIndex = newIndex;
      });

      _fadeController.reset();
      _fadeController.forward();

      _startAutoRotate();
    }
  }

  void _handleMobileHeroSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 180) return;

    if (velocity < 0) {
      _changeProduct((_currentProductIndex + 1) % heroProducts.length);
    } else {
      _changeProduct((_currentProductIndex - 1 + heroProducts.length) % heroProducts.length);
    }
  }

  // AI Search Methods
  void _handleAISearch() {
    final query = _aiSearchController.text.trim();
    if (query.isEmpty) return;

    _aiSearchController.clear();
    _performAISearch(query);
  }

  Future<void> _performAISearch(String query) async {
    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      final userId = authManager.userProfile?['id'] ?? 'guest';

      setState(() {
        _aiMessages.add({
          'role': 'user',
          'text': query,
          'type': 'text',
          'timestamp': DateTime.now(),
        });
        // Add loading message
        _aiMessages.add({
          'role': 'ai',
          'text': '',
          'type': 'loading',
          'timestamp': DateTime.now(),
        });
      });

      final response = await ApiService.postRequest(
        '/ai/chat',
        {
          'message': query,
          'userId': userId,
          'language': 'auto',
        },
      );

      // Remove loading message
      setState(() {
        _aiMessages.removeWhere((m) => m['type'] == 'loading');
      });

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        final products = data['products'] as List?;
        final message = data['message'] as String? ?? '';

        setState(() {
          _aiMessages.add({
            'role': 'ai',
            'text': message,
            'type': 'text',
            'timestamp': DateTime.now(),
          });

          if (products != null && products.isNotEmpty) {
            _aiProducts = products.cast<Map<String, dynamic>>();
            _aiMessages.add({
              'role': 'ai',
              'type': 'product',
              'products': _aiProducts,
              'timestamp': DateTime.now(),
            });
          }
        });
      }
    } catch (e) {
      // Remove loading message on error
      setState(() {
        _aiMessages.removeWhere((m) => m['type'] == 'loading');
      });
      print('AI Search Error: $e');
      setState(() {
        _aiMessages.add({
          'role': 'ai',
          'text': 'Sorry, I encountered an error. Please try again.',
          'type': 'text',
          'timestamp': DateTime.now(),
        });
      });
    }
  }

  void _handleCollapseConversation() {
    setState(() => _isAIExpanded = false);
    _aiExpandAnimation.reverse();
  }

  void _startNewConversation() {
    setState(() {
      _aiMessages.clear();
      _aiProducts = null;
      _aiSearchController.clear();
    });
  }

  void _handleAddToCart(dynamic product) {
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

      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding to cart'),
          backgroundColor: Colors.red.withOpacity(0.8),
        ),
      );
    }
  }

  @override
  void dispose() {
    openCartDrawerSignal.removeListener(_onOpenCartSignal);
    _autoRotateTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _fadeController.dispose();
    _aiSearchController.dispose();
    _aiSearchFocusNode.dispose();
    _aiExpandAnimation.dispose();
    _sendButtonAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final bool isMobile = screenW < 700;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      endDrawer: const Drawer(child: SideCartViewContents()),
      body: Stack(
        children: [
          if (isMobile)
            _buildMobileLayout(isDark, screenW, screenH)
          else
            // Main Content
            SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Column(
                children: [
                  // Hero Section
                  RepaintBoundary(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height,
                      child: Stack(
                        children: [
                          _buildHeroContent(),
                          Positioned(
                            left: 40,
                            top: 0,
                            bottom: 0,
                            child: RepaintBoundary(
                              child: _buildProductSidebar(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: Container(
                      color: isDark ? Colors.black : Colors.white,
                      child: Column(
                        children: [
                          const SizedBox(height: 80),
                          _VideoSection(isDark: isDark),
                          const SizedBox(height: 80),
                          _buildBrandsSection(isDark),
                          const SizedBox(height: 100),
                          _buildFooter(isDark),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Floating Header
          kIsWeb ? _buildWebGlassNavbar(isDark) : _buildFloatingHeader(isDark, isMobile),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark, double screenW, double screenH) {
    final currentProduct = heroProducts[_currentProductIndex];
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: _handleMobileHeroSwipe,
            child: RepaintBoundary(
              child: SizedBox(
                height: screenH * 0.96,
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: currentProduct.gradientColors,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 112,
                      left: 16,
                      right: 16,
                      child: AIHomeConversationBox(
                        onSearch: _performAISearch,
                        onAddToCart: _handleAddToCart,
                        messages: _aiMessages,
                        isExpanded: _isAIExpanded,
                        onToggleExpand: (val) {
                          setState(() => _isAIExpanded = val);
                          if (val) _aiExpandAnimation.forward();
                        },
                        onCollapse: _handleCollapseConversation,
                        onNewConversation: _startNewConversation,
                        aiSearchController: _aiSearchController,
                        aiSearchFocusNode: _aiSearchFocusNode,
                        sendButtonAnimation: _sendButtonAnimation,
                      ),
                    ),
                    Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isAIExpanded ? 0.15 : 1.0,
                        child: FadeTransition(
                          opacity: _fadeController,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.18, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              key: ValueKey(currentProduct.imagePath),
                              padding: EdgeInsets.only(top: screenH * 0.05),
                              child: Image.asset(
                                'assets/images/${currentProduct.imagePath}',
                                height: screenH * 0.25,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomInset + 104,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isAIExpanded ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: _isAIExpanded,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 450),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.16),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: Column(
                                key: ValueKey(currentProduct.name),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentProduct.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'TenorSans',
                                      fontSize: 30,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.white,
                                      letterSpacing: 2.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    currentProduct.subtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'TenorSans',
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.72),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  _buildExploreButton(currentProduct.category),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: bottomInset + 16,
                      child: _buildMobileCategoryToolbar(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: Container(
              color: isDark ? Colors.black : Colors.white,
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  _VideoSection(isDark: isDark),
                  const SizedBox(height: 48),
                  _buildBrandsSection(isDark),
                  const SizedBox(height: 72),
                  _buildFooter(isDark),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Hero Content
  Widget _buildHeroContent() {
    final currentProduct = heroProducts[_currentProductIndex];

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: currentProduct.gradientColors,
          ),
        ),
        child: Stack(
          children: [
            // Product Image - Fade when AI expanded
            Center(
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 300),
                opacity: _isAIExpanded ? 0.1 : 1.0,
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Image.asset(
                    'assets/images/${currentProduct.imagePath}',
                    height: MediaQuery.of(context).size.height * 0.5,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    cacheHeight: (MediaQuery.of(context).size.height *
                            0.5 *
                            MediaQuery.of(context).devicePixelRatio)
                        .round(),
                  ),
                ),
              ),
            ),

            // AI Search Bar (INSIDE HERO)
            Positioned(
              top: 140,
              left: MediaQuery.of(context).size.width > 600 
                ? MediaQuery.of(context).size.width * 0.15 
                : MediaQuery.of(context).size.width * 0.08,
              right: MediaQuery.of(context).size.width > 600 
                ? MediaQuery.of(context).size.width * 0.15 
                : MediaQuery.of(context).size.width * 0.08,
              child: AIHomeConversationBox(
                onSearch: _performAISearch,
                onAddToCart: _handleAddToCart,
                messages: _aiMessages,
                isExpanded: _isAIExpanded,
                onToggleExpand: (val) {
                  setState(() => _isAIExpanded = val);
                  if (val) _aiExpandAnimation.forward();
                },
                onCollapse: _handleCollapseConversation,
                onNewConversation: _startNewConversation,
                aiSearchController: _aiSearchController,
                aiSearchFocusNode: _aiSearchFocusNode,
                sendButtonAnimation: _sendButtonAnimation,
              ),
            ),

            // Bottom Text - Fade out when AI expanded
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 300),
                opacity: _isAIExpanded ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isAIExpanded,
                  child: RepaintBoundary(
                    child: FadeTransition(
                      opacity: _fadeController,
                      child: Column(
                        children: [
                          Text(
                            currentProduct.name,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: MediaQuery.of(context).size.width > 600 ? 48 : 32,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentProduct.subtitle,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                              color: Colors.white.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildExploreButton(currentProduct.category),
                        ],
                      ),
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

  Widget _buildExploreButton(String category) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) {
              return StoresListView(categoryName: category);
            },
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final fadeAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              );

              final scaleAnimation = Tween<double>(
                begin: 0.95,
                end: 1.0,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));

              return FadeTransition(
                opacity: fadeAnimation,
                child: ScaleTransition(
                  scale: scaleAnimation,
                  child: child,
                ),
              );
            },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1.5),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EXPLORE',
              style: TextStyle(
                fontFamily: 'TenorSans',
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCategoryToolbar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(heroProducts.length, (index) {
              final isSelected = _currentProductIndex == index;
              final product = heroProducts[index];

              return GestureDetector(
                onTap: () => _changeProduct(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.14) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white.withOpacity(0.32) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    product.icon,
                    size: isSelected ? 22 : 20,
                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.56),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSidebar() {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 300),
      opacity: _isAIExpanded ? 0.0 : 1.0,
      child: IgnorePointer(
        ignoring: _isAIExpanded,
        child: SizedBox(
          width: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildVisibleProducts(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVisibleProducts() {
    List<Widget> widgets = [];

    for (int i = -1; i <= 1; i++) {
      final index = (_currentProductIndex + i) % heroProducts.length;
      final actualIndex = index < 0 ? heroProducts.length + index : index;
      final product = heroProducts[actualIndex];
      final isActive = i == 0;

      widgets.add(
        GestureDetector(
          onTap: () => _changeProduct(actualIndex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            height: 60,
            margin: EdgeInsets.symmetric(vertical: isActive ? 8 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 2,
                  height: isActive ? 40 : 0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.4),
                        Colors.white,
                      ],
                    ),
                  ),
                ),
                SizedBox(width: isActive ? 12 : 0),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isActive ? 1.0 : 0.25,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 300),
                      scale: isActive ? 1.0 : 0.85,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: isActive ? 14 : 11,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w400,
                              color: Colors.white,
                              letterSpacing: isActive ? 1.2 : 0.8,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(height: 4),
                            Text(
                              product.subtitle,
                              style: TextStyle(
                                fontFamily: 'TenorSans',
                                fontSize: 9,
                                color: Colors.white.withOpacity(0.5),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
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
    }

    return widgets;
  }

  // Web-only floating glass navbar — a frosted pill centered at the top of
  // the viewport, matching the DroneHub reference design (logo left, nav
  // links center, theme/cart/profile right), rather than the phone-style
  // header used on the native mobile apps.
  Widget _buildWebGlassNavbar(bool isDark) {
    final authManager = Provider.of<AuthManager>(context);
    final themeManager = Provider.of<ThemeManager>(context, listen: false);
    // Genuinely transparent glass — just enough tint for the blur to read,
    // not a near-solid bar sitting on top of the page.
    final bgColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.12);
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : Colors.black;

    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 960),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Text(
                      'YSHOP',
                      style: TextStyle(
                        fontFamily: 'CinzelDecorative',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        letterSpacing: 2,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: categories.take(6).map((c) => _WebNavLink(
                                  label: c,
                                  color: textColor,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => StoresListView(categoryName: c)),
                                  ),
                                )).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _WebIconBtn(
                      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      color: textColor,
                      onTap: () => themeManager.setTheme(isDark ? ThemeMode.light : ThemeMode.dark),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CartIconWithBadge(iconColor: textColor, iconSize: 22),
                    ),
                    _WebIconBtn(
                      icon: authManager.isAuthenticated ? Icons.person_rounded : Icons.person_outline_rounded,
                      color: authManager.isAuthenticated ? const Color(0xFF3B82F6) : textColor,
                      onTap: () => ProfilePopupView.show(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingHeader(bool isDark, bool isMobile) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + (isMobile ? 10 : 16),
          left: isMobile ? 16 : 40,
          right: isMobile ? 16 : 40,
          bottom: isMobile ? 10 : 16,
        ),
        child: isMobile
            ? Row(
                children: [
                  GestureDetector(
                    onTap: () => ProfilePopupView.show(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Image.asset(
                        'assets/icons/user.png',
                        width: 18,
                        height: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'YSHOP',
                    style: TextStyle(
                      fontFamily: 'CinzelDecorative',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  CartIconWithBadge(iconColor: Colors.white),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Text(
                    'YSHOP',
                    style: TextStyle(
                      fontFamily: 'CinzelDecorative',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => ProfilePopupView.show(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Image.asset(
                            'assets/icons/user.png',
                            width: 20,
                            height: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CartIconWithBadge(iconColor: Colors.white),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBrandsSection(bool isDark) {
    final screenW = MediaQuery.of(context).size.width;
    final bool isMobile = screenW < 700;
    final double sectionHorizontal = isMobile ? 20 : 60;
    final double showcaseHeight = isMobile ? 200 : 260;
    final double showcasePadding = isMobile ? 14 : 24;

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: EdgeInsets.symmetric(horizontal: sectionHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'FEATURED BRANDS',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.2,
                    color: isDark
                        ? Colors.white.withOpacity(0.5)
                        : Colors.black.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 54,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              Colors.white.withOpacity(0.65),
                              Colors.white.withOpacity(0.12)
                            ]
                          : [
                              Colors.black.withOpacity(0.65),
                              Colors.black.withOpacity(0.12)
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 18 : 28),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? 420 : 980,
              ),
              child: Container(
                height: showcaseHeight,
                padding: EdgeInsets.all(showcasePadding),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(isMobile ? 22 : 28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const BrandShowcaseView(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 60),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.08),
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'YSHOP',
            style: TextStyle(
              fontFamily: 'CinzelDecorative',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Curated Excellence, Delivered',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 12,
              letterSpacing: 2,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Video showcase carousel ─────────────────────────────────────────────
// Infinite-loop carousel of autoplaying, looping, muted videos — only the
// centered ("active") card actually plays; the rest sit paused and dimmed.
// Navigation is arrow-button only (no direct swipe), matching the reference
// design. Placeholder video assets (assets/videos/hero1-3.mp4) — swap for
// real product footage whenever it's ready, same widget/behavior either way.
class _VideoSection extends StatefulWidget {
  final bool isDark;
  const _VideoSection({required this.isDark});

  @override
  State<_VideoSection> createState() => _VideoSectionState();
}

class _VideoSectionState extends State<_VideoSection> {
  static const List<Map<String, String>> _videos = [
    {'path': 'assets/videos/hero1.mp4', 'title': 'Featured Selection', 'sub': 'HANDPICKED FOR YOU'},
    {'path': 'assets/videos/hero2.mp4', 'title': 'New Arrivals', 'sub': 'FRESH ON YSHOP'},
    {'path': 'assets/videos/hero3.mp4', 'title': 'Best Sellers', 'sub': 'LOVED BY CUSTOMERS'},
  ];

  static const int _virtualCount = 999999;
  static const int _initialPage = _virtualCount ~/ 2;
  late final PageController _pageController;
  int _realIndex = _initialPage % _videos.length;

  @override
  void initState() {
    super.initState();
    // 0.78 viewport fraction is what leaves the previous/next cards visibly
    // peeking in on both sides — the actual "cover flow" look — rather than
    // a single card floating alone with empty space around it.
    _pageController = PageController(viewportFraction: 0.78, initialPage: _initialPage);
    _pageController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_pageController.hasClients) return;
    final virtual = _pageController.page?.round() ?? _initialPage;
    final real = virtual % _videos.length;
    if (real != _realIndex) setState(() => _realIndex = real);
  }

  void _go(int delta) {
    final current = _pageController.page?.round() ?? _initialPage;
    _pageController.animateToPage(current + delta, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * 0.78;
        final cardHeight = cardWidth * 9 / 16;

        return Column(
          children: [
            SizedBox(
          height: cardHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final data = _videos[index % _videos.length];
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      double page = _initialPage.toDouble();
                      if (_pageController.hasClients && _pageController.position.haveDimensions) {
                        page = _pageController.page ?? _initialPage.toDouble();
                      }
                      final delta = (page - index).clamp(-1.0, 1.0);
                      final scale = 1 - delta.abs() * 0.14;
                      final opacity = 1 - delta.abs() * 0.65;
                      return Center(
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Transform.scale(scale: scale, child: child),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _VideoCard(
                        videoData: data,
                        isActive: index == (_pageController.hasClients ? (_pageController.page?.round() ?? _initialPage) : _initialPage),
                      ),
                    ),
                  );
                },
              ),
              // Arrows float over the peeking side cards, at the outer
              // edges of the whole carousel — not against the main card.
              Positioned(
                left: 4,
                child: _CarouselArrow(icon: Icons.chevron_left_rounded, onTap: () => _go(-1)),
              ),
              Positioned(
                right: 4,
                child: _CarouselArrow(icon: Icons.chevron_right_rounded, onTap: () => _go(1)),
              ),
            ],
          ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_videos.length, (i) {
                final isActive = i == _realIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: (widget.isDark ? Colors.white : Colors.black).withOpacity(isActive ? 0.9 : 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CarouselArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Icon(icon, size: 26, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  final Map<String, String> videoData;
  final bool isActive;
  const _VideoCard({required this.videoData, required this.isActive});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.asset(widget.videoData['path']!)
      ..setLooping(true)
      ..setVolume(0);
    try {
      await ctrl.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    _ctrl = ctrl;
    setState(() => _ready = true);
    if (widget.isActive) _ctrl!.play();
  }

  @override
  void didUpdateWidget(_VideoCard old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      widget.isActive ? _ctrl?.play() : _ctrl?.pause();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_ready && _ctrl != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.size.width,
                height: _ctrl!.value.size.height,
                child: VideoPlayer(_ctrl!),
              ),
            ),
          if (!widget.isActive) Container(color: Colors.black.withOpacity(0.5)),
          // Bottom scrim so the overlay text stays legible over bright footage.
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: AnimatedOpacity(
              opacity: widget.isActive ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.videoData['sub']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.videoData['title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _VideoLink('Learn More'),
                      const SizedBox(width: 20),
                      _VideoLink('Shop Now'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoLink extends StatelessWidget {
  final String label;
  const _VideoLink(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 3),
        const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
      ],
    );
  }
}

class _WebNavLink extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _WebNavLink({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color.withOpacity(0.85)),
          ),
        ),
      ),
    );
  }
}

class _WebIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _WebIconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class HeroProduct {
  final String name;
  final String subtitle;
  final String imagePath;
  final List<Color> gradientColors;
  final String category;
  final IconData icon;

  HeroProduct({
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.gradientColors,
    required this.category,
    required this.icon,
  });
}