// lib/screens/category_home_view_dji_final.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart'; 
import '../../widgets/category_widgets.dart';
import '../../widgets/side_menu_view_contents.dart'; 
import '../../widgets/side_cart_view_contents.dart'; 
import '../../widgets/cart_icon_with_badge.dart';
import '../../screens/auth/sign_in_ui.dart';
import '../../state_management/cart_manager.dart';
import '../../state_management/theme_manager.dart';
import '../../constants/store_categories.dart';
import '../../services/api_service.dart'; 
import 'stores_list_view.dart';

class CategoryHomeView extends StatefulWidget {
  const CategoryHomeView({Key? key}) : super(key: key); 

  @override
  State<CategoryHomeView> createState() => _CategoryHomeViewState();
}

class _CategoryHomeViewState extends State<CategoryHomeView> with SingleTickerProviderStateMixin {
  // Hero Products Data
  final List<HeroProduct> heroProducts = [
    HeroProduct(
      name: 'PREMIUM FOOD',
      subtitle: 'Gourmet Excellence',
      imagePath: '9.png',
      gradientColors: [Color(0xFF2A1810), Color(0xFF0D0806)],
      category: 'Food',
    ),
    HeroProduct(
      name: 'HEALTHCARE',
      subtitle: 'Wellness Essentials',
      imagePath: 'Hero.png',
      gradientColors: [Color(0xFF1A2530), Color(0xFF000000)],
      category: 'Pharmacy',
    ),
    HeroProduct(
      name: 'FASHION',
      subtitle: 'Curated Style',
      imagePath: '0.png',
      gradientColors: [Color(0xFF25283A), Color(0xFF0A0B12)],
      category: 'Clothes',
    ),
    HeroProduct(
      name: 'FRESH MARKET',
      subtitle: 'Farm to Table',
      imagePath: '1.png',
      gradientColors: [Color(0xFF2D2418), Color(0xFF0F0A06)],
      category: 'Market',
    ),
  ];
  
  late final List<String> categories;
  final ScrollController _scrollController = ScrollController();
  int _currentProductIndex = 0;
  late AnimationController _fadeController;
  Timer? _autoRotateTimer;

  @override
  void initState() {
    super.initState();
    ApiService.clearCache();
    categories = StoreCategories.all;
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    
    // Preload images after first frame to avoid context errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadImages();
    });
    
    // Start auto-rotation immediately
    _startAutoRotate();
  }

  // Preload all product images
  void _preloadImages() {
    for (var product in heroProducts) {
      precacheImage(
        AssetImage('assets/images/${product.imagePath}'),
        context,
      );
    }
  }

  void _startAutoRotate() {
    // Cancel any existing timer
    _autoRotateTimer?.cancel();
    
    // Create new timer - rotates every 4 seconds
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
      
      // Animate fade
      _fadeController.reset();
      _fadeController.forward();
      
      // Restart timer when manually changing
      _startAutoRotate();
    }
  }

  @override
  void dispose() {
    _autoRotateTimer?.cancel();
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      drawer: const Drawer(child: SideMenuViewContents()),
      endDrawer: const Drawer(child: SideCartViewContents()),
      body: Stack(
        children: [
          // Main Content - Optimized
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
                        // Carousel
                        _buildHeroContent(),
                        
                        // Left Sidebar
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
                
                // Content Below - Cached
                RepaintBoundary(
                  child: Container(
                    color: isDark ? Colors.black : Colors.white,
                    child: Column(
                      children: [
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
          _buildFloatingHeader(isDark),
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
            // Product Image - Optimized with gapless playback
            Center(
              child: FadeTransition(
                opacity: _fadeController,
                child: Image.asset(
                  'assets/images/${currentProduct.imagePath}',
                  height: MediaQuery.of(context).size.height * 0.5,
                  fit: BoxFit.contain,
                  gaplessPlayback: true, // Prevents flicker
                  cacheHeight: (MediaQuery.of(context).size.height * 0.5 * MediaQuery.of(context).devicePixelRatio).round(),
                ),
              ),
            ),
            
            // Bottom Text
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Column(
                    children: [
                      Text(
                        currentProduct.name,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 48,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        currentProduct.subtitle,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildExploreButton(currentProduct.category),
                    ],
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
        // ✨ Elegant Fade Transition
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) {
              return StoresListView(categoryName: category);
            },
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              // Simple fade with slight scale
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

  // MARK: - Product Sidebar (3 items circular)

  Widget _buildProductSidebar() {
    return SizedBox(
      width: 200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _buildVisibleProducts(),
      ),
    );
  }

  List<Widget> _buildVisibleProducts() {
    List<Widget> widgets = [];
    
    // Show 3 products: previous, current, next
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
                // Small line - active only
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
                
                // Product name
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
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
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

  // MARK: - Floating Header

  Widget _buildFloatingHeader(bool isDark) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          left: 40,
          right: 40,
          bottom: 16,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Builder(
              builder: (context) => IconButton(
                icon: Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
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
                IconButton(
                  icon: Icon(Icons.person_outline, color: Colors.white),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                CartIconWithBadge(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Brands Section

  Widget _buildBrandsSection(bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FEATURED BRANDS',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: isDark 
                ? Colors.white.withOpacity(0.5)
                : Colors.black.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 50,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                  ? [Colors.white.withOpacity(0.6), Colors.white.withOpacity(0.1)]
                  : [Colors.black.withOpacity(0.6), Colors.black.withOpacity(0.1)],
              ),
            ),
          ),
          const SizedBox(height: 40),
          const BrandShowcaseView(),
        ],
      ),
    );
  }

  // MARK: - Footer

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

// MARK: - Models

class HeroProduct {
  final String name;
  final String subtitle;
  final String imagePath;
  final List<Color> gradientColors;
  final String category;

  HeroProduct({
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.gradientColors,
    required this.category,
  });
}