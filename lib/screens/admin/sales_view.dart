// lib/screens/admin/sales_view.dart
//
// Admin "Sales" — per-store monthly settlement/reconciliation.
// Flow: categories → stores in category (live running total) → History
// (past settled periods) or the current unsettled period detail, and a
// split-screen (local | online) itemized view with an Invoice PDF button.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../../models/product.dart';
import 'common.dart';

String _fmtMoney(num? v, String currency) => '${(v ?? 0).toStringAsFixed(2)} $currency';

String _fmtDate(dynamic v) {
  final d = v == null ? null : DateTime.tryParse(v.toString());
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _fmtDateTime(dynamic v) {
  final d = v == null ? null : DateTime.tryParse(v.toString());
  if (d == null) return '—';
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${_fmtDate(v)} $h:$min';
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'food':
      return Icons.restaurant_rounded;
    case 'clothes':
    case 'clothing':
    case 'fashion':
      return Icons.checkroom_rounded;
    case 'electronics':
      return Icons.devices_rounded;
    case 'grocery':
    case 'groceries':
      return Icons.local_grocery_store_rounded;
    case 'pharmacy':
      return Icons.local_pharmacy_rounded;
    case 'beauty':
      return Icons.face_retouching_natural_rounded;
    default:
      return Icons.storefront_rounded;
  }
}

Gradient _categoryGradient(int index) {
  const gradients = [
    AppGradients.primary,
    AppGradients.success,
    AppGradients.warning,
    AppGradients.purple,
    AppGradients.cyan,
    AppGradients.pink,
    AppGradients.danger,
  ];
  return gradients[index % gradients.length];
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'cancelled':
      return kAccentRed;
    case 'pending':
      return kAccentOrange;
    case 'confirmed':
    case 'preparing':
    case 'ready':
      return kAccentBlue;
    case 'delivered':
    case 'completed':
      return kAccentGreen;
    default:
      return kSecondaryTextColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  1. CATEGORY GRID (landing screen)
// ═══════════════════════════════════════════════════════════════════════════

class SalesCategoriesView extends StatefulWidget {
  const SalesCategoriesView({super.key});

  @override
  State<SalesCategoriesView> createState() => _SalesCategoriesViewState();
}

class _SalesCategoriesViewState extends State<SalesCategoriesView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiService.getRequest('/admin/sales/categories');
      final rows = (response?['data'] as List?) ?? [];
      setState(() {
        _categories = rows.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text('Sales', style: TextStyle(color: kPrimaryTextColor)),
        backgroundColor: kDarkBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Error: $_error', style: const TextStyle(color: kSecondaryTextColor)))
              : _categories.isEmpty
                  ? const Center(
                      child: Text('No approved stores yet',
                          style: TextStyle(color: kSecondaryTextColor)))
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final cross = constraints.maxWidth > 1100
                            ? 4
                            : constraints.maxWidth > 700
                                ? 3
                                : 2;
                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cross,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.3,
                          ),
                          itemCount: _categories.length,
                          itemBuilder: (_, i) {
                            final c = _categories[i];
                            final name = c['category']?.toString() ?? 'General';
                            final count = c['store_count'] ?? 0;
                            final gradient = _categoryGradient(i);
                            return _CategoryCard(
                              name: name,
                              count: count,
                              icon: _categoryIcon(name),
                              gradient: gradient,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SalesStoresView(category: name),
                              )),
                            );
                          },
                        );
                      }),
                    ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final int count;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.count,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGlassBorder),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(name,
                  style: const TextStyle(
                      color: kPrimaryTextColor, fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 4),
              Text('$count store${count == 1 ? '' : 's'}',
                  style: const TextStyle(color: kSecondaryTextColor, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. STORES IN CATEGORY (live running totals + Done)
// ═══════════════════════════════════════════════════════════════════════════

class SalesStoresView extends StatefulWidget {
  final String category;
  const SalesStoresView({super.key, required this.category});

  @override
  State<SalesStoresView> createState() => _SalesStoresViewState();
}

class _SalesStoresViewState extends State<SalesStoresView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _stores = [];
  final Set<int> _expanded = {};
  int? _settlingStoreId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response =
          await ApiService.getRequest('/admin/sales/stores?category=${Uri.encodeComponent(widget.category)}');
      final rows = (response?['data'] as List?) ?? [];
      setState(() {
        _stores = rows.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _settle(Map<String, dynamic> store) async {
    final storeId = store['store_id'] as int;
    final currency = store['currency'] as String? ?? 'USD';
    final net = (store['totals'] as Map<String, dynamic>?)?['net'] as Map<String, dynamic>? ?? {};
    final storeOwes = net['store_owes_platform'] ?? 0;
    final platformOwes = net['platform_owes_store'] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text('Settle this period?', style: TextStyle(color: kPrimaryTextColor)),
        content: Text(
          'This locks in the current totals (store owes platform: ${_fmtMoney(storeOwes, currency)} · '
          'platform owes store: ${_fmtMoney(platformOwes, currency)}) '
          'as a permanent record and resets the running total to zero starting now. '
          'You can undo this from History if it was a mistake — nothing is ever deleted.',
          style: const TextStyle(color: kSecondaryTextColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Settle (Done)')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _settlingStoreId = storeId);
    try {
      await ApiService.postRequest('/admin/sales/stores/$storeId/settle', {});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settled. Running total reset.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to settle: $e')));
      }
    } finally {
      if (mounted) setState(() => _settlingStoreId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: Text(widget.category, style: const TextStyle(color: kPrimaryTextColor)),
        backgroundColor: kDarkBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: kSecondaryTextColor)))
              : _stores.isEmpty
                  ? const Center(
                      child: Text('No stores in this category', style: TextStyle(color: kSecondaryTextColor)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _stores.length,
                      itemBuilder: (_, i) {
                        final store = _stores[i];
                        final storeId = store['store_id'] as int;
                        return _StoreSalesCard(
                          store: store,
                          expanded: _expanded.contains(storeId),
                          settling: _settlingStoreId == storeId,
                          onToggle: () => setState(() {
                            if (!_expanded.add(storeId)) _expanded.remove(storeId);
                          }),
                          onSettle: () => _settle(store),
                          onViewDetail: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SalesDetailView(
                              storeId: storeId,
                              storeName: store['store_name']?.toString() ?? '—',
                              currency: store['currency'] as String? ?? 'USD',
                              isCurrent: true,
                            ),
                          )),
                          onHistory: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SalesHistoryView(
                              storeId: storeId,
                              storeName: store['store_name']?.toString() ?? '—',
                              currency: store['currency'] as String? ?? 'USD',
                            ),
                          )),
                        );
                      },
                    ),
    );
  }
}

class _StoreSalesCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final bool expanded;
  final bool settling;
  final VoidCallback onToggle;
  final VoidCallback onSettle;
  final VoidCallback onViewDetail;
  final VoidCallback onHistory;

  const _StoreSalesCard({
    required this.store,
    required this.expanded,
    required this.settling,
    required this.onToggle,
    required this.onSettle,
    required this.onViewDetail,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final currency = store['currency'] as String? ?? 'USD';
    final totals = store['totals'] as Map<String, dynamic>? ?? {};
    final online = totals['online'] as Map<String, dynamic>? ?? {};
    final local = totals['local'] as Map<String, dynamic>? ?? {};
    final net = totals['net'] as Map<String, dynamic>? ?? {};
    final storeOwesPlatform = (net['store_owes_platform'] ?? 0) as num;
    final platformOwesStore = (net['platform_owes_store'] ?? 0) as num;
    final orderCount = (online['order_count'] ?? 0) + (local['order_count'] ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: AppGradients.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: onToggle,
            title: Text(store['store_name']?.toString() ?? '—',
                style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w700, fontSize: 16)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Since ${_fmtDate(store['period_start'])} · $orderCount orders',
                style: const TextStyle(color: kSecondaryTextColor, fontSize: 12),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (storeOwesPlatform > 0) ...[
                  const Text('Store owes platform', style: TextStyle(color: kTertiaryTextColor, fontSize: 9)),
                  Text(_fmtMoney(storeOwesPlatform, currency),
                      style: const TextStyle(color: kAccentRed, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
                if (storeOwesPlatform > 0 && platformOwesStore > 0) const SizedBox(height: 4),
                if (platformOwesStore > 0) ...[
                  const Text('Platform owes store', style: TextStyle(color: kTertiaryTextColor, fontSize: 9)),
                  Text(_fmtMoney(platformOwesStore, currency),
                      style: const TextStyle(color: kAccentGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
                if (storeOwesPlatform == 0 && platformOwesStore == 0)
                  const Text('—', style: TextStyle(color: kTertiaryTextColor, fontSize: 13)),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: kSeparatorColor),
                  _breakdownLine('Online (delivery)', online, currency, showDriver: true),
                  const SizedBox(height: 8),
                  _breakdownLine('In-store / dine-in', local, currency, showDriver: false),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip(icon: Icons.receipt_long_rounded, label: 'Details', onTap: onViewDetail),
                _actionChip(icon: Icons.history_rounded, label: 'History', onTap: onHistory),
                settling
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _actionChip(
                        icon: Icons.check_circle_rounded,
                        label: 'Settle (Done)',
                        onTap: onSettle,
                        gradient: AppGradients.success,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownLine(String label, Map<String, dynamic> data, String currency, {required bool showDriver}) {
    final count = data['order_count'] ?? 0;
    final gross = data['gross_charged'];
    final platform = data['platform_share'];
    final store_ = data['store_share'];
    final driver = data['driver_share'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$label · $count orders',
                style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(_fmtMoney(gross, currency), style: const TextStyle(color: kPrimaryTextColor, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Platform ${_fmtMoney(platform, currency)}'
          '${showDriver ? ' · Driver ${_fmtMoney(driver, currency)}' : ''}'
          ' · Store keeps ${_fmtMoney(store_, currency)}',
          style: const TextStyle(color: kSecondaryTextColor, fontSize: 11),
        ),
      ],
    );
  }

  Widget _actionChip({required IconData icon, required String label, required VoidCallback onTap, Gradient? gradient}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null ? Colors.white.withOpacity(0.06) : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kGlassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. SETTLEMENT HISTORY (per store, permanent record)
// ═══════════════════════════════════════════════════════════════════════════

class SalesHistoryView extends StatefulWidget {
  final int storeId;
  final String storeName;
  final String currency;
  const SalesHistoryView({super.key, required this.storeId, required this.storeName, required this.currency});

  @override
  State<SalesHistoryView> createState() => _SalesHistoryViewState();
}

class _SalesHistoryViewState extends State<SalesHistoryView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _settlements = [];
  bool _undoing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiService.getRequest('/admin/sales/stores/${widget.storeId}/settlements');
      final rows = (response?['data'] as List?) ?? [];
      setState(() {
        _settlements = rows.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _undoLatest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text('Undo most recent settlement?', style: TextStyle(color: kPrimaryTextColor)),
        content: const Text(
          'This settlement record is kept (nothing is deleted), but its orders will '
          'count toward the running total again.',
          style: TextStyle(color: kSecondaryTextColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAccentRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _undoing = true);
    try {
      await ApiService.postRequest('/admin/sales/stores/${widget.storeId}/undo-settle', {});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to undo: $e')));
      }
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }

  void _openInvoice(int settlementId) {
    launchUrl(
      Uri.parse('${ApiConfig.baseUrl}/admin/sales/settlements/$settlementId/invoice'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: Text('${widget.storeName} · History', style: const TextStyle(color: kPrimaryTextColor)),
        backgroundColor: kDarkBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: kSecondaryTextColor)))
              : _settlements.isEmpty
                  ? const Center(
                      child: Text('No settled periods yet', style: TextStyle(color: kSecondaryTextColor)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _settlements.length,
                      itemBuilder: (_, i) {
                        final s = _settlements[i];
                        final isLatest = i == 0;
                        final onlineGross = double.tryParse(s['online_gross_charged']?.toString() ?? '0') ?? 0;
                        final localGross = double.tryParse(s['local_gross_charged']?.toString() ?? '0') ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: AppGradients.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kGlassBorder),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SalesDetailView(
                                settlementId: s['id'] as int,
                                storeName: widget.storeName,
                                currency: widget.currency,
                                isCurrent: false,
                              ),
                            )),
                            title: Text(
                              '${_fmtDate(s['period_start'])} → ${_fmtDate(s['period_end'])}',
                              style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Online ${_fmtMoney(onlineGross, widget.currency)} (${s['online_order_count'] ?? 0}) · '
                                'Local ${_fmtMoney(localGross, widget.currency)} (${s['local_order_count'] ?? 0})\n'
                                'Platform total: ${_fmtMoney(double.tryParse(s['total_platform_share']?.toString() ?? '0'), widget.currency)}',
                                style: const TextStyle(color: kSecondaryTextColor, fontSize: 12),
                              ),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Invoice',
                                  icon: const Icon(Icons.picture_as_pdf_rounded, color: kAccentBlue),
                                  onPressed: () => _openInvoice(s['id'] as int),
                                ),
                                if (isLatest)
                                  IconButton(
                                    tooltip: 'Undo this settlement',
                                    icon: _undoing
                                        ? const SizedBox(
                                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.undo_rounded, color: kAccentRed),
                                    onPressed: _undoing ? null : _undoLatest,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. SPLIT-SCREEN DETAIL (local | online), fully itemized + Invoice
// ═══════════════════════════════════════════════════════════════════════════

class SalesDetailView extends StatefulWidget {
  final int? storeId; // required if isCurrent
  final int? settlementId; // required if !isCurrent
  final String storeName;
  final String currency;
  final bool isCurrent;

  const SalesDetailView({
    super.key,
    this.storeId,
    this.settlementId,
    required this.storeName,
    required this.currency,
    required this.isCurrent,
  });

  @override
  State<SalesDetailView> createState() => _SalesDetailViewState();
}

class _SalesDetailViewState extends State<SalesDetailView> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _totals = {};
  List<Map<String, dynamic>> _localOrders = [];
  List<Map<String, dynamic>> _onlineOrders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final endpoint = widget.isCurrent
          ? '/admin/sales/stores/${widget.storeId}/current'
          : '/admin/sales/settlements/${widget.settlementId}';
      final response = await ApiService.getRequest(endpoint);
      final data = response?['data'] as Map<String, dynamic>? ?? {};
      final orders = ((data['orders'] as List?) ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _totals = data['totals'] as Map<String, dynamic>? ?? {};
        _localOrders = orders.where((o) => o['order_type'] == 'local').toList();
        _onlineOrders = orders.where((o) => o['order_type'] == 'online').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openInvoice() {
    final url = widget.isCurrent
        ? '${ApiConfig.baseUrl}/admin/sales/stores/${widget.storeId}/current/invoice'
        : '${ApiConfig.baseUrl}/admin/sales/settlements/${widget.settlementId}/invoice';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: Text(
          '${widget.storeName} · ${widget.isCurrent ? 'Current Period' : 'Settled Period'}',
          style: const TextStyle(color: kPrimaryTextColor),
        ),
        backgroundColor: kDarkBackground,
        foregroundColor: kPrimaryTextColor,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _openInvoice,
            icon: const Icon(Icons.picture_as_pdf_rounded, color: kAccentBlue),
            label: const Text('Invoice', style: TextStyle(color: kAccentBlue)),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: kSecondaryTextColor)))
              : Column(children: [
                  _NetSummaryBar(net: _totals['net'] as Map<String, dynamic>? ?? {}, currency: widget.currency),
                  Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth > 900;
                  final localCol = _OrdersColumn(
                    title: 'In-store / dine-in',
                    icon: Icons.table_bar_rounded,
                    orders: _localOrders,
                    totals: _totals['local'] as Map<String, dynamic>? ?? {},
                    currency: widget.currency,
                    isLocal: true,
                  );
                  final onlineCol = _OrdersColumn(
                    title: 'Online (delivery)',
                    icon: Icons.delivery_dining_rounded,
                    orders: _onlineOrders,
                    totals: _totals['online'] as Map<String, dynamic>? ?? {},
                    currency: widget.currency,
                    isLocal: false,
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: localCol),
                        const VerticalDivider(width: 1, color: kSeparatorColor),
                        Expanded(child: onlineCol),
                      ],
                    );
                  }
                  return DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: kAccentBlue,
                          unselectedLabelColor: kSecondaryTextColor,
                          indicatorColor: kAccentBlue,
                          tabs: [Tab(text: 'In-store'), Tab(text: 'Online')],
                        ),
                        Expanded(child: TabBarView(children: [localCol, onlineCol])),
                      ],
                    ),
                  );
                })),
                ]),
    );
  }
}

class _NetSummaryBar extends StatelessWidget {
  final Map<String, dynamic> net;
  final String currency;
  const _NetSummaryBar({required this.net, required this.currency});

  @override
  Widget build(BuildContext context) {
    final storeOwes = (net['store_owes_platform'] ?? 0) as num;
    final platformOwes = (net['platform_owes_store'] ?? 0) as num;
    final driverOwed = (net['platform_owes_driver'] ?? 0) as num;
    if (storeOwes == 0 && platformOwes == 0 && driverOwed == 0) return const SizedBox.shrink();

    Widget chip(String label, num value, Color color) => Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Text('$label: ${value.toStringAsFixed(2)} $currency',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: kSurfaceDark,
      child: Wrap(children: [
        if (storeOwes > 0) chip('Store owes platform', storeOwes, kAccentRed),
        if (platformOwes > 0) chip('Platform owes store', platformOwes, kAccentGreen),
        if (driverOwed > 0) chip('Platform owes driver', driverOwed, kAccentOrange),
      ]),
    );
  }
}

class _OrdersColumn extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> orders;
  final Map<String, dynamic> totals;
  final String currency;
  final bool isLocal;

  const _OrdersColumn({
    required this.title,
    required this.icon,
    required this.orders,
    required this.totals,
    required this.currency,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: kSurfaceDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: kAccentBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Gross ${_fmtMoney(totals['gross_charged'], currency)} · '
                'Platform ${_fmtMoney(totals['platform_share'], currency)}'
                '${isLocal ? '' : ' · Driver ${_fmtMoney(totals['driver_share'], currency)}'}'
                ' · Store keeps ${_fmtMoney(totals['store_share'], currency)}',
                style: const TextStyle(color: kSecondaryTextColor, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const Center(child: Text('No orders', style: TextStyle(color: kSecondaryTextColor)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _OrderCard(order: orders[i], currency: currency, isLocal: isLocal),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String currency;
  final bool isLocal;

  const _OrderCard({required this.order, required this.currency, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? 'pending';
    final cancelled = status == 'cancelled';
    final items = ((order['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cancelled ? kAccentRed.withOpacity(0.3) : kGlassBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${order['order_id']}',
                  style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              if (isLocal && order['table_name'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration:
                      BoxDecoration(color: kAccentBlue.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text('Table ${order['table_name']}',
                      style: const TextStyle(color: kAccentBlue, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              if (!isLocal && order['payment_type'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (order['payment_type'] == 'cod' ? kAccentOrange : kAccentGreen).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(order['payment_type'] == 'cod' ? 'Pay at Door' : 'Paid Online',
                      style: TextStyle(
                          color: order['payment_type'] == 'cod' ? kAccentOrange : kAccentGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_fmtDateTime(order['created_at']), style: const TextStyle(color: kTertiaryTextColor, fontSize: 11)),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (item['image_url'] != null && item['image_url'].toString().isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: Product.getFullImageUrl(item['image_url']?.toString()),
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                  width: 36, height: 36, color: kSurfaceLight, child: const Icon(Icons.fastfood, size: 16, color: kTertiaryTextColor)),
                              placeholder: (_, __) => Container(width: 36, height: 36, color: kSurfaceLight),
                            )
                          : Container(
                              width: 36,
                              height: 36,
                              color: kSurfaceLight,
                              child: const Icon(Icons.fastfood, size: 16, color: kTertiaryTextColor)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${item['quantity']}x ${item['product_name'] ?? 'Product'}',
                          style: const TextStyle(color: kPrimaryTextColor, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(_fmtMoney(item['price'], currency), style: const TextStyle(color: kSecondaryTextColor, fontSize: 12)),
                  ],
                ),
              )),
          const Divider(color: kSeparatorColor, height: 16),
          if (cancelled)
            const Text('Cancelled — excluded from totals', style: TextStyle(color: kAccentRed, fontSize: 11, fontStyle: FontStyle.italic))
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total ${_fmtMoney(order['total_price'], currency)}',
                    style: const TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w700, fontSize: 12)),
                Text(
                  'Platform ${_fmtMoney(order['platform_share'], currency)}'
                  '${isLocal ? '' : ' · Driver ${_fmtMoney(order['driver_share'], currency)}'}'
                  ' · Store ${_fmtMoney(order['store_share'], currency)}',
                  style: const TextStyle(color: kSecondaryTextColor, fontSize: 11),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
