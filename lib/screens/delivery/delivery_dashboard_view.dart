// lib/screens/delivery/delivery_dashboard_view.dart
// ═══════════════════════════════════════════════════════════════════════════════
// 📊 DELIVERY DRIVER DASHBOARD - Statistics, Earnings & History
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../services/api_service.dart';
import '../../state_management/auth_manager.dart';
import 'delivery_shared.dart' as ds;

// ─────────────────────────────────────────────────────────────────────────────
//  DESIGN CONSTANTS (Match Swift Theme)
// ─────────────────────────────────────────────────────────────────────────────

const Color kDarkBackground = Color(0xFF121212);
const Color kCardBackground = Color(0xFF1E1E1E);
const Color kAppBarBackground = Color(0xFF121212);
const Color kPrimaryTextColor = Color(0xFFEEEEEE);
const Color kSecondaryTextColor = Color(0xFFB0B0B0);
const Color kAccentBlue = Color(0xFF2979FF);
const Color kAccentGreen = Color(0xFF00E676);
const Color kAccentRed = Color(0xFFFF5252);
const Color kAccentOrange = Color(0xFFFF9800);
const Color kSeparatorColor = Color(0xFF333333);

// ─────────────────────────────────────────────────────────────────────────────
// 📊 DELIVERY DASHBOARD VIEW
// ─────────────────────────────────────────────────────────────────────────────

class DeliveryDashboardView extends StatefulWidget {
  const DeliveryDashboardView({super.key});

  @override
  State<DeliveryDashboardView> createState() => _DeliveryDashboardViewState();
}

class _DeliveryDashboardViewState extends State<DeliveryDashboardView> {
  List<ds.Order> _deliveryHistory = [];
  Map<String, dynamic>? _driverStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uid = Provider.of<AuthManager>(context, listen: false).userProfile?['uid'] as String?;
      if (uid == null) throw Exception('No UID found');

      // Fetch stats and history in parallel
      final statsTask = ApiService.getDeliveryStats();
      final historyTask = ApiService.getDeliveryHistory();

      final stats = await statsTask;
      var history = await historyTask;

      // Filter: Only delivered orders from current driver
      final driverProfile = await ApiService.getDeliveryRequestByUid(uid);
      if (driverProfile != null) {
        final driverId = driverProfile['uid'] as String?;
        history = history
            .where((order) {
              final ownedByDriver = order.driverId?.isEmpty ?? true ? true : order.driverId == driverId;
              return ownedByDriver && order.status == 'delivered';
            })
            .toList()
            .cast<ds.Order>();
      } else {
        history = history.where((order) => order.status == 'delivered').toList().cast<ds.Order>();
      }

      if (mounted) {
        setState(() {
          _driverStats = stats;
          _deliveryHistory = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatMoney(double amount) => '₺${amount.toStringAsFixed(2)}';

  bool _isCash(String? paymentMethod) {
    final method = (paymentMethod ?? '').toLowerCase();
    return method.contains('pay at door') || method.contains('cash') || method.contains('cod');
  }

  _Summary _computedSummary() {
    final cashOrders = _deliveryHistory.where((o) => _isCash(o.paymentMethod)).toList();
    final onlineOrders = _deliveryHistory.where((o) => !_isCash(o.paymentMethod)).toList();
    
    final gross = _deliveryHistory.fold<double>(0, (sum, order) => sum + order.total);
    final cashAmount = cashOrders.fold<double>(0, (sum, order) => sum + order.total);
    
    return _Summary(
      gross: gross,
      earnings: gross * 0.10,
      toTransfer: cashAmount * 0.90,
      onlineTotal: onlineOrders.fold<double>(0, (sum, order) => sum + order.total),
      cashCount: cashOrders.length,
      onlineCount: onlineOrders.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text('My Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kAppBarBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(kAccentBlue)))
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 20),
                      _buildHistorySection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _computedSummary();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Summary",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kSecondaryTextColor),
          ),
          const SizedBox(height: 12),
          // Gross amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatMoney(summary.gross),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
              ),
              const SizedBox(width: 6),
              Text(
                'collected',
                style: TextStyle(fontSize: 13, color: kSecondaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: kSeparatorColor, thickness: 1),
          const SizedBox(height: 12),
          // Stats grid: Orders, Cash, Online
          Row(
            children: [
              _buildStatItem(
                label: 'Orders',
                value: '${_deliveryHistory.length}',
                icon: Icons.shopping_bag,
              ),
              _buildStatItem(
                label: 'Cash',
                value: '${summary.cashCount}',
                icon: Icons.money,
              ),
              _buildStatItem(
                label: 'Online',
                value: '${summary.onlineCount}',
                icon: Icons.credit_card,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats grid: Your 10%, To Transfer, Online Settled
          Row(
            children: [
              _buildStatItem(
                label: 'Your 10%',
                value: _formatMoney(summary.earnings),
                icon: Icons.attach_money,
              ),
              _buildStatItem(
                label: 'To Transfer',
                value: _formatMoney(summary.toTransfer),
                icon: Icons.arrow_circle_up,
              ),
              _buildStatItem(
                label: 'Online Settled',
                value: _formatMoney(summary.onlineTotal),
                icon: Icons.verified,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Cash orders require transfer to the platform. Online orders are already settled.',
            style: TextStyle(fontSize: 11, color: kSecondaryTextColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String label, required String value, required IconData icon}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: kAccentBlue),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: kSecondaryTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Deliveries',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
            ),
            if (_deliveryHistory.isNotEmpty)
              Text(
                '${_deliveryHistory.length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kSecondaryTextColor),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_deliveryHistory.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                children: [
                  Icon(Icons.shopping_bag, size: 36, color: kSecondaryTextColor.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No deliveries yet',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: kSecondaryTextColor),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _deliveryHistory.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _buildHistoryRow(_deliveryHistory[index]),
          ),
      ],
    );
  }

  Widget _buildHistoryRow(ds.Order order) {
    final cash = _isCash(order.paymentMethod);
    final driverEarnings = _formatMoney(order.total * 0.10);
    final toTransfer = _formatMoney(order.total * 0.90);
    
    final accentColor = cash ? kAccentOrange : kAccentGreen;
    final accentBackground = cash ? kAccentOrange.withOpacity(0.12) : kAccentGreen.withOpacity(0.12);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(cash ? 0.35 : 0.12),
          width: 1.25,
        ),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 14,
              color: accentColor,
              weight: 900,
            ),
          ),
          const SizedBox(width: 12),
          // Store name and order info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.storeName.isNotEmpty ? order.storeName : 'Order #${order.id}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kPrimaryTextColor),
                ),
                Text(
                  'Order #${order.id} • ${cash ? 'Pay at Door' : 'Paid online'}',
                  style: TextStyle(fontSize: 11, color: kSecondaryTextColor),
                ),
              ],
            ),
          ),
          // Amount and status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(order.total),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
              ),
              const SizedBox(height: 2),
              Text(
                cash ? 'Transfer $toTransfer • You $driverEarnings' : 'Settled online • You $driverEarnings',
                style: TextStyle(fontSize: 10, color: kSecondaryTextColor),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  cash ? 'Transfer required' : 'Already settled',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUMMARY DATA CLASS
// ─────────────────────────────────────────────────────────────────────────────

class _Summary {
  final double gross;
  final double earnings;
  final double toTransfer;
  final double onlineTotal;
  final int cashCount;
  final int onlineCount;

  _Summary({
    required this.gross,
    required this.earnings,
    required this.toTransfer,
    required this.onlineTotal,
    required this.cashCount,
    required this.onlineCount,
  });
}
