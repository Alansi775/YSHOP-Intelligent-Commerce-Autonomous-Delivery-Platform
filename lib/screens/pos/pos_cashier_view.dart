// pos_cashier_view.dart — Unified POS: Table Management + Cashier
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/pos_models.dart';
import '../../models/store.dart' show Store;
import '../../services/pos_service.dart';
import '../../services/api_service.dart';
import '../../widgets/store_admin_widgets.dart' show ProductS;

// ─── Design Tokens ────────────────────────────────────────────────────────────
const _bg = Color(0xFF000000);
const _card = Color(0xFF0F0F0F);
const _lift = Color(0xFF1C1C1E);
const _bdr = Color(0xFF2C2C2E);
const _w = Color(0xFFFFFFFF);
const _dim = Color(0xFF636366);
const _soft = Color(0xFF8E8E93);

const _green = Color(0xFF32D74B);
const _orange = Color(0xFFFF9F0A);
const _blue = Color(0xFF0A84FF);
const _purple = Color(0xFFBF5AF2);
const _gray = Color(0xFF3A3A3C);
const _red = Color(0xFFFF453A);

String _fmt(double v) => NumberFormat('#,##0.00').format(v);

Color _tableColor(String s) => switch (s) {
  'available' => _green,
  'occupied' => _orange,
  'preparing' => _blue,
  'waiting_payment' => _purple,
  _ => _gray,
};

String _tableLabel(String s) => switch (s) {
  'available' => 'Available',
  'occupied' => 'Occupied',
  'preparing' => 'Preparing',
  'waiting_payment' => 'Settle',
  'disabled' => 'Disabled',
  _ => s,
};

Color _kitchenColor(String s) => switch (s) {
  'pending' => _blue,
  'preparing' => _orange,
  'delivered' => _green,
  _ => _dim,
};

String _kitchenLabel(String s) => switch (s) {
  'pending' => 'Awaiting',
  'preparing' => 'Preparing',
  'delivered' => 'Done',
  _ => s,
};

// ─── Main Widget ──────────────────────────────────────────────────────────────
class POSCashierView extends StatefulWidget {
  final int storeId;
  final String storeName;
  final String currency;
  final String storeOwnerUid;

  const POSCashierView({
    super.key,
    required this.storeId,
    required this.storeName,
    required this.currency,
    required this.storeOwnerUid,
  });

  @override
  State<POSCashierView> createState() => _POSCashierViewState();
}

class _POSCashierViewState extends State<POSCashierView> {
  final _pos = POSService();

  List<POSTable> _tables = [];
  List<ProductS> _products = [];
  List<POSOrder> _activeOrders = [];
  bool _loading = true;

  StreamSubscription? _orderSub;
  StreamSubscription? _tableSub;

  @override
  void initState() {
    super.initState();
    _pos.joinStoreRoom(widget.storeId);
    _orderSub = _pos.orderStream.listen(_onOrderEvent);
    _tableSub = _pos.tableStream.listen(_onTableEvent);
    _loadAll();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _tableSub?.cancel();
    super.dispose();
  }

  void _onOrderEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final raw = data['order'];
    if (raw == null) return;
    final order = POSOrder.fromJson(Map<String, dynamic>.from(raw));
    setState(() {
      final i = _activeOrders.indexWhere((o) => o.id == order.id);
      // Stay visible until actually paid/cancelled — a "delivered" pay-later
      // order still needs a cashier action (Settle) and the table is still busy.
      final done = !order.isActive;
      if (done) {
        if (i >= 0) _activeOrders.removeAt(i);
      } else {
        i >= 0 ? _activeOrders[i] = order : _activeOrders.insert(0, order);
      }
    });
  }

  void _onTableEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final action = data['action'] as String?;
    final raw = data['table'];
    final tid = data['tableId'];
    setState(() {
      if (action == 'deleted' && tid != null) {
        _tables.removeWhere((t) => t.id == tid);
      } else if (raw != null) {
        final t = POSTable.fromJson(Map<String, dynamic>.from(raw));
        final i = _tables.indexWhere((x) => x.id == t.id);
        i >= 0 ? _tables[i] = t : _tables.add(t);
      }
    });
  }

  Future<void> _loadAll() async {
    // Each fetch is independent — one failure must never blank-out the others.
    final results = await Future.wait([
      _pos.getTables(widget.storeId).catchError((_) => <POSTable>[]),
      _loadProducts(),
      _pos
          .getOrders(widget.storeId, activeOnly: true)
          .catchError((_) => <POSOrder>[]),
    ]);
    if (mounted) {
      setState(() {
        _tables = results[0] as List<POSTable>;
        _products = results[1] as List<ProductS>;
        _activeOrders = (results[2] as List<POSOrder>)
            .where((o) => o.isActive)
            .toList();
        _loading = false;
      });
    }
  }

  Future<void> _reloadOrders() async {
    final results = await Future.wait([
      _pos
          .getOrders(widget.storeId, activeOnly: true)
          .catchError((_) => <POSOrder>[]),
      _pos.getTables(widget.storeId).catchError((_) => <POSTable>[]),
    ]);
    if (mounted) {
      setState(() {
        // Stay visible until actually paid/cancelled (see _onOrderEvent for why)
        _activeOrders = (results[0] as List<POSOrder>)
            .where((o) => o.isActive)
            .toList();
        _tables = results[1] as List<POSTable>;
      });
    }
  }

  Future<List<ProductS>> _loadProducts() async {
    // Primary: owner-uid endpoint (same as admin view, always reliable).
    try {
      if (widget.storeOwnerUid.isNotEmpty) {
        final list = await ApiService.getStoreProducts(
          widget.storeOwnerUid,
          bypassCache: true,
        );
        final sid = widget.storeId.toString();
        return list
            .where((p) => (p as Map)['store_id']?.toString() == sid)
            .map((p) {
              final m = Map<String, dynamic>.from(p as Map);
              // Resolve relative image paths to full URLs (same as admin view does)
              m['image_url'] = Store.getFullImageUrl(m['image_url'] as String?);
              return ProductS.fromApi(m);
            })
            .where((p) => p.approved)
            .toList();
      }
    } catch (_) {
      /* fall through to public endpoint */
    }

    // Fallback: public endpoint filtered by storeId.
    try {
      final res = await ApiService.getRequest(
        '/products?storeId=${widget.storeId}&limit=500',
      );
      return ((res['products'] as List?) ?? [])
          .map((p) {
            final m = Map<String, dynamic>.from(p as Map);
            m['image_url'] = Store.getFullImageUrl(m['image_url'] as String?);
            return ProductS.fromApi(m);
          })
          .where((p) => p.approved)
          .toList();
    } catch (_) {
      return [];
    }
  }

  POSOrder? _orderForTable(int tableId) {
    for (final o in _activeOrders) {
      if (o.tableId == tableId) return o;
    }
    return null;
  }

  // ─── Table CRUD ──────────────────────────────────────────────────────────────

  void _tapTable(POSTable table) {
    if (table.status == 'disabled') return;
    final order = _orderForTable(table.id);
    _openOrderSheet(table: table, existingOrder: order);
  }

  void _openOrderSheet({POSTable? table, POSOrder? existingOrder}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSheet(
        storeId: widget.storeId,
        table: table,
        products: _products,
        existingOrder: existingOrder,
        pos: _pos,
        onRefresh: _reloadOrders,
      ),
    );
  }

  Future<void> _showAddTableDialog() async {
    final nameCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '4');
    final result = await showDialog<_TableDialogResult>(
      context: context,
      builder: (ctx) => _TableFormDialog(
        title: 'New Table',
        nameCtrl: nameCtrl,
        capCtrl: capCtrl,
      ),
    );
    if (result != _TableDialogResult.save || nameCtrl.text.trim().isEmpty)
      return;
    try {
      final table = await _pos.createTable(
        widget.storeId,
        nameCtrl.text.trim(),
        capacity: int.tryParse(capCtrl.text) ?? 4,
      );
      // Insert immediately — don't wait on the socket round-trip to show it.
      if (mounted) {
        setState(() {
          if (!_tables.any((t) => t.id == table.id)) _tables.add(table);
        });
      }
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _editTable(POSTable table) async {
    final nameCtrl = TextEditingController(text: table.name);
    final capCtrl = TextEditingController(text: '${table.capacity}');
    final result = await showDialog<_TableDialogResult>(
      context: context,
      builder: (ctx) => _TableFormDialog(
        title: 'Edit Table',
        nameCtrl: nameCtrl,
        capCtrl: capCtrl,
        showDelete: true,
      ),
    );
    if (result == null) return;
    if (result == _TableDialogResult.delete) {
      await _confirmDelete(table);
    } else if (result == _TableDialogResult.save &&
        nameCtrl.text.trim().isNotEmpty) {
      try {
        final updated = await _pos.updateTable(
          table.id,
          name: nameCtrl.text.trim(),
          capacity: int.tryParse(capCtrl.text) ?? table.capacity,
        );
        if (mounted) {
          setState(() {
            final i = _tables.indexWhere((t) => t.id == updated.id);
            if (i >= 0) _tables[i] = updated;
          });
        }
      } catch (e) {
        _err(e);
      }
    }
  }

  Future<void> _confirmDelete(POSTable table) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _lift,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _bdr),
        ),
        title: const Text(
          'Delete Table?',
          style: TextStyle(color: _w, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove "${table.name}" permanently?',
          style: const TextStyle(color: _soft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _pos.deleteTable(table.id);
      if (mounted) setState(() => _tables.removeWhere((t) => t.id == table.id));
    } catch (e) {
      _err(e);
    }
  }

  // ─── Order Actions ────────────────────────────────────────────────────────────

  Future<void> _payOrder(POSOrder order) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => _PayDialog(order: order),
    );
    if (method == null || !mounted) return;
    try {
      await _pos.processPayment(order.id, method);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _cancelOrder(POSOrder order) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _lift,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _bdr),
        ),
        title: const Text(
          'Cancel Order?',
          style: TextStyle(color: _w, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Order #${order.id} will be cancelled and stock restored.',
          style: const TextStyle(color: _soft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: _soft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel Order',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _pos.cancelOrder(order.id);
    } catch (e) {
      _err(e);
    }
  }

  void _openInvoice(POSOrder order) {
    launchUrl(
      Uri.parse(_pos.invoiceUrl(order.id)),
      mode: LaunchMode.externalApplication,
    );
  }

  void _err(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString(), style: const TextStyle(color: _w)),
        backgroundColor: _red.withOpacity(0.15),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _red),
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _WalkInFAB(onTap: () => _openOrderSheet()),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _w, strokeWidth: 1.5),
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildAppBar(),
                if (_tables.isEmpty) _buildEmptyState() else _buildTableGrid(),
                if (_activeOrders.isNotEmpty) _buildActiveOrders(),
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      expandedHeight: 72,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _w, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.storeName.toUpperCase(),
              style: const TextStyle(
                color: _w,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        GestureDetector(
          onTap: _showAddTableDialog,
          child: Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _lift,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: _bdr),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: _w, size: 16),
                SizedBox(width: 5),
                Text(
                  'Table',
                  style: TextStyle(
                    color: _w,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: _bdr),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _lift,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _bdr),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: _soft,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No tables yet',
                style: TextStyle(
                  color: _w,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add your first table to start taking local orders.',
                style: TextStyle(color: _soft, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _showAddTableDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Add First Table',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _w,
                  foregroundColor: _bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableGrid() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisExtent: 190,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate((_, i) {
          final t = _tables[i];
          return _TableCard(
            table: t,
            activeOrder: _orderForTable(t.id),
            onTap: () => _tapTable(t),
            onLongPress: () => _editTable(t),
          );
        }, childCount: _tables.length),
      ),
    );
  }

  Widget _buildActiveOrders() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Section header
          Row(
            children: [
              const Text(
                'ACTIVE ORDERS',
                style: TextStyle(
                  color: _soft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _orange.withOpacity(0.3)),
                ),
                child: Text(
                  '${_activeOrders.length}',
                  style: const TextStyle(
                    color: _orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._activeOrders.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ActiveOrderCard(
                order: o,
                onPay: _payOrder,
                onCancel: _cancelOrder,
                onInvoice: _openInvoice,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Walk-in FAB ──────────────────────────────────────────────────────────────
class _WalkInFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _WalkInFAB({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: _w,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, color: _bg, size: 18),
          SizedBox(width: 8),
          Text(
            'Walk-in',
            style: TextStyle(
              color: _bg,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Table Card ───────────────────────────────────────────────────────────────
class _TableCard extends StatelessWidget {
  final POSTable table;
  final POSOrder? activeOrder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TableCard({
    required this.table,
    this.activeOrder,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final sc = _tableColor(table.status);
    final disabled = table.status == 'disabled';

    return GestureDetector(
      onTap: disabled ? null : onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: disabled ? _bdr : sc.withOpacity(0.45),
            width: 1.5,
          ),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: sc.withOpacity(0.10),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: status dot + capacity
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: sc,
                    shape: BoxShape.circle,
                    boxShadow: disabled
                        ? null
                        : [
                            BoxShadow(
                              color: sc.withOpacity(0.65),
                              blurRadius: 7,
                              spreadRadius: 0,
                            ),
                          ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.group_rounded, size: 12, color: _dim),
                    const SizedBox(width: 4),
                    Text(
                      '${table.capacity}',
                      style: const TextStyle(
                        color: _dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Spacer(),

            // Table name
            Text(
              table.name,
              style: TextStyle(
                color: disabled ? _dim : _w,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),

            // Status or kitchen progress + total
            if (activeOrder != null) ...[
              Text(
                _kitchenLabel(activeOrder!.kitchenStatus),
                style: TextStyle(
                  color: _kitchenColor(activeOrder!.kitchenStatus),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_fmt(activeOrder!.totalPrice)} ${activeOrder!.currency}',
                style: TextStyle(
                  color: sc,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else
              Text(
                _tableLabel(table.status),
                style: TextStyle(
                  color: disabled ? _dim : sc.withOpacity(0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Active Order Card ────────────────────────────────────────────────────────
class _ActiveOrderCard extends StatelessWidget {
  final POSOrder order;
  final Function(POSOrder) onPay;
  final Function(POSOrder) onCancel;
  final Function(POSOrder) onInvoice;

  const _ActiveOrderCard({
    required this.order,
    required this.onPay,
    required this.onCancel,
    required this.onInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final kc = _kitchenColor(order.kitchenStatus);
    final canPay = order.kitchenStatus == 'delivered';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _bdr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'ORD-${order.id}',
                style: const TextStyle(
                  color: _w,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
              if (order.tableName != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _lift,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: _bdr),
                  ),
                  child: Text(
                    order.tableName!,
                    style: const TextStyle(
                      color: _soft,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Kitchen status pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kc.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: kc.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: kc,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: kc.withOpacity(0.5), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      order.kitchenStatus.toUpperCase(),
                      style: TextStyle(
                        color: kc,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Items preview
          Text(
            order.items
                .map((i) => '${i.productName} ×${i.quantity}')
                .join('  •  '),
            style: const TextStyle(color: _soft, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 14),

          // Footer: total + actions
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      color: _dim,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmt(order.totalPrice)} ${order.currency}',
                    style: const TextStyle(
                      color: _w,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Invoice
              _ActionBtn(
                icon: Icons.receipt_long_rounded,
                onTap: () => onInvoice(order),
              ),
              const SizedBox(width: 6),
              // Cancel
              _ActionBtn(
                icon: Icons.close_rounded,
                onTap: () => onCancel(order),
                danger: true,
              ),
              if (canPay) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => onPay(order),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: _green.withOpacity(0.3),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Text(
                      'SETTLE',
                      style: TextStyle(
                        color: _bg,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _ActionBtn({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: danger ? _red.withOpacity(0.08) : _lift,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: danger ? _red.withOpacity(0.25) : _bdr),
      ),
      child: Icon(icon, size: 16, color: danger ? _red : _soft),
    ),
  );
}

// ─── Order Sheet ──────────────────────────────────────────────────────────────
class _OrderSheet extends StatefulWidget {
  final int storeId;
  final POSTable? table;
  final List<ProductS> products;
  final POSOrder? existingOrder;
  final POSService pos;
  final Future<void> Function() onRefresh;

  const _OrderSheet({
    required this.storeId,
    this.table,
    required this.products,
    this.existingOrder,
    required this.pos,
    required this.onRefresh,
  });

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final _searchCtrl = TextEditingController();
  final _cart = <POSOrderItem>[]; // NEW items being added this session
  String _search = '';
  bool _submitting = false;

  bool get _isAdding => widget.existingOrder != null;

  @override
  void initState() {
    super.initState();
    // Editing an existing order — pre-populate the cart with its current items
    // so the cashier can change quantities or remove ones already sent to the
    // kitchen (not just add new ones).
    if (widget.existingOrder != null) {
      _cart.addAll(widget.existingOrder!.items);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Payment method picker shown before sending a NEW order to kitchen
  Future<String?> _showPaymentPicker() => showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _lift,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _bdr),
      ),
      title: const Text(
        'Payment Method',
        style: TextStyle(color: _w, fontWeight: FontWeight.w700, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'How will the customer pay?',
            style: TextStyle(color: _soft, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...[
            ('cash', 'Cash', Icons.payments_rounded),
            ('card', 'Card', Icons.credit_card_rounded),
            ('bank_transfer', 'IBAN Transfer', Icons.account_balance_rounded),
            ('later', 'Pay Later', Icons.schedule_rounded),
          ].map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PayTile(
                label: t.$2,
                icon: t.$3,
                onTap: () => Navigator.pop(ctx, t.$1),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: _soft)),
        ),
      ],
    ),
  );

  List<ProductS> get _filtered {
    final q = _search.toLowerCase();
    return widget.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
  }

  int _cartQty(String productId) {
    final pid = int.tryParse(productId) ?? 0;
    for (final i in _cart) {
      if (i.productId == pid) return i.quantity;
    }
    return 0;
  }

  void _add(ProductS p) {
    final pid = int.tryParse(p.id) ?? 0;
    final price = double.tryParse(p.price) ?? 0.0;
    setState(() {
      final i = _cart.indexWhere((x) => x.productId == pid);
      if (i >= 0) {
        _cart[i] = _cart[i].copyWith(quantity: _cart[i].quantity + 1);
      } else {
        _cart.add(
          POSOrderItem(
            productId: pid,
            productName: p.name,
            imageUrl: p.imageUrl.isNotEmpty ? p.imageUrl : null,
            quantity: 1,
            price: price,
            currency: p.currency ?? '',
          ),
        );
      }
    });
  }

  void _changeQty(int i, int delta) {
    setState(() {
      final nq = _cart[i].quantity + delta;
      nq <= 0 ? _cart.removeAt(i) : _cart[i] = _cart[i].copyWith(quantity: nq);
    });
  }

  // The cart now holds the FULL item list (pre-populated from the existing
  // order when editing), so its total already IS the order's grand total —
  // no need to add existingOrder.totalPrice on top.
  double get _total => _cart.fold(0, (s, i) => s + i.subtotal);

  // Only let the cashier hit "Update Order" once something actually changed
  // (quantity edited or an item removed) — otherwise it's a no-op round trip.
  bool get _dirty {
    if (!_isAdding) return true;
    final before = <int, int>{};
    for (final it in widget.existingOrder!.items) {
      before[it.productId] = (before[it.productId] ?? 0) + it.quantity;
    }
    final after = <int, int>{};
    for (final it in _cart) {
      after[it.productId] = (after[it.productId] ?? 0) + it.quantity;
    }
    if (before.length != after.length) return true;
    for (final e in before.entries) {
      if (after[e.key] != e.value) return true;
    }
    return false;
  }

  String get _currency => _cart.isNotEmpty
      ? _cart.first.currency
      : (widget.existingOrder?.currency ?? '');

  Future<void> _sendToKitchen() async {
    if (_cart.isEmpty) return;

    String? paymentMethod;
    if (!_isAdding) {
      // New order — ask how customer will pay
      paymentMethod = await _showPaymentPicker();
      if (paymentMethod == null) return; // cancelled
    }

    setState(() => _submitting = true);
    try {
      if (_isAdding) {
        // The cart already holds the full, edited item list (quantities
        // changed / items removed included) — send it as-is.
        await widget.pos.updateOrderItems(
          widget.existingOrder!.id,
          List.from(_cart),
        );
      } else {
        await widget.pos.createOrder(
          storeId: widget.storeId,
          tableId: widget.table?.id,
          items: List.from(_cart),
          paymentMethod: paymentMethod == 'later' ? null : paymentMethod,
        );
      }
      await widget.onRefresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString(), style: const TextStyle(color: _w)),
            backgroundColor: _red.withOpacity(0.15),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _red),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final wide = w > 640;

    return Container(
      height: h * 0.93,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: _bdr.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildProducts()),
                      Container(width: 0.5, color: _bdr),
                      SizedBox(width: 300, child: _buildCart()),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _buildProducts()),
                      if (_cart.isNotEmpty) ...[
                        Container(height: 0.5, color: _bdr),
                        _buildCart(maxH: 280),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isWalkIn = widget.table == null;
    final existing = widget.existingOrder;
    final kc = existing != null ? _kitchenColor(existing.kitchenStatus) : _soft;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _bdr)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _bdr,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isAdding ? kc.withOpacity(0.12) : _lift,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isAdding ? kc.withOpacity(0.35) : _bdr,
                  ),
                ),
                child: Icon(
                  _isAdding
                      ? Icons.add_shopping_cart_rounded
                      : (isWalkIn
                            ? Icons.directions_walk_rounded
                            : Icons.table_restaurant_rounded),
                  color: _isAdding ? kc : _soft,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAdding
                          ? 'Order #${existing!.id}'
                          : (isWalkIn ? 'Walk-in Order' : widget.table!.name),
                      style: const TextStyle(
                        color: _w,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_isAdding)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: kc,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kc.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _kitchenLabel(existing!.kitchenStatus),
                            style: TextStyle(
                              color: kc,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Live cart total (editable below), not the original snapshot
                          Text(
                            '${_cart.length} item${_cart.length != 1 ? 's' : ''}  •  ${_fmt(_total)} $_currency',
                            style: const TextStyle(color: _dim, fontSize: 11),
                          ),
                        ],
                      )
                    else if (!isWalkIn)
                      Text(
                        '${widget.table!.capacity} seats  •  Long press to edit',
                        style: const TextStyle(color: _dim, fontSize: 11),
                      ),
                  ],
                ),
              ),
              // Invoice button for existing orders
              if (_isAdding) ...[
                GestureDetector(
                  onTap: () {
                    final url = widget.pos.invoiceUrl(existing!.id);
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _lift,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _bdr),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: _soft,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _lift,
                    shape: BoxShape.circle,
                    border: Border.all(color: _bdr),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: _soft,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProducts() {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: _w, fontSize: 14),
            cursorColor: _w,
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: const TextStyle(color: _dim),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: _dim,
                size: 18,
              ),
              filled: true,
              fillColor: _lift,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _bdr),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _w, width: 1.5),
              ),
            ),
          ),
        ),
        // Grid
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No products found',
                    style: TextStyle(color: _dim, fontSize: 14),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisExtent: 195,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final p = _filtered[i];
                    return _ProductCard(
                      product: p,
                      qty: _cartQty(p.id),
                      onAdd: () => _add(p),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCart({double? maxH}) {
    final content = Column(
      children: [
        // Cart header
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              const Text(
                'ORDER',
                style: TextStyle(
                  color: _soft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (_cart.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _cart.clear()),
                  child: const Text(
                    'Clear all',
                    style: TextStyle(
                      color: _red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Items
        Expanded(
          child: _cart.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _isAdding
                          ? 'No items left.\nUse "Cancel Order" on the table card to cancel it entirely.'
                          : 'Tap a product\nto add it here',
                      style: const TextStyle(
                        color: _dim,
                        fontSize: 13,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _cart.length,
                  itemBuilder: (_, i) => _CartRow(
                    item: _cart[i],
                    onIncrease: () => _changeQty(i, 1),
                    onDecrease: () => _changeQty(i, -1),
                  ),
                ),
        ),
        // Total + CTA
        if (_cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _bdr)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        color: _dim,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_fmt(_total)} $_currency',
                      style: const TextStyle(
                        color: _w,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_submitting || (_isAdding && !_dirty))
                        ? null
                        : _sendToKitchen,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: _bg,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            _isAdding ? Icons.sync_rounded : Icons.send_rounded,
                            size: 18,
                          ),
                    label: Text(
                      _isAdding ? 'UPDATE ORDER' : 'SEND TO KITCHEN',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _w,
                      foregroundColor: _bg,
                      disabledBackgroundColor: _lift,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return maxH != null ? SizedBox(height: maxH, child: content) : content;
  }
}

// ─── Product Card ─────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final ProductS product;
  final int qty;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.product,
    required this.qty,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final oos = (product.stock ?? 1) <= 0;
    final inCart = qty > 0;

    return GestureDetector(
      onTap: oos ? null : onAdd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _lift,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: inCart ? _w.withOpacity(0.5) : _bdr,
            width: inCart ? 1.5 : 1,
          ),
          boxShadow: inCart
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.06),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: oos ? 0.38 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image area
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(17),
                      ),
                      child: product.imageUrl.isNotEmpty
                          ? Image.network(
                              product.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _noImage(),
                            )
                          : _noImage(),
                    ),
                    if (inCart)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: _w,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$qty',
                              style: const TextStyle(
                                color: _bg,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (oos)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(17),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'OUT OF\nSTOCK',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _red,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        color: _w,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmt(double.tryParse(product.price) ?? 0)} ${product.currency ?? ''}',
                      style: const TextStyle(color: _soft, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noImage() => Container(
    color: _card,
    child: const Center(
      child: Icon(Icons.fastfood_rounded, color: _dim, size: 28),
    ),
  );
}

// ─── Cart Row ─────────────────────────────────────────────────────────────────
class _CartRow extends StatelessWidget {
  final POSOrderItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _CartRow({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    // Items pre-populated from an existing order carry the raw path the
    // backend stored (e.g. "/uploads/products/x.jpg"), not yet resolved to a
    // full URL the way freshly-added cart items are in _add() — resolve it
    // here so both cases render the same (same fix Kitchen view already uses).
    final imgUrl = Store.getFullImageUrl(item.imageUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr),
      ),
      child: Row(
        children: [
          // Product thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: imgUrl.isNotEmpty
                  ? Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _lift,
                        child: const Icon(
                          Icons.fastfood_rounded,
                          color: _dim,
                          size: 20,
                        ),
                      ),
                    )
                  : Container(
                      color: _lift,
                      child: const Icon(
                        Icons.fastfood_rounded,
                        color: _dim,
                        size: 20,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    color: _w,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(item.subtotal)} ${item.currency}',
                  style: const TextStyle(color: _soft, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            children: [
              _QBtn(icon: Icons.remove_rounded, onTap: onDecrease),
              SizedBox(
                width: 30,
                child: Center(
                  child: Text(
                    '${item.quantity}',
                    style: const TextStyle(
                      color: _w,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _QBtn(icon: Icons.add_rounded, onTap: onIncrease),
            ],
          ),
        ],
      ),
    );
  }
}

class _QBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _lift,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _bdr),
      ),
      child: Icon(icon, size: 13, color: _w),
    ),
  );
}

// ─── Payment Tile ─────────────────────────────────────────────────────────────
class _PayTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PayTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _lift,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _soft, size: 18),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              color: _w,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: _dim, size: 18),
        ],
      ),
    ),
  );
}

// ─── Payment Dialog (for active order settle) ─────────────────────────────────
class _PayDialog extends StatelessWidget {
  final POSOrder order;
  const _PayDialog({required this.order});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _lift,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: _bdr),
    ),
    title: const Text(
      'Process Payment',
      style: TextStyle(color: _w, fontWeight: FontWeight.w700, fontSize: 18),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _bdr),
          ),
          child: Row(
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(color: _soft, fontSize: 12, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '${_fmt(order.totalPrice)} ${order.currency}',
                style: const TextStyle(
                  color: _w,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...[
          ('cash', 'Cash', Icons.payments_rounded),
          ('card', 'Card', Icons.credit_card_rounded),
          ('bank_transfer', 'IBAN Transfer', Icons.account_balance_rounded),
          ('mixed', 'Split', Icons.compare_arrows_rounded),
        ].map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PayTile(
              label: t.$2,
              icon: t.$3,
              onTap: () => Navigator.pop(context, t.$1),
            ),
          ),
        ),
      ],
    ),
  );
}

// ─── Table Form Dialog ────────────────────────────────────────────────────────
enum _TableDialogResult { save, delete }

class _TableFormDialog extends StatelessWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController capCtrl;
  final bool showDelete;

  const _TableFormDialog({
    required this.title,
    required this.nameCtrl,
    required this.capCtrl,
    this.showDelete = false,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _lift,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: _bdr),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: _w,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FormField(
          label: 'Table Name',
          ctrl: nameCtrl,
          hint: 'e.g. Table 1, VIP, Bar',
        ),
        const SizedBox(height: 12),
        _FormField(
          label: 'Capacity',
          ctrl: capCtrl,
          hint: '4',
          type: TextInputType.number,
        ),
      ],
    ),
    actions: [
      if (showDelete)
        TextButton(
          onPressed: () => Navigator.pop(context, _TableDialogResult.delete),
          child: const Text(
            'Delete',
            style: TextStyle(color: _red, fontWeight: FontWeight.w700),
          ),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context, null),
        child: const Text('Cancel', style: TextStyle(color: _soft)),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _TableDialogResult.save),
        style: FilledButton.styleFrom(
          backgroundColor: _w,
          foregroundColor: _bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        child: const Text(
          'Save',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final TextInputType type;

  const _FormField({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.type = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _soft,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: _w, fontSize: 15),
        cursorColor: _w,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _dim),
          filled: true,
          fillColor: _bg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _bdr),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _w, width: 1.5),
          ),
        ),
      ),
    ],
  );
}
