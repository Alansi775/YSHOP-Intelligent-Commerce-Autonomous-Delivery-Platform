// lib/screens/admin/returns_view.dart - DJI STYLE
// Admin Returns Management - Clean, minimal, desktop-optimized

import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ReturnsManagementView extends StatefulWidget {
  const ReturnsManagementView({Key? key}) : super(key: key);

  @override
  State<ReturnsManagementView> createState() => _ReturnsManagementViewState();
}

class _ReturnsManagementViewState extends State<ReturnsManagementView> {
  List<Map<String, dynamic>> _returnedProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReturnedProducts();
  }

  Future<void> _loadReturnedProducts() async {
    try {
      setState(() => _isLoading = true);
      final data = await ApiService.getReturnedProducts();
      setState(() {
        _returnedProducts = List<Map<String, dynamic>>.from(
          data.map((item) => item is Map<String, dynamic> ? item : {}),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: RefreshIndicator(
        onRefresh: _loadReturnedProducts,
        color: Colors.white,
        backgroundColor: const Color(0xFF0A0A0A),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withOpacity(0.5),
                ),
              )
            : _returnedProducts.isEmpty
                ? _buildEmptyState()
                : _buildReturnsList(isDesktop),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Return Requests',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'All return requests have been processed',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnsList(bool isDesktop) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 80 : 24,
                vertical: 48,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Return Requests',
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '${_returnedProducts.length}',
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  ..._returnedProducts.map((returnData) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildReturnCard(returnData, isDesktop),
                    );
                  }).toList(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnCard(Map<String, dynamic> returnData, bool isDesktop) {
    final storeName = returnData['store_name'] ?? 'Unknown Store';
    final productName = returnData['product_name'] ?? 'Unknown Product';
    final reason = returnData['return_reason'] ?? 'No reason provided';
    final driverName = returnData['driver_name'] ?? 'Not assigned';
    final returnRequestedAt = returnData['return_requested_at'] ?? '';

    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: const TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      productName,
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'PENDING',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade300,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Details Grid
          if (isDesktop)
            Row(
              children: [
                Expanded(child: _buildDetailItem('Reason', reason)),
                const SizedBox(width: 32),
                Expanded(child: _buildDetailItem('Driver', driverName)),
                const SizedBox(width: 32),
                Expanded(child: _buildDetailItem('Requested', _formatDate(returnRequestedAt))),
              ],
            )
          else
            Column(
              children: [
                _buildDetailItem('Reason', reason),
                const SizedBox(height: 16),
                _buildDetailItem('Driver', driverName),
                const SizedBox(height: 16),
                _buildDetailItem('Requested', _formatDate(returnRequestedAt)),
              ],
            ),

          // Photos
          if (_hasPhotos(returnData)) ...[
            const SizedBox(height: 32),
            Text(
              'Product Photos',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            _buildPhotosGrid(returnData, isDesktop),
          ],

          const SizedBox(height: 32),

          // Actions
          Row(
            children: [
              if (isDesktop) const Spacer(),
              Expanded(
                flex: isDesktop ? 0 : 1,
                child: _buildActionButton(
                  label: 'Approve',
                  onTap: () => _approveReturn(returnData),
                  color: Colors.green,
                  isDesktop: isDesktop,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: isDesktop ? 0 : 1,
                child: _buildActionButton(
                  label: 'Reject',
                  onTap: () => _rejectReturn(returnData),
                  color: Colors.red,
                  isDesktop: isDesktop,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 12,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'TenorSans',
            fontSize: 14,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  bool _hasPhotos(Map<String, dynamic> returnData) {
    final photoFields = ['photo_top', 'photo_bottom', 'photo_left', 'photo_right', 'photo_front', 'photo_back'];
    return photoFields.any((field) => returnData[field] != null && returnData[field].toString().isNotEmpty);
  }

  Widget _buildPhotosGrid(Map<String, dynamic> returnData, bool isDesktop) {
    final photos = {
      'Top': returnData['photo_top'],
      'Bottom': returnData['photo_bottom'],
      'Left': returnData['photo_left'],
      'Right': returnData['photo_right'],
      'Front': returnData['photo_front'],
      'Back': returnData['photo_back'],
    };

    final validPhotos = photos.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).toList();

    return GridView.count(
      crossAxisCount: isDesktop ? 6 : 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: validPhotos.map((entry) {
        final imageUrl = _buildImageUrl(entry.value);
        return GestureDetector(
          onTap: () => _showImageViewer(context, imageUrl),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.03),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white.withOpacity(0.2),
                        size: 32,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isDesktop,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isDesktop ? 150 : null,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: label == 'Approve' ? Colors.green.shade300 : Colors.red.shade300,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _approveReturn(Map<String, dynamic> returnData) async {
    try {
      // final returnId = returnData['id'];
      // await ApiService.approveReturn(returnId);
      _loadReturnedProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Return approved'),
            backgroundColor: Colors.green.withOpacity(0.9),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }
  }

  Future<void> _rejectReturn(Map<String, dynamic> returnData) async {
    try {
      // final returnId = returnData['id'];
      // await ApiService.rejectReturn(returnId);
      _loadReturnedProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Return rejected'),
            backgroundColor: Colors.orange.withOpacity(0.9),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }
  }

  // Build full image URL from relative path
  String _buildImageUrl(dynamic photoPath) {
    if (photoPath == null) return '';
    final path = photoPath.toString();
    if (path.startsWith('http')) return path;
    return 'http://localhost:3000$path';
  }

  // Show image viewer with blur backdrop
  void _showImageViewer(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white.withOpacity(0.03),
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}