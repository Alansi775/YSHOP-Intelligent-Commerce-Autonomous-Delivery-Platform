// lib/screens/admin/orders_view.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'common.dart';
import 'admin_order_map_view.dart';
import 'widgets.dart' as w;
import 'package:latlong2/latlong.dart';
import '../delivery/delivery_shared.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ORDERS & REVENUE MANAGEMENT VIEW
// ═══════════════════════════════════════════════════════════════════════════════

class OrdersManagementView extends StatefulWidget {
  const OrdersManagementView({super.key});

  @override
  State<OrdersManagementView> createState() => _OrdersManagementViewState();
}

class _OrdersManagementViewState extends State<OrdersManagementView> {
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String _filterStatus = 'all';
  
  // Revenue data
  double _totalRevenue = 0.0;
  double _appRevenue = 0.0;
  double _storeRevenue = 0.0;
  double _driverRevenue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getAdminOrders();
      debugPrint('🔍 Admin Orders Response: $response');
      if (mounted) {
        final orders = (response as List?)?.map((o) {
          debugPrint('📦 Processing order: $o');
          return OrderModel.fromMap(o);
        }).toList() ?? [];
        debugPrint('✅ Loaded ${orders.length} orders');
        
        // Calculate revenue
        double total = 0.0;
        double app = 0.0;
        double driver = 0.0;
        double store = 0.0;
        for (final order in orders) {
          total += order.totalPrice;
          app += RevenueCalculator.calculateAppRevenue(order.totalPrice);
          driver += RevenueCalculator.calculateDriverRevenue(order.totalPrice);
          store += RevenueCalculator.calculateStoreOwnerRevenue(order.totalPrice);
        }
        
        setState(() {
          _orders = orders;
          _totalRevenue = total;
          _appRevenue = app;
          _driverRevenue = driver;
          _storeRevenue = store;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<OrderModel> get _filteredOrders {
    if (_filterStatus == 'all') return _orders;
    final filtered = _orders.where((o) => o.status.toLowerCase() == _filterStatus).toList();
    debugPrint('🔍 Filtering by "$_filterStatus": ${_orders.length} total orders, ${filtered.length} matched');
    return filtered;
  }

  void _showOrderDetails(OrderModel order) {
    showDialog(
      context: context,
      builder: (_) => _OrderDetailsDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccentBlue));
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: kAccentBlue,
      child: CustomScrollView(
        slivers: [
          // Revenue Summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildRevenueSummary(),
            ),
          ),
          
          // Filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildFilterChips(),
            ),
          ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          
          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: w.SectionHeader(
                title: 'All Orders',
                subtitle: '${_filteredOrders.length} orders found',
              ),
            ),
          ),
          
          // Orders list
          _orders.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: w.EmptyStateView(
                      icon: Icons.receipt_long_rounded,
                      title: 'No Orders Yet',
                      message: 'Orders will appear here when customers make purchases.',
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final order = _filteredOrders[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OrderCard(
                            order: order,
                            onTap: () => _showOrderDetails(order),
                          ),
                        );
                      },
                      childCount: _filteredOrders.length,
                    ),
                  ),
                ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildRevenueSummary() {
    return w.GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue Overview',
            style: TextStyle(
              color: kPrimaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Revenue cards grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              
              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: _RevenueStatCard(
                      title: 'Total Revenue',
                      value: '\$${_totalRevenue.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_rounded,
                      gradient: AppGradients.primary,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _RevenueStatCard(
                      title: 'Your Earnings (25%)',
                      value: '\$${_appRevenue.toStringAsFixed(2)}',
                      icon: Icons.trending_up_rounded,
                      gradient: AppGradients.success,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _RevenueStatCard(
                      title: 'Store Earnings (65%)',
                      value: '\$${_storeRevenue.toStringAsFixed(2)}',
                      icon: Icons.storefront_rounded,
                      gradient: AppGradients.purple,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _RevenueStatCard(
                      title: 'Driver Earnings (10%)',
                      value: '\$${_driverRevenue.toStringAsFixed(2)}',
                      icon: Icons.delivery_dining_rounded,
                      gradient: AppGradients.warning,
                    )),
                  ],
                );
              }
              
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _RevenueStatCard(
                        title: 'Total Revenue',
                        value: '\$${_totalRevenue.toStringAsFixed(2)}',
                        icon: Icons.account_balance_wallet_rounded,
                        gradient: AppGradients.primary,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _RevenueStatCard(
                        title: 'Your Earnings',
                        value: '\$${_appRevenue.toStringAsFixed(2)}',
                        icon: Icons.trending_up_rounded,
                        gradient: AppGradients.success,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _RevenueStatCard(
                        title: 'Store Earnings',
                        value: '\$${_storeRevenue.toStringAsFixed(2)}',
                        icon: Icons.storefront_rounded,
                        gradient: AppGradients.purple,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _RevenueStatCard(
                        title: 'Driver Earnings',
                        value: '\$${_driverRevenue.toStringAsFixed(2)}',
                        icon: Icons.delivery_dining_rounded,
                        gradient: AppGradients.warning,
                      )),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      {'key': 'all', 'label': 'All', 'icon': Icons.list_rounded},
      {'key': 'pending', 'label': 'Pending', 'icon': Icons.pending_rounded},
      {'key': 'confirmed', 'label': 'Confirmed', 'icon': Icons.check_circle_outline_rounded},
      {'key': 'shipped', 'label': 'Shipped', 'icon': Icons.local_shipping_rounded},
      {'key': 'delivered', 'label': 'Delivered', 'icon': Icons.check_circle_rounded},
      {'key': 'cancelled', 'label': 'Cancelled', 'icon': Icons.cancel_outlined},
      {'key': 'return', 'label': 'Return', 'icon': Icons.assignment_return_rounded},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _filterStatus == filter['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    filter['icon'] as IconData,
                    size: 16,
                    color: isSelected ? Colors.white : kSecondaryTextColor,
                  ),
                  const SizedBox(width: 6),
                  Text(filter['label'] as String),
                ],
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : kSecondaryTextColor,
                fontWeight: FontWeight.w500,
              ),
              backgroundColor: kGlassBackground,
              selectedColor: kAccentBlue,
              side: BorderSide(
                color: isSelected ? kAccentBlue : kGlassBorder,
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (_) {
                setState(() => _filterStatus = filter['key'] as String);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 💰 REVENUE STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Gradient gradient;

  const _RevenueStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kGlassBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGlassBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: kPrimaryTextColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: kSecondaryTextColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ORDER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appEarning = RevenueCalculator.calculateAppRevenue(order.totalPrice);
    final storeEarning = RevenueCalculator.calculateStoreOwnerRevenue(order.totalPrice);
    final driverEarning = RevenueCalculator.calculateDriverRevenue(order.totalPrice);
    final currencySymbol = getCurrencySymbol(order.currency);
    
    return w.GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: _getStatusGradient(order.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getStatusIcon(order.status),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.id}',
                      style: const TextStyle(
                        color: kPrimaryTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.createdAt != null
                          ? '${order.createdAt!.day}/${order.createdAt!.month}/${order.createdAt!.year} ${order.createdAt!.hour}:${order.createdAt!.minute.toString().padLeft(2, '0')}'
                          : 'N/A',
                      style: const TextStyle(
                        color: kSecondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              w.StatusBadgeView(status: order.status),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: kSeparatorColor, height: 1),
          const SizedBox(height: 16),
          
          // Details row
          Row(
            children: [
              Expanded(
                child: _OrderInfoItem(
                  icon: Icons.storefront_rounded,
                  label: 'Store',
                  value: order.storeName.isNotEmpty ? order.storeName : order.storeId,
                ),
              ),
              Expanded(
                child: _OrderInfoItem(
                  icon: Icons.payment_rounded,
                  label: 'Payment',
                  value: order.paymentMethod,
                ),
              ),
              Expanded(
                child: _OrderInfoItem(
                  icon: Icons.local_shipping_rounded,
                  label: 'Delivery',
                  value: order.deliveryOption,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Address
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: kTertiaryTextColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.shippingAddress.isEmpty ? 'N/A' : order.shippingAddress,
                  style: const TextStyle(color: kSecondaryTextColor, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Driver info
          if (order.driverName != null && order.driverName!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.delivery_dining_rounded, size: 16, color: kAccentBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${order.driverName}' + (order.driverPhone != null ? ' • ${order.driverPhone}' : ''),
                    style: const TextStyle(color: kAccentBlue, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          const Divider(color: kSeparatorColor, height: 1),
          const SizedBox(height: 16),
          
          // Revenue breakdown
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(color: kTertiaryTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${getCurrencySymbol(order.currency)}${order.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: kPrimaryTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kAccentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccentGreen.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded, color: kAccentGreen, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Your: ${getCurrencySymbol(order.currency)}${appEarning.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: kAccentGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kAccentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccentBlue.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_rounded, color: kAccentBlue, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Store: ${getCurrencySymbol(order.currency)}${storeEarning.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: kAccentBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delivery_dining_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Driver: ${getCurrencySymbol(order.currency)}${driverEarning.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Gradient _getStatusGradient(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return AppGradients.success;
      case 'confirmed':
        return AppGradients.primary;
      case 'pending':
        return AppGradients.warning;
      case 'cancelled':
        return AppGradients.danger;
      default:
        return AppGradients.dark;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'confirmed':
        return Icons.thumb_up_rounded;
      case 'pending':
        return Icons.schedule_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

class _OrderInfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OrderInfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: kTertiaryTextColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: kTertiaryTextColor, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? 'N/A' : value,
          style: const TextStyle(
            color: kPrimaryTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 📋 ORDER DETAILS DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _OrderDetailsDialog extends StatelessWidget {
  final OrderModel order;

  const _OrderDetailsDialog({required this.order});

  @override
  Widget build(BuildContext context) {
    final appEarning = RevenueCalculator.calculateAppRevenue(order.totalPrice);
    final storeEarning = RevenueCalculator.calculateStoreOwnerRevenue(order.totalPrice);
    final driverEarning = RevenueCalculator.calculateDriverRevenue(order.totalPrice);
    final currencySymbol = getCurrencySymbol(order.currency);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: w.GlassContainer(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order.id}',
                          style: const TextStyle(
                            color: kPrimaryTextColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        w.StatusBadgeView(status: order.status, fontSize: 14),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: kSecondaryTextColor),
                    ),
                  ],
                ),
                
                const SizedBox(height: 28),
                
                // Revenue breakdown card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kAccentGreen.withOpacity(0.1),
                        kAccentBlue.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kGlassBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Total Price',
                              style: TextStyle(color: kSecondaryTextColor, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${getCurrencySymbol(order.currency)}${order.totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: kPrimaryTextColor,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 60, color: kSeparatorColor),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Your Earning',
                              style: TextStyle(color: kAccentGreen, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$currencySymbol${appEarning.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: kAccentGreen,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 60, color: kSeparatorColor),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Store Earning',
                              style: TextStyle(color: kAccentBlue, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$currencySymbol${storeEarning.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: kAccentBlue,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 60, color: kSeparatorColor),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Driver Earning',
                              style: TextStyle(color: Colors.orange, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$currencySymbol${driverEarning.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                
                const SizedBox(height: 24),
                
                // Order details
                const Text(
                  'Order Details',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                
                _DetailItem(label: 'Order ID', value: order.id, icon: Icons.tag_rounded),
                _DetailItem(label: 'User ID', value: order.oderId, icon: Icons.person_rounded),
                _DetailItem(label: 'Store', value: order.storeName.isNotEmpty ? order.storeName : order.storeId, icon: Icons.storefront_rounded),
                _DetailItem(label: 'Payment Method', value: order.paymentMethod, icon: Icons.payment_rounded),
                _DetailItem(label: 'Delivery Option', value: order.deliveryOption, icon: Icons.local_shipping_rounded),
                if (order.driverName != null && order.driverName!.isNotEmpty) ...[
                  _DetailItem(label: 'Driver Name', value: order.driverName!, icon: Icons.person_pin_rounded),
                  _DetailItem(label: 'Driver Phone', value: order.driverPhone ?? 'N/A', icon: Icons.phone_rounded),
                ],
                _DriverStatusCard(order: order),
                _DetailItem(
                  label: 'Created At',
                  value: order.createdAt != null
                      ? '${order.createdAt!.day}/${order.createdAt!.month}/${order.createdAt!.year} ${order.createdAt!.hour}:${order.createdAt!.minute.toString().padLeft(2, '0')}'
                      : 'N/A',
                  icon: Icons.calendar_today_rounded,
                ),
                
                const SizedBox(height: 16),
                
                // Shipping address
                const Text(
                  'Shipping Address',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGlassBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGlassBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: kAccentBlue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          order.shippingAddress.isEmpty ? 'N/A' : order.shippingAddress,
                          style: const TextStyle(color: kPrimaryTextColor, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // See on map + Close buttons
                Row(
                  children: [
                    Expanded(
                      child: w.GradientButton(
                        label: 'See on map',
                        onPressed: () async {
                          // show loader
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(child: CircularProgressIndicator()),
                          );

                          try {
                            final orderData = await ApiService.getOrderById(order.id, requiresAuth: true);
                            Navigator.pop(context); // remove loader

                            if (orderData == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Order data not available')),
                              );
                              return;
                            }

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AdminOrderMapView(orderData: Map<String, dynamic>.from(orderData)),
                              ),
                            );
                          } catch (e) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to open map: $e')),
                            );
                          }
                        },
                        gradient: AppGradients.cyan,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: w.GradientButton(
                        label: 'Close',
                        onPressed: () => Navigator.pop(context),
                        gradient: AppGradients.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kGlassBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: kAccentBlue, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: kTertiaryTextColor,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'N/A' : value,
                  style: const TextStyle(
                    color: kPrimaryTextColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStatusCard extends StatefulWidget {
  final OrderModel order;
  const _DriverStatusCard({required this.order});

  @override
  State<_DriverStatusCard> createState() => _DriverStatusCardState();
}

class _DriverStatusCardState extends State<_DriverStatusCard> {
  bool _loading = true;
  String _label = 'Driver Location';
  String _eta = '';
  String _distance = '';
  String _driverName = '';
  bool _hasDriver = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() { _loading = true; });
    try {
      final orderData = await ApiService.getOrderById(widget.order.id, requiresAuth: true);
      if (orderData == null) {
        setState(() { _hasDriver = false; _loading = false; });
        return;
      }

      // parse coordinates
      double? storeLat = _parseDouble(orderData['store_latitude'] ?? orderData['storeLatitude'] ?? orderData['store']?['latitude']);
      double? storeLng = _parseDouble(orderData['store_longitude'] ?? orderData['storeLongitude'] ?? orderData['store']?['longitude']);
      double? custLat = _parseDouble(orderData['location_Latitude'] ?? orderData['locationLatitude'] ?? orderData['customer']?['latitude']);
      double? custLng = _parseDouble(orderData['location_Longitude'] ?? orderData['locationLongitude'] ?? orderData['customer']?['longitude']);

      LatLng? storeLoc;
      LatLng? custLoc;
      if (storeLat != null && storeLng != null) storeLoc = LatLng(storeLat, storeLng);
      if (custLat != null && custLng != null) custLoc = LatLng(custLat, custLng);

      // Try to get driver location from OrderModel first
      LatLng? driverLoc;
      if (widget.order.driverLatitude != null && widget.order.driverLongitude != null) {
        driverLoc = LatLng(widget.order.driverLatitude!, widget.order.driverLongitude!);
        _driverName = widget.order.driverName ?? '';
      }

      // If no driver location in OrderModel, try from order data
      if (driverLoc == null) {
        final dloc = orderData['driver_location'];
        if (dloc is Map) {
          final dlat = _parseDouble(dloc['latitude'] ?? dloc['lat']);
          final dlng = _parseDouble(dloc['longitude'] ?? dloc['lng'] ?? dloc['long']);
          if (dlat != null && dlng != null) driverLoc = LatLng(dlat, dlng);
        }

        // if no embedded driver loc, try driver uid lookup
        final driverUid = orderData['driver_id']?.toString() ?? orderData['driverId']?.toString();
        Map<String, dynamic>? driverData;
        if (driverLoc == null && driverUid != null && driverUid.isNotEmpty) {
          try {
            driverData = await ApiService.getDeliveryRequestByUid(driverUid);
          } catch (_) { driverData = null; }

          if (driverData == null) {
            try {
              final lists = <dynamic>[];
              final active = await ApiService.getActiveDeliveryRequests();
              lists.addAll(active);
              final approved = await ApiService.getApprovedDeliveryRequests();
              lists.addAll(approved);
              final pending = await ApiService.getPendingDeliveryRequests();
              lists.addAll(pending);

              final found = lists.cast<dynamic?>().firstWhere((e) => (e?['uid'] ?? e?['UID'] ?? '') == driverUid, orElse: () => null);
              if (found != null) driverData = Map<String, dynamic>.from(found as Map);
            } catch (_) {}
          }

          if (driverData != null) {
            final dlat = _parseDouble(driverData['latitude'] ?? driverData['lat']);
            final dlng = _parseDouble(driverData['longitude'] ?? driverData['lng'] ?? driverData['long']);
            if (dlat != null && dlng != null) driverLoc = LatLng(dlat, dlng);
            _driverName = (driverData['name'] ?? driverData['full_name'] ?? '') as String? ?? '';
          }
        }
      }

      if (driverLoc == null) {
        setState(() { _hasDriver = false; _loading = false; });
        return;
      }

      _hasDriver = true;

      final dist = const Distance();
      double? drvToStore;
      double? drvToCust;
      double? storeToCust;
      if (storeLoc != null) drvToStore = dist.as(LengthUnit.Meter, driverLoc, storeLoc);
      if (custLoc != null) drvToCust = dist.as(LengthUnit.Meter, driverLoc, custLoc);
      if (storeLoc != null && custLoc != null) storeToCust = dist.as(LengthUnit.Meter, storeLoc, custLoc);

      // decide phase: prefer order status if indicates confirmed/processing => going to store
      final statusLower = widget.order.status.toLowerCase();
      bool goingToStore = false;
      if (statusLower.contains('confirmed') || statusLower.contains('processing') || statusLower.contains('pending')) {
        goingToStore = true;
      } else if (drvToStore != null && drvToCust != null) {
        goingToStore = drvToStore > drvToCust ? false : true;
      } else if (drvToStore != null) {
        goingToStore = drvToStore > 100; // heuristic
      }

      if (goingToStore && drvToStore != null) {
        _label = 'Heading to Store';
        _eta = _formatDuration(drvToStore / 10.0); // approx: 10 m/s
        _distance = _formatDistance(drvToStore);
      } else if (!goingToStore && drvToCust != null) {
        _label = 'Heading to Customer';
        _eta = _formatDuration(drvToCust / 10.0);
        _distance = _formatDistance(drvToCust);
      } else {
        _label = 'Driver Nearby';
        _eta = '';
        _distance = '';
      }

      setState(() { _loading = false; });
    } catch (e) {
      debugPrint('Driver status load failed: $e');
      setState(() { _loading = false; _hasDriver = false; });
    }
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '< 1 min';
    if (minutes == 1) return '1 min';
    return '$minutes min';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    try { return double.tryParse(v.toString()); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kGlassBackground, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.my_location_rounded, color: kAccentBlue, size: 16)),
          const SizedBox(width: 12),
          const Expanded(child: Text('Loading driver status...', style: TextStyle(color: kPrimaryTextColor))),
        ]),
      );
    }

    if (!_hasDriver) {
      return _DetailItem(label: 'Driver Location', value: 'N/A', icon: Icons.my_location_rounded);
    }

    // Styled status card
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kGlassBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kGlassBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppGradients.cyan.colors.first, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
              child: const Icon(Icons.navigation, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label, style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (_eta.isNotEmpty) Text(_eta, style: const TextStyle(color: kAccentGreen, fontWeight: FontWeight.bold)),
                    if (_eta.isNotEmpty) const SizedBox(width: 8),
                    if (_distance.isNotEmpty) Text(_distance, style: const TextStyle(color: kSecondaryTextColor)),
                  ]),
                  if (_driverName.isNotEmpty) Padding(padding: const EdgeInsets.only(top:6), child: Text(_driverName, style: const TextStyle(color: kTertiaryTextColor, fontSize: 12))),
                ],
              ),
            ),
            IconButton(
              onPressed: _loadStatus,
              icon: Icon(Icons.refresh_rounded, color: kSecondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}