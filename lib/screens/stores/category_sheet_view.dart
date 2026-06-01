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
  String _customCategoryQuery = '';
  bool _showCustomInput = false;
  bool _isLoading = false;
  final TextEditingController _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    availableCategories =
        CategoryTemplates.getAvailableCategories(widget.existingCategories, widget.storeType);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String _normalizeName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  void _filterCategories(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _toggleCustomInput() {
    setState(() {
      _showCustomInput = !_showCustomInput;
      if (!_showCustomInput) {
        _customCategoryQuery = '';
        _customController.clear();
      }
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

  Future<void> _createCustomCategory() async {
    final rawName = _customController.text.trim();
    final normalized = _normalizeName(rawName);
    if (normalized.length < 3) return;

    final exactMatch = availableCategories.where((cat) {
      final name = _normalizeName(cat['name'] ?? '');
      final displayName = _normalizeName(cat['displayName'] ?? '');
      return name == normalized || displayName == normalized;
    }).toList();

    if (exactMatch.isNotEmpty) {
      await _createCategory(exactMatch.first);
      return;
    }

    await _createCategory({
      'name': rawName,
      'displayName': rawName,
    });
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

    final customNormalized = _normalizeName(_customCategoryQuery);
    final customMatches = customNormalized.length < 3
        ? <Map<String, String>>[]
        : availableCategories.where((cat) {
            final name = _normalizeName(cat['name'] ?? '');
            final displayName = _normalizeName(cat['displayName'] ?? '');
            return name.contains(customNormalized) || displayName.contains(customNormalized);
          }).toList();
    final exactExists = customNormalized.length >= 3 && customMatches.any((cat) {
      final name = _normalizeName(cat['name'] ?? '');
      final displayName = _normalizeName(cat['displayName'] ?? '');
      return name == customNormalized || displayName == customNormalized;
    });

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

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _toggleCustomInput,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      backgroundColor: Colors.white.withOpacity(0.03),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      _showCustomInput ? Icons.close_rounded : Icons.add_rounded,
                      size: 18,
                    ),
                    label: Text(
                      'Add New Category',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ),
                ),

                if (_showCustomInput) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customController,
                    onChanged: (value) {
                      setState(() {
                        _customCategoryQuery = value;
                      });
                    },
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      final normalizedInput = _customCategoryQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
                      if (normalizedInput.length >= 3 && !exactExists) {
                        _createCustomCategory();
                      }
                    },
                    style: const TextStyle(
                      fontFamily: 'TenorSans',
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type category name (min 3 letters)',
                      hintStyle: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      prefixIcon: Icon(
                        Icons.edit_rounded,
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
                  const SizedBox(height: 10),
                  if (_customCategoryQuery.trim().replaceAll(RegExp(r'\s+'), ' ').length < 3)
                    Text(
                      'Type at least 3 letters to search or create.',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    )
                  else if (exactExists)
                    Text(
                      'This category already exists. Tap it below instead of creating a duplicate.',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _createCustomCategory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: Text(
                          'Create "${_customCategoryQuery.trim()}"',
                          style: const TextStyle(
                            fontFamily: 'TenorSans',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  if (_customCategoryQuery.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 3 && customMatches.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        exactExists ? 'Existing match' : 'Suggested matches',
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Categories List
          Flexible(
            child: _showCustomInput && _customCategoryQuery.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 3
                ? (customMatches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(60),
                        child: Center(
                          child: Text(
                            'No matching category found',
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
                        itemCount: customMatches.length,
                        itemBuilder: (context, index) {
                          final category = customMatches[index];
                          final isExact = _normalizeName(category['name'] ?? '') == customNormalized ||
                              _normalizeName(category['displayName'] ?? '') == customNormalized;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildCategoryItem(
                              category,
                              disabled: isExact,
                            ),
                          );
                        },
                      ))
                : filtered.isEmpty
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

  Widget _buildCategoryItem(Map<String, String> category, {bool disabled = false}) {
    final canCreate = !disabled;
    return GestureDetector(
      onTap: (_isLoading || disabled) ? null : () => _createCategory(category),
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
                disabled ? Icons.check_circle_outline : Icons.add_circle_outline,
                color: disabled ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.6),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}