// lib/screens/stores/category_reorder_view.dart

import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../services/api_service.dart';

class CategoryReorderView extends StatefulWidget {
  final int storeId;
  final List<Category> categories;
  final VoidCallback onReorderComplete;

  const CategoryReorderView({
    Key? key,
    required this.storeId,
    required this.categories,
    required this.onReorderComplete,
  }) : super(key: key);

  @override
  State<CategoryReorderView> createState() => _CategoryReorderViewState();
}

class _CategoryReorderViewState extends State<CategoryReorderView> {
  late List<Category> _reorderedCategories;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // ترتيب الفئات حسب display_order
    _reorderedCategories = List.from(widget.categories);
    _reorderedCategories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }

  Future<void> _saveReorder() async {
    setState(() => _isSaving = true);

    try {
      // تحضير البيانات للإرسال
      final categoriesToSend = _reorderedCategories
          .asMap()
          .entries
          .map((entry) {
            return {
              'id': entry.value.id,
              'display_order': entry.key + 1, // ترقيم من 1
            };
          })
          .toList();

      final success = await ApiService.reorderCategories(
        widget.storeId,
        categoriesToSend,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم حفظ الترتيب بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onReorderComplete();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ حدث خطأ في حفظ الترتيب'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving reorder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ حدث خطأ في الاتصال'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'ترتيب الفئات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _reorderedCategories.isEmpty
          ? Center(
              child: Text(
                'لا توجد فئات لترتيبها',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
            )
          : Column(
              children: [
                // Info banner
                Container(
                  color: const Color(0xFF1E1E1E),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.amber, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'اسحب الفئات لإعادة ترتيبها. الترتيب الأعلى سيظهر أولاً.',
                          style: TextStyle(color: Colors.grey[300], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                // Reorderable list
                Expanded(
                  child: ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _reorderedCategories.removeAt(oldIndex);
                        _reorderedCategories.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (int i = 0; i < _reorderedCategories.length; i++)
                        _buildCategoryItem(
                          key: ValueKey(_reorderedCategories[i].id),
                          index: i,
                          category: _reorderedCategories[i],
                        ),
                    ],
                  ),
                ),
                // Save button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveReorder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'حفظ الترتيب',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryItem({
    required ValueKey key,
    required int index,
    required Category category,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.drag_handle, color: Colors.blue, size: 20),
                Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          category.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '${category.productCount} منتج',
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '#${index + 1}',
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
