// lib/screens/admin/products_view.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../models/store.dart';
import '../../models/product.dart';
import '../../models/currency.dart';
import 'common.dart';
import 'widgets.dart' as w;

// دالة للحصول على رمز العملة الصحيح
String getCurrencySymbol(String? currencyCode) {
  if (currencyCode == null || currencyCode.isEmpty) return '';
  final currency = Currency.fromCode(currencyCode);
  return currency?.symbol ?? '';
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PRODUCTS MANAGEMENT VIEW
// ═══════════════════════════════════════════════════════════════════════════════

class ProductsManagementView extends StatefulWidget {
  final int initialTabIndex;
  final VoidCallback? onProductUpdated; //  Callback to notify parent when product is updated

  const ProductsManagementView({
    super.key,
    this.initialTabIndex = 0,
    this.onProductUpdated,
  });

  @override
  State<ProductsManagementView> createState() => _ProductsManagementViewState();
}

class _ProductsManagementViewState extends State<ProductsManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ProductSS> _pendingProducts = [];
  List<ProductSS> _approvedProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, initialIndex: widget.initialTabIndex, vsync: this);
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    debugPrint('📥 [_loadProducts] Starting to load products from backend...');
    setState(() => _isLoading = true);
    try {
      //  Clear cache first to ensure fresh data
      ApiService.clearCache();
      
      final pendingResp = await ApiService.getPendingProducts();
      final approvedResp = await ApiService.getApprovedProducts();

      if (mounted) {
        setState(() {
          //  FIX: Read status from API response, don't hardcode it!
          _pendingProducts = (pendingResp as List?)?.map((p) => ProductSS.fromMap({
                'id': p['id'],
                'name': p['name'],
                'description': p['description'],
                'price': p['price'],
                'currency': p['currency'],
                'store_id': p['store_id'],
                'store_name': p['store_name'],
                'image_url': Product.getFullImageUrl(p['image_url'] as String?),
                'stock': p['stock'],
                'status': p['status'] ?? 'pending', //  Read from API
                'owner_email': p['owner_email'],
                'store_phone': p['store_phone'],
                'category_id': p['category_id'],  //  Map category_id
                'category_name': p['category_name'],  //  Map category_name
              })).toList() ?? [];

          //  FIXED: Now using getApprovedProducts() which returns ONLY approved products
          _approvedProducts = (approvedResp as List?)?.map((p) => ProductSS.fromMap({
                'id': p['id'],
                'name': p['name'],
                'description': p['description'],
                'price': p['price'],
                'currency': p['currency'],
                'store_id': p['store_id'],
                'store_name': p['store_name'],
                'image_url': Product.getFullImageUrl(p['image_url'] as String?),
                'stock': p['stock'],
                'status': p['status'] ?? 'approved', //  Read from API
                'owner_email': p['owner_email'],
                'store_phone': p['store_phone'],
                'category_id': p['category_id'],  //  Map category_id
                'category_name': p['category_name'],  //  Map category_name
              })).toList() ?? [];

          _isLoading = false;
          
          debugPrint('📥 [_loadProducts] Loaded ${_pendingProducts.length} pending + ${_approvedProducts.length} approved');
        });
      }
    } catch (e) {
      debugPrint('❌ [_loadProducts] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveProduct(ProductSS product) async {
    try {
      await ApiService.approveProduct(product.id);
      if (mounted) {
        //  FIX: Create NEW ProductSS with updated status = 'approved' and approved = true
        setState(() {
          //  IMPORTANT: Remove from ALL lists first to avoid duplicates
          _pendingProducts.removeWhere((p) => p.id == product.id);
          _approvedProducts.removeWhere((p) => p.id == product.id);
          //  Create a new object with the correct status
          final approvedProduct = ProductSS(
            id: product.id,
            storeName: product.storeName,
            storeId: product.storeId,
            name: product.name,
            price: product.price,
            description: product.description,
            imageUrl: product.imageUrl,
            videoUrl: product.videoUrl,
            stock: product.stock,
            storeOwnerEmail: product.storeOwnerEmail,
            storePhone: product.storePhone,
            status: 'approved',  //  Explicitly set to 'approved'
            approved: true,      //  Explicitly set to true
          );
          _approvedProducts.insert(0, approvedProduct);
        });
        // Clear cache for next load
        ApiService.clearCache();
        //  Wait for backend to update before next action (same as stores)
        await Future.delayed(const Duration(milliseconds: 1000));
        //  Reload products from backend to sync state
        await _loadProducts();
        //  Notify parent (Dashboard) to refresh counts
        widget.onProductUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kAccentRed),
        );
      }
    }
  }

  Future<void> _rejectProduct(ProductSS product) async {
    try {
      //  FIX: Use 'pending' instead of 'rejected' to match the UI filtering
      await ApiService.setProductPending(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} moved to pending'),
            backgroundColor: kAccentOrange,
          ),
        );
        //  FIX: Create NEW ProductSS with updated status = 'pending'
        setState(() {
          //  IMPORTANT: Remove from ALL lists first to avoid duplicates
          _approvedProducts.removeWhere((p) => p.id == product.id);
          _pendingProducts.removeWhere((p) => p.id == product.id);
          //  Create a new object with the correct status
          final pendingProduct = ProductSS(
            id: product.id,
            storeName: product.storeName,
            storeId: product.storeId,
            name: product.name,
            price: product.price,
            description: product.description,
            imageUrl: product.imageUrl,
            videoUrl: product.videoUrl,
            stock: product.stock,
            storeOwnerEmail: product.storeOwnerEmail,
            storePhone: product.storePhone,
            status: 'pending',  //  Explicitly set to 'pending'
            approved: false,     //  Explicitly set to false
          );
          _pendingProducts.insert(0, pendingProduct);
        });
        // Clear cache for next load
        ApiService.clearCache();
        //  Wait for backend to update before next action (same as stores)
        await Future.delayed(const Duration(milliseconds: 1000));
        //  Reload products from backend to sync state
        await _loadProducts();
        //  Notify parent (Dashboard) to refresh counts
        widget.onProductUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kAccentRed),
        );
      }
    }
  }

  Future<void> _suspendProduct(ProductSS product) async {
    try {
      await ApiService.setProductPending(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} suspended'),
            backgroundColor: kAccentOrange,
          ),
        );
        //  FIX: Create NEW ProductSS with updated status = 'pending'
        setState(() {
          _approvedProducts.removeWhere((p) => p.id == product.id);
          //  Create a new object with the correct status
          final suspendedProduct = ProductSS(
            id: product.id,
            storeName: product.storeName,
            storeId: product.storeId,
            name: product.name,
            price: product.price,
            description: product.description,
            imageUrl: product.imageUrl,
            videoUrl: product.videoUrl,
            stock: product.stock,
            storeOwnerEmail: product.storeOwnerEmail,
            storePhone: product.storePhone,
            status: 'pending',  //  Explicitly set to 'pending'
            approved: false,    //  Explicitly set to false
          );
          _pendingProducts.insert(0, suspendedProduct);
        });
        //  Clear cache for next load
        ApiService.clearCache();
        //  Wait for backend to update before next action (same as stores)
        await Future.delayed(const Duration(milliseconds: 1000));
        //  Reload products from backend to sync state
        await _loadProducts();
        //  Notify parent (Dashboard) to refresh counts
        widget.onProductUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kAccentRed),
        );
      }
    }
  }

  Future<void> _deleteProduct(ProductSS product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => w.GlassConfirmDialog(
        title: 'Delete Product',
        message: 'Are you sure you want to permanently delete "${product.name}"?',
        confirmLabel: 'Delete',
        isDanger: true,
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      await ApiService.deleteProduct(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} deleted successfully'),
            backgroundColor: kAccentGreen,
          ),
        );
        //  Optimistic: remove from list immediately
        setState(() {
          _approvedProducts.removeWhere((p) => p.id == product.id);
          _pendingProducts.removeWhere((p) => p.id == product.id);
        });
        //  Only clear cache, don't reload (avoid race condition)
        ApiService.clearCache();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kAccentRed),
        );
      }
    }
  }

  void _showProductDetails(ProductSS product) {
    showDialog(
      context: context,
      builder: (_) => _ProductDetailsDialog(
        product: product,
        onApprove: () {
          Navigator.pop(context);
          final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
          if (role == 'user') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission denied'), backgroundColor: kAccentRed));
            return;
          }
          if (product.approved) {
            _suspendProduct(product);
          } else {
            _approveProduct(product);
          }
        },
        onReject: () {
          Navigator.pop(context);
          final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
          if (role == 'user') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission denied'), backgroundColor: kAccentRed));
            return;
          }
          _rejectProduct(product);
        },
        onDelete: () {
          Navigator.pop(context);
          final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
          if (role != 'superadmin') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only superadmin can delete products'), backgroundColor: kAccentRed));
            return;
          }
          _deleteProduct(product);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: kAccentBlue));

    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: kGlassBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kGlassBorder, width: 1),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            labelColor: Colors.white,
            unselectedLabelColor: kSecondaryTextColor,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.check_circle_rounded, size: 18), const SizedBox(width: 8), Text('Approved (${_approvedProducts.length})')])),
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.pending_rounded, size: 18), const SizedBox(width: 8), Text('Pending (${_pendingProducts.length})')])),
            ],
          ),
        ),

        // Quick search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: TextField(
            style: const TextStyle(color: kPrimaryTextColor),
            decoration: InputDecoration(
              hintText: 'Search product name...',
              hintStyle: TextStyle(color: kSecondaryTextColor.withOpacity(0.7)),
              prefixIcon: const Icon(Icons.search, color: kSecondaryTextColor),
              filled: true,
              fillColor: kCardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
          ),
        ),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: kAccentBlue))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsList(_approvedProducts, isApproved: true),
                    _buildProductsList(_pendingProducts, isApproved: false),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildProductsList(List<ProductSS> products, {required bool isApproved}) {
    final filtered = _searchQuery.isEmpty
        ? products
        : products.where((p) => p.name.toLowerCase().contains(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: w.EmptyStateView(
          icon: isApproved ? Icons.check_circle_rounded : Icons.pending_rounded,
          title: isApproved ? 'No Approved Products' : 'No Pending Products',
          message: isApproved ? 'No approved products yet.' : 'No pending products.',
        ),
      );
    }

    // Group products by store, then by category within each store
    final Map<String, Map<String, List<ProductSS>>> groupedByStoreAndCategory = {};
    for (final product in filtered) {
      final storeKey = '${product.storeId}|${product.storeName}'; // Use ID and name
      final categoryKey = product.categoryName ?? 'Uncategorized';
      
      groupedByStoreAndCategory.putIfAbsent(storeKey, () => {});
      groupedByStoreAndCategory[storeKey]!.putIfAbsent(categoryKey, () => []);
      groupedByStoreAndCategory[storeKey]![categoryKey]!.add(product);
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: kAccentBlue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 1200
              ? 4
              : constraints.maxWidth > 900
                  ? 3
                  : constraints.maxWidth > 600
                      ? 2
                      : 1;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Expanded category sections for each store
                ...groupedByStoreAndCategory.entries.map((storeEntry) {
                  final storeInfo = storeEntry.key.split('|');
                  final storeName = storeInfo.length > 1 ? storeInfo[1] : 'Unknown Store';
                  final categoriesInStore = storeEntry.value;
                  final totalProductsInStore = categoriesInStore.values.fold<int>(0, (sum, list) => sum + list.length);
                  
                  return _StoreSection(
                    storeName: storeName,
                    totalProducts: totalProductsInStore,
                    categoriesInStore: categoriesInStore,
                    crossAxisCount: crossAxisCount,
                    onProductTap: _showProductDetails,
                    onApprove: (product) {
                      final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
                      if (role != 'user') {
                        if (product.approved) {
                          _suspendProduct(product);
                        } else {
                          _approveProduct(product);
                        }
                      }
                    },
                    onDelete: (product) {
                      final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
                      if (role == 'superadmin') {
                        _deleteProduct(product);
                      }
                    },
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final ProductSS product;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onDelete;

  const _ProductCard({
    required this.product,
    required this.onTap,
    this.onApprove,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return w.GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: kGlassBackground,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kAccentBlue,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: kGlassBackground,
                            child: const Icon(
                              Icons.broken_image_rounded,
                              color: kSecondaryTextColor,
                              size: 40,
                            ),
                          ),
                        )
                      : Container(
                          color: kGlassBackground,
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            color: kSecondaryTextColor,
                            size: 40,
                          ),
                        ),
                ),
              ),
              // Status badge
              Positioned(
                top: 8,
                right: 8,
                child: w.StatusBadgeView(status: product.status),
              ),
            ],
          ),
          
          const SizedBox(height: 14),
          
          // Product name
          Text(
            product.name,
            style: const TextStyle(
              color: kPrimaryTextColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 6),
          
          // Store name
          Row(
            children: [
              Icon(Icons.storefront_rounded, size: 14, color: kTertiaryTextColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  product.storeName,
                  style: const TextStyle(color: kSecondaryTextColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Price
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppGradients.success,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${getCurrencySymbol(product.currency)}${product.price}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          
          const Spacer(),
          
          // Actions
          const Divider(color: kSeparatorColor, height: 20),
          Row(
            children: [
              Expanded(
                child: w.GradientButton(
                  label: product.approved ? 'Suspend' : 'Approve',
                  icon: product.approved ? Icons.pause_rounded : Icons.check_rounded,
                  onPressed: onApprove,
                  gradient: product.approved ? AppGradients.warning : AppGradients.success,
                  isSmall: true,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: kAccentRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccentRed.withOpacity(0.3), width: 1),
                ),
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_rounded, color: kAccentRed, size: 20),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📋 PRODUCT DETAILS DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _ProductDetailsDialog extends StatelessWidget {
  final ProductSS product;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _ProductDetailsDialog({
    required this.product,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: w.GlassContainer(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Product Details',
                      style: TextStyle(
                        color: kPrimaryTextColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: kSecondaryTextColor),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Product image and info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 180,
                        height: 180,
                        child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: product.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: kGlassBackground,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kAccentBlue,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: kGlassBackground,
                                  child: const Icon(
                                    Icons.broken_image_rounded,
                                    color: kSecondaryTextColor,
                                    size: 50,
                                  ),
                                ),
                              )
                            : Container(
                                color: kGlassBackground,
                                child: const Icon(
                                  Icons.inventory_2_rounded,
                                  color: kSecondaryTextColor,
                                  size: 50,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 24),
                    
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              color: kPrimaryTextColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          w.StatusBadgeView(status: product.status, fontSize: 14),
                          const SizedBox(height: 16),
                          _DetailRow(label: 'Price', value: '${getCurrencySymbol(product.currency)}${product.price}'),
                          _DetailRow(label: 'Stock', value: '${product.stock ?? "N/A"}'),
                          _DetailRow(label: 'Store', value: product.storeName),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Description
                const Text(
                  'Description',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGlassBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGlassBorder, width: 1),
                  ),
                  child: Text(
                    product.description.isEmpty ? 'No description provided' : product.description,
                    style: const TextStyle(color: kPrimaryTextColor, fontSize: 14),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Store info
                const Text(
                  'Store Information',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoCard(icon: Icons.storefront_rounded, label: 'Store Name', value: product.storeName),
                const SizedBox(height: 8),
                _InfoCard(icon: Icons.email_rounded, label: 'Owner Email', value: product.storeOwnerEmail),
                const SizedBox(height: 8),
                _InfoCard(icon: Icons.phone_rounded, label: 'Store Phone', value: product.storePhone),
                
                const SizedBox(height: 28),
                
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: w.GradientButton(
                        label: product.approved ? 'Suspend' : 'Approve',
                        icon: product.approved ? Icons.pause_rounded : Icons.check_rounded,
                        onPressed: onApprove,
                        gradient: product.approved ? AppGradients.warning : AppGradients.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: w.GlassOutlineButton(
                        label: 'Reject',
                        icon: Icons.close_rounded,
                        onPressed: onReject,
                        color: kAccentOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: kAccentRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kAccentRed.withOpacity(0.3), width: 1),
                      ),
                      child: IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_rounded, color: kAccentRed),
                        padding: const EdgeInsets.all(12),
                        tooltip: 'Delete Permanently',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: kTertiaryTextColor, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kPrimaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kGlassBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kGlassBorder, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: kAccentBlue, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: kTertiaryTextColor, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'N/A' : value,
                  style: const TextStyle(color: kPrimaryTextColor, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STORE HEADER BOX (Square Grid)
// ─────────────────────────────────────────────────────────────────────────────

class _StoreHeaderBox extends StatelessWidget {
  final String storeName;
  final int totalProducts;
  final String storeKey;
  final VoidCallback onTap;

  const _StoreHeaderBox({
    required this.storeName,
    required this.totalProducts,
    required this.storeKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: kAccentBlue.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        constraints: const BoxConstraints.expand(), // Expand to fill grid cell
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Store icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            // Store name
            Text(
              storeName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Product count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$totalProducts ${totalProducts == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STORE SECTION (Expandable with Categories)
// ─────────────────────────────────────────────────────────────────────────────

class _StoreSection extends StatefulWidget {
  final String storeName;
  final int totalProducts;
  final Map<String, List<ProductSS>> categoriesInStore;
  final int crossAxisCount;
  final Function(ProductSS) onProductTap;
  final Function(ProductSS) onApprove;
  final Function(ProductSS) onDelete;

  const _StoreSection({
    required this.storeName,
    required this.totalProducts,
    required this.categoriesInStore,
    required this.crossAxisCount,
    required this.onProductTap,
    required this.onApprove,
    required this.onDelete,
  });

  @override
  State<_StoreSection> createState() => _StoreSectionState();
}

class _StoreSectionState extends State<_StoreSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Store header (clickable to expand/collapse)
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: kAccentBlue.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Store icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                // Store name and count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.storeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${widget.totalProducts} pending product${widget.totalProducts != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Expand/collapse icon
                Icon(
                  _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        
        // Expanded categories section
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Build each category within this store
                ...widget.categoriesInStore.entries.map((catEntry) {
                  final categoryName = catEntry.key;
                  final categoryProducts = catEntry.value;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category header
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, left: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: kCardBackground,
                                border: Border.all(color: kAccentBlue, width: 1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                categoryName,
                                style: const TextStyle(
                                  color: kAccentBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: kGlassBackground,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${categoryProducts.length}',
                                style: const TextStyle(
                                  color: kSecondaryTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Products grid for this category
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: widget.crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: categoryProducts.length,
                        itemBuilder: (context, index) {
                          final product = categoryProducts[index];
                          return _ProductCard(
                            product: product,
                            onTap: () => widget.onProductTap(product),
                            onApprove: () => widget.onApprove(product),
                            onDelete: () => widget.onDelete(product),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        
        const SizedBox(height: 16),
      ],
    );
  }
}