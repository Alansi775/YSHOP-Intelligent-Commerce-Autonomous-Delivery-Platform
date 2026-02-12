import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🎨 MODERN ORDERS VIEW - DJI-Inspired Design
// ═══════════════════════════════════════════════════════════════════════════

class OrdersView extends StatefulWidget {
  final String storeEmail;
  static const double APP_COMMISSION_RATE = 0.25; // 25%

  const OrdersView({super.key, required this.storeEmail});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late Future<Map<String, List<dynamic>>> _allDataFuture;
  
  // Smart filter instead of tabs
  String _filterMode = 'all'; // 'all', 'orders', 'returns'
  
  static const double kMaxWidth = 800.0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    
    // Load data ONCE on init
    _allDataFuture = _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus, BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();
      await ApiService.updateOrderStatus(orderId, newStatus);
      setState(() => _allDataFuture = _loadAllData());

      if (context.mounted) {
        _showSuccessSnackBar(context, 'Order #$orderId updated to ${newStatus.toUpperCase()}');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to update order');
      }
    }
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange.shade600;
      case 'confirmed':
      case 'processing': return Colors.blue.shade600;
      case 'rejected':
      case 'cancelled': return Colors.red.shade600;
      case 'out for delivery':
      case 'shipped': return Colors.cyan.shade600;
      case 'delivered': return Colors.green.shade600;
      default: return Colors.grey.shade600;
    }
  }

  DateTime _parseOrderDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final sqlTs = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})');
      final match = sqlTs.firstMatch(raw);
      if (match != null) {
        return DateTime(
          int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!),
          int.parse(match.group(4)!), int.parse(match.group(5)!), int.parse(match.group(6)!),
        );
      }
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          _buildModernAppBar(theme, isDark),
          
          // Filter Chips
          SliverToBoxAdapter(
            child: _buildFilterChips(theme, isDark),
          ),
          
          // Search Bar
          SliverToBoxAdapter(
            child: _buildSearchBar(theme, isDark),
          ),
          
          // Smart Combined List
          SliverToBoxAdapter(
            child: _buildSmartList(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar(ThemeData theme, bool isDark) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A1A), const Color(0xFF0A0A0A)]
                : [Colors.white, const Color(0xFFF8F9FA)],
          ),
        ),
        child: FlexibleSpaceBar(
          centerTitle: false,
          titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
          title: Text(
            'Orders',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
          ),
          onPressed: () => setState(() {
            _allDataFuture = _loadAllData();
          }),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            _showErrorSnackBar(context, 'QR Scanner - Coming Soon');
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: kMaxWidth),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All', 'all', Icons.receipt_long_rounded, theme, isDark),
              const SizedBox(width: 12),
              _buildFilterChip('Orders', 'orders', Icons.shopping_bag_outlined, theme, isDark),
              const SizedBox(width: 12),
              _buildFilterChip('Returns', 'returns', Icons.assignment_return_rounded, theme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String mode,
    IconData icon,
    ThemeData theme,
    bool isDark,
  ) {
    final isSelected = _filterMode == mode;
    
    return GestureDetector(
      onTap: () {
        if (_filterMode != mode) {
          HapticFeedback.selectionClick();
          setState(() => _filterMode = mode);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: kMaxWidth),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: TextField(
          controller: _searchController,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Search by order ID or customer name...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 15,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark ? Colors.white24 : Colors.black12,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartList(ThemeData theme, bool isDark) {
    return FutureBuilder<Map<String, List<dynamic>>>(
      future: _allDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 400,
            child: Center(
              child: CircularProgressIndicator(
                color: isDark ? Colors.white : Colors.black,
                strokeWidth: 2,
              ),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return _buildErrorState('Error loading data', isDark);
        }
        
        final allOrders = snapshot.data?['orders'] ?? [];
        final allReturns = snapshot.data?['returns'] ?? [];
        
        // Apply search filter
        final filteredOrders = allOrders.where((order) {
          final orderId = (order['id'] ?? '').toString().toLowerCase();
          final name = (order['customerName'] ?? order['userName'] ?? '').toString().toLowerCase();
          final status = (order['status'] ?? '').toString().toLowerCase();
          
          if (status == 'return') return false;
          if (_searchQuery.isEmpty) return true;
          return orderId.contains(_searchQuery) || name.contains(_searchQuery);
        }).toList();

        final filteredReturns = allReturns.where((returnItem) {
          if (_searchQuery.isEmpty) return true;
          final productName = (returnItem['product_name'] ?? '').toString().toLowerCase();
          return productName.contains(_searchQuery);
        }).toList();

        // Apply filter mode
        List<Widget> items = [];
        
        if (_filterMode == 'all' || _filterMode == 'orders') {
          if (filteredOrders.isNotEmpty) {
            // Orders Section
            if (_filterMode == 'all' && filteredReturns.isNotEmpty) {
              items.add(_buildSectionHeader('Orders', filteredOrders.length, Icons.shopping_bag_outlined, isDark));
            }
            
            for (int i = 0; i < filteredOrders.length; i++) {
              final order = filteredOrders[i] as Map<String, dynamic>;
              final orderId = (order['id'] ?? '').toString();
              items.add(_buildModernOrderCard(context, orderId, order, theme, isDark, i));
            }
          }
        }
        
        if (_filterMode == 'all' || _filterMode == 'returns') {
          if (filteredReturns.isNotEmpty) {
            // Returns Section
            if (_filterMode == 'all' && filteredOrders.isNotEmpty) {
              items.add(_buildSectionHeader('Returns', filteredReturns.length, Icons.assignment_return_rounded, isDark));
            }
            
            for (int i = 0; i < filteredReturns.length; i++) {
              final returnData = filteredReturns[i] as Map<String, dynamic>;
              items.add(_buildModernReturnCard(context, returnData, theme, isDark, i));
            }
          }
        }

        if (items.isEmpty) {
          String emptyTitle = 'No items found';
          String emptySubtitle = 'Try adjusting your filters';
          IconData emptyIcon = Icons.inbox_rounded;
          
          if (_filterMode == 'orders') {
            emptyTitle = 'No orders found';
            emptySubtitle = 'Your orders will appear here';
            emptyIcon = Icons.receipt_long_rounded;
          } else if (_filterMode == 'returns') {
            emptyTitle = 'No return requests';
            emptySubtitle = 'All return requests have been processed';
            emptyIcon = Icons.assignment_return_rounded;
          }
          
          return _buildEmptyState(emptyTitle, emptySubtitle, emptyIcon, isDark);
        }

        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: kMaxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: items,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, int count, IconData icon, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, List<dynamic>>> _loadAllData() async {
    try {
      final store = await ApiService.getUserStore();
      final storeId = store?['id']?.toString();
      if (storeId == null) {
        return {'orders': [], 'returns': []};
      }
      
      final allOrders = await ApiService.getStoreOrders(storeId: storeId);
      
      // Separate orders and returns
      final orders = allOrders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        return status != 'return';
      }).toList();
      
      final returns = allOrders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        // Handle both boolean true and numeric 1 (MySQL returns 1 for TRUE)
        final adminAccepted = order['admin_accepted'] == true || 
                              order['admin_accepted'] == 1 || 
                              order['admin_accepted'] == 'true' || 
                              order['admin_accepted'] == '1';
        return status == 'return' && adminAccepted;
      }).toList();
      
      return {
        'orders': orders,
        'returns': returns,
      };
    } catch (e) {
      debugPrint('Error loading all data: $e');
      return {'orders': [], 'returns': []};
    }
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon, bool isDark) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message, bool isDark) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernOrderCard(
    BuildContext context,
    String orderId,
    Map<String, dynamic> orderData,
    ThemeData theme,
    bool isDark,
    int index,
  ) {
    final status = (orderData['status'] as String?) ?? 'pending';
    final statusLower = status.toLowerCase();
    
    final userName = (orderData['customerName'] as String?) ??
        (orderData['userName'] as String?) ??
        (orderData['customer']?['display_name'] as String?) ??
        (orderData['customer']?['name'] as String?) ??
        'Guest';

    final createdAt = orderData['created_at'] ?? orderData['createdAt'] ?? orderData['created'];
    final date = _parseOrderDate(createdAt);
    final formattedTime = DateFormat('MMM d, h:mm a').format(date);

    final items = orderData['items'] as List<dynamic>? ?? [];
    double storeSubtotal = 0.0;
    
    for (var item in items) {
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final qty = int.tryParse(item['quantity']?.toString() ?? '0') ?? 1;
      storeSubtotal += price * qty;
    }

    final commission = storeSubtotal * OrdersView.APP_COMMISSION_RATE;
    final netStoreProfit = storeSubtotal - commission;
    final statusColor = _getStatusColor(status);

    final firstItemImage = items.isNotEmpty 
        ? (items.first['imageUrl'] ?? items.first['image_url'] ?? items.first['image'] ?? items.first['photo']) as String? 
        : null;
    final String? resolvedFirstImage = firstItemImage != null && firstItemImage.isNotEmpty 
        ? _resolveImageUrl(firstItemImage) 
        : null;

    // Driver info
    final Map<String, dynamic>? driverMap = orderData['driver'] is Map<String, dynamic> 
        ? Map<String, dynamic>.from(orderData['driver']) 
        : null;
    final String? driverName = (driverMap?['name'] ?? 
        driverMap?['display_name'] ?? 
        orderData['driverName'] ?? 
        orderData['driver_name'] ?? 
        orderData['driver_full_name'])?.toString();
    final String? driverPhone = (driverMap?['phone'] ?? 
        driverMap?['phoneNumber'] ?? 
        orderData['driverPhone'] ?? 
        orderData['driver_phone'])?.toString();

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.white.withOpacity(0.03)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark 
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.1 : 0.03),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showOrderDetailsSheet(
                  context,
                  orderData,
                  resolvedFirstImage,
                  driverName,
                  driverPhone,
                  null,
                  null,
                  null,
                  isDark,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        if (resolvedFirstImage != null && resolvedFirstImage.isNotEmpty)
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark 
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.03),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: resolvedFirstImage,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isDark ? Colors.white24 : Colors.black12,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Icon(
                                  Icons.shopping_bag_outlined,
                                  color: isDark ? Colors.white24 : Colors.black26,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark 
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.03),
                            ),
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #$orderId',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formattedTime,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Customer & Items Info
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          userName,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Revenue
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? Colors.white.withOpacity(0.03)
                            : Colors.black.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatPrice(storeSubtotal, orderData['currency'] as String?),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDark 
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Profit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatPrice(netStoreProfit, orderData['currency'] as String?),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Actions
                    if (statusLower == 'pending') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildModernButton(
                              'Reject',
                              Icons.close_rounded,
                              Colors.red,
                              isDark,
                              () => _updateOrderStatus(orderId, 'cancelled', context),
                              outlined: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildModernButton(
                              'Accept',
                              Icons.check_rounded,
                              Colors.green,
                              isDark,
                              () => _updateOrderStatus(orderId, 'confirmed', context),
                            ),
                          ),
                        ],
                      ),
                    ] else if (statusLower == 'confirmed' || statusLower == 'processing') ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _buildModernButton(
                          'Show QR Code',
                          Icons.qr_code_2_rounded,
                          isDark ? Colors.white : Colors.black,
                          isDark,
                          () => _showModernQRModal(context, orderId, isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernReturnCard(
    BuildContext context,
    Map<String, dynamic> returnData,
    ThemeData theme,
    bool isDark,
    int index,
  ) {
    // For return orders, get product details from items[0] (returned_products)
    final items = returnData['items'] as List? ?? [];
    final returnItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : {};
    
    final productName = returnItem['product_name'] ?? returnData['product_name'] ?? 'Unknown Product';
    final reason = returnItem['return_reason'] ?? returnData['return_reason'] ?? 'No reason provided';
    final requestedAt = returnItem['return_requested_at'] ?? returnData['return_requested_at'] ?? '';
    final quantity = returnItem['quantity'] ?? returnData['quantity'] ?? 1;
    final productImage = returnItem['product_image_url'] ?? returnData['product_image_url'];

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.white.withOpacity(0.03)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.orange.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  if (productImage != null && productImage.toString().isNotEmpty)
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDark 
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _buildImageUrl(productImage),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.image_not_supported_outlined,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDark 
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                      ),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'RETURN REQUEST',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Reason
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reason',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white.withOpacity(0.87) : Colors.black.withOpacity(0.87),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Photos
              Text(
                'Return Photos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              _buildModernReturnPhotosGrid(context, returnData, isDark),
              
              const SizedBox(height: 16),
              
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Qty: $quantity',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatDate(requestedAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernReturnPhotosGrid(
    BuildContext context,
    Map<String, dynamic> returnData,
    bool isDark,
  ) {
    // Extract photos from the return item (items[0])
    final items = returnData['items'] as List? ?? [];
    final returnItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : {};
    
    final photos = {
      'Top': returnItem['photo_top'] ?? returnData['photo_top'],
      'Bottom': returnItem['photo_bottom'] ?? returnData['photo_bottom'],
      'Left': returnItem['photo_left'] ?? returnData['photo_left'],
      'Right': returnItem['photo_right'] ?? returnData['photo_right'],
      'Front': returnItem['photo_front'] ?? returnData['photo_front'],
      'Back': returnItem['photo_back'] ?? returnData['photo_back'],
    };

    final validPhotos = photos.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();

    if (validPhotos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark 
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No photos provided',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: validPhotos.map((entry) {
        final imageUrl = _buildImageUrl(entry.value);
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _showImageGallery(context, validPhotos, entry.key, isDark);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
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
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: isDark 
                          ? Colors.white.withOpacity(0.03)
                          : Colors.black.withOpacity(0.02),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
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

  Widget _buildModernButton(
    String label,
    IconData icon,
    Color color,
    bool isDark,
    VoidCallback onTap, {
    bool outlined = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: outlined ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: outlined ? color : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: outlined ? color : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModernQRModal(BuildContext context, String orderId, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              const SizedBox(height: 32),
              
              Text(
                'Handover QR Code',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'Let the driver scan this code',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // QR Code
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: orderId,
                  version: QrVersions.auto,
                  size: 200,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Colors.black,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              Text(
                '#$orderId',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              
              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                child: _buildModernButton(
                  'Close',
                  Icons.close_rounded,
                  isDark ? Colors.white : Colors.black,
                  isDark,
                  () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageGallery(
    BuildContext context,
    List<MapEntry<String, dynamic>> photos,
    String initialPhoto,
    bool isDark,
  ) {
    final initialIndex = photos.indexWhere((e) => e.key == initialPhoto);
    final PageController pageController = PageController(
      initialPage: initialIndex >= 0 ? initialIndex : 0,
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          int currentPage = initialIndex >= 0 ? initialIndex : 0;
          pageController.addListener(() {
            setState(() {
              currentPage = pageController.page?.round() ?? 0;
            });
          });

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                // Images
                PageView.builder(
                  controller: pageController,
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final imageUrl = _buildImageUrl(photos[index].value);
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Center(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                
                // Close button
                Positioned(
                  top: 60,
                  right: 24,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                
                // Photo indicator
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${photos[currentPage].key}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showOrderDetailsSheet(
    BuildContext context,
    Map<String, dynamic> orderData,
    String? imageUrl,
    String? driverName,
    String? driverPhone,
    double? driverLat,
    double? driverLng,
    String? driverId,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Text(
                  'Order Details',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Store info
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 80,
                            height: 80,
                            color: isDark 
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black.withOpacity(0.03),
                            child: const Icon(Icons.store),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orderData['storeName'] ?? 
                                  orderData['store_name'] ?? 
                                  'Store',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              orderData['address'] ?? 
                                  orderData['addressFull'] ?? 
                                  orderData['address_full'] ?? 
                                  '',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 24),
                
                // Driver info
                if (driverName != null && driverName.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withOpacity(0.03)
                          : Colors.black.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.05),
                          child: Text(
                            driverName[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              if (driverPhone != null && driverPhone.isNotEmpty)
                                Text(
                                  driverPhone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (driverPhone != null && driverPhone.isNotEmpty)
                          IconButton(
                            onPressed: () => _callPhone(driverPhone),
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.phone_rounded,
                                color: Colors.green.shade600,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildModernButton(
                          'View Map',
                          Icons.map_rounded,
                          Colors.blue,
                          isDark,
                          () {
                            Navigator.pop(context);
                            if (driverLat != null && driverLng != null) {
                              final mapUrl = Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$driverLat,$driverLng',
                              );
                              launchUrl(mapUrl);
                            } else {
                              _showErrorSnackBar(context, 'Driver location not available');
                            }
                          },
                          outlined: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModernButton(
                          'Call Driver',
                          Icons.phone_rounded,
                          Colors.green,
                          isDark,
                          () {
                            Navigator.pop(context);
                            _callPhone(driverPhone);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      debugPrint('Could not launch phone: $e');
    }
  }

  String _buildImageUrl(dynamic photoPath) {
    if (photoPath == null) return '';
    final path = photoPath.toString();
    if (path.startsWith('http')) return path;
    return 'http://localhost:3000$path';
  }

  String _resolveImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    final u = url.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    final host = ApiService.baseHost;
    if (u.startsWith('/')) return '$host$u';
    return '$host/$u';
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Get currency symbol based on currency code
  String _getCurrencySymbol(String? currencyCode) {
    if (currencyCode == null) return '\$';
    
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'TRY':
        return '₺';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      case 'YER':
        return 'ر.ي';
      case 'CNY':
        return '¥';
      case 'KRW':
        return '₩';
      default:
        return '\$';
    }
  }

  /// Format price with correct currency symbol
  String _formatPrice(double price, String? currencyCode) {
    final symbol = _getCurrencySymbol(currencyCode);
    return '$symbol${price.toStringAsFixed(2)}';
  }
}