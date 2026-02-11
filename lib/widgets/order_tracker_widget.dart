// استبدل order_tracker_widget.dart بهذا الكود الكامل
// نسخة كاملة مع Map Widget للتتبع المباشر

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/navigation_service.dart';
import 'package:intl/intl.dart';
import '../state_management/cart_manager.dart';
import '../state_management/auth_manager.dart';
import '../models/product.dart';
import '../screens/auth/sign_in_ui.dart';
import 'dart:ui' as ui;
import '../main.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Order Tracker - DJI Style
class OrderTrackerWidget extends StatefulWidget {
  const OrderTrackerWidget({Key? key}) : super(key: key);

  @override
  State<OrderTrackerWidget> createState() => _OrderTrackerWidgetState();
}

class _OrderTrackerWidgetState extends State<OrderTrackerWidget> {
  Map<String, dynamic>? _cachedOrder;
  String? _currentOrderId;
  Timer? _pollingTimer;
  bool _isLoading = false;
  bool _isCheckingLatestOrder = false;
  bool _isDialogOpen = false;
  String? _lastCheckedUserId;
  DateTime? _lastCheckTime;
  int _consecutiveAuthErrors = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authManager = Provider.of<AuthManager>(context, listen: true);
    
    if (!authManager.isAuthenticated && _lastCheckedUserId != null) {
      _clearOrderData();
      _lastCheckedUserId = null;
      _consecutiveAuthErrors = 0;
      return;
    }
    
    if (authManager.isAuthenticated && authManager.userProfile != null) {
      final newUserId = authManager.userProfile?['uid']?.toString();
      
      if (newUserId != _lastCheckedUserId && newUserId != null) {
        _lastCheckedUserId = newUserId;
        _consecutiveAuthErrors = 0;
        
        final now = DateTime.now();
        if (_lastCheckTime == null || now.difference(_lastCheckTime!).inSeconds >= 5) {
          _lastCheckTime = now;
          _checkForLatestOrder();
        }
      }
    }
  }

  void _clearOrderData() {
    _pollingTimer?.cancel();
    if (mounted) {
      setState(() {
        _cachedOrder = null;
        _currentOrderId = null;
        _isLoading = false;
        _isCheckingLatestOrder = false;
      });
    }
    Future.microtask(() {
      if (mounted) {
        try {
          Provider.of<CartManager>(context, listen: false).setLastOrderId(null);
        } catch (e) {}
      }
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is DateTime) {
      if (raw.isUtc) {
        return DateTime(raw.year, raw.month, raw.day, raw.hour, raw.minute, raw.second);
      }
      return raw;
    }
    if (raw is String) {
      final sqlTs = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})');
      final match = sqlTs.firstMatch(raw);
      if (match != null) {
        return DateTime(
          int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!),
          int.parse(match.group(4)!), int.parse(match.group(5)!), int.parse(match.group(6)!),
        );
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second);
      }
      return DateTime.now();
    }
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is Map && raw.containsKey('seconds')) {
      final secs = raw['seconds'];
      if (secs is int) return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    }
    return DateTime.now();
  }

  Future<void> _checkForLatestOrder() async {
    if (_isCheckingLatestOrder) return;
    if (_consecutiveAuthErrors >= 3) return;
    
    final authManager = Provider.of<AuthManager>(context, listen: false);
    if (!authManager.isAuthenticated) {
      _clearOrderData();
      return;
    }
    
    if (_currentOrderId != null) return;
    
    _isCheckingLatestOrder = true;
    try {
      final orders = await ApiService.getUserOrders();
      _consecutiveAuthErrors = 0;
      
      if (orders != null && orders.isNotEmpty && mounted) {
        Map<String, dynamic>? latestPendingOrder;
        for (final order in orders) {
          final status = _normalizeStatus(order['status']?.toString() ?? 'pending');
          if (status != 'Delivered' && status != 'Cancelled') {
            if (latestPendingOrder == null) {
              latestPendingOrder = order;
            } else {
              final currentDate = _parseDate(order['created_at'] ?? order['createdAt']);
              final latestDate = _parseDate(latestPendingOrder['created_at'] ?? latestPendingOrder['createdAt']);
              if (currentDate.isAfter(latestDate)) {
                latestPendingOrder = order;
              }
            }
          }
        }

        if (latestPendingOrder != null) {
          final orderId = latestPendingOrder['id']?.toString() ?? latestPendingOrder['order_id']?.toString();
          if (orderId != null && orderId.isNotEmpty && mounted) {
            setState(() {
              _cachedOrder = Map<String, dynamic>.from(latestPendingOrder!);
              _currentOrderId = orderId;
            });
            Provider.of<CartManager>(context, listen: false).setLastOrderId(orderId);
            _startLightPolling(orderId);
          }
        }
      }
    } catch (e) {
      if (e is ApiException && e.isUnauthorized) {
        _consecutiveAuthErrors++;
        if (_consecutiveAuthErrors >= 3) _clearOrderData();
      } else if (e is ApiException && e.isRateLimited) {
        _consecutiveAuthErrors = 0;
        _clearOrderData();
      } else {
        _consecutiveAuthErrors = 0;
      }
    } finally {
      _isCheckingLatestOrder = false;
    }
  }

  void _startLightPolling(String orderId) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      final authManager = Provider.of<AuthManager>(context, listen: false);
      if (!authManager.isAuthenticated) {
        _clearOrderData();
        return;
      }
      if (!mounted) return;
      try {
        final orders = await ApiService.getUserOrders();
        if (orders != null) {
          for (final order in orders) {
            if ((order['id']?.toString() ?? order['order_id']?.toString()) == orderId) {
              if (mounted) {
                setState(() => _cachedOrder!['status'] = order['status']);
              }
              return;
            }
          }
        }
      } catch (e) {
        if (e is ApiException && e.isUnauthorized) {
          _pollingTimer?.cancel();
          _clearOrderData();
        } else if (e is ApiException && e.isRateLimited) {
          _pollingTimer?.cancel();
          Future.delayed(const Duration(minutes: 10), () {
            if (mounted && _currentOrderId == orderId) {
              _startLightPolling(orderId);
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartManager = Provider.of<CartManager>(context);
    final orderId = cartManager.lastOrderId;
    final authManager = Provider.of<AuthManager>(context);

    return ValueListenableBuilder<String?>(
      valueListenable: ApiService.adminRoleNotifier,
      builder: (context, adminRole, child) {
        // Hide order tracker for admins, delivery drivers, and any non-customer users
        if (adminRole != null) return const SizedBox.shrink();
        
        // Check if current user is a delivery driver or store owner
        final userType = authManager.userProfile?['userType'] as String?;
        if (userType == 'deliveryDriver' || userType == 'storeOwner') {
          return const SizedBox.shrink();
        }

        if (orderId == null && !_isCheckingLatestOrder && _currentOrderId == null) {
          Future.microtask(() {
            if (mounted) _checkForLatestOrder();
          });
          return const SizedBox.shrink();
        }

        if (orderId == null) {
          _pollingTimer?.cancel();
          return const SizedBox.shrink();
        }

        if (_currentOrderId != orderId) {
          Future.microtask(() {
            if (mounted) _startSmartPolling(orderId);
          });
        }

        if (_cachedOrder == null && _isLoading) {
          return _buildLoadingIndicator(context);
        }

        if (_cachedOrder == null) return const SizedBox.shrink();

        final status = _normalizeStatus(_cachedOrder!['status']?.toString() ?? 'pending');
        return _buildTrackerIndicator(context, orderId, status);
      },
    );
  }

  void _startSmartPolling(String orderId) {
    if (_currentOrderId == orderId && _pollingTimer != null) return;
    _currentOrderId = orderId;
    _pollingTimer?.cancel();
    _fetchOrder(orderId, isInitial: true);
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchOrder(orderId, isInitial: false);
    });
  }

  Future<void> _fetchOrder(String orderId, {bool isInitial = false}) async {
    if (_isLoading && !isInitial) return;
    try {
      if (isInitial) setState(() => _isLoading = true);
      final order = await ApiService.getOrderById(orderId);
      if (order != null && mounted) {
        setState(() {
          _cachedOrder = Map<String, dynamic>.from(order);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20),
          ],
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildTrackerIndicator(BuildContext context, String orderId, String status) {
    Color statusColor = _getStatusColor(status);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (status == 'Delivered') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 1), () {
          Provider.of<CartManager>(context, listen: false).setLastOrderId(null);
        });
      });
      return const SizedBox.shrink();
    }

    IconData statusIcon;
    String statusText;
    String? statusMessage;
    bool isReturnStatus = status == 'Return Pending';

    switch (status) {
      case 'Pending':
        statusIcon = Icons.schedule;
        statusText = 'Pending';
        break;
      case 'Processing':
        statusIcon = Icons.shopping_bag_outlined;
        statusText = 'Processing';
        break;
      case 'Out for Delivery':
        statusIcon = Icons.local_shipping_outlined;
        statusText = 'On the way';
        break;
      case 'Return Pending':
        statusIcon = Icons.undo;
        statusText = 'Return Pending';
        statusMessage = 'Driver will contact you soon to pick up the return order';
        break;
      default:
        statusIcon = Icons.info_outline;
        statusText = 'Order';
    }

    return ValueListenableBuilder<bool>(
      valueListenable: isAboveHeroNotifier,
      builder: (context, isAboveHero, child) {
        final useWhiteBackground = isDark ? false : isAboveHero;
        final containerColor = useWhiteBackground ? Colors.white : (isDark ? Colors.white : Colors.black);
        final textIconColor = useWhiteBackground ? Colors.black : (isDark ? Colors.black : Colors.white);
        final borderColor = useWhiteBackground
          ? Colors.black.withOpacity(0.15)
          : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12));

        return Positioned(
          bottom: 24,
          right: 24,
          child: AnimatedOpacity(
            opacity: _isDialogOpen ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: _isDialogOpen,
              child: GestureDetector(
                onTap: () => _showOrderDetailsDialog(context, orderId, status),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textIconColor,
                          letterSpacing: 0.3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(statusIcon, color: textIconColor.withOpacity(0.8), size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOrderDetailsDialog(BuildContext context, String orderId, String currentStatus) {
    setState(() => _isDialogOpen = true);
    
    final navContext = NavigationService.navigatorKey.currentContext;
    if (navContext == null) return;
    
    Navigator.of(navContext).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.5),
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Material(
                color: Colors.transparent,
                child: _OrderDetailsDialog(
                  orderId: orderId,
                  initialData: _cachedOrder,
                  toDouble: _toDouble,
                  parseDate: _parseDate,
                ),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  String _normalizeStatus(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'pending': return 'Pending';
      case 'confirmed':
      case 'processing': return 'Processing';
      case 'shipped':
      case 'out for delivery':
      case 'out_for_delivery': return 'Out for Delivery';
      case 'delivered': return 'Delivered';
      case 'cancelled': return 'Cancelled';
      case 'return': return 'Return Pending';
      default: return raw;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending': return Colors.orange.shade600;
      case 'Processing': return Colors.blue.shade600;
      case 'Out for Delivery': return Colors.green.shade600;
      case 'Delivered': return Colors.green.shade700;
      case 'Return Pending': return Colors.amber.shade600;
      default: return Colors.red.shade600;
    }
  }
}

// ============== ORDER DETAILS DIALOG ==============
class _OrderDetailsDialog extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic>? initialData;
  final double Function(dynamic) toDouble;
  final DateTime Function(dynamic) parseDate;

  const _OrderDetailsDialog({
    required this.orderId,
    required this.initialData,
    required this.toDouble,
    required this.parseDate,
  });

  @override
  State<_OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<_OrderDetailsDialog> {
  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  bool _isAugmented = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchFullOrder();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _statusTimer = null;
    super.dispose();
  }

  Future<void> _fetchFullOrder() async {
    try {
      final orders = await ApiService.getUserOrders();
      if (orders != null && orders.isNotEmpty) {
        Map<String, dynamic>? foundOrder;
        for (final order in orders) {
          final orderId = order['id']?.toString() ?? order['order_id']?.toString();
          if (orderId == widget.orderId) {
            foundOrder = order;
            break;
          }
        }
        if (foundOrder != null && mounted) {
          setState(() {
            _orderData = Map<String, dynamic>.from(foundOrder!);
            _isLoading = false;
          });
          _augmentOrderData();
          return;
        }
      }
      final order = await ApiService.getOrderById(widget.orderId);
      if (order != null && mounted) {
        setState(() {
          _orderData = Map<String, dynamic>.from(order);
          _isLoading = false;
        });
        _augmentOrderData();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshStatus() async {
    if (_orderData == null) return;
    try {
      final orders = await ApiService.getUserOrders();
      if (orders != null) {
        for (final order in orders) {
          if ((order['id']?.toString() ?? order['order_id']?.toString()) == widget.orderId) {
            final newStatus = order['status'];
            if (newStatus != _orderData!['status'] && mounted) {
              setState(() => _orderData!['status'] = newStatus);
            }
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _augmentOrderData() async {
    if (_orderData == null || _isAugmented) return;
    try {
      final order = _orderData!;
      order['documentId'] = order['id']?.toString() ?? order['order_id']?.toString() ?? 'N/A';
      if (order['total_price'] != null && order['total'] == null) order['total'] = order['total_price'];
      if (order['created_at'] != null && order['createdAt'] == null) order['createdAt'] = order['created_at'];

      var items = (order['items'] as List<dynamic>?) ?? [];
      if (items.isNotEmpty) {
        final futures = <Future>[];
        final productCache = <String, dynamic>{};
        for (final item in items) {
          final pid = (item['product_id'] ?? item['productId'])?.toString();
          if (pid != null && pid.isNotEmpty && !productCache.containsKey(pid)) {
            futures.add(ApiService.getProductById(pid).then((prod) {
              if (prod != null) productCache[pid] = prod;
            }).catchError((_) {}));
          }
        }
        await Future.wait(futures);
        final updatedItems = <dynamic>[];
        for (var i = 0; i < items.length; i++) {
          final item = Map<String, dynamic>.from(items[i] as Map);
          final pid = (item['product_id'] ?? item['productId'])?.toString();
          if (pid != null && productCache.containsKey(pid)) {
            final prod = productCache[pid] as Map<String, dynamic>;
            item['name'] = item['name'] ?? prod['name'] ?? prod['product_name'];
            final rawImage = prod['image_url'] ?? prod['imageUrl'] ?? prod['image'];
            final String existingImage = (item['imageUrl'] as String?) ?? (item['image_url'] as String?) ?? '';
            String resolvedImage = '';
            if (existingImage.isNotEmpty) {
              resolvedImage = Product.getFullImageUrl(existingImage);
            } else if (rawImage != null && rawImage.toString().isNotEmpty) {
              resolvedImage = Product.getFullImageUrl(rawImage.toString());
            }
            item['imageUrl'] = resolvedImage;
          }
          updatedItems.add(item);
        }
        order['items'] = updatedItems;
      }
      if (mounted) {
        setState(() {
          _orderData = order;
          _isAugmented = true;
        });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.85) : Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 40,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            children: [
              _buildDialogHeader(context, isDark),
              Expanded(
                child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black))
                  : _orderData == null
                    ? Center(child: Text('Order not found', style: TextStyle(fontFamily: 'TenorSans', fontSize: 16, color: isDark ? Colors.white : Colors.black)))
                    : _buildOrderContent(context, _orderData!, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Order Tracking',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 18,
                color: isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderContent(BuildContext context, Map<String, dynamic> orderData, bool isDark) {
    final status = _normalizeStatus(orderData['status']?.toString() ?? 'pending');
    final total = widget.toDouble(orderData['total_price'] ?? orderData['total']);
    final documentId = orderData['documentId']?.toString() ?? orderData['id']?.toString() ?? 'N/A';
    final items = (orderData['items'] as List<dynamic>?) ?? [];
    final currency = orderData['currency']?.toString() ?? 'USD';
    
    // Get currency symbol
    String getCurrencySymbol(String currencyCode) {
      switch (currencyCode.toUpperCase()) {
        case 'YER': return 'ر.ي';
        case 'SAR': return 'ر.س';
        case 'AED': return 'د.إ';
        case 'USD': return '\$';
        case 'EUR': return '€';
        case 'TRY': return '₺';
        case 'CNY': return '¥';
        case 'KRW': return '₩';
        default: return currencyCode;
      }
    }
    
    final currencySymbol = getCurrencySymbol(currency);
    
    final rawCreatedAt = orderData['createdAt'] ?? orderData['created_at'];
    final date = widget.parseDate(rawCreatedAt);
    final timeFormat = DateFormat('h:mm a');
    final dateFormat = DateFormat('MMM d');
    final formattedTime = '${timeFormat.format(date)} - ${dateFormat.format(date)}';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order ID Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                ),
              ),
              child: Text(
                'Order #$documentId',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Status Timeline
          _buildStatusTimeline(context, status, isDark),
          
          const SizedBox(height: 32),
          
          // 🗺️ MAP - Show only when Out for Delivery
          if (status == 'Out for Delivery') ...[
            Text(
              'LIVE TRACKING',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            _DeliveryMapWidget(
              key: ValueKey('map-${orderData['id'] ?? orderData['documentId']}'),
              orderData: orderData,
            ),
            const SizedBox(height: 32),
          ],
          
          // Order Info Card
          _buildInfoCard(
            context,
            isDark,
            [
              _InfoRow('Time', formattedTime, Icons.access_time),
              _InfoRow('Total', '$currencySymbol${total.toStringAsFixed(2)}', Icons.payments_outlined),
              _InfoRow('Items', '${items.length} items', Icons.shopping_bag_outlined),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Items List
          if (items.isNotEmpty) ...[
            Text(
              'ORDER ITEMS',
              style: TextStyle(
                fontFamily: 'TenorSans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            ...items.map((item) => _buildItemCard(context, Map<String, dynamic>.from(item), isDark, currencySymbol)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(BuildContext context, String status, bool isDark) {
    // For Return orders, show reversed steps: Done -> Driver Picked -> Returned
    final isReturnStatus = status.toLowerCase().contains('return');
    final steps = isReturnStatus
      ? [
          _TimelineStep('Delivered', 'Done', Icons.home_outlined),
          _TimelineStep('Return Pending', 'Driver Picked Up', Icons.local_shipping_outlined),
          _TimelineStep('Return Pending', 'Returned to Store', Icons.store_outlined),
        ]
      : [
          _TimelineStep('Pending', 'Placed', Icons.check_circle_outline),
          _TimelineStep('Processing', 'Preparing', Icons.inventory_2_outlined),
          _TimelineStep('Out for Delivery', 'On the way', Icons.local_shipping_outlined),
          _TimelineStep('Delivered', 'Done', Icons.home_outlined),
        ];
    
    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        // For Return orders, first step is completed, others are pending
        final isCompleted = isReturnStatus
          ? index == 0
          : _isStepCompleted(step.status, status);
        final isCurrent = isReturnStatus
          ? (index == 0) // First step is current for return
          : (step.status == status);
        final color = isCompleted ? _getStatusColor(step.status) : (isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.08));
        
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCompleted ? color : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color,
                    width: isCurrent ? 2.5 : 1.5,
                  ),
                ),
                child: Icon(
                  step.icon,
                  size: 20,
                  color: isCompleted ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.label,
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 10,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  color: isCompleted ? color : (isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4)),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoCard(BuildContext context, bool isDark, List<_InfoRow> rows) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final row = entry.value;
          return Padding(
            padding: EdgeInsets.only(bottom: entry.key < rows.length - 1 ? 16 : 0),
            child: Row(
              children: [
                Icon(row.icon, size: 16, color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4)),
                const SizedBox(width: 12),
                Text(
                  row.label,
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 13,
                    color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                  ),
                ),
                const Spacer(),
                Text(
                  row.value,
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, Map<String, dynamic> item, bool isDark, String currencySymbol) {
    final price = widget.toDouble(item['price']);
    final quantity = item['quantity'] as int? ?? 1;
    final imageUrl = (item['imageUrl'] as String?) ?? '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(10),
              image: imageUrl.isNotEmpty
                ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                : null,
            ),
            child: imageUrl.isEmpty
              ? Icon(Icons.image_not_supported, color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.2))
              : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String? ?? 'Product',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$quantity × $currencySymbol${price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 12,
                    color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$currencySymbol${(price * quantity).toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'TenorSans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  bool _isStepCompleted(String stepStatus, String currentStatus) {
    final statusOrder = ['Pending', 'Processing', 'Out for Delivery', 'Delivered'];
    final currentIdx = statusOrder.indexOf(currentStatus);
    final stepIdx = statusOrder.indexOf(stepStatus);
    return currentIdx >= stepIdx;
  }

  String _normalizeStatus(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'pending': return 'Pending';
      case 'confirmed':
      case 'processing': return 'Processing';
      case 'shipped':
      case 'out for delivery':
      case 'out_for_delivery': return 'Out for Delivery';
      case 'delivered': return 'Delivered';
      case 'cancelled': return 'Cancelled';
      default: return raw;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending': return Colors.orange.shade600;
      case 'Processing': return Colors.blue.shade600;
      case 'Out for Delivery': return Colors.green.shade600;
      case 'Delivered': return Colors.green.shade700;
      case 'Return Pending': return Colors.amber.shade600;
      default: return Colors.red.shade600;
    }
  }
}

// Helper Classes
class _TimelineStep {
  final String status;
  final String label;
  final IconData icon;
  _TimelineStep(this.status, this.label, this.icon);
}

class _InfoRow {
  final String label;
  final String value;
  final IconData icon;
  _InfoRow(this.label, this.value, this.icon);
}

// ============== DELIVERY MAP WIDGET ==============
class _DeliveryMapWidget extends StatefulWidget {
  final Map<String, dynamic> orderData;

  const _DeliveryMapWidget({
    Key? key,
    required this.orderData,
  }) : super(key: key);

  @override
  State<_DeliveryMapWidget> createState() => _DeliveryMapWidgetState();
}

class _DeliveryMapWidgetState extends State<_DeliveryMapWidget> {
  List<LatLng> _routePoints = [];
  String _eta = 'Calculating...';
  Timer? _updateTimer;
  final MapController _mapController = MapController();

  late LatLng customerLocation;
  LatLng? driverLocation;
  bool _hasValidLocations = false;

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _startPeriodicUpdate();
  }

  @override
  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    super.dispose();
  }

  void _initializeLocations() {
    try {
      // Helper function to safely parse latitude/longitude from any type
      double? _parseCoordinate(dynamic value) {
        if (value == null) return null;
        if (value is num) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value);
          return parsed;
        }
        return null;
      }

      // Try multiple field name variations for customer location
      double? customerLat = _parseCoordinate(widget.orderData['location_Latitude']);
      double? customerLon = _parseCoordinate(widget.orderData['location_Longitude']);
      
      // Fallback to alternative field names
      customerLat ??= _parseCoordinate(widget.orderData['locationLatitude']);
      customerLon ??= _parseCoordinate(widget.orderData['locationLongitude']);
      customerLat ??= _parseCoordinate(widget.orderData['customer_latitude']);
      customerLon ??= _parseCoordinate(widget.orderData['customer_longitude']);
      customerLat ??= _parseCoordinate(widget.orderData['latitude']);
      customerLon ??= _parseCoordinate(widget.orderData['longitude']);
      
      // Check if we have valid coordinates
      if (customerLat != null && customerLon != null && customerLat != 0.0 && customerLon != 0.0) {
        customerLocation = LatLng(customerLat, customerLon);
        _hasValidLocations = true;
      } else {
        // Default fallback - should not be used with invalid coordinates
        customerLocation = LatLng(24.7136, 46.6753); // Riyadh center as fallback
        _hasValidLocations = false;
      }
      
      // Try both driverLocation (camelCase) and driver_location (snake_case)
      driverLocation = _parseDriverLocation(widget.orderData['driverLocation'] ?? widget.orderData['driver_location']);
    } catch (e) {
      debugPrint('Error initializing locations: $e');
      customerLocation = LatLng(24.7136, 46.6753);
      driverLocation = null;
      _hasValidLocations = false;
    }
  }

  void _startPeriodicUpdate() {
    _fetchRouteAndEta();
    _updateTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final id = (widget.orderData['id'] ?? widget.orderData['documentId'])?.toString();
        if (id == null) return;
        final latest = await ApiService.getOrderById(id);
        if (latest != null) {
          // Try both driverLocation (camelCase) and driver_location (snake_case)
          final driverLocRaw = latest['driverLocation'] ?? latest['driver_location'];
          final parsed = _parseDriverLocation(driverLocRaw);
          if (parsed != null && mounted) {
            setState(() => driverLocation = parsed);
            _fetchRouteAndEta();
          }
        }
      } catch (_) {}
    });
  }

  LatLng? _parseDriverLocation(dynamic raw) {
    if (raw == null) return null;
    
    try {
      if (raw is Map) {
        final latRaw = raw['latitude'] ?? raw['lat'];
        final lonRaw = raw['longitude'] ?? raw['lng'] ?? raw['lon'];
        
        double? lat, lon;
        
        // Handle both num and String types
        if (latRaw is num) {
          lat = latRaw.toDouble();
        } else if (latRaw is String) {
          lat = double.tryParse(latRaw);
        }
        
        if (lonRaw is num) {
          lon = lonRaw.toDouble();
        } else if (lonRaw is String) {
          lon = double.tryParse(lonRaw);
        }
        
        if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
          return LatLng(lat, lon);
        }
      }
      
      if (raw is List && raw.length >= 2) {
        final a = raw[0];
        final b = raw[1];
        
        double? lat, lon;
        if (a is num) {
          lat = a.toDouble();
        } else if (a is String) {
          lat = double.tryParse(a);
        }
        
        if (b is num) {
          lon = b.toDouble();
        } else if (b is String) {
          lon = double.tryParse(b);
        }
        
        if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
          return LatLng(lat, lon);
        }
      }
    } catch (e) {
      debugPrint('Error parsing driver location: $e');
    }
    
    return null;
  }

  Future<void> _fetchRouteAndEta() async {
    if (driverLocation == null) {
      if (mounted) {
        setState(() {
          _eta = 'Waiting for driver...';
          _routePoints = [];
        });
      }
      return;
    }

    final coordinates = '${driverLocation!.longitude},${driverLocation!.latitude};${customerLocation.longitude},${customerLocation.latitude}';
    final url = Uri.parse('http://router.project-osrm.org/route/v1/driving/$coordinates?geometries=geojson&overview=full');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final durationInSeconds = route['duration'] as double;
          final minutes = (durationInSeconds / 60).ceil();
          final List<dynamic> coords = route['geometry']['coordinates'];
          final newRoutePoints = coords.map<LatLng>((coord) {
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();
          if (mounted) {
            setState(() {
              _routePoints = newRoutePoints;
              _eta = '$minutes min';
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _eta = 'Route unavailable';
          _routePoints = [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _eta = 'Error';
          _routePoints = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    LatLng mapCenter = driverLocation != null
        ? LatLng(
            (driverLocation!.latitude + customerLocation.latitude) / 2,
            (driverLocation!.longitude + customerLocation.longitude) / 2,
          )
        : customerLocation;
    double initialZoom = driverLocation != null ? 14.0 : 12.0;

    return Column(
      children: [
        // ETA Badge
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: driverLocation != null 
                ? Colors.green.shade600.withOpacity(0.15)
                : Colors.amber.shade600.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: driverLocation != null 
                  ? Colors.green.shade600.withOpacity(0.3)
                  : Colors.amber.shade600.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined, 
                color: driverLocation != null ? Colors.green.shade600 : Colors.amber.shade600, 
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'ETA: $_eta',
                style: TextStyle(
                  fontFamily: 'TenorSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: driverLocation != null ? Colors.green.shade700 : Colors.amber.shade700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        
        // Map Container
        Container(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            ),
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          ),
          clipBehavior: Clip.antiAlias,
          child: _hasValidLocations
              ? FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: initialZoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.yshop.customer.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_routePoints.isNotEmpty)
                          Polyline(
                            points: _routePoints,
                            color: Colors.blue.shade400,
                            strokeWidth: 5.0,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Customer marker
                        Marker(
                          point: customerLocation,
                          width: 45,
                          height: 45,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.person, color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                        // Driver marker
                        if (driverLocation != null)
                          Marker(
                            point: driverLocation!,
                            width: 45,
                            height: 45,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 12, spreadRadius: 2),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.delivery_dining, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 48,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Waiting for location...',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}