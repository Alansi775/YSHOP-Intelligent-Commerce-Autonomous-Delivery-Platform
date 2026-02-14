// my_orders_view.dart - TRUE DJI STYLE
// Minimal, elegant, sophisticated

import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../state_management/auth_manager.dart';
import '../../state_management/theme_manager.dart';
import '../../services/api_service.dart';
import '../../services/reactive_sync_mixin.dart';
import 'return_request_dialog.dart';

class MyOrdersView extends StatefulWidget {
  const MyOrdersView({Key? key}) : super(key: key);

  @override
  State<MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<MyOrdersView> with ReactiveSyncMixin {
  late List<Order> orders = [];
  bool isLoading = true;
  String? _customerId;

  @override
  String get reactiveChannel {
    if (_customerId == null) return 'customer:orders:unknown';
    return 'customer:orders:$_customerId';
  }

  @override
  void onReactiveUpdate(Map<String, dynamic> update) {
    final newData = (update['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final baseUrl = 'http://localhost:3000';

    if (mounted) {
      setState(() {
        orders = newData.map((order) {
          final items = (order['items'] as List?)?.map((item) {
            String imageUrl = item['imageUrl'] ?? item['image_url'] ?? '';
            if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
              imageUrl = '$baseUrl$imageUrl';
            }
            return OrderItem(
              id: item['id'] ?? 0,
              productId: item['product_id'] ?? 0,
              name: item['name'] ?? 'Unknown Product',
              imageUrl: imageUrl,
              quantity: item['quantity'] ?? 1,
              price: double.tryParse(item['price'].toString()) ?? 0.0,
            );
          }).toList() ?? [];
          
          return Order(
            id: order['id'] ?? 0,
            userId: order['user_id']?.toString() ?? '',
            storeId: order['store_id']?.toString() ?? '',
            storeName: order['store_name'] ?? 'Store',
            totalPrice: double.tryParse(order['total_price'].toString()) ?? 0.0,
            currency: order['currency'] ?? 'USD',
            status: order['status'] ?? 'pending',
            shippingAddress: order['shipping_address']?.toString() ?? 'N/A',
            deliveredAt: DateTime.tryParse(order['delivered_at']?.toString() ?? '') ?? DateTime.now(),
            items: items,
          );
        }).toList();
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Get customer ID and initialize reactive sync
    _initializeCustomerSync();
    _loadOrders();
  }

  Future<void> _initializeCustomerSync() async {
    try {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      _customerId = authManager.userProfile?['id']?.toString();
      debugPrint('🔥 Customer Sync: customerId = $_customerId');
    } catch (e) {
      debugPrint('❌ Error getting customer ID: $e');
    }
  }

  void _loadOrders() async {
    try {
      final ordersList = await ApiService.getUserOrders();
      const baseUrl = 'http://localhost:3000';
      
      setState(() {
        orders = ordersList.map((order) {
          final items = (order['items'] as List?)?.map((item) {
            String imageUrl = item['imageUrl'] ?? item['image_url'] ?? '';
            if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
              imageUrl = '$baseUrl$imageUrl';
            }
            return OrderItem(
              id: item['id'] ?? 0,
              productId: item['product_id'] ?? 0,
              name: item['name'] ?? 'Unknown Product',
              imageUrl: imageUrl,
              quantity: item['quantity'] ?? 1,
              price: double.tryParse(item['price'].toString()) ?? 0.0,
            );
          }).toList() ?? [];
          
          return Order(
            id: order['id'] ?? 0,
            userId: order['user_id']?.toString() ?? '',
            storeId: order['store_id']?.toString() ?? '',
            storeName: order['store_name'] ?? 'Store',
            totalPrice: double.tryParse(order['total_price'].toString()) ?? 0.0,
            currency: order['currency'] ?? 'USD',
            status: order['status'] ?? 'pending',
            shippingAddress: order['shipping_address'] ?? '',
            deliveredAt: order['delivered_at'] != null 
              ? DateTime.parse(order['delivered_at'])
              : DateTime.now(),
            items: items,
          );
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  /// Get currency symbol based on currency code
  String _getCurrencySymbol(String? currencyCode) {
    if (currencyCode == null || currencyCode.isEmpty) return '\$'; // Default to USD
    final code = currencyCode.toUpperCase();
    switch (code) {
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'JPY': return '¥';
      case 'INR': return '₹';
      case 'TRY': return '₺';
      case 'AED': return 'د.إ';
      case 'SAR': return 'ر.س';
      case 'EGP': return '£';
      case 'YER': return '﷼'; // Yemeni Rial
      case 'OMR': return 'ر.ع.';
      case 'QAR': return 'ر.ق';
      case 'KWD': return 'د.ك';
      case 'BHD': return 'د.ب';
      case 'JOD': return 'د.ا';
      case 'LBP': return '£';
      case 'SYP': return '£';
      case 'IQD': return 'ع.د';
      default: return code; // Fallback: show currency code
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Minimal App Bar
          SliverAppBar(
            backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
            elevation: 0,
            pinned: true,
            expandedHeight: 120,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: EdgeInsets.only(
                left: isDesktop ? 80 : 60,
                bottom: 20,
              ),
              title: Text(
                'Orders',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          // Content
          if (isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                ),
              ),
            )
          else if (orders.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(isDark))
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 80 : 24,
                vertical: 24,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _buildOrderCard(orders[index], isDark, isDesktop),
                  ),
                  childCount: orders.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark 
                ? Colors.white.withOpacity(0.04)
                : Colors.black.withOpacity(0.02),
            ),
            child: Center(
              child: Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: isDark 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.black.withOpacity(0.2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Orders Yet',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: isDark 
                ? Colors.white.withOpacity(0.6)
                : Colors.black.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your orders will appear here',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              color: isDark 
                ? Colors.white.withOpacity(0.35)
                : Colors.black.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Order order, bool isDark, bool isDesktop) {
    final canReturn = order.daysSinceDelivery <= 3 && order.status == 'delivered';
    final isReturned = order.status == 'return';

    return Container(
      constraints: BoxConstraints(maxWidth: isDesktop ? 900 : double.infinity),
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withOpacity(0.02)
          : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark 
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${order.id}',
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                              color: isDark ? Colors.white : Colors.black,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            order.storeName,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                              fontSize: 13,
                              color: isDark 
                                ? Colors.white.withOpacity(0.45)
                                : Colors.black.withOpacity(0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _getStatusText(order.status),
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(order.status),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Separator
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  isDark 
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.all(28),
            child: order.items.isNotEmpty
              ? _buildItemsHorizontalList(order.items, order.currency, isDark)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No items',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 13,
                        color: isDark 
                          ? Colors.white.withOpacity(0.3)
                          : Colors.black.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
          ),

          // Separator
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  isDark 
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                _buildDetailRow('Total', '${_getCurrencySymbol(order.currency)}${order.totalPrice.toStringAsFixed(2)}', isDark),
                const SizedBox(height: 16),
                _buildDetailRow('Delivered', DateFormat('MMM dd, yyyy').format(order.deliveredAt), isDark),
                const SizedBox(height: 16),
                _buildDetailRow('Address', order.shippingAddress, isDark, isAddress: true),
                
                // Action Button
                if (canReturn || isReturned) ...[
                  const SizedBox(height: 32),
                  _buildActionButton(order, isDark, canReturn, isReturned),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsHorizontalList(List<OrderItem> items, String currency, bool isDark) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(right: index < items.length - 1 ? 16 : 0),
          child: _buildItemCard(items[index], currency, isDark),
        ),
      ),
    );
  }

  Widget _buildItemCard(OrderItem item, String currency, bool isDark) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: isDark 
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark 
                  ? Colors.white.withOpacity(0.02)
                  : Colors.black.withOpacity(0.01),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: item.imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (c, u) => Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: isDark 
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black.withOpacity(0.2),
                          ),
                        ),
                      ),
                      errorWidget: (c, u, e) => Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: isDark 
                            ? Colors.white.withOpacity(0.15)
                            : Colors.black.withOpacity(0.15),
                          size: 32,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: isDark 
                        ? Colors.white.withOpacity(0.15)
                        : Colors.black.withOpacity(0.15),
                      size: 32,
                    ),
                  ),
            ),
          ),
          
          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Qty ${item.quantity}',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 11,
                        color: isDark 
                          ? Colors.white.withOpacity(0.4)
                          : Colors.black.withOpacity(0.4),
                      ),
                    ),
                    Text(
                      '${_getCurrencySymbol(currency)}${item.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontFamily: 'TenorSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isAddress = false}) {
    return Row(
      crossAxisAlignment: isAddress ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              color: isDark 
                ? Colors.white.withOpacity(0.45)
                : Colors.black.withOpacity(0.45),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
              height: isAddress ? 1.5 : 1.0,
            ),
            maxLines: isAddress ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(Order order, bool isDark, bool canReturn, bool isReturned) {
    final color = canReturn ? Colors.red : Colors.orange;
    final text = canReturn ? 'Request Return' : 'Cancel Return';
    
    return GestureDetector(
      onTap: () => canReturn 
        ? _handleReturn(order.id, isDark)
        : _handleCancelReturn(order.id, isDark),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered': return Colors.green;
      case 'return': return Colors.orange;
      case 'cancelled': return Colors.red;
      case 'processing': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    return status.toUpperCase();
  }

  void _handleReturn(int orderId, bool isDark) async {
    showDialog(
      context: context,
      builder: (context) => ReturnRequestDialog(
        orderId: orderId,
        orderData: {},
        onSuccess: () {
          _loadOrders();
        },
      ),
    );
  }

  void _handleCancelReturn(int orderId, bool isDark) async {
    try {
      final result = await ApiService.cancelOrderReturn(orderId);
      if (result['success'] == true) {
        _loadOrders();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Models
class Order {
  final int id;
  final String userId;
  final String storeId;
  final String storeName;
  final double totalPrice;
  final String currency;
  final String status;
  final String shippingAddress;
  final DateTime deliveredAt;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.userId,
    required this.storeId,
    required this.storeName,
    required this.totalPrice,
    required this.currency,
    required this.status,
    required this.shippingAddress,
    required this.deliveredAt,
    required this.items,
  });

  int get daysSinceDelivery {
    return DateTime.now().difference(deliveredAt).inDays;
  }
}

class OrderItem {
  final int id;
  final int productId;
  final String name;
  final String imageUrl;
  final int quantity;
  final double price;

  OrderItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.quantity,
    required this.price,
  });
}