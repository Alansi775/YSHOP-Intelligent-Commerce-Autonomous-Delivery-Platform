// lib/screens/category_selector_sheet.dart

import 'package:flutter/material.dart';
import 'dart:ui';
import '../../models/category.dart';
import '../../models/store.dart';
import '../../services/api_service.dart';

class CategorySelectorSheet extends StatefulWidget {
  final List<Category> categories;
  final Function(Category) onCategorySelected;

  const CategorySelectorSheet({
    Key? key,
    required this.categories,
    required this.onCategorySelected,
  }) : super(key: key);

  @override
  State<CategorySelectorSheet> createState() => _CategorySelectorSheetState();
}

class _CategorySelectorSheetState extends State<CategorySelectorSheet> {
  String _searchQuery = '';
  Map<int, String?> _lastProductImages = {};

  @override
  void initState() {
    super.initState();
    // Don't load images on init - load them only when needed
  }

  Future<String?> _getLastProductImage(int categoryId) async {
    // Return cached image if available
    if (_lastProductImages.containsKey(categoryId)) {
      return _lastProductImages[categoryId];
    }

    try {
      final products = await ApiService.getCategoryProducts(categoryId);
      if (products.isNotEmpty) {
        final lastProduct = products.last;
        final imageUrl = lastProduct['image_url'] as String? ?? '';
        final fullUrl = imageUrl.isNotEmpty 
            ? Store.getFullImageUrl(imageUrl)
            : null;
        _lastProductImages[categoryId] = fullUrl;
        return fullUrl;
      }
    } catch (e) {
      debugPrint('Error loading product image for category $categoryId: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty
        ? widget.categories
        : widget.categories
            .where((cat) =>
                cat.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                cat.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 40), // Placeholder for spacing
                              const Text(
                                'Select Category',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Search field
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: TextField(
                              onChanged: (value) => setState(() => _searchQuery = value),
                              decoration: InputDecoration(
                                hintText: 'Search categories...',
                                hintStyle: TextStyle(
                                  color: Colors.grey[500],
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: Colors.grey[400],
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Categories grid
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No categories available'
                                    : 'No categories found',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: GridView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.9,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final category = filtered[index];

                                  return GestureDetector(
                                    onTap: () => widget.onCategorySelected(category),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          // Image or Emoji - Lazy loaded only when visible
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                topRight: Radius.circular(16),
                                              ),
                                              child: category.id != null
                                                  ? FutureBuilder<String?>(
                                                      future: _getLastProductImage(category.id!),
                                                      builder: (context, snapshot) {
                                                        final imageUrl = snapshot.data;
                                                        if (imageUrl != null && imageUrl.isNotEmpty) {
                                                          return Image.network(
                                                            imageUrl,
                                                            fit: BoxFit.cover,
                                                            width: double.infinity,
                                                            errorBuilder: (context, error, stackTrace) {
                                                              return Container(
                                                                color: Colors.grey[800],
                                                                child: Center(
                                                                  child: Text(
                                                                    _extractEmoji(category.displayName),
                                                                    style: const TextStyle(fontSize: 32),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          );
                                                        }
                                                        return Container(
                                                          color: Colors.grey[800],
                                                          child: Center(
                                                            child: Text(
                                                              _extractEmoji(category.displayName),
                                                              style: const TextStyle(fontSize: 32),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    )
                                                  : Container(
                                                      color: Colors.grey[800],
                                                      child: Center(
                                                        child: Text(
                                                          _extractEmoji(category.displayName),
                                                          style: const TextStyle(fontSize: 32),
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          // Category name
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              category.displayName
                                                  .replaceAll(RegExp(r' [^\s]*$'), ''),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _extractEmoji(String displayName) {
    final parts = displayName.split(' ');
    return parts.isNotEmpty ? parts.last : '';
  }
}
