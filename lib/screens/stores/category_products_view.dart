// lib/screens/category_products_view.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/category.dart';
import '../../models/store.dart';
import '../../widgets/store_admin_widgets.dart';
import '../../services/api_service.dart';
import './product_details_view.dart' as pdv;
import './edit_product_view.dart';

class CategoryProductsView extends StatefulWidget {
  final Category category;
  final int storeId;
  final String? storeName;
  final String? storeOwnerEmail;
  final String? storePhone;
  final VoidCallback onCategoryDeleted;
  final VoidCallback onCategoryContentChanged;

  const CategoryProductsView({
    Key? key,
    required this.category,
    required this.storeId,
    this.storeName,
    this.storeOwnerEmail,
    this.storePhone,
    required this.onCategoryDeleted,
    required this.onCategoryContentChanged,
  }) : super(key: key);

  @override
  State<CategoryProductsView> createState() => _CategoryProductsViewState();
}

class _CategoryProductsViewState extends State<CategoryProductsView> {
  List<ProductS> _products = [];
  List<ProductS> _filteredProducts = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getCategoryProducts(widget.category.id!);
      setState(() {
        _products = response
            .map((item) => ProductS(
                  id: item['id'].toString(),
                  storeName: widget.storeName ?? '',
                  name: item['name'] ?? '',
                  price: item['price'].toString(),
                  description: item['description'] ?? '',
                  imageUrl: Store.getFullImageUrl(item['image_url']),
                  approved: item['status'] == 'approved',
                  status: item['status'] ?? 'pending',
                  storeOwnerEmail: widget.storeOwnerEmail ?? item['owner_email'] ?? '',
                  storePhone: widget.storePhone ?? '',
                  customerID: '',
                  stock: item['stock'],
                  currency: item['currency'] ?? 'USD',
                ))
            .toList();
        _filteredProducts = _products;
      });
    } catch (e) {
      debugPrint('Error fetching products: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((product) =>
                product.name.toLowerCase().contains(_searchQuery) ||
                product.description.toLowerCase().contains(_searchQuery) ||
                product.price.toLowerCase().contains(_searchQuery))
            .toList();
      }
    });
  }

  Future<void> _removeProductFromCategory(String productId) async {
    try {
      final success = await ApiService.removeProductFromCategory(int.parse(productId));
      if (success && mounted) {
        widget.onCategoryContentChanged();
        _fetchProducts();
      }
    } catch (e) {
      debugPrint('Error removing product: $e');
    }
  }

  Future<void> _deleteProductPermanently(ProductS product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete ${product.name}?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete this product? This cannot be undone and you will need to enter the product details again if you want it back.',
          style: TextStyle(color: Colors.grey[300], height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await ApiService.deleteProduct(product.id);
      if (success && mounted) {
        widget.onCategoryContentChanged();
        _fetchProducts();
      }
    } catch (e) {
      debugPrint('Error deleting product permanently: $e');
    }
  }

  Future<void> _deleteCategory() async {
    final action = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete Category?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose what should happen to the ${_filteredProducts.length} products in this category.',
              style: TextStyle(color: Colors.grey[300]),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete category only: products will stay but become uncategorized.\n'
              'Delete category + products: remove both from this store completely.',
              style: TextStyle(
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Cancel keeps everything unchanged.',
              style: TextStyle(
                color: Colors.red[400],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'detach'),
            child: const Text(
              'Delete Category Only',
              style: TextStyle(color: Colors.orange),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'deleteProducts'),
            child: const Text(
              'Delete Category + Products',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (action == null) return;

    final deleteProducts = action == 'deleteProducts';

    if (action == 'detach' || deleteProducts) {
      setState(() => _isDeleting = true);
      try {
        final success =
            await ApiService.deleteCategory(
          widget.storeId,
          widget.category.id!,
          deleteProducts: deleteProducts,
        );
        if (success && mounted) {
          widget.onCategoryDeleted();
          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint('Error deleting category: $e');
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  void _onProductTap(ProductS product) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => pdv.ProductDetailsView(product: product),
    ));
  }

  void _onEditProduct(ProductS product) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => EditProductView(product: product),
    )).then((result) {
      if (result == true) {
        _fetchProducts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const double _maxWidth = 1100.0;
    final screenWidth = MediaQuery.of(context).size.width;
    
    int productCrossAxisCount;
    if (screenWidth > 1000) {
      productCrossAxisCount = 4;
    } else if (screenWidth > 600) {
      productCrossAxisCount = 3;
    } else {
      productCrossAxisCount = 2;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.displayName),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F).withOpacity(0.8),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
            ),
          ),
        ),
      ),
      body: Container(
        color: const Color(0xFF0F0F0F),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              children: [
                // Search
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      onChanged: _filterProducts,
                      decoration: InputDecoration(
                        hintText: 'Search products in category...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close, color: Colors.grey[400]),
                                onPressed: () => _filterProducts(''),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                // Products Grid - نفس تصميم store_admin_view
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : _filteredProducts.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No products in this category'
                                    : 'No products found',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: productCrossAxisCount,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 20,
                                  childAspectRatio: 0.75,
                                ),
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = _filteredProducts[index];
                                  return CategoryProductCard(
                                    product: product,
                                    onDelete: () => _deleteProductPermanently(product),
                                    onTap: () => _onProductTap(product),
                                    onEdit: () => _onEditProduct(product),
                                    onRemoveFromCategory: () => _removeProductFromCategory(product.id),
                                  );
                                },
                              ),
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

// بطاقة المنتج داخل الفئة - نفس تصميم ProductCardView
class CategoryProductCard extends StatelessWidget {
  final ProductS product;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemoveFromCategory;

  const CategoryProductCard({
    Key? key,
    required this.product,
    required this.onDelete,
    required this.onTap,
    required this.onEdit,
    required this.onRemoveFromCategory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        hoverColor: Colors.white.withOpacity(0.02),
        splashColor: Colors.white.withOpacity(0.05),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(24),
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
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.white.withOpacity(0.03),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.white.withOpacity(0.03),
                          child: Center(
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2)),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: StatusBadge(status: product.approved ? 'Approved' : 'Pending'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${getCurrencySymbol(product.currency)}${product.price}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Tooltip(
                          message: 'Delete product permanently',
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: onDelete,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red.withOpacity(0.06),
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Remove from category',
                          child: IconButton(
                            icon: const Icon(Icons.arrow_forward, color: Colors.orange),
                            onPressed: onRemoveFromCategory,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.orange.withOpacity(0.06),
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Edit product',
                          child: TextButton(
                            onPressed: onEdit,
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.blue.withOpacity(0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                            ),
                            child: const Text(
                              'Edit',
                              style: TextStyle(fontSize: 13, color: Colors.blue),
                            ),
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
      ),
    );
  }
}
