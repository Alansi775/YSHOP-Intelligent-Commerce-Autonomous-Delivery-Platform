import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// Admin-only financial breakdown per store: online (delivery) vs in-store
/// (dine-in/POS) revenue, in each store's own currency, with what's owed to
/// the platform/drivers vs what the store keeps — so the admin can settle
/// up with each restaurant/store without mixing the two order types.
class StoreFinanceView extends StatefulWidget {
  const StoreFinanceView({super.key});

  @override
  State<StoreFinanceView> createState() => _StoreFinanceViewState();
}

class _StoreFinanceViewState extends State<StoreFinanceView> {
  String _period = 'month';
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _stores = [];
  final Set<int> _expandedStoreIds = {};

  static const _periods = [
    ('today', 'Today'),
    ('week', 'This Week'),
    ('month', 'This Month'),
    ('year', 'This Year'),
  ];

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
      final response = await ApiService.getRequest('/analytics/admin/stores-summary?period=$_period');
      final stores = (response?['data']?['stores'] as List?) ?? [];
      setState(() {
        _stores = stores.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _fmt(num? v, String currency) => '${(v ?? 0).toStringAsFixed(2)} $currency';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : Colors.black;
    final sub = isDark ? Colors.white60 : Colors.black54;
    final card = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('Store Finances'),
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7),
        foregroundColor: text,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _periods.map((p) {
                  final selected = _period == p.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.$2),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _period = p.$1);
                        _load();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error', style: TextStyle(color: sub)))
                    : _stores.isEmpty
                        ? Center(child: Text('No orders in this period', style: TextStyle(color: sub)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _stores.length,
                            itemBuilder: (_, i) => _StoreCard(
                              store: _stores[i],
                              expanded: _expandedStoreIds.contains(_stores[i]['store_id'] as int),
                              onToggle: () => setState(() {
                                final id = _stores[i]['store_id'] as int;
                                if (!_expandedStoreIds.add(id)) _expandedStoreIds.remove(id);
                              }),
                              text: text,
                              sub: sub,
                              card: card,
                              fmt: _fmt,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final bool expanded;
  final VoidCallback onToggle;
  final Color text, sub, card;
  final String Function(num?, String) fmt;

  const _StoreCard({
    required this.store,
    required this.expanded,
    required this.onToggle,
    required this.text,
    required this.sub,
    required this.card,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final currency = store['currency'] as String? ?? 'USD';
    final online = store['online'] as Map<String, dynamic>? ?? {};
    final local = store['local'] as Map<String, dynamic>? ?? {};
    final totals = store['totals'] as Map<String, dynamic>? ?? {};
    final byTable = (local['by_table'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final storeType = (store['store_type'] as String? ?? '').toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(store['store_name']?.toString() ?? '—',
                style: TextStyle(color: text, fontWeight: FontWeight.w700)),
            subtitle: Text(
              '$storeType · ${totals['order_count'] ?? 0} orders · You take: ${fmt(totals['owed_to_platform'], currency)}',
              style: TextStyle(color: sub, fontSize: 12),
            ),
            trailing: Text(
              fmt(totals['gross_charged'], currency),
              style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onTap: onToggle,
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  _line('Online (delivery)', '${online['order_count'] ?? 0} orders', fmt(online['gross_charged'], currency), text, sub),
                  _subline('  → platform', fmt(online['store_owes_platform'], currency), sub),
                  _subline('  → driver', fmt(online['store_owes_driver'], currency), sub),
                  _subline('  → store keeps', fmt(online['store_keeps'], currency), sub),
                  const SizedBox(height: 10),
                  _line('In-store / dine-in', '${local['order_count'] ?? 0} orders', fmt(local['gross_charged'], currency), text, sub),
                  _subline('  → platform', fmt(local['store_owes_platform'], currency), sub),
                  _subline('  → store keeps (no driver)', fmt(local['store_keeps'], currency), sub),
                  if (byTable.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('By table', style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 4),
                    ...byTable.map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${t['table_name']} (${t['order_count']} orders)',
                                  style: TextStyle(color: sub, fontSize: 12)),
                              Text(fmt(t['gross_charged'], currency), style: TextStyle(color: sub, fontSize: 12)),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, String meta, String amount, Color text, Color sub) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(meta, style: TextStyle(color: sub, fontSize: 11)),
              ],
            ),
            Text(amount, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  Widget _subline(String label, String amount, Color sub) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: sub, fontSize: 12)),
            Text(amount, style: TextStyle(color: sub, fontSize: 12)),
          ],
        ),
      );
}
