// store_admin_view_dji_real.dart - REAL DJI INSPIRATION
// Hero section + Breathing space + Minimal + Visual focus

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../auth/sign_in_view.dart';
import './add_product_view.dart';
import './orders_view.dart';
import './chat_list_view.dart';
import 'store_settings_view.dart';
import './product_details_view.dart';
import './edit_product_view.dart';
import 'category_sheet_view.dart';
import 'category_products_view.dart';
import 'category_selector_sheet.dart';

import '../../widgets/store_admin_widgets.dart';
import '../../models/store.dart';
import '../../models/category.dart';
import '../../services/api_service.dart';
import '../../services/reactive_sync_service.dart';
import '../../state_management/auth_manager.dart';

class StoreAdminView extends StatefulWidget {
  final String initialStoreName;
  
  const StoreAdminView({super.key, required this.initialStoreName});

  @override
  State<StoreAdminView> createState() => _StoreAdminViewState();
}

class _StoreAdminViewState extends State<StoreAdminView> with TickerProviderStateMixin {
  String _storeName = "";
  String _storeIconUrl = "";
  String _storeType = "";
  String _storeOwnerUid = "";
  int _storeId = 0;
  List<ProductS> _products = [];
  List<ProductS> _filteredProducts = [];
  List<Category> _categories = [];
  int _totalProductsCount = 0;
  bool _isLoading = false;
  String _searchQuery = "";
  final ScrollController _scrollController = ScrollController();
  final Set<String> _subscribedOrderChannels = {};
  StreamSubscription<Map<String, dynamic>>? _orderSyncSubscription;
  Timer? _orderRefreshTimer;
  late final AnimationController _orderPulseController;
  late final Animation<double> _orderPulseAnimation;
  int _activeOrdersCount = 0;
  String? _liveOrdersStoreId;

  @override
  void initState() {
    super.initState();
    _orderPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _orderPulseAnimation = CurvedAnimation(
      parent: _orderPulseController,
      curve: Curves.easeInOut,
    );
    ApiService.clearCache();
    _fetchStoreNameAndProducts();
  }
  
  @override
  void dispose() {
    _orderRefreshTimer?.cancel();
    _orderSyncSubscription?.cancel();
    for (final channel in _subscribedOrderChannels) {
      reactiveSyncService.unsubscribe(channel);
    }
    _orderPulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredProducts = _searchQuery.isEmpty
        ? _products
        : _products.where((p) =>
            p.name.toLowerCase().contains(_searchQuery) ||
            p.description.toLowerCase().contains(_searchQuery)).toList();
    });
  }
  
  Future<void> _fetchProductsQuietly() async {
    try {
      final response = await ApiService.getStoreProducts(_storeOwnerUid, bypassCache: true);
      
      if (response is List && mounted) {
        _totalProductsCount = response.length;
        
        final productsWithoutCategory = response.where((item) {
          final categoryId = item['category_id'];
          return categoryId == null || categoryId == 0 || categoryId == '';
        }).toList();
        
        setState(() {
          _products = productsWithoutCategory.map((item) => ProductS(
            id: item['id'].toString(),
            storeName: _storeName,
            name: item['name'] ?? '',
            price: item['price'].toString(),
            description: item['description'] ?? '',
            imageUrl: Store.getFullImageUrl(item['image_url']),
            approved: item['status'] == 'approved',
            status: item['status'] ?? 'pending',
            storeOwnerEmail: item['owner_email'] ?? '',
            storePhone: '',
            customerID: _storeOwnerUid,
            stock: item['stock'],
            currency: item['currency'] ?? 'USD',
          )).toList();
          
          _filteredProducts = _searchQuery.isEmpty ? _products : _products.where((p) =>
            p.name.toLowerCase().contains(_searchQuery)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _startLiveOrderAlerts(String storeId) async {
    if (_liveOrdersStoreId == storeId) return;

    _liveOrdersStoreId = storeId;
    _orderRefreshTimer?.cancel();
    _orderSyncSubscription?.cancel();
    _subscribedOrderChannels.removeWhere((channel) => channel.startsWith('orders:'));

    await _refreshActiveOrdersCount(storeId);

    if (!reactiveSyncService.isConnected) {
      reactiveSyncService.initialize(serverUrl: ApiService.baseHost);
      await Future.delayed(const Duration(milliseconds: 400));
    }

    final channel = 'orders:$storeId';
    reactiveSyncService.subscribe(channel);
    _subscribedOrderChannels.add(channel);

    _orderSyncSubscription = reactiveSyncService.dataStream.listen((update) {
      if (!mounted) return;
      if (update['channel'] != channel) return;
      _refreshActiveOrdersCount(storeId);
    });

    _orderRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshActiveOrdersCount(storeId);
    });
  }

  Future<void> _fetchStoreNameAndProducts() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      final uidFromAuth = authManager.userProfile?['uid'] as String? ?? '';
      
      dynamic storeData = await ApiService.getUserStore(uid: uidFromAuth);
      
      if (storeData != null && storeData is Map && storeData.isNotEmpty) {
        final storeDataMap = Map<String, dynamic>.from(storeData);
        final store = Store.fromJson(storeDataMap);
        final ownerUid = (store.uid ?? storeDataMap['uid']?.toString() ?? uidFromAuth).trim();
        final storeId = storeDataMap['id'] as int? ?? 0;
        final storeType = storeDataMap['store_type'] as String? ?? '';
        
        setState(() {
          _storeName = store.storeName.isNotEmpty ? store.storeName : widget.initialStoreName;
          _storeIconUrl = store.storeIconUrl;
          _storeOwnerUid = ownerUid;
          _storeId = storeId;
          _storeType = storeType;
        });
        
        if (storeId > 0) {
          _startLiveOrderAlerts(storeId.toString());
        }

        if (ownerUid.isNotEmpty) await _fetchProducts(ownerUid);
        if (storeId > 0) await _fetchCategories(storeId);
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    }

  Future<void> _refreshActiveOrdersCount(String storeId) async {
    try {
      final orders = await ApiService.getStoreOrders(storeId: storeId);
      if (!mounted) return;
      _updateLiveOrdersCount(_countActiveOrders(orders));
    } catch (e) {
      debugPrint('Error refreshing active orders count: $e');
    }
  }

  int _countActiveOrders(List<dynamic> orders) {
    return orders.where((order) {
      final status = (order is Map ? order['status'] : null).toString().toLowerCase();
      return !_isTerminalOrderStatus(status);
    }).length;
  }

  bool _isTerminalOrderStatus(String status) {
    return status == 'delivered' || status == 'cancelled' || status == 'canceled' || status == 'failed';
  }

  void _updateLiveOrdersCount(int newCount) {
    final previousCount = _activeOrdersCount;
    if (!mounted) return;

    setState(() {
      _activeOrdersCount = newCount;
    });

    if (newCount > 0) {
      if (!_orderPulseController.isAnimating) {
        _orderPulseController.repeat(reverse: true);
      }
      if (newCount > previousCount) {
        _orderPulseController
          ..reset()
          ..repeat(reverse: true);
      }
    } else {
      _orderPulseController.stop();
      _orderPulseController.value = 0.0;
    }
  }

  Future<void> _fetchProducts([String? ownerUidParam]) async {
    final uidToFetch = ownerUidParam ?? _storeOwnerUid;
    if (uidToFetch.isEmpty) return;

    try {
      final response = await ApiService.getStoreProducts(uidToFetch, bypassCache: true);
      
      if (response is List) {
        _totalProductsCount = response.length;
        
        final productsWithoutCategory = response.where((item) {
          final categoryId = item['category_id'];
          return categoryId == null || categoryId == 0 || categoryId == '';
        }).toList();
        
        setState(() {
          _products = productsWithoutCategory.map((item) => ProductS(
            id: item['id'].toString(),
            storeName: _storeName,
            name: item['name'] ?? '',
            price: item['price'].toString(),
            description: item['description'] ?? '',
            imageUrl: Store.getFullImageUrl(item['image_url']),
            approved: item['status'] == 'approved',
            status: item['status'] ?? 'pending',
            storeOwnerEmail: item['owner_email'] ?? '',
            storePhone: '',
            customerID: uidToFetch,
            stock: item['stock'],
            currency: item['currency'] ?? 'USD',
          )).toList();
          
          _filteredProducts = _searchQuery.isEmpty ? _products : _products.where((p) =>
            p.name.toLowerCase().contains(_searchQuery)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _fetchCategories(int storeId) async {
    try {
      final response = await ApiService.getStoreCategories(storeId, bypassCache: true);
      if (mounted) {
        final categories = response.map((item) => Category.fromJson(item)).toList();
        categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        setState(() => _categories = categories);
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _saveAndReorderCategories() async {
    try {
      final categoriesToSend = _categories
          .asMap()
          .entries
          .map((entry) => {
            'id': entry.value.id,
            'display_order': entry.key + 1,
          })
          .toList();
      await ApiService.reorderCategories(_storeId, categoriesToSend);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showCreateCategorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      isScrollControlled: true,
      builder: (context) => CategorySheetView(
        storeId: _storeId,
        existingCategories: _categories,
        storeType: _storeType,
      ),
    ).then((result) {
      if (result is Category && mounted) {
        setState(() => _categories.add(result));
      }
    });
  }

  void _showCategoryProducts(Category category) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => CategoryProductsView(
        category: category,
        storeId: _storeId,
        storeName: _storeName,
        storeOwnerEmail: Provider.of<AuthManager>(context, listen: false)
          .userProfile?['email'] ?? '',
        storePhone: '',
        onCategoryDeleted: () {
          _fetchCategories(_storeId);
          _fetchProducts();
        },
        onProductRemoved: (productId) => _fetchProducts(),
      ),
    ));
  }

  Future<void> _deleteCategory(Category category) async {
    final action = await showDialog<String?>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450), // يحافظ على حجم أنيق في اللابتوب
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161618), // لون داكن نظيف جداً
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الهيدر: أيقونة + العنوان
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Delete Category?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // الوصف الأساسي
              Text(
                'What should happen to the products inside "${category.displayName}"?',
                style: const TextStyle(
                  color: Color(0xFFEBEBF5),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You can choose to keep the products as uncategorized, or completely remove them along with this category.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              // الخيارات (محولة لكروت أنيقة بدل أزرار نصية)
              _buildDeleteOptionCard(
                title: 'Delete Category + Products',
                subtitle: 'Remove the category and all its products.',
                icon: Icons.delete_forever_rounded,
                color: Colors.redAccent,
                onTap: () => Navigator.pop(context, 'deleteProducts'),
              ),
              const SizedBox(height: 12),
              _buildDeleteOptionCard(
                title: 'Delete Category Only',
                subtitle: 'Products stay, but become uncategorized.',
                icon: Icons.folder_delete_outlined,
                color: Colors.orangeAccent,
                onTap: () => Navigator.pop(context, 'detach'),
              ),
              const SizedBox(height: 20),

              // زر الإلغاء
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || category.id == null || _storeId <= 0) return;

    try {
      final success = await ApiService.deleteCategory(
        _storeId,
        category.id!,
        deleteProducts: action == 'deleteProducts',
      );

      if (success && mounted) {
        await _fetchCategories(_storeId);
        await _fetchProducts();
      }
    } catch (e) {
      debugPrint('Error deleting category: $e');
    }
  }

  // ويدجت مساعدة لبناء خيارات الحذف بشكل كروت تفاعلية
  Widget _buildDeleteOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        highlightColor: color.withOpacity(0.05),
        splashColor: color.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            border: Border.all(
              color: color.withOpacity(0.15),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _assignProductToCategory(ProductS product) {
    showDialog(
      context: context,
      builder: (context) => CategorySelectorSheet(
        categories: _categories,
        onCategorySelected: (category) async {
          Navigator.pop(context);
          final success = await ApiService.assignProductToCategory(
            int.parse(product.id), category.id!);
          if (success && mounted) {
            setState(() {
              _products.removeWhere((p) => p.id == product.id);
              _filteredProducts.removeWhere((p) => p.id == product.id);
            });
          }
        },
      ),
    );
  }

  Future<void> _deleteProduct(String productId) async {
    setState(() => _isLoading = true);
    try {
      await ApiService.deleteProduct(productId);
      await _fetchProducts();
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  void _logout() async {
    ApiService.setAdminRole(null);
    ApiService.setAdminProfile(null);
    final authManager = Provider.of<AuthManager>(context, listen: false);
    await authManager.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SignInView()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isDesktop = screenWidth > 900;

    if (_isLoading && _storeName.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Main Content
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Transparent App Bar
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                floating: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 70,
                flexibleSpace: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 80 : 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      // Store Logo & Name
                      if (_storeIconUrl.isNotEmpty)
                        Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.network(
                              _storeIconUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.store,
                                size: 20,
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                      Text(
                        _storeName.isEmpty ? 'Store' : _storeName,
                        style: const TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      // Settings Icon
                      IconButton(
                        onPressed: () => Navigator.push(context, 
                          MaterialPageRoute(builder: (_) => const StoreSettingsView())),
                        icon: Icon(
                          Icons.settings_outlined,
                          color: Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Hero Section
              SliverToBoxAdapter(
                child: Container(
                  height: screenHeight * 0.65,
                  padding: EdgeInsets.symmetric(horizontal: isDesktop ? 120 : 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Store Icon - Large
                      if (_storeIconUrl.isNotEmpty)
                        Container(
                          width: 120,
                          height: 120,
                          margin: const EdgeInsets.only(bottom: 32),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 40,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.network(
                              _storeIconUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.store,
                                size: 60,
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                          ),
                        ),
                      
                      // Store Name - Large
                      Text(
                        _storeName.isEmpty ? 'Your Store' : _storeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 48,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          letterSpacing: -1,
                          height: 1.1,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Tagline
                      Text(
                        'Manage Your Business',
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.5),
                          letterSpacing: 0.5,
                        ),
                      ),
                      
                      const SizedBox(height: 48),
                      
                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildHeroButton(
                            'Add Product',
                            () => Navigator.push(context, 
                              MaterialPageRoute(builder: (_) => const AddProductView()))
                                .then((_) => _fetchStoreNameAndProducts()),
                            isPrimary: true,
                          ),
                          const SizedBox(width: 16),
                          _buildHeroButton(
                            'View Orders',
                            () {
                              final email = Provider.of<AuthManager>(context, listen: false)
                                .userProfile?['email'] as String?;
                              if (email != null) {
                                Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => OrdersView(storeEmail: email)));
                              }
                            },
                            isPrimary: false,
                            badgeCount: _activeOrdersCount,
                            alerting: _activeOrdersCount > 0,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Categories Section
              if (_storeType.isNotEmpty && _storeType.toLowerCase() != 'market')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 120 : 32,
                      vertical: 80,
                    ),
                    child: _buildCategoriesSection(context, isDesktop),
                  ),
                ),

              // Products Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 120 : 32,
                    vertical: 80,
                  ),
                  child: _buildProductsSection(context, isDesktop),
                ),
              ),

              // Footer
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _logout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.red.withOpacity(0.7),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sign Out',
                                style: TextStyle(
                                  fontFamily: 'TenorSans',
                                  fontSize: 14,
                                  color: Colors.red.withOpacity(0.7),
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Search Removed - Now integrated above Products section
        ],
      ),
    );
  }

  Widget _buildHeroButton(
    String text,
    VoidCallback onTap, {
    required bool isPrimary,
    int badgeCount = 0,
    bool alerting = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _orderPulseAnimation,
        builder: (context, child) {
          final pulseScale = alerting ? 1.0 + (_orderPulseAnimation.value * 0.035) : 1.0;
          return Transform.scale(
            scale: pulseScale,
            child: child,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: isPrimary ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isPrimary
                      ? Colors.transparent
                      : alerting
                          ? Colors.white.withOpacity(0.55)
                          : Colors.white.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: alerting
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.08 + (_orderPulseAnimation.value * 0.12)),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isPrimary ? Colors.black : Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -12,
                right: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(BuildContext context, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Categories',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            GestureDetector(
              onTap: _showCreateCategorySheet,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Add Category',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        Text(
          'Drag to reorder',
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 13,
            color: Colors.white.withOpacity(0.3),
            letterSpacing: 0.3,
          ),
        ),
        
        const SizedBox(height: 40),
        
        if (_categories.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: Text(
                'No categories yet',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.25),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 320,
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              scrollDirection: Axis.horizontal,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _categories.removeAt(oldIndex);
                  _categories.insert(newIndex, item);
                });
                _saveAndReorderCategories();
              },
              children: [
                for (int i = 0; i < _categories.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(_categories[i].id ?? 'new_$i'),
                    index: i,
                    child: Padding(
                      padding: EdgeInsets.only(right: i < _categories.length - 1 ? 24 : 0),
                      child: _CategoryCardLarge(
                        category: _categories[i],
                        orderNumber: i + 1,
                        onTap: () => _showCategoryProducts(_categories[i]),
                        onDelete: () => _deleteCategory(_categories[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProductsSection(BuildContext context, bool isDesktop) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 650;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: TextField(
            onChanged: _filterProducts,
            style: const TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 16,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 16,
                color: Colors.white.withOpacity(0.3),
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.white.withOpacity(0.3),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      onPressed: () => _filterProducts(''),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Products',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              '${_filteredProducts.length}',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 18,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 40),
        
        if (_totalProductsCount == 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(80),
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 80,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No products yet',
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 20,
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_filteredProducts.isEmpty && _searchQuery.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(80),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 80,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No products found',
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 20,
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try searching with different keywords',
                    style: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isDesktop ? 4 : (isPhone ? 1 : 2),
              crossAxisSpacing: isPhone ? 16 : 24,
              mainAxisSpacing: isPhone ? 16 : 24,
              childAspectRatio: isPhone ? 0.82 : 0.7,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) => _buildProductCardLarge(_filteredProducts[index]),
          ),
      ],
    );
  }

  Widget _buildProductCardLarge(ProductS product) {
  return GestureDetector(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailsView(product: product))),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06), // خلفية أغمق قليلاً
        borderRadius: BorderRadius.circular(24), // زوايا أكثر دائرية
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: product.imageUrl.isNotEmpty
                      ? Image.network(product.imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                      : Container(color: Colors.white.withOpacity(0.03), child: Center(child: Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.2)))),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: StatusBadge(
                    status: product.approved ? 'Approved' : 'Pending',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('${product.currency} ${product.price}', style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Delete
                    Tooltip(
                      message: 'Delete product',
                      child: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteProduct(product.id),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.06),
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                    // Add to category
                    Tooltip(
                      message: 'Add to category',
                      child: IconButton(
                        icon: const Icon(Icons.category_outlined, color: Colors.white),
                        onPressed: () => _assignProductToCategory(product),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.02),
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                    // Edit
                    Tooltip(
                      message: 'Edit product',
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => EditProductView(product: product),
                        )),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        ),
                        child: const Text('Edit', style: TextStyle(color: Colors.blue, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0A0A0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                onChanged: (value) {
                  _filterProducts(value);
                  Navigator.pop(context);
                },
                style: const TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 18,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Search products or categories...',
                  hintStyle: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Large Category Card
class _CategoryCardLarge extends StatefulWidget {
  final Category category;
  final int orderNumber;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CategoryCardLarge({
    required this.category,
    required this.orderNumber,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_CategoryCardLarge> createState() => _CategoryCardLargeState();
}

class _CategoryCardLargeState extends State<_CategoryCardLarge> {
  String? _lastProductImage;
  bool _isLoading = true;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _loadLastProductImage();
  }

  Future<void> _loadLastProductImage() async {
    try {
      if (widget.category.id != null) {
        final products = await ApiService.getCategoryProducts(widget.category.id!);
        if (products.isNotEmpty && mounted) {
          final lastProduct = products.last;
          final imageUrl = lastProduct['image_url'] as String? ?? '';
          setState(() {
            _lastProductImage = imageUrl.isNotEmpty ? Store.getFullImageUrl(imageUrl) : null;
            _isLoading = false;
          });
        } else if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _deleteButton(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: const Icon(Icons.close, color: Colors.white, size: 16),
        ),
      );

  Widget _badgeContainer(int orderNumber) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        orderNumber > 99 ? '99+' : '$orderNumber',
        style: const TextStyle(
          fontFamily: 'TenorSans',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_hovering ? 1.02 : 1.0),
          width: 240,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _hovering ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.08),
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 8))]
                : null,
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // background image or placeholder with rounded top
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: _isLoading
                          ? Container(color: Colors.white.withOpacity(0.03))
                          : (_lastProductImage != null
                              ? Image.network(
                                  _lastProductImage!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Container(color: Colors.white.withOpacity(0.03))),
                    ),

                    // dim overlay
                    Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.2))),

                    // controls: delete on left, badge on right
                    Positioned(top: 12, left: 12, child: _deleteButton(widget.onDelete)),
                    Positioned(top: 12, right: 12, child: _badgeContainer(widget.orderNumber)),

                    // subtle hint text when hovering
                    if (_hovering)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Opacity(
                          opacity: 0.9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Hold & drag to reorder',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.category.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}