// lib/screens/stores/store_sales_view.dart
//
// Store owner's own itemized settlement view — same period window and
// underlying numbers as what the admin sees before pressing "Done", split
// into local (in-store) and online (delivery) columns:
//
//   • Local orders: you always keep everything except the platform's cut
//     (no driver is ever involved) — "You owe platform" for that slice.
//   • Online orders (paid up-front OR at the door): the cash landed with
//     the platform or the driver first, never with you, so it's reversed
//     — "Platform owes you" for that slice, regardless of which of the
//     two online payment types it was.
//
// A section is hidden entirely when there's nothing in it this period.
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../../models/product.dart';

String _fmtMoney(num? v, String currency) => '${(v ?? 0).toStringAsFixed(2)} $currency';

String _fmtDateTime(dynamic v) {
  final d = v == null ? null : DateTime.tryParse(v.toString());
  if (d == null) return '—';
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} $h:$min';
}

class StoreSalesView extends StatefulWidget {
  final String storeId;
  final String storeName;

  const StoreSalesView({super.key, required this.storeId, required this.storeName});

  @override
  State<StoreSalesView> createState() => _StoreSalesViewState();
}

class _StoreSalesViewState extends State<StoreSalesView> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _totals = {};
  DateTime? _periodStart;
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
      final response = await ApiService.getRequest('/analytics/store/${widget.storeId}/current-period');
      final data = response?['data'] as Map<String, dynamic>? ?? {};
      final orders = ((data['orders'] as List?) ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _totals = data['totals'] as Map<String, dynamic>? ?? {};
        _periodStart = DateTime.tryParse(data['period_start']?.toString() ?? '');
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
    launchUrl(
      Uri.parse('${ApiConfig.baseUrl}/analytics/store/${widget.storeId}/current-period/invoice'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF2F2F2);
    final card = isDark ? const Color(0xFF141414) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF111111);
    final sub = isDark ? Colors.white38 : Colors.black38;

    final online = _totals['online'] as Map<String, dynamic>? ?? {};
    final local = _totals['local'] as Map<String, dynamic>? ?? {};
    final net = _totals['net'] as Map<String, dynamic>? ?? {};
    final currency = _localOrders.isNotEmpty
        ? _localOrders.first['currency']?.toString()
        : _onlineOrders.isNotEmpty
            ? _onlineOrders.first['currency']?.toString()
            : 'USD';
    final hasOnline = (online['order_count'] ?? 0) > 0;
    final hasLocal = (local['order_count'] ?? 0) > 0;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: text.withOpacity(0.07), shape: BoxShape.circle),
                    child: Icon(Icons.arrow_back_ios_new, size: 14, color: text),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sales', style: TextStyle(fontFamily: 'TenorSans', fontSize: 17, fontWeight: FontWeight.w700, color: text)),
                  Text(widget.storeName, style: TextStyle(fontFamily: 'TenorSans', fontSize: 11, color: sub)),
                ])),
                GestureDetector(
                  onTap: _isLoading ? null : _openInvoice,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: kAccentBlueish.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.picture_as_pdf_rounded, size: 15, color: kAccentBlueish),
                      const SizedBox(width: 6),
                      Text('Invoice', style: TextStyle(fontFamily: 'TenorSans', fontSize: 12, fontWeight: FontWeight.w600, color: kAccentBlueish)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _load,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: text.withOpacity(0.07), shape: BoxShape.circle),
                    child: Icon(Icons.refresh, size: 17, color: text),
                  ),
                ),
              ]),
            ),
            if (_periodStart != null && !_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Since ${_fmtDateTime(_periodStart)} · current period',
                      style: TextStyle(fontFamily: 'TenorSans', fontSize: 10.5, color: sub)),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: text, strokeWidth: 1.5))
                  : _error != null
                      ? Center(child: Text('Failed to load: $_error', style: TextStyle(fontFamily: 'TenorSans', color: sub, fontSize: 13)))
                      : (!hasOnline && !hasLocal)
                          ? Center(child: Text('No sales this period yet.', style: TextStyle(fontFamily: 'TenorSans', color: sub, fontSize: 13)))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                              children: [
                                _SummaryGrid(online: online, local: local, net: net, currency: currency ?? 'USD', text: text, sub: sub, card: card),
                                const SizedBox(height: 20),
                                if (hasLocal) ...[
                                  _SectionLabel('In-Store — Total ${_fmtMoney(local['gross_charged'], currency ?? 'USD')}', sub),
                                  const SizedBox(height: 10),
                                  ..._localOrders.map((o) => _StoreOrderCard(order: o, currency: currency ?? 'USD', isLocal: true, text: text, sub: sub, card: card)),
                                  const SizedBox(height: 20),
                                ],
                                if (hasOnline) ...[
                                  _SectionLabel('Online — Total ${_fmtMoney(online['gross_charged'], currency ?? 'USD')}', sub),
                                  const SizedBox(height: 10),
                                  ..._onlineOrders.map((o) => _StoreOrderCard(order: o, currency: currency ?? 'USD', isLocal: false, text: text, sub: sub, card: card)),
                                ],
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

const kAccentBlueish = Color(0xFF3B82F6);
const kAccentGreenish = Color(0xFF16A34A);
const kAccentRedish = Color(0xFFDC2626);
const kAccentAmberish = Color(0xFFD97706);

class _SummaryGrid extends StatelessWidget {
  final Map<String, dynamic> online, local, net;
  final String currency;
  final Color text, sub, card;

  const _SummaryGrid({required this.online, required this.local, required this.net, required this.currency, required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    final grand = (online['gross_charged'] ?? 0) + (local['gross_charged'] ?? 0);
    final owePlatform = (net['store_owes_platform'] ?? 0) as num;
    final platformOwesYou = (net['platform_owes_store'] ?? 0) as num;
    final owedToDriver = (net['platform_owes_driver'] ?? 0) as num;

    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Border.all(color: text.withOpacity(0.06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total this period', style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub)),
          const SizedBox(height: 4),
          Text(_fmtMoney(grand, currency), style: TextStyle(fontFamily: 'TenorSans', fontSize: 24, fontWeight: FontWeight.w800, color: text)),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        if (owePlatform > 0)
          Expanded(child: _NetTile(label: 'You owe platform', value: _fmtMoney(owePlatform, currency), color: kAccentRedish, icon: Icons.arrow_upward_rounded)),
        if (owePlatform > 0 && platformOwesYou > 0) const SizedBox(width: 10),
        if (platformOwesYou > 0)
          Expanded(child: _NetTile(label: 'Platform owes you', value: _fmtMoney(platformOwesYou, currency), color: kAccentGreenish, icon: Icons.arrow_downward_rounded)),
      ]),
      if (owedToDriver > 0) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _NetTile(label: 'Platform owes driver (info)', value: _fmtMoney(owedToDriver, currency), color: kAccentAmberish, icon: Icons.delivery_dining_rounded)),
        ]),
      ],
    ]);
  }
}

class _NetTile extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _NetTile({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(child: Text(label, style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: color, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontFamily: 'TenorSans', fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color sub;
  const _SectionLabel(this.text, this.sub);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: TextStyle(fontFamily: 'TenorSans', fontSize: 11, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1.2));
  }
}

class _StoreOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String currency;
  final bool isLocal;
  final Color text, sub, card;

  const _StoreOrderCard({required this.order, required this.currency, required this.isLocal, required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? 'pending';
    final cancelled = status == 'cancelled';
    final items = ((order['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final paymentType = order['payment_type']?.toString();

    Color badgeColor;
    String badgeLabel;
    if (isLocal) {
      badgeColor = const Color(0xFF0891B2);
      badgeLabel = order['table_name'] != null ? 'Table ${order['table_name']}' : 'In-Store';
    } else if (paymentType == 'cod') {
      badgeColor = kAccentAmberish;
      badgeLabel = 'Pay at Door';
    } else {
      badgeColor = kAccentGreenish;
      badgeLabel = 'Paid Online';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cancelled ? kAccentRedish.withOpacity(0.3) : text.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${order['order_id']}', style: TextStyle(fontFamily: 'TenorSans', fontSize: 12, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(badgeLabel, style: TextStyle(fontFamily: 'TenorSans', fontSize: 9.5, fontWeight: FontWeight.w600, color: badgeColor)),
          ),
          const Spacer(),
          if (cancelled)
            Text('CANCELLED', style: TextStyle(fontFamily: 'TenorSans', fontSize: 9.5, fontWeight: FontWeight.w700, color: kAccentRedish))
          else
            Text(_fmtDateTime(order['created_at']), style: TextStyle(fontFamily: 'TenorSans', fontSize: 9.5, color: sub)),
        ]),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (item['image_url'] != null && item['image_url'].toString().isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: Product.getFullImageUrl(item['image_url']?.toString()),
                          width: 34, height: 34, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(width: 34, height: 34, color: text.withOpacity(0.05)),
                          placeholder: (_, __) => Container(width: 34, height: 34, color: text.withOpacity(0.05)),
                        )
                      : Container(width: 34, height: 34, color: text.withOpacity(0.05)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('${item['quantity']}x ${item['product_name'] ?? 'Product'}',
                    style: TextStyle(fontFamily: 'TenorSans', fontSize: 12, color: text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(_fmtMoney(item['price'], currency), style: TextStyle(fontFamily: 'TenorSans', fontSize: 11.5, color: sub)),
              ]),
            )),
        Divider(color: text.withOpacity(0.06), height: 16),
        if (cancelled)
          Text('Excluded from totals — no charge occurred', style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, fontStyle: FontStyle.italic, color: kAccentRedish))
        else
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total ${_fmtMoney(order['total_price'], currency)}', style: TextStyle(fontFamily: 'TenorSans', fontSize: 11.5, fontWeight: FontWeight.w700, color: text)),
            Text(
              'Platform ${_fmtMoney(order['platform_share'], currency)}'
              '${isLocal ? '' : ' · Driver ${_fmtMoney(order['driver_share'], currency)}'}'
              ' · You keep ${_fmtMoney(order['store_share'], currency)}',
              style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub),
            ),
          ]),
      ]),
    );
  }
}
