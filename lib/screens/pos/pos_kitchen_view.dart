// pos_kitchen_view.dart — Kitchen Display Screen
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_models.dart';
import '../../models/store.dart' show Store;
import '../../services/pos_service.dart';

// ─── Shared color tokens (same as cashier) ────────────────────────────────────
const _kBg     = Color(0xFF000000);
const _kCard   = Color(0xFF0F0F0F);
const _kLift   = Color(0xFF1C1C1E);
const _kBdr    = Color(0xFF2C2C2E);
const _kW      = Color(0xFFFFFFFF);
const _kDim    = Color(0xFF636366);
const _kSoft   = Color(0xFF8E8E93);
const _kOrange = Color(0xFFFF9F0A);
const _kGreen  = Color(0xFF32D74B);
const _kBlue   = Color(0xFF0A84FF);
const _kRed    = Color(0xFFFF453A);

Color _kStatusColor(String s) => switch (s) {
  'pending'   => _kBlue,
  'preparing' => _kOrange,
  'delivered' => _kGreen,
  _           => _kDim,
};

String _kStatusLabel(String s) => switch (s) {
  'pending'   => 'Awaiting',
  'preparing' => 'Preparing',
  'delivered' => 'Done',
  _           => s,
};

class POSKitchenView extends StatefulWidget {
  final int storeId;
  final String storeName;
  const POSKitchenView({super.key, required this.storeId, required this.storeName});

  @override
  State<POSKitchenView> createState() => _POSKitchenViewState();
}

class _POSKitchenViewState extends State<POSKitchenView> {
  final _pos = POSService();
  List<POSOrder> _orders   = [];
  final _departing = <int>{};   // order IDs showing 5-sec "Delivered ✓" farewell
  bool _loading = true;
  StreamSubscription? _orderSub;

  @override
  void initState() {
    super.initState();
    _pos.joinStoreRoom(widget.storeId);
    _orderSub = _pos.orderStream.listen(_onOrderEvent);
    _load();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    super.dispose();
  }

  void _onOrderEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final orderData = data['order'];
    if (orderData == null) return;
    final order = POSOrder.fromJson(Map<String, dynamic>.from(orderData));

    final show = ['pending', 'preparing'].contains(order.kitchenStatus)
        && !order.isCancelled && !order.isCompleted;
    final isDelivered = order.kitchenStatus == 'delivered';

    if (data['event'] == 'new' || data['trigger'] == 'kitchen') {
      _notify(order);
    }

    setState(() {
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (show) {
        idx >= 0 ? _orders[idx] = order : _orders.insert(0, order);
      } else if (isDelivered && idx >= 0 && !_departing.contains(order.id)) {
        // Show "Delivered ✓" farewell card for 5 seconds then remove
        _orders[idx] = order;
        _departing.add(order.id);
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) setState(() {
            _orders.removeWhere((o) => o.id == order.id);
            _departing.remove(order.id);
          });
        });
      } else if (!isDelivered) {
        if (idx >= 0) _orders.removeAt(idx);
      }
      _sort();
    });
  }

  void _sort() {
    const p = {'pending': 0, 'preparing': 1};
    _orders.sort((a, b) {
      final d = (p[a.kitchenStatus] ?? 9).compareTo(p[b.kitchenStatus] ?? 9);
      return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
    });
  }

  void _notify(POSOrder order) {
    if (!mounted) return;
    final msg = order.kitchenStatus == 'pending'
        ? 'New order! ${order.tableName != null ? 'Table: ${order.tableName}' : '#${order.id}'}'
        : 'Order #${order.id} updated';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.notifications_active_rounded, color: _kW, size: 18),
        const SizedBox(width: 8),
        Text(msg, style: const TextStyle(color: _kW, fontWeight: FontWeight.w600)),
      ]),
      backgroundColor: _kOrange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _load() async {
    try {
      final orders = await _pos.getKitchenOrders(widget.storeId);
      if (mounted) {
        setState(() {
          _orders = orders.where((o) =>
              ['pending', 'preparing'].contains(o.kitchenStatus) &&
              !o.isCancelled && !o.isCompleted).toList();
          _sort();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _advance(POSOrder order) async {
    final next = order.kitchenStatus == 'pending' ? 'preparing' : 'delivered';
    try {
      await _pos.updateKitchenStatus(order.id, next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(), style: const TextStyle(color: _kW)),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kW),
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _kOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kOrange.withAlpha(80)),
            ),
            child: const Icon(Icons.local_fire_department_rounded, color: _kOrange, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Kitchen — ${widget.storeName}',
              style: const TextStyle(color: _kW, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _orders.isEmpty ? _kLift : _kOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _orders.isEmpty ? _kBdr : _kOrange.withAlpha(80)),
            ),
            child: Text('${_orders.length} active',
                style: TextStyle(
                  color: _orders.isEmpty ? _kSoft : _kOrange,
                  fontSize: 12, fontWeight: FontWeight.w700,
                )),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kSoft, size: 20),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _kBdr),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 1.5))
          : _orders.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _kLift,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _kBdr),
                    ),
                    child: const Icon(Icons.check_circle_rounded, size: 38, color: _kGreen),
                  ),
                  const SizedBox(height: 20),
                  const Text('All done!',
                      style: TextStyle(color: _kW, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Waiting for new orders...',
                      style: TextStyle(color: _kSoft, fontSize: 14)),
                ]))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 340,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _orders.length,
                  itemBuilder: (_, i) {
                    // Capture this specific order by value, not by index —
                    // a socket-driven refresh can reorder/insert into
                    // _orders between build and tap, which made the button
                    // fire on whatever order was *currently* at position i
                    // rather than the one actually shown/tapped.
                    final order = _orders[i];
                    return _KitchenCard(
                      key:         ValueKey(order.id),
                      order:       order,
                      isDeparting: _departing.contains(order.id),
                      onAdvance:   () => _advance(order),
                    );
                  },
                ),
    );
  }
}

// ─── Kitchen Card ─────────────────────────────────────────────────────────────
class _KitchenCard extends StatelessWidget {
  final POSOrder order;
  final bool isDeparting;
  final VoidCallback onAdvance;
  const _KitchenCard({super.key, required this.order, required this.isDeparting, required this.onAdvance});

  String _elapsed() {
    final diff = DateTime.now().difference(order.createdAt);
    if (diff.inMinutes < 1) return '< 1 min';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    if (isDeparting) {
      return Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kGreen.withAlpha(120), width: 1.5),
          boxShadow: [BoxShadow(color: _kGreen.withAlpha(30), blurRadius: 18)],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _kGreen.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(color: _kGreen.withAlpha(80)),
            ),
            child: const Icon(Icons.check_rounded, color: _kGreen, size: 32),
          ),
          const SizedBox(height: 16),
          const Text('Delivered!',
              style: TextStyle(color: _kGreen, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (order.tableName != null)
            Text('Table ${order.tableName} is now free',
                style: const TextStyle(color: _kDim, fontSize: 12)),
        ]),
      );
    }

    final sc  = _kStatusColor(order.kitchenStatus);
    final lbl = _kStatusLabel(order.kitchenStatus);

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sc.withAlpha(100), width: 1.5),
        boxShadow: [BoxShadow(color: sc.withAlpha(25), blurRadius: 18, spreadRadius: 1)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: sc.withAlpha(18),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
            border: Border(bottom: BorderSide(color: sc.withAlpha(50))),
          ),
          child: Row(children: [
            // Status dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: sc, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: sc.withAlpha(160), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 8),
            Text(lbl,
                style: TextStyle(color: sc, fontSize: 12,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const Spacer(),
            // Always show the order number, and the table too when this is
            // a dine-in order — kitchen staff need both to avoid mixing up
            // orders when several arrive close together.
            Text('#${order.id}',
                style: const TextStyle(color: _kSoft, fontWeight: FontWeight.w700, fontSize: 14)),
            if (order.tableName != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: sc.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sc.withAlpha(80)),
                ),
                child: Text(order.tableName!,
                    style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 10),
            Row(children: [
              const Icon(Icons.schedule_rounded, color: _kDim, size: 12),
              const SizedBox(width: 3),
              Text(_elapsed(), style: const TextStyle(color: _kDim, fontSize: 11)),
            ]),
          ]),
        ),

        // ── Items ────────────────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            itemCount: order.items.length,
            itemBuilder: (_, i) {
              final it = order.items[i];
              final imgUrl = Store.getFullImageUrl(it.imageUrl);
              final isNew = order.isNewItem(it);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: isNew ? const EdgeInsets.all(6) : EdgeInsets.zero,
                decoration: isNew
                    ? BoxDecoration(
                        color: _kGreen.withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kGreen.withAlpha(90)),
                      )
                    : null,
                child: Row(children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40, height: 40,
                      child: imgUrl.isNotEmpty
                          ? Image.network(imgUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: _kLift,
                                child: const Icon(Icons.fastfood_rounded, color: _kDim, size: 18),
                              ))
                          : Container(
                              color: _kLift,
                              child: const Icon(Icons.fastfood_rounded, color: _kDim, size: 18),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (isNew)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _kGreen,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('NEW',
                                style: TextStyle(color: _kBg, fontSize: 9, fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6)),
                          ),
                        ),
                      Text(it.productName,
                          style: const TextStyle(color: _kW, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sc.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sc.withAlpha(80)),
                    ),
                    child: Text('×${it.quantity}',
                        style: TextStyle(color: sc, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ]),
              );
            },
          ),
        ),

        if (order.cashierNotes != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              const Icon(Icons.sticky_note_2_rounded, color: _kDim, size: 13),
              const SizedBox(width: 5),
              Expanded(
                child: Text(order.cashierNotes!,
                    style: const TextStyle(color: _kDim, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),

        // ── Action button ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdvance,
              icon: Icon(
                order.kitchenStatus == 'pending'
                    ? Icons.local_fire_department_rounded
                    : Icons.check_circle_rounded,
                size: 18,
              ),
              label: Text(
                order.kitchenStatus == 'pending' ? 'Start Cooking' : 'Done',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: sc,
                foregroundColor: _kBg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
