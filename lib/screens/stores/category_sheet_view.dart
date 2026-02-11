// lib/screens/stores/category_sheet_view.dart - DJI STYLE
// Minimal, clean, elegant bottom sheet

import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../services/api_service.dart';

class CategorySheetView extends StatefulWidget {
  final int storeId;
  final List<Category> existingCategories;
  final String storeType;

  const CategorySheetView({
    Key? key,
    required this.storeId,
    required this.existingCategories,
    required this.storeType,
  }) : super(key: key);

  @override
  State<CategorySheetView> createState() => _CategorySheetViewState();
}

class _CategorySheetViewState extends State<CategorySheetView> {
  late List<Map<String, String>> availableCategories;
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    availableCategories =
        CategoryTemplates.getAvailableCategories(widget.existingCategories, widget.storeType);
  }

  void _filterCategories(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  Future<void> _createCategory(Map<String, String> category) async {
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.createCategory(
        widget.storeId,
        category['name']!,
      );

      if (result != null && mounted) {
        Navigator.pop(context, Category.fromJson(result));
      }
    } catch (e) {
      debugPrint('Error creating category: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty
        ? availableCategories
        : availableCategories
            .where((cat) =>
                cat['displayName']!.toLowerCase().contains(_searchQuery) ||
                cat['name']!.toLowerCase().contains(_searchQuery))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Category',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Search Field
                TextField(
                  onChanged: _filterCategories,
                  style: const TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search categories...',
                    hintStyle: TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Categories List
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(60),
                    child: Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No categories available'
                            : 'No results',
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final category = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCategoryItem(category),
                      );
                    },
                  ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(Map<String, String> category) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _createCategory(category),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category['displayName']!,
                    style: const TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  if (category['name'] != category['displayName']) ...[
                    const SizedBox(height: 4),
                    Text(
                      category['name']!,
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (_isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withOpacity(0.5),
                ),
              )
            else
              Icon(
                Icons.add_circle_outline,
                color: Colors.white.withOpacity(0.6),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}