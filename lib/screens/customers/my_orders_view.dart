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
import '../../widgets/order_tracker_widget.dart';

class MyOrdersView extends StatefulWidget {
  const MyOrdersView({Key? key}) : super(key: key);

  @override
  State<MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<MyOrdersView> with ReactiveSyncMixin {
  late List<Order> orders = [];
  bool isLoading = true;
  String? _customerId;
  Map<String, Map<String, dynamic>> _complaintsByOrderId = {};
  bool _complaintsLoaded = false;
  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  @override
  String get reactiveChannel {
    if (_customerId == null) return 'customer:orders:unknown';
    return 'customer:orders:$_customerId';
  }

  @override
  void onReactiveUpdate(Map<String, dynamic> update) {
    final newData = (update['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final baseUrl = ApiService.baseHost;

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
            storeType: order['store_type']?.toString() ?? '',
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
    _initializeCustomerSync();
    _loadOrders();
    _loadComplaints();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
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

  Future<void> _loadComplaints() async {
    try {
      final complaints = await ApiService.getMyComplaints();
      if (mounted) {
        setState(() {
          _complaintsByOrderId = {};
          for (final c in complaints) {
            final orderId = c['order_id']?.toString() ?? '';
            if (orderId.isNotEmpty) _complaintsByOrderId[orderId] = c;
          }
          _complaintsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading complaints: $e');
      if (mounted) setState(() => _complaintsLoaded = true);
    }
  }

  bool _isWithinComplaintWindow(Order order) {
    final expiry = order.deliveredAt.add(const Duration(minutes: 30));
    return _now.isBefore(expiry);
  }

  String _remainingTime(Order order) {
    final expiry = order.deliveredAt.add(const Duration(minutes: 30));
    final diff = expiry.difference(_now);
    if (diff.isNegative) return 'Expired';
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _complaintStatusColor(String status) {
    switch (status) {
      case 'APPROVED': return Colors.green;
      case 'REJECTED': return Colors.red;
      case 'UNDER_REVIEW': return const Color(0xFF3B82F6);
      default: return Colors.orange;
    }
  }

  void _loadOrders() async {
    try {
      final ordersList = await ApiService.getUserOrders();
      final baseUrl = ApiService.baseHost;
      
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
            storeType: order['store_type']?.toString() ?? '',
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
    final canReturn = order.isWithinReturnWindow && order.status == 'delivered';
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
                    const SizedBox(width: 12),
                    // Tracking Button
                    GestureDetector(
                      onTap: () {
                        // Navigate to order tracker
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: const Text('Track Order'),
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                              ),
                              body: const OrderTrackerWidget(),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: Colors.blue,
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

                // Complaint section — for delivered orders (30-min window)
                if (order.status == 'delivered') ...[
                  const SizedBox(height: 16),
                  _buildComplaintSection(order, isDark),
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

  Widget _buildComplaintSection(Order order, bool isDark) {
    final orderId = order.id.toString();
    final existing = _complaintsByOrderId[orderId];
    final withinWindow = _isWithinComplaintWindow(order);

    // Wait for DB check before showing any complaint button
    if (!_complaintsLoaded) {
      return const SizedBox(
        height: 32,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey))),
      );
    }

    if (!withinWindow && existing == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withinWindow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.18)),
            ),
            child: Row(children: [
              const Icon(Icons.timer_outlined, size: 13, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                'Report window: ${_remainingTime(order)} remaining',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
              ),
            ]),
          ),
        if (withinWindow) const SizedBox(height: 8),
        if (existing != null)
          _buildComplaintTrackingButton(existing, orderId, isDark)
        else if (withinWindow)
          _buildReportButton(order, isDark),
      ],
    );
  }

  Widget _buildReportButton(Order order, bool isDark) {
    return GestureDetector(
      onTap: () => _showComplaintDialog(order),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withOpacity(0.22)),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.flag_outlined, size: 15, color: Colors.red),
          SizedBox(width: 7),
          Text(
            'Report a Problem',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildComplaintTrackingButton(Map<String, dynamic> complaint, String orderId, bool isDark) {
    final status = complaint['status']?.toString() ?? 'PENDING';
    final isResolved = status == 'APPROVED' || status == 'REJECTED';
    final color = _complaintStatusColor(status);
    final label = isResolved ? 'View Response' : 'Track Complaint';
    final icon = isResolved ? Icons.mark_chat_read_outlined : Icons.track_changes_outlined;

    return GestureDetector(
      onTap: () => _showComplaintTracking(complaint),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, fontFamily: 'TenorSans')),
          const Spacer(),
          if (!isResolved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
            ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 16, color: color),
        ]),
      ),
    );
  }

  void _showComplaintDialog(Order order) {
    showDialog(
      context: context,
      builder: (_) => _ComplaintDialog(
        order: order,
        onSuccess: (complaint) {
          setState(() {
            _complaintsByOrderId[order.id.toString()] = complaint;
          });
        },
      ),
    );
  }

  void _showComplaintTracking(Map<String, dynamic> complaint) {
    showDialog(
      context: context,
      builder: (_) => _ComplaintTrackingDialog(complaint: complaint),
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

// ─── Complaint Dialog ─────────────────────────────────────────────────────────

class _ComplaintDialog extends StatefulWidget {
  final Order order;
  final void Function(Map<String, dynamic> complaint) onSuccess;
  const _ComplaintDialog({required this.order, required this.onSuccess});

  @override
  State<_ComplaintDialog> createState() => _ComplaintDialogState();
}

class _ComplaintDialogState extends State<_ComplaintDialog> {
  static final _types = <(String, String, IconData, Color)>[
    ('missing_item',   'Missing Item',  Icons.remove_shopping_cart_outlined, const Color(0xFFFFA500)),
    ('wrong_item',     'Wrong Item',   Icons.swap_horiz_rounded,             const Color(0xFF2196F3)),
    ('bad_quality',    'Bad Quality',  Icons.warning_amber_rounded,          const Color(0xFFF44336)),
    ('late_delivery',  'Late Delivery',Icons.schedule_rounded,               const Color(0xFF9C27B0)),
    ('other',          'Other Issue',  Icons.help_outline_rounded,           const Color(0xFF9E9E9E)),
  ];

  String? _selectedType;
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedType == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final result = await ApiService.submitComplaint(
        orderId: widget.order.id,
        complaintType: _selectedType!,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      final now = DateTime.now().toIso8601String();
      final newComplaint = <String, dynamic>{
        'id': result['data']?['id'] ?? 0,
        'order_id': widget.order.id.toString(),
        'complaint_type': _selectedType,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'status': 'PENDING',
        'admin_notes': null,
        'responsible_party': null,
        'created_at': now,
        'updated_at': now,
      };
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess(newComplaint);
      }
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Report a Problem', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'TenorSans')),
            const SizedBox(height: 4),
            Text('Order #${widget.order.id}', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.45))),
            const SizedBox(height: 20),
            ..._types.map(((String, String, IconData, Color) t) {
              final selected = _selectedType == t.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? t.$4.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? t.$4.withOpacity(0.45) : Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(children: [
                      Icon(t.$3, size: 18, color: selected ? t.$4 : Colors.white.withOpacity(0.45)),
                      const SizedBox(width: 10),
                      Text(t.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white.withOpacity(0.65))),
                      const Spacer(),
                      if (selected) Icon(Icons.check_circle_rounded, size: 18, color: t.$4),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Describe the issue (optional)...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.red)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AnimatedOpacity(
                  opacity: _selectedType != null ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _selectedType != null && !_saving ? _submit : null,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Complaint Tracking Dialog ────────────────────────────────────────────────

class _ComplaintTrackingDialog extends StatelessWidget {
  final Map<String, dynamic> complaint;
  const _ComplaintTrackingDialog({required this.complaint});

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED': return Colors.green;
      case 'REJECTED': return Colors.red;
      case 'UNDER_REVIEW': return const Color(0xFF3B82F6);
      default: return Colors.orange;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'APPROVED': return 'Approved';
      case 'REJECTED': return 'Rejected';
      case 'UNDER_REVIEW': return 'Under Review';
      default: return 'Pending';
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'APPROVED': return Icons.check_circle_rounded;
      case 'REJECTED': return Icons.cancel_rounded;
      case 'UNDER_REVIEW': return Icons.manage_search_rounded;
      default: return Icons.hourglass_top_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = complaint['status']?.toString() ?? 'PENDING';
    final sc = _statusColor(status);
    final adminNotes = complaint['admin_notes']?.toString() ?? '';
    final responsibleParty = complaint['responsible_party']?.toString() ?? '';
    final hasResponse = adminNotes.isNotEmpty;

    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: sc.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(_statusIcon(status), color: sc, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_statusLabel(status), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sc, fontFamily: 'TenorSans')),
              Text('Order #${complaint['order_id']}', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
            ])),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, color: Colors.white.withOpacity(0.4), size: 18),
            ),
          ]),
          const SizedBox(height: 20),
          // Progress steps
          _ProgressRow(status: status),
          const SizedBox(height: 20),
          if (hasResponse) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.shield_outlined, size: 14, color: Colors.amber),
                  SizedBox(width: 6),
                  Text('YShop Response', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
                ]),
                const SizedBox(height: 8),
                Text(adminNotes, style: TextStyle(fontSize: 13, color: Colors.amber.withOpacity(0.85), height: 1.5)),
                if (responsibleParty.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.gavel_rounded, size: 12, color: Colors.purpleAccent),
                      const SizedBox(width: 5),
                      Text(_fmtParty(responsibleParty), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                    ]),
                  ),
                ],
              ]),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.hourglass_empty_rounded, size: 18, color: Colors.white.withOpacity(0.35)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Your complaint is under review. Our team will respond within 24 hours.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55), height: 1.5),
                )),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  String _fmtParty(String raw) {
    switch (raw) {
      case 'platform': return 'YShop Platform';
      case 'store': return 'Store Owner';
      case 'driver': return 'Driver';
      case 'platform_store': return 'YShop + Store';
      case 'platform_driver': return 'YShop + Driver';
      case 'store_driver': return 'Store + Driver';
      default: return raw;
    }
  }
}

class _ProgressRow extends StatelessWidget {
  final String status;
  const _ProgressRow({required this.status});

  int get _step {
    switch (status) {
      case 'APPROVED':
      case 'REJECTED': return 2;
      case 'UNDER_REVIEW': return 1;
      default: return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Submitted', Icons.check_circle_outline),
      ('Reviewing', Icons.manage_search_outlined),
      ('Resolved',  Icons.verified_outlined),
    ];
    return Row(children: List.generate(steps.length * 2 - 1, (i) {
      if (i.isOdd) {
        final lineStep = i ~/ 2;
        return Expanded(child: Container(
          height: 2,
          color: lineStep < _step ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.1),
        ));
      }
      final idx = i ~/ 2;
      final done = idx <= _step;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(steps[idx].$2, size: 20, color: done ? Colors.white : Colors.white.withOpacity(0.2)),
        const SizedBox(height: 4),
        Text(steps[idx].$1, style: TextStyle(fontSize: 10, color: done ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.2))),
      ]);
    }));
  }
}

// Models
class Order {
  final int id;
  final String userId;
  final String storeId;
  final String storeName;
  final String storeType;
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
    this.storeType = '',
    required this.totalPrice,
    required this.currency,
    required this.status,
    required this.shippingAddress,
    required this.deliveredAt,
    required this.items,
  });

  bool get isClothesStore => storeType.trim().toLowerCase() == 'clothes';

  // clothes: 3 days, all others (food/market/pharmacy): 30 minutes
  bool get isWithinReturnWindow {
    final window = isClothesStore ? const Duration(days: 3) : const Duration(minutes: 30);
    return DateTime.now().isBefore(deliveredAt.add(window));
  }

  Duration get returnWindowRemaining {
    final window = isClothesStore ? const Duration(days: 3) : const Duration(minutes: 30);
    return deliveredAt.add(window).difference(DateTime.now());
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