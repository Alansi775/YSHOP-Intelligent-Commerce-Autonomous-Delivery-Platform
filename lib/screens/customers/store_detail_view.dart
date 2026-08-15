import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'dart:async';

// Models & State
import '../../state_management/cart_manager.dart';
import '../../models/store.dart';
import '../../models/product.dart';
import '../../models/category.dart' as app_category;
import '../../widgets/side_cart_view_contents.dart';
import '../../widgets/cart_icon_with_badge.dart';
import '../../services/api_service.dart';
import '../customers/product_detail_view.dart';
import '../../widgets/burger_assembly_widget.dart';
import 'package:flutter/rendering.dart';

class StoreDetailView extends StatefulWidget {
  final Store store;
  const StoreDetailView({Key? key, required this.store}) : super(key: key);

  @override
  State<StoreDetailView> createState() => _StoreDetailViewState();
}

class _StoreDetailViewState extends State<StoreDetailView> with TickerProviderStateMixin {
  late ScrollController _mainScrollController;
  final ValueNotifier<double> _scrollNotifier = ValueNotifier(0.0);
  late AnimationController _headerEntranceController;
  late AnimationController _productsRevealController;
  late AnimationController _categoryRevealController;
  late ValueNotifier<double> _burgerWelcomeOpacity;
  
  // Data
  List<Product> _products = [];
  List<app_category.Category> _categories = [];
  Map<String, GlobalKey> _categoryKeys = {};
  bool _isLoading = true;
  int? _selectedCategoryId;

  // Animation States
  bool _showMenu = false;

  // 🎯 SCROLL CONFIGURATION متناسق مع البرغر
  // 6 طبقات × 150px = 900px + 100px buffer = 1000px
  final double _burgerScrollEnd = 1700.0;

  @override
  void initState() {
    super.initState();
    _mainScrollController = ScrollController();
    _mainScrollController.addListener(_onScroll);
    _burgerWelcomeOpacity = ValueNotifier<double>(1.0);
    _headerEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _productsRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _categoryRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _loadData();
  }

  void _onScroll() {
    _scrollNotifier.value = _mainScrollController.offset;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadCategories(),
      _loadProducts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCategories() async {
    try {
      final raw = await ApiService.getStoreCategories(int.tryParse(widget.store.id) ?? 0);
      final cats = raw.map((m) => app_category.Category.fromJson(m)).toList();
      //  Sort categories by display_order
      cats.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

      final allCat = app_category.Category(
        id: null,
        storeId: int.tryParse(widget.store.id) ?? 0,
        name: 'all',
        displayName: 'All',
      );

      _categories = [allCat, ...cats];
      _categoryKeys = { for (var c in _categories) (c.id?.toString() ?? 'all') : GlobalKey() };
      
      //  DEFAULT: Show ALL products (no category selected)
      // User can then click a specific category if they want
    } catch (e) {
      _categories = [];
    }
  }

  Future<void> _loadProducts() async {
    try {
      final productsData = await ApiService.getStoreProductsById(widget.store.id);
      if (mounted) {
        setState(() {
          _products = productsData.map((data) => Product.fromJson(data)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  @override
  void dispose() {
    _headerEntranceController.dispose();
    _productsRevealController.dispose();
    _categoryRevealController.dispose();
    _mainScrollController.dispose();
    _burgerWelcomeOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF050505) : Colors.white,
      endDrawer: const Drawer(child: SideCartViewContents()),
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark 
                    ? [
                        const Color(0xFF0F0F0F),
                        const Color(0xFF000000),
                        const Color(0xFF0A0A0A),
                      ]
                    : [
                        Colors.white,
                        const Color(0xFFF8F8F8),
                        Colors.white,
                      ],
                ),
              ),
            ),
          ),

          // 🎬 BURGER ASSEMBLY - Fixed in Center
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height,
            child: RepaintBoundary(
              child: IgnorePointer(  // لا يمنع الـ scroll
                child: Center(
                  child: BurgerAssemblyWidget(
                    scrollNotifier: _scrollNotifier,
                    storeName: widget.store.storeName,
                    welcomeOpacityNotifier: _burgerWelcomeOpacity,
                    onAssembled: () async {
                      if (!mounted) return;
                      
                      setState(() => _showMenu = true);
                      
                      // Animate header
                      await Future.delayed(const Duration(milliseconds: 150));
                      _headerEntranceController.forward(from: 0.0);
                      
                      // Animate categories
                      await Future.delayed(const Duration(milliseconds: 350));
                      _categoryRevealController.forward(from: 0.0);
                      
                      // Animate products
                      await Future.delayed(const Duration(milliseconds: 550));
                      _productsRevealController.forward(from: 0.0);
                    },
                  ),
                ),
              ),
            ),
          ),

          // Scrollable Content
          CustomScrollView(
            controller: _mainScrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              //  SPACER - مساحة للبرغر
              SliverToBoxAdapter(
                child: SizedBox(height: _burgerScrollEnd),
              ),

              // Menu Content
              if (_showMenu) ...[
                // Store header
                SliverToBoxAdapter(
                  child: _buildAnimatedStoreHeader(isDark),
                ),
                
                // "THE MENU" title
                SliverToBoxAdapter(
                  child: AnimatedBuilder(
                    animation: _headerEntranceController,
                    builder: (context, child) {
                      final t = Curves.easeOut.transform(_headerEntranceController.value);
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 20),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 16),
                            child: Text(
                              'THE MENU',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'TenorSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Category filter
                SliverStickyHeader(
                  child: AnimatedBuilder(
                    animation: _categoryRevealController,
                    builder: (context, child) {
                      final t = Curves.easeOutCubic.transform(_categoryRevealController.value);
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 30),
                          child: _buildGlassyCategoryFilter(isDark),
                        ),
                      );
                    },
                  ),
                ),

                // Products grid
                if (_isLoading)
                  SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: isDark ? const Color(0xFF4A9FFF) : const Color(0xFF2196F3),
                      ),
                    ),
                  )
                else
                  _buildAnimatedProductGrid(isDark),
                
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ] else ...[
                // Placeholder
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                  ),
                ),
              ],
            ],
          ),

          // Floating UI
          _buildFloatingHeader(context, isDark),
        ],
      ),
    );
  }

  Widget _buildAnimatedStoreHeader(bool isDark) {
    return AnimatedBuilder(
      animation: _headerEntranceController,
      builder: (context, child) {
        final t = Curves.elasticOut.transform(_headerEntranceController.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.8 + (0.2 * t),
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 60,
                left: 20,
                right: 20,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? Colors.blue : Colors.black).withOpacity(0.2 * t),
                          blurRadius: 20 * t,
                          spreadRadius: 5 * t,
                        ),
                      ],
                      border: Border.all(
                        color: isDark 
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: widget.store.storeIconUrl.isEmpty
                          ? Container(
                              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                              child: Icon(Icons.store, size: 32, color: (isDark ? Colors.white : Colors.black).withOpacity(0.5)),
                            )
                          : CachedNetworkImage(
                              imageUrl: widget.store.storeIconUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 144,
                              memCacheHeight: 144,
                              errorWidget: (context, url, error) => Container(
                                color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                                child: Icon(Icons.store, size: 32, color: (isDark ? Colors.white : Colors.black).withOpacity(0.5)),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.store.storeName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.store.address ?? '',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingHeader(BuildContext context, bool isDark) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleBtn(
            Icons.arrow_back_ios_new,
            () => Navigator.pop(context),
            isDark,
          ),
          ValueListenableBuilder<double>(
            valueListenable: _burgerWelcomeOpacity,
            builder: (context, opacity, _) {
              return AnimatedOpacity(
                opacity: 1.0 - opacity,
                duration: const Duration(milliseconds: 300),
                child: CartIconWithBadge(iconColor: Colors.white),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark 
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.08),
          ),
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white : Colors.black,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildGlassyCategoryFilter(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark
              ? Colors.black.withOpacity(0.5)
              : Colors.white.withOpacity(0.8),
            border: Border(
              top: BorderSide(
                color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              ),
              bottom: BorderSide(
                color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                return AnimatedBuilder(
                  animation: _categoryRevealController,
                  builder: (context, child) {
                    final delay = index * 0.1;
                    final t = (((_categoryRevealController.value - delay) / (1 - delay)).clamp(0.0, 1.0));
                    final curve = Curves.easeOutCubic.transform(t);
                    
                    return Opacity(
                      opacity: curve.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - curve) * 20),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildCategoryChip(category, isDark),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(app_category.Category cat, bool isDark) {
    final id = cat.id;
    final isSelected = _selectedCategoryId == id;

    Color backgroundColor;
    Color textColor;
    Color borderColor;

    if (isDark) {
      if (isSelected) {
        backgroundColor = const Color(0xFF4A9FFF).withOpacity(0.2);
        textColor = const Color(0xFF4A9FFF);
        borderColor = const Color(0xFF4A9FFF).withOpacity(0.4);
      } else {
        backgroundColor = Colors.white.withOpacity(0.05);
        textColor = Colors.white70;
        borderColor = Colors.white.withOpacity(0.1);
      }
    } else {
      if (isSelected) {
        backgroundColor = const Color(0xFF2196F3).withOpacity(0.1);
        textColor = const Color(0xFF2196F3);
        borderColor = const Color(0xFF2196F3).withOpacity(0.3);
      } else {
        backgroundColor = Colors.black.withOpacity(0.03);
        textColor = Colors.black54;
        borderColor = Colors.black.withOpacity(0.08);
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() => _selectedCategoryId = id);
        _productsRevealController.forward(from: 0.0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Text(
          cat.displayName.toUpperCase(),
          style: TextStyle(
            fontFamily: 'TenorSans',
            color: textColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  /// Sort products by category order (display_order)
  List<Product> _sortProductsByCategory(List<Product> products) {
    final sorted = List<Product>.from(products);
    
    sorted.sort((a, b) {
      final catIdA = int.tryParse(a.categoryId ?? '0') ?? 0;
      final catIdB = int.tryParse(b.categoryId ?? '0') ?? 0;
      
      // Get category display order
      final catA = _categories.firstWhere(
        (c) => c.id == catIdA,
        orElse: () => app_category.Category(
          id: catIdA,
          storeId: 0,
          name: '',
          displayName: '',
          displayOrder: 999,
        ),
      );
      
      final catB = _categories.firstWhere(
        (c) => c.id == catIdB,
        orElse: () => app_category.Category(
          id: catIdB,
          storeId: 0,
          name: '',
          displayName: '',
          displayOrder: 999,
        ),
      );
      
      // Sort by category display_order
      return catA.displayOrder.compareTo(catB.displayOrder);
    });
    
    return sorted;
  }

  Widget _buildAnimatedProductGrid(bool isDark) {
    final filtered = _selectedCategoryId == null
        ? _sortProductsByCategory(_products)
        : _products.where((p) => 
            (int.tryParse(p.categoryId ?? '0') ?? 0) == _selectedCategoryId
          ).toList();

    //  ذكاء الاستجابة (Responsive Design)
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    
    // عدد الأعمدة يتكيف مع الشاشة
    final int columns = isMobile ? 2 : (screenWidth < 900 ? 3 : 4);
    
    // The card is a compact fixed-height image + two text lines now (was a
    // flex-stretched image filling most of the cell) — a shorter cell fits
    // it without a lot of empty space at the bottom.
    final double childAspectRatio = isMobile ? 0.74 : 0.85;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: childAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final product = filtered[index];
            return _buildProductCardWithAnimation(product, index, isDark);
          },
          childCount: filtered.length,
        ),
      ),
    );
  }

  // هذه الدالة ضرورية لربط الأنيميشن بالكارت
  Widget _buildProductCardWithAnimation(Product product, int index, bool isDark) {
    return AnimatedBuilder(
      animation: _productsRevealController,
      builder: (context, child) {
        final delay = (index % 6) * 0.1;
        final adjustedValue = (_productsRevealController.value - delay) / (1 - delay);
        final t = Curves.easeOutCubic.transform(adjustedValue.clamp(0.0, 1.0));
        
        final isEven = index % 2 == 0;
        final offsetX = isEven ? -30.0 * (1 - t) : 30.0 * (1 - t);
        final offsetY = 40.0 * (1 - t);
        final rotation = (isEven ? -0.1 : 0.1) * (1 - t);
        
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            transform: Matrix4.identity()
              ..translate(offsetX, offsetY)
              ..rotateZ(rotation),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: _buildProductCard(product, isDark),
    );
  }

  // Matches the native iOS app's StoreMinimalProductCard exactly: a fixed-
  // height cover image (no blur/glass), plain semi-transparent background,
  // product name, and a price + subtle add icon row. The previous version's
  // BackdropFilter blur on every single card (dozens on screen at once) was
  // real GPU/compositing cost on top of the image-cache pressure fixed
  // above — removing it also helps the "heavy while scrolling" feeling.
  Widget _buildProductCard(Product product, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailView(product: product)),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Hero(
                tag: 'product_${product.id}',
                child: SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    // Grid cards render these at well under 200px — without
                    // this, every product photo (some are multi-MB
                    // originals) was being decoded at full resolution into
                    // memory. With dozens of products on screen that blew
                    // through Flutter's image cache budget, which evicts
                    // older entries under pressure — the actual cause of
                    // images "disappearing" and everything feeling heavy
                    // while scrolling.
                    memCacheWidth: 360,
                    placeholder: (c, u) => Container(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                    ),
                    errorWidget: (c, u, e) => Container(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.2),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${product.currency} ${product.price}",
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF4A9FFF) : const Color(0xFF2196F3),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    try {
                      final cart = Provider.of<CartManager>(context, listen: false);
                      await cart.addToCart(product: product, quantity: 1);
                      ScaffoldMessenger.of(context).removeCurrentSnackBar();
                    } catch (e) {
                      ScaffoldMessenger.of(context).removeCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not add item: $e')),
                      );
                    }
                  },
                  child: Icon(
                    Icons.add_circle_rounded,
                    size: 20,
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Sticky Header
class SliverStickyHeader extends SingleChildRenderObjectWidget {
  const SliverStickyHeader({Key? key, Widget? child}) : super(key: key, child: child);
  
  @override
  RenderObject createRenderObject(BuildContext context) => RenderSliverStickyHeader();
}

class RenderSliverStickyHeader extends RenderSliverSingleBoxAdapter {
  @override
  void performLayout() {
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child!.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final double childHeight = child!.size.height;
    final double paintExtent = math.min(childHeight, constraints.remainingPaintExtent);
    geometry = SliverGeometry(
      scrollExtent: childHeight,
      paintExtent: paintExtent,
      maxPaintExtent: childHeight,
      layoutExtent: paintExtent,
      hasVisualOverflow: childHeight > constraints.remainingPaintExtent,
    );
  }
  
  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    if (child != null && mainAxisPosition >= 0 && mainAxisPosition <= (geometry?.paintExtent ?? 0)) {
      return child!.hitTest(
        BoxHitTestResult.wrap(result),
        position: Offset(crossAxisPosition, mainAxisPosition),
      );
    }
    return false;
  }
}