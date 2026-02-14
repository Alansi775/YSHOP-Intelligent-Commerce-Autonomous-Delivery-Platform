import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/reactive_sync_service.dart';
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
  late Future<List<dynamic>> _ordersFuture;
  late Future<Map<String, List<dynamic>>> _allDataFuture;
  
  // Smart filter instead of tabs
  String _filterMode = 'all'; // 'all', 'orders', 'returns'
  
  // Track loading state for returns
  Map<int, bool> _loadingReturns = {};
  
  // Force rebuild of FutureBuilder when data updates
  int _dataRefreshCounter = 0;
  
  // Cache orders to avoid reloading during return refresh
  List<dynamic> _cachedOrders = [];
  
  // 🔥 STORE CURRENT DATA (avoid FutureBuilder flickering!)
  Map<String, List<dynamic>> _currentData = {'orders': [], 'returns': []};
  bool _isLoadingInitial = true;
  
  // 🔥 Reactive Sync subscription
  late StreamSubscription<Map<String, dynamic>> _reactiveSyncSubscription;
  String? _storeId;
  
  static const double kMaxWidth = 800.0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    
    _ordersFuture = _loadOrders();
    _allDataFuture = _loadAllData();
    
    // 🔥 INITIALIZE REACTIVE SYNC
    _initializeReactiveSync();
  }

  /// 🔥 Initialize reactive sync listener for Orders + Returns
  Future<void> _initializeReactiveSync() async {
    try {
      // Get store ID first
      final store = await ApiService.getUserStore();
      _storeId = store?['id']?.toString();
      
      if (_storeId == null) return;

      // Load initial data ONCE
      final initialData = await _loadAllData();
      if (mounted) {
        setState(() {
          _currentData = initialData;
          _isLoadingInitial = false;
        });
      }

      // Initialize Socket.io (first time only)
      if (!reactiveSyncService.isConnected) {
        reactiveSyncService.initialize(serverUrl: 'http://localhost:3000');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 🔥 Subscribe to BOTH orders and returns channels
      reactiveSyncService.subscribe('orders:$_storeId');
      reactiveSyncService.subscribe('returns:$_storeId');
      debugPrint('🔥 REACTIVE SYNC: Subscribed to orders:$_storeId & returns:$_storeId');

      // Listen to delta updates from BOTH channels
      _reactiveSyncSubscription =
          reactiveSyncService.dataStream.listen((update) {
        final channel = update['channel'] as String?;
        
        if (channel == 'returns:$_storeId') {
          // 📦 RETURNS UPDATE
          debugPrint(
              '✨ REACTIVE RETURNS UPDATE: ${update['count']} items');
          
          if (mounted) {
            setState(() {
              final newReturns = (update['data'] as List?)
                      ?.cast<Map<String, dynamic>>() ??
                  [];
              _currentData = {
                'orders': _currentData['orders'] ?? [],
                'returns': newReturns,
              };
            });
          }
        }
        
        if (channel == 'orders:$_storeId') {
          // 📦 ORDERS UPDATE
          debugPrint(
              '✨ REACTIVE ORDERS UPDATE: ${update['count']} items');
          
          if (mounted) {
            setState(() {
              final newOrders = (update['data'] as List?)
                      ?.cast<Map<String, dynamic>>() ??
                  [];
              // Cache new orders for returns-only updates
              _cachedOrders = newOrders;
              _currentData = {
                'orders': newOrders,
                'returns': _currentData['returns'] ?? [],
              };
            });
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Reactive sync init error: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reactiveSyncSubscription.cancel();
    if (_storeId != null) {
      reactiveSyncService.unsubscribe('orders:$_storeId');
      reactiveSyncService.unsubscribe('returns:$_storeId');
    }
    super.dispose();
  }

  Future<List<dynamic>> _loadOrders() async {
    final store = await ApiService.getUserStore();
    final storeId = store?['id']?.toString();
    if (storeId == null) return [];
    final orders = await ApiService.getStoreOrders(storeId: storeId);
    return orders;
  }

  Future<List<dynamic>> _loadReturns() async {
    try {
      final store = await ApiService.getUserStore();
      final storeId = store?['id']?.toString();
      if (storeId == null) return [];
      
      // Get all orders and filter for returns
      final orders = await ApiService.getStoreOrders(storeId: storeId);
      final returns = orders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        return status == 'return';
      }).toList();
      
      return returns;
    } catch (e) {
      debugPrint('Error loading returns: $e');
      return [];
    }
  }

  Future<void> _receiveReturnOrder(int returnId, BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();
      
      // Set loading state
      if (mounted) {
        setState(() {
          _loadingReturns[returnId] = true;
        });
      }
      
      final success = await ApiService.receiveReturnOrder(returnId);
      
      if (success && mounted) {
        // ⚡ OPTIMIZED: Only reload returns data (not orders) for instant update
        setState(() {
          _loadingReturns[returnId] = false;
          _allDataFuture = _loadAllDataOptimized();  // Fast path: refresh returns only!
          _dataRefreshCounter++;  // Force rebuild
        });
        debugPrint('✅ Return received - refreshing returns data only');
        // ✅ No success message - button state change is the feedback
      } else if (mounted) {
        setState(() {
          _loadingReturns[returnId] = false;
        });
        _showErrorSnackBar(context, 'Failed to receive return');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingReturns[returnId] = false;
        });
        _showErrorSnackBar(context, 'Error receiving return');
      }
      debugPrint('Error receiving return order: $e');
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus, BuildContext context) async {
    try {
      HapticFeedback.mediumImpact();
      
      // Update the order in the data immediately (optimistic update)
      if (mounted) {
        setState(() {
          // Update orders list with new status
          for (var i = 0; i < _currentData['orders']!.length; i++) {
            if (_currentData['orders']![i]['id'].toString() == orderId) {
              _currentData['orders']![i]['status'] = newStatus;
              break;
            }
          }
        });
      }
      
      // Then sync with backend
      await ApiService.updateOrderStatus(orderId, newStatus);

      if (context.mounted) {
        _showSuccessSnackBar(context, 'Order #$orderId updated to ${newStatus.toUpperCase()}');
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to update order: $e');
        // Reload to revert optimistic update
        if (mounted) {
          setState(() {
            _allDataFuture = _loadAllData();
          });
        }
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
      case 'shipped': return Colors.purple.shade600;
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

  /// Get currency symbol based on currency code
  String _getCurrencySymbol(String? currencyCode) {
    if (currencyCode == null || currencyCode.isEmpty) return '₺'; // Default to TRY
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

  /// 💰 Calculate profit from orders and returns
  Map<String, dynamic> _calculateProfit() {
    final orders = _currentData['orders'] ?? [];
    final returns = _currentData['returns'] ?? [];
    
    // Get the first order's currency (all orders should use same currency per store)
    String storeCurrency = 'USD';
    for (var order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status != 'return') {
        final currency = (order['currency'] ?? '').toString().trim();
        if (currency.isNotEmpty) {
          storeCurrency = currency;
          break;
        }
      }
    }
    
    debugPrint('💰 CALCULATING PROFIT: ${orders.length} orders, store currency=$storeCurrency');
    
    double totalRevenue = 0;
    
    // Calculate revenue from ALL orders (except 'return' status)
    for (var order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      // Try both 'total_price' (from backend) and 'total' (legacy)
      final total = double.tryParse(order['total_price']?.toString() ?? order['total']?.toString() ?? '0') ?? 0;
      
      // Count all orders (they all have real payment)
      if (status != 'return' && total > 0) {
        totalRevenue += total;
        debugPrint('  ✅ Order total: $total');
      }
    }
    
    debugPrint('💵 Total revenue: $totalRevenue $storeCurrency');
    
    // Calculate profit at 75%
    double totalProfit = totalRevenue * 0.75;
    
    // Deduct returns
    double returnsDeduction = 0;
    for (var returnItem in returns) {
      final returnTotal = double.tryParse(returnItem['refund_amount'].toString()) ?? 0;
      returnsDeduction += returnTotal;
    }
    
    final finalProfit = totalProfit - returnsDeduction;
    
    debugPrint('💰 Final profit: $finalProfit (profit=$totalProfit, returns_deduction=$returnsDeduction)');
    
    return {
      'storeCurrency': storeCurrency,
      'totalRevenue': totalRevenue,
      'totalProfit': totalProfit,
      'returnsDeduction': returnsDeduction,
      'finalProfit': finalProfit,
    };
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
          
          // 💰 Profit Tracker
          SliverToBoxAdapter(
            child: _buildProfitTracker(theme, isDark),
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
            _ordersFuture = _loadOrders();
            _allDataFuture = _loadAllData();
            _dataRefreshCounter++;  // Force rebuild
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

  /// 💰 Build profit tracker widget
  Widget _buildProfitTracker(ThemeData theme, bool isDark) {
    final profitData = _calculateProfit();
    final storeCurrency = profitData['storeCurrency'] as String;
    final totalRevenue = profitData['totalRevenue'] as double;
    final totalProfit = profitData['totalProfit'] as double;
    final returnsDeduction = profitData['returnsDeduction'] as double;
    final finalProfit = profitData['finalProfit'] as double;
    
    final currencySymbol = _getCurrencySymbol(storeCurrency);
    
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: kMaxWidth),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 22,
                  color: isDark ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 12),
                Text(
                  'Earnings Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Revenue section
            if (totalRevenue > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Revenue',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black.withOpacity(0.6),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$currencySymbol${totalRevenue.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            
            // Separator
            Divider(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.08),
              height: 1,
            ),
            const SizedBox(height: 16),
            
            // Profit Details
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Profit (75%)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      '$currencySymbol${totalProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
                
                if (returnsDeduction > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Minus Returns',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white60 : Colors.black.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        '−$currencySymbol${returnsDeduction.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 16),
                Divider(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.08),
                  height: 1,
                ),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Final Amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      '$currencySymbol${finalProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartList(ThemeData theme, bool isDark) {
    // 🔥 NO FutureBuilder - use stored data to avoid flickering!
    if (_isLoadingInitial) {
      return SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: isDark ? Colors.white : Colors.black,
                strokeWidth: 2,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading orders...',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allOrders = _currentData['orders'] ?? [];
    final allReturns = _currentData['returns'] ?? [];
    
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
          
          // Add currency from the parent order
          if (returnData['order_id'] != null) {
            final orderId = returnData['order_id'].toString();
            final parentOrder = allOrders.firstWhere(
              (o) => o['id'].toString() == orderId,
              orElse: () => null,
            );
            if (parentOrder != null) {
              returnData['product_currency'] = parentOrder['currency'] ?? 'USD';
            }
          }
          
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
      debugPrint('🔍 _loadAllData START - storeId: $storeId');
      
      if (storeId == null) {
        debugPrint('❌ storeId is null!');
        return {'orders': [], 'returns': []};
      }
      
      debugPrint('📦 Fetching orders for store: $storeId');
      final allOrders = await ApiService.getStoreOrders(storeId: storeId);
      debugPrint('✅ Got ${allOrders.length} orders');
      
      // Separate orders and returns
      final orders = allOrders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        return status != 'return';
      }).toList();
      
      // 💾 Cache orders for fast return-only refresh
      _cachedOrders = orders;

      debugPrint('📦 Fetching RETURNS from API for store: $storeId');
      // 🔥 CRITICAL FIX: Get returns from returned_products table (correct IDs!)
      // This ensures returnData['id'] is from returned_products.id, not orders.id
      final returns = await ApiService.getStoreReturns(storeId: storeId);
      debugPrint('✅ Got ${returns.length} returns from API');
      
      debugPrint('📦 Loaded ${orders.length} orders, ${returns.length} returns');
      
      return {
        'orders': orders,
        'returns': returns,
      };
    } catch (e) {
      debugPrint('❌ Error loading all data: $e');
      return {'orders': [], 'returns': []};
    }
  }

  /// ⚡ OPTIMIZED: Load returns ONLY (fast path for button refresh)
  /// Uses cached orders + fresh returns for instant update
  Future<Map<String, List<dynamic>>> _loadAllDataOptimized() async {
    try {
      final store = await ApiService.getUserStore();
      final storeId = store?['id']?.toString();
      debugPrint('⚡ _loadAllDataOptimized START (returns only) - storeId: $storeId');
      
      if (storeId == null) {
        debugPrint('❌ storeId is null!');
        return {'orders': _cachedOrders, 'returns': []};
      }

      // ⚡ SKIP orders - just load returns for instant update
      debugPrint('📦 Fetching RETURNS ONLY for store: $storeId (⚡ fast path)');
      final returns = await ApiService.getStoreReturns(storeId: storeId);
      debugPrint('⚡ Got ${returns.length} returns (returns-only refresh = instant!)');
      
      return {
        'orders': _cachedOrders,  // Use cached orders from previous load
        'returns': returns,
      };
    } catch (e) {
      debugPrint('❌ Error loading returns only: $e');
      return {'orders': _cachedOrders, 'returns': []};
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

    // 🔥 Get images for MULTIPLE items (first 2-3) for preview grid
    final List<String> itemImages = [];
    for (var item in items.take(3)) {
      final img = (item['imageUrl'] ?? item['image_url'] ?? item['image'] ?? item['photo']) as String?;
      if (img != null && img.isNotEmpty) {
        final resolved = _resolveImageUrl(img);
        if (resolved.isNotEmpty) {
          itemImages.add(resolved);
        }
      }
    }
    
    // Fallback: single image for backward compatibility
    final String? resolvedFirstImage = itemImages.isNotEmpty ? itemImages.first : null;

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
                        // 🔥 Horizontal Image List (compact for many items)
                        if (itemImages.isNotEmpty)
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              shrinkWrap: true,
                              itemCount: itemImages.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (context, index) {
                                // Show individual images or count if more
                                if (index < 3) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: itemImages[index],
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: isDark 
                                            ? Colors.white.withOpacity(0.05)
                                            : Colors.black.withOpacity(0.03),
                                        child: Center(
                                          child: SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1,
                                              color: isDark ? Colors.white24 : Colors.black12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: isDark 
                                            ? Colors.white.withOpacity(0.05)
                                            : Colors.black.withOpacity(0.03),
                                        child: Icon(
                                          Icons.shopping_bag_outlined,
                                          size: 16,
                                          color: isDark ? Colors.white24 : Colors.black26,
                                        ),
                                      ),
                                    ),
                                  );
                                } else if (index == 3 && itemImages.length > 3) {
                                  // "+N" badge for remaining items
                                  return Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade400,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '+${itemImages.length - 3}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          )
                        else
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: isDark 
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.03),
                            ),
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: isDark ? Colors.white24 : Colors.black26,
                              size: 20,
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
                                '${_getCurrencySymbol(orderData['currency'])}${storeSubtotal.toStringAsFixed(2)}',
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
                                '${_getCurrencySymbol(orderData['currency'])}${netStoreProfit.toStringAsFixed(2)}',
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
    final productName = returnData['product_name'] ?? 'Unknown Product';
    final productPrice = double.tryParse(returnData['product_price']?.toString() ?? '0') ?? 0.0;
    final productCurrency = returnData['product_currency'] ?? 'USD';
    final reason = returnData['return_reason'] ?? 'No reason provided';
    final requestedAt = returnData['return_requested_at'] ?? '';
    final quantity = returnData['quantity'] ?? 1;
    final productImage = returnData['product_image_url'];
    final returnId = returnData['id'] as int? ?? 0;
    final isLoading = _loadingReturns[returnId] ?? false;

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
                        const SizedBox(height: 4),
                        Text(
                          '${_getCurrencySymbol(productCurrency)}${productPrice.toStringAsFixed(2)} × $quantity = ${_getCurrencySymbol(productCurrency)}${(productPrice * quantity).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'Refund: ${_getCurrencySymbol(productCurrency)}${(productPrice * quantity * 0.75).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade600,
                            ),
                          ),
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
              
              const SizedBox(height: 16),
              
              // 🔥 Receive Return Button (uses correct returned_products.id)
              SizedBox(
                width: double.infinity,
                child: _buildReturnActionButton(
                  'Receive Return',
                  Icons.check_circle_outlined,
                  Colors.green.shade600,
                  isDark,
                  isLoading: isLoading,
                  onPressed: () {
                    if (!isLoading) {
                      debugPrint('🔥 Receiving return ID: $returnId (from returned_products table)');
                      _receiveReturnOrder(returnId, context);
                    }
                  },
                ),
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
    final photos = {
      'Top': returnData['photo_top'],
      'Bottom': returnData['photo_bottom'],
      'Left': returnData['photo_left'],
      'Right': returnData['photo_right'],
      'Front': returnData['photo_front'],
      'Back': returnData['photo_back'],
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: outlined ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: outlined 
                    ? color 
                    : (color.computeLuminance() > 0.5 ? Colors.black : Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: outlined 
                      ? color 
                      : (color.computeLuminance() > 0.5 ? Colors.black : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnActionButton(
    String label,
    IconData icon,
    Color color,
    bool isDark, {
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 48,
      decoration: BoxDecoration(
        color: isLoading 
            ? (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLoading
              ? Colors.grey.shade400
              : color,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey.shade400,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
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
    final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(
      initialIndex >= 0 ? initialIndex : 0,
    );

    // Listen to page changes
    pageController.addListener(() {
      if (pageController.hasClients) {
        currentIndexNotifier.value = pageController.page?.round() ?? 0;
      }
    });

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
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
            
            // Photo indicator with correct label
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: currentIndexNotifier,
                  builder: (context, currentIndex, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        photos[currentIndex].key,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
                
                // 🔥 ORDER ITEMS LIST (ALL PRODUCTS)
                Text(
                  'Items',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Items List
                Container(
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        ...(orderData['items'] as List<dynamic>? ?? []).map((item) {
                          final itemName = item['name'] ?? item['product_name'] ?? 'Unknown Product';
                          final quantity = item['quantity'] ?? 1;
                          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
                          final itemTotal = price * quantity;
                          final imageUrl = item['imageUrl'] ?? item['image_url'] ?? '';
                          
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Item Image
                                    if (imageUrl.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          _resolveImageUrl(imageUrl),
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, st) => Container(
                                            width: 64,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: isDark 
                                                  ? Colors.white.withOpacity(0.05)
                                                  : Colors.black.withOpacity(0.03),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.image_not_supported,
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
                                          color: isDark 
                                              ? Colors.white.withOpacity(0.05)
                                              : Colors.black.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.shopping_bag,
                                          color: isDark ? Colors.white24 : Colors.black26,
                                        ),
                                      ),
                                    
                                    const SizedBox(width: 12),
                                    
                                    // Item Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            itemName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Qty: $quantity × ${_getCurrencySymbol(orderData['currency'])}${price.toStringAsFixed(2)} = ${_getCurrencySymbol(orderData['currency'])}${itemTotal.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Price
                                    Text(
                                      '${_getCurrencySymbol(orderData['currency'])}${itemTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if ((orderData['items'] as List).indexOf(item) < (orderData['items'] as List).length - 1)
                                Divider(
                                  height: 1,
                                  indent: 12,
                                  endIndent: 12,
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05),
                                ),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Order Total Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subtotal:',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            '${_getCurrencySymbol(orderData['currency'])}${(orderData['total_price'] ?? 0).toString()}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Your Profit (75%):',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${_getCurrencySymbol(orderData['currency'])}${((double.tryParse(orderData['total_price']?.toString() ?? '0') ?? 0) * 0.75).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Shipping Info
                if (orderData['shipping_address'] != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shipping Address',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark 
                              ? Colors.white.withOpacity(0.03)
                              : Colors.black.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          orderData['shipping_address'].toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
}