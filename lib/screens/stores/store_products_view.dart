// lib/screens/store_products_view.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../services/api_service.dart'; //  استخدام API Service
import '../../models/currency.dart'; // للحصول على رموز العملات
import '../auth/admin_login_view.dart'; // لاستخدام الألوان الداكنة

// دالة للحصول على رمز العملة الصحيح
String getCurrencySymbol(String? currencyCode) {
  if (currencyCode == null || currencyCode.isEmpty) return '';
  final currency = Currency.fromCode(currencyCode);
  return currency?.symbol ?? '';
}

// --------------------------------------------------
// MARK: - Model: ProductSS (مُحدث للـ API)
// --------------------------------------------------
class ProductSS {
  final String id;
  final String storeName;
  final String name;
  final String price;
  final String description;
  final String? imageUrl;
  final String? videoUrl;
  final int? stock;
  final String storeOwnerEmail;
  final String storePhone;
  final String status;
  final bool approved;
  final String? currency;
  final String? categoryName;

  ProductSS({
    required this.id,
    required this.storeName,
    required this.name,
    required this.price,
    required this.description,
    this.imageUrl,
    this.videoUrl,
    this.stock,
    required this.storeOwnerEmail,
    required this.storePhone,
    required this.status,
    required this.approved,
    this.currency,
    this.categoryName,
  });

  //  Factory من API Response (MySQL)
  factory ProductSS.fromApi(Map<String, dynamic> data) {
    return ProductSS(
      id: data['id'].toString(),
      storeName: data['store_name'] as String? ?? 'Unknown Store',
      name: data['name'] as String? ?? '',
      price: data['price']?.toString() ?? '0.00',
      description: data['description'] as String? ?? '',
      imageUrl: data['image_url'] as String?,
      videoUrl: data['video_url'] as String?,
      stock: data['stock'] as int?,
      storeOwnerEmail: data['owner_email'] as String? ?? 'unknown@store.com',
      storePhone: data['store_phone']?.toString() ?? 'N/A', //  هنا المفتاح الصحيح
      status: data['status'] as String? ?? 'pending',
      approved: data['status'] == 'approved',
      currency: data['currency'] as String? ?? 'USD',
      categoryName: data['category_name'] as String?,
    );
  }
}

// --------------------------------------------------
// MARK: - Store Products View
// --------------------------------------------------

class StoreProductsView extends StatefulWidget {
  final String storeId;
  final String storeName;
  final bool embedInAdmin;

  const StoreProductsView({
    super.key,
    required this.storeId,
    required this.storeName,
    this.embedInAdmin = false,
  });

  @override
  State<StoreProductsView> createState() => _StoreProductsViewState();
}

class _StoreProductsViewState extends State<StoreProductsView> {
  String _searchQuery = "";
  List<ProductSS> _products = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollingTimer; //  Auto-refresh timer
  int _pollingCount = 0; // Debug: count polling requests

  @override
  void initState() {
    super.initState();
    final storeId = widget.storeId;
    debugPrint(' StoreProductsView INIT: storeId=$storeId, embedInAdmin=${widget.embedInAdmin}');
    _fetchProducts();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    debugPrint(' Polling timer STOPPED for storeId=${widget.storeId}');
    super.dispose();
  }

  //  جلب المنتجات من API
  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final storeId = widget.storeId;
    if (storeId.isEmpty || storeId == 'null' || storeId == null) {
      setState(() {
        _error = "Store ID is missing. Cannot fetch products.";
        _isLoading = false;
      });
      return;
    }

    try {
      final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'user';
      debugPrint(' _fetchProducts: storeId=$storeId, role=$role, embedInAdmin=${widget.embedInAdmin}');
      
      final response = (widget.embedInAdmin || role != 'user')
          ? await ApiService.getStoreProductsByIdAdmin(storeId)
          : await ApiService.getStoreProductsById(storeId);

      debugPrint(' API Response Count: ${response is List ? response.length : 'not a list'}');

      if (response is List) {
        final products = response.map((item) => ProductSS.fromApi(item)).toList();
        debugPrint(' Loaded ${products.length} products');
        for (var p in products) {
          debugPrint('   - Product ID: ${p.id}, Name: ${p.name}, Status: ${p.status}');
        }
        
        //  Filter to show only approved products in the store view
        final approvedProducts = products.where((p) => p.status == 'approved').toList();
        debugPrint(' Filtered to ${approvedProducts.length} approved products');
        for (var p in approvedProducts) {
          debugPrint('    Approved - ID: ${p.id}, Name: ${p.name}');
        }
        
        setState(() {
          _products = approvedProducts;
          _isLoading = false;
        });
      } else {
        setState(() {
          _products = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading products: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _refreshData() {
    _fetchProducts();
  }

  //  Fetch products WITHOUT showing loading (used for polling)
  Future<void> _fetchProductsQuietly() async {
    final storeId = widget.storeId;
    if (storeId.isEmpty || storeId == 'null' || storeId == null) {
      return;
    }

    try {
      final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'user';
      
      //  For polling, API now has NO CACHE (products change frequently)
      // Timeout after 5 seconds to not block polling
      final response = await Future.any([
        (widget.embedInAdmin || role != 'user')
            ? ApiService.getStoreProductsByIdAdmin(storeId)
            : ApiService.getStoreProductsById(storeId),
        Future.delayed(const Duration(seconds: 5)).then((_) => throw TimeoutException('Polling timeout', null)),
      ]);

      if (response is List) {
        final products = response.map((item) => ProductSS.fromApi(item)).toList();
        
        //  Filter to show only approved products (for customer view)
        final approvedProducts = products.where((p) => p.status == 'approved').toList();
        
        //  Debug: Log all products from API
        debugPrint(' POLLING DATA: Got ${products.length} total, ${approvedProducts.length} approved');
        for (var p in products) {
          debugPrint('   - Polling Result: ID=${p.id}, Status=${p.status}');
        }
        
        //  Build a set of IDs for comparison (order-independent)
        final existingIds = _products.map((p) => p.id).toSet();
        final newIds = approvedProducts.map((p) => p.id).toSet();
        
        //  Only update if product IDs actually changed
        if (existingIds != newIds) {
          debugPrint('✨ CHANGE DETECTED: Had ${existingIds.length}, now ${newIds.length}');
          debugPrint('   Added IDs: ${newIds.difference(existingIds)}');
          debugPrint('   Removed IDs: ${existingIds.difference(newIds)}');
          
          if (mounted) {
            setState(() {
              _products = approvedProducts;
              _error = null;
            });
          }
        }
      }
    } on TimeoutException {
      debugPrint('⏱️ Polling timeout (skipping this cycle)');
    } catch (e) {
      debugPrint('⚠️ Polling error: $e');
    }
  }


  // --------------------------------------------------
  // MARK: - Actions
  // --------------------------------------------------

  void _updateProductStatus(ProductSS product, {required String status}) async {
    try {
      //  OPTIMISTIC UPDATE: Update UI immediately
      setState(() {
        _products.removeWhere((p) => p.id == product.id);
        if (status == 'approved') {
          // If approving, add it to the list (since we only show approved)
          final updatedProduct = ProductSS(
            id: product.id,
            storeName: product.storeName,
            name: product.name,
            price: product.price,
            description: product.description,
            imageUrl: product.imageUrl,
            videoUrl: product.videoUrl,
            stock: product.stock,
            storeOwnerEmail: product.storeOwnerEmail,
            storePhone: product.storePhone,
            status: 'approved',
            approved: true,
          );
          _products.insert(0, updatedProduct);
        }
        // If setting to pending, just remove it (we only show approved products)
      });

      //  Show toast immediately
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Product ${status == 'approved' ? 'approved' : 'set to pending'}")),
        );
      }

      //  Send to backend in the background
      await ApiService.updateProductStatus(product.id, status);
      
      //  Clear cache
      ApiService.clearCache();
      ApiService.clearPendingRequests();
      
      //  Verify with API after a delay
      await Future.delayed(const Duration(milliseconds: 1500));
      await _fetchProducts();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
      //  Reload if error occurs
      _fetchProducts();
    }
  }

  void _deleteProduct(ProductSS product) async {
    try {
      await ApiService.deleteProduct(product.id);
      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product deleted")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  void _showProductDetails(BuildContext context, ProductSS product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
        return _ProductDetailView(
          product: product,
          onApprove: role == 'user' ? null : () => _updateProductStatus(product, status: 'approved'),
          onReject: role == 'user' ? null : () => _deleteProduct(product),
          onPending: role == 'user' ? null : () => _updateProductStatus(product, status: 'pending'),
          onDismiss: _refreshData,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int getCrossAxisCount(double width) {
      if (width > 1200) return 5;
      if (width > 800) return 4;
      if (width > 600) return 3;
      return 2;
    }

    // build page body (works both embedded and full-screen)
    final pageBody = LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = getCrossAxisCount(constraints.maxWidth);

        return Column(
          children: [
            // شريط البحث
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                style: const TextStyle(color: kPrimaryTextColor),
                decoration: InputDecoration(
                  hintText: "Search product name...",
                  hintStyle: TextStyle(color: kSecondaryTextColor.withOpacity(0.7)),
                  prefixIcon: const Icon(Icons.search, color: kSecondaryTextColor),
                  filled: true,
                  fillColor: kCardBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),

            // قائمة المنتجات
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refreshData(),
                child: _buildProductList(crossAxisCount),
              ),
            ),
          ],
        );
      },
    );

    if (!widget.embedInAdmin) {
      return Scaffold(
        backgroundColor: kDarkBackground,
        appBar: AppBar(
          title: Text('${widget.storeName} Products', style: const TextStyle(color: kPrimaryTextColor)),
          backgroundColor: kAppBarBackground,
          foregroundColor: kPrimaryTextColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshData,
            ),
          ],
        ),
        body: pageBody,
      );
    }

    // Embedded: return content that fits inside AdminHomeView (no Scaffold/appbar)
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12),
            child: Text(
              '${widget.storeName} Products',
              style: const TextStyle(color: kPrimaryTextColor, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: pageBody),
        ],
      ),
    );
  }

  Widget _buildProductList(int crossAxisCount) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccentBlue));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Error: $_error", style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshData,
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    // تطبيق فلتر البحث
    final filteredProducts = _products.where((product) {
      return product.name.toLowerCase().contains(_searchQuery);
    }).toList();

    if (filteredProducts.isEmpty && _products.isNotEmpty) {
      return Center(
        child: Text(
          "No products found matching '$_searchQuery'",
          style: const TextStyle(color: kSecondaryTextColor),
        ),
      );
    }

    if (filteredProducts.isEmpty && _products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30.0),
          child: Text(
            "This store has no products yet.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: kSecondaryTextColor),
          ),
        ),
      );
    }

    // تجميع المنتجات حسب الـ category وترتيبها أبجديا
    final Map<String, List<ProductSS>> groupedByCategory = {};
    for (final product in filteredProducts) {
      final categoryName = product.categoryName ?? 'Uncategorized';
      groupedByCategory.putIfAbsent(categoryName, () => []);
      groupedByCategory[categoryName]!.add(product);
    }

    // ترتيب الـ categories أبجديا
    final sortedCategories = groupedByCategory.keys.toList()..sort();

    final role = ApiService.cachedAdminRole?.toLowerCase() ?? 'admin';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sortedCategories.map((category) {
            final productsInCategory = groupedByCategory[category]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kCardBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF42A5F5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        color: Color(0xFF42A5F5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                // Products Grid for this category
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: productsInCategory.length,
                  itemBuilder: (context, index) {
                    final product = productsInCategory[index];
                    return _ProductCardView(
                      product: product,
                      onTap: () => _showProductDetails(context, product),
                      onApprove: role == 'user' ? null : () => _updateProductStatus(product, status: 'approved'),
                      onReject: role == 'user' ? null : () => _deleteProduct(product),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// MARK: - Nested Components (Private Widgets)
// --------------------------------------------------

class _ProductCardView extends StatelessWidget {
  final ProductSS product;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ProductCardView({
    super.key,
    required this.product,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = ApiService.cachedAdminRole?.toLowerCase() == 'user';

    return Card(
      color: kCardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl ?? '',
                fit: BoxFit.cover,
                height: 120,
                width: double.infinity,
                placeholder: (context, url) => Container(
                  height: 120,
                  color: kSecondaryTextColor.withOpacity(0.1),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 120,
                  color: kSecondaryTextColor.withOpacity(0.1),
                  child: const Center(
                    child: Icon(Icons.image_not_supported, color: kSecondaryTextColor),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.storeName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: kSecondaryTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${getCurrencySymbol(product.currency)}${product.price}',
                    style: const TextStyle(fontSize: 12, color: kSecondaryTextColor),
                  ),
                  const SizedBox(height: 8),
                  StatusBadgeView(status: product.status),

                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!isUser && onApprove != null)
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: onApprove,
                          tooltip: 'Approve',
                        ),
                      if (!isUser && onReject != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: onReject,
                          tooltip: 'Delete',
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

  void _showContextMenu(BuildContext context) {
    final items = <PopupMenuEntry<void>>[];
    if (onApprove != null) {
      items.add(PopupMenuItem(
        onTap: onApprove,
        child: const Text('Approve', style: TextStyle(color: Colors.green)),
      ));
    }
    if (onReject != null) {
      items.add(PopupMenuItem(
        onTap: onReject,
        child: const Text('Reject (Delete)', style: TextStyle(color: Colors.red)),
      ));
    }

    if (items.isEmpty) return;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        const Rect.fromLTWH(0, 0, 0, 0),
        Offset.zero & MediaQuery.of(context).size,
      ),
      items: items,
    );
  }
}

class StatusBadgeView extends StatelessWidget {
  final String status;

  const StatusBadgeView({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bgColor;

    switch (status.toLowerCase()) {
      case "pending":
        color = Colors.orange;
        bgColor = Colors.orange.withOpacity(0.2);
        break;
      case "approved":
        color = Colors.green;
        bgColor = Colors.green.withOpacity(0.2);
        break;
      case "rejected":
        color = Colors.red;
        bgColor = Colors.red.withOpacity(0.2);
        break;
      default:
        color = kSecondaryTextColor;
        bgColor = kSecondaryTextColor.withOpacity(0.1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.substring(0, 1).toUpperCase() + status.substring(1),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ActionTextButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionTextButton({
    super.key,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.5), width: 1),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// --------------------------------------------------
// MARK: - Detail Screen (Sheet)
// --------------------------------------------------

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kSecondaryTextColor,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMultiline;
  final TextAlign valueAlignment;

  const _DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isMultiline = false,
    this.valueAlignment = TextAlign.end,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryTextColor),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: valueAlignment,
              style: const TextStyle(color: kSecondaryTextColor),
              maxLines: isMultiline ? null : 1,
              overflow: isMultiline ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: kPrimaryTextColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

class _ProductDetailView extends StatelessWidget {
  final ProductSS product;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onPending;
  final VoidCallback onDismiss;

  const _ProductDetailView({
    super.key,
    required this.product,
    this.onApprove,
    this.onReject,
    this.onPending,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: kDarkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Product Review', style: TextStyle(color: kPrimaryTextColor)),
          backgroundColor: kAppBarBackground,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onDismiss();
              },
              child: const Text("Done", style: TextStyle(color: kAccentBlue, fontSize: 18)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //  Product Image - تم إصلاح القص
              Center(
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: kCardBackground,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl ?? '',
                    fit: BoxFit.contain, //  تم التغيير من cover إلى contain
                    width: double.infinity,
                    placeholder: (context, url) => Container(
                      height: 250,
                      color: kSecondaryTextColor.withOpacity(0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 250,
                      color: kSecondaryTextColor.withOpacity(0.1),
                      child: const Center(
                        child: Icon(Icons.image, size: 50, color: kSecondaryTextColor),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Product Details Section
              _DetailSection(
                title: "Product Details",
                children: [
                  _DetailRow(label: "Store Name", value: product.storeName),
                  _DetailRow(label: "Name", value: product.name),
                  _DetailRow(label: "Price", value: "${getCurrencySymbol(product.currency)}${product.price}"),
                  if (product.stock != null)
                    _DetailRow(label: "Stock", value: "${product.stock} units"),
                  _DetailRow(
                    label: "Description",
                    value: product.description,
                    isMultiline: true,
                    valueAlignment: TextAlign.start,
                  ),
                  _DetailRow(label: "Store Email", value: product.storeOwnerEmail),
                  _DetailRow(
                    label: "Store Phone",
                    value: product.storePhone, //  الآن سيظهر الرقم من API
                  ),
                  _DetailRow(label: "Status", value: product.status),
                ],
              ),
              const SizedBox(height: 30),

              // Actions Section
              _DetailSection(
                title: "Actions",
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _ActionTextButton(
                          label: "Accept",
                          color: Colors.green,
                          onPressed: onApprove == null ? null : () {
                            onApprove!();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ActionTextButton(
                          label: "Pending",
                          color: Colors.orange,
                          onPressed: onPending == null ? null : () {
                            onPending!();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ActionTextButton(
                          label: "Delete",
                          color: Colors.red,
                          onPressed: onReject == null ? null : () {
                            onReject!();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}