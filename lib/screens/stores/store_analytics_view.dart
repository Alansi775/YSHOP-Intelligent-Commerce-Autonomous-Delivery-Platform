import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../models/product.dart';

class StoreAnalyticsView extends StatefulWidget {
  final String storeId;
  final String storeName;

  const StoreAnalyticsView({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<StoreAnalyticsView> createState() => _StoreAnalyticsViewState();
}

class _StoreAnalyticsViewState extends State<StoreAnalyticsView> {
  String _period = 'month';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  static const _periods = [
    ('hour', 'Last Hour'),
    ('today', 'Today'),
    ('week', '7 Days'),
    ('month', '30 Days'),
    ('year', 'This Year'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await AnalyticsService.getStoreAnalytics(widget.storeId, period: _period);
    if (!mounted) return;
    if (result == null) {
      setState(() { _loading = false; _error = 'Failed to load analytics.'; });
    } else {
      setState(() { _loading = false; _data = result; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg   = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF2F2F2);
    final card = isDark ? const Color(0xFF141414) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF111111);
    final sub  = isDark ? Colors.white38 : Colors.black38;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(storeName: widget.storeName, onBack: () => Navigator.pop(context), onRefresh: _load, text: text, sub: sub),
            _PeriodBar(selected: _period, onSelect: (p) { setState(() => _period = p); _load(); }, text: text, sub: sub),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: text, strokeWidth: 1.5))
                  : _error != null
                      ? _ErrorView(onRetry: _load, sub: sub)
                      : _Content(data: _data!, isDark: isDark, card: card, text: text, sub: sub),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String storeName;
  final VoidCallback onBack, onRefresh;
  final Color text, sub;
  const _Header({required this.storeName, required this.onBack, required this.onRefresh, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(children: [
        _CircleBtn(icon: Icons.arrow_back_ios_new, size: 14, onTap: onBack, color: text),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Analytics', style: TextStyle(fontFamily: 'TenorSans', fontSize: 17, fontWeight: FontWeight.w700, color: text)),
          Text(storeName, style: TextStyle(fontFamily: 'TenorSans', fontSize: 11, color: sub)),
        ])),
        _CircleBtn(icon: Icons.refresh, size: 17, onTap: onRefresh, color: text),
      ]),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;
  const _CircleBtn({required this.icon, required this.size, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: color.withOpacity(0.07), shape: BoxShape.circle),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}

// ─── Period Bar ──────────────────────────────────────────────────────────────

class _PeriodBar extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  final Color text, sub;
  const _PeriodBar({required this.selected, required this.onSelect, required this.text, required this.sub});

  static const _periods = [
    ('hour', 'Last Hour'), ('today', 'Today'), ('week', '7 Days'), ('month', '30 Days'), ('year', 'This Year'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _periods.map((p) {
          final sel = selected == p.$1;
          return GestureDetector(
            onTap: () => onSelect(p.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? text : text.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(p.$2, style: TextStyle(
                fontFamily: 'TenorSans', fontSize: 12, fontWeight: FontWeight.w600,
                color: sel ? (text == Colors.white ? Colors.black : Colors.white) : sub,
              )),
            ),
          );
        }).toList()),
      ),
    );
  }
}

// ─── Error ───────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final Color sub;
  const _ErrorView({required this.onRetry, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bar_chart_outlined, size: 44, color: sub.withOpacity(0.4)),
      const SizedBox(height: 10),
      Text('Failed to load analytics', style: TextStyle(fontFamily: 'TenorSans', color: sub, fontSize: 13)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(color: sub.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text('Retry', style: TextStyle(fontFamily: 'TenorSans', color: sub, fontSize: 12)),
        ),
      ),
    ]));
  }
}

// ─── Main Content ─────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  final Color card, text, sub;
  const _Content({required this.data, required this.isDark, required this.card, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    final summary     = data['summary']            as Map<String, dynamic>? ?? {};
    final topProducts = (data['top_products']      as List?) ?? [];
    final returned    = (data['returned_products'] as List?) ?? [];
    final trend       = (data['revenue_trend']     as List?) ?? [];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: _buildList(topProducts, returned, trend, summary, card, text, sub),
      ),
    );
  }

  Widget _buildList(List topProducts, List returned, List trend, Map<String, dynamic> summary, Color card, Color text, Color sub) {
    final currency = topProducts.isNotEmpty
        ? (topProducts.first as Map<String, dynamic>)['currency'] as String?
        : returned.isNotEmpty
            ? (returned.first as Map<String, dynamic>)['currency'] as String?
            : summary['currency'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _SummaryGrid(summary: summary, text: text, sub: sub, card: card),
        if (trend.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ChartCard(trend: trend, text: text, sub: sub, card: card, currency: currency),
        ],
        if (topProducts.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Label('Top Products', sub),
          const SizedBox(height: 10),
          ...topProducts.asMap().entries.map((e) => _ProductRow(
            rank: e.key + 1, item: e.value as Map<String, dynamic>,
            text: text, sub: sub, card: card,
          )),
        ],
        if (returned.isNotEmpty) ...[
          const SizedBox(height: 22),
          _Label('Return Analysis', sub),
          const SizedBox(height: 10),
          ...returned.map((r) => _ReturnRow(item: r as Map<String, dynamic>, text: text, sub: sub, card: card)),
        ],
        if (topProducts.isEmpty && returned.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(child: Text('No data for this period.',
              style: TextStyle(fontFamily: 'TenorSans', color: sub, fontSize: 13))),
          ),
      ],
    );
  }
}

// ─── Summary ─────────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final Map<String, dynamic> summary;
  final Color text, sub, card;
  const _SummaryGrid({required this.summary, required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    final currency  = summary['currency']          as String?;
    final revenue   = (summary['total_revenue']    as num?)?.toDouble() ?? 0;
    final returned  = (summary['returns_deducted'] as num?)?.toDouble() ?? 0;
    final orders    = (summary['total_orders']     as num?)?.toInt() ?? 0;
    final items     = (summary['total_items_sold'] as num?)?.toInt() ?? 0;
    final cancelled = (summary['cancelled_orders'] as num?)?.toInt() ?? 0;
    final grossOnline = (summary['gross_revenue_online'] as num?)?.toDouble() ?? 0;
    final grossLocal  = (summary['gross_revenue_local']  as num?)?.toDouble() ?? 0;

    return Column(children: [
      Row(children: [
        Expanded(child: _StatTile(
          _fmtAmount(revenue, currency), 'Your Earnings',
          Icons.payments_outlined, const Color(0xFF34D399), text, sub, card,
          sub2: returned > 0 ? '↩ - ${_fmtAmount(returned, currency)} deducted' : null,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatTile('$orders', 'Orders', Icons.receipt_long_outlined, const Color(0xFF60A5FA), text, sub, card)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile('$items', 'Items Sold', Icons.shopping_bag_outlined, const Color(0xFFA78BFA), text, sub, card)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile('$cancelled', 'Cancelled', Icons.cancel_outlined, const Color(0xFFF87171), text, sub, card)),
      ]),
      // Online (delivery) vs in-store (dine-in/POS) split — different
      // commission rates apply, so this needs to be visible: in-store
      // sales never have a driver cut taken out.
      if (grossOnline > 0 || grossLocal > 0) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatTile(
            _fmtAmount(grossOnline, currency), 'Online (delivery fee applies)',
            Icons.delivery_dining_outlined, const Color(0xFFFBBF24), text, sub, card,
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatTile(
            _fmtAmount(grossLocal, currency), 'In-Store (no delivery fee)',
            Icons.storefront_outlined, const Color(0xFF38BDF8), text, sub, card,
          )),
        ]),
      ],
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  final String? sub2;
  final IconData icon;
  final Color accent, text, sub, card;
  const _StatTile(this.value, this.label, this.icon, this.accent, this.text, this.sub, this.card, {this.sub2});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: sub2 != null ? 78 : 70,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: text.withOpacity(0.06)),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontFamily: 'TenorSans', fontSize: 15, fontWeight: FontWeight.w700, color: text)),
            Text(label,  style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub)),
            if (sub2 != null) Text(sub2!, style: TextStyle(fontFamily: 'TenorSans', fontSize: 9, color: Colors.red.shade400), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),
      ]),
    );
  }
}

// ─── Chart ────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final List trend;
  final Color text, sub, card;
  final String? currency;
  const _ChartCard({required this.trend, required this.text, required this.sub, required this.card, this.currency});

  @override
  Widget build(BuildContext context) {
    final rawValues = trend.map((r) => (r['revenue'] as num?)?.toDouble() ?? 0.0).toList();
    final rawDates  = trend.map((r) => r['date']?.toString() ?? '').toList();
    // painter needs ≥2 points; pad a single point to draw a flat line
    final values = rawValues.length == 1 ? [rawValues[0], rawValues[0]] : rawValues;
    final dates  = rawDates.length  == 1 ? [rawDates[0],  rawDates[0]]  : rawDates;
    final maxVal = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label('Revenue Trend', sub),
      const SizedBox(height: 10),
      Container(
        height: 150,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: text.withOpacity(0.06)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(children: [
          Expanded(
            child: CustomPaint(
              painter: _AreaPainter(values: values),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(dates.isNotEmpty ? dates.first : '', style: TextStyle(fontFamily: 'TenorSans', fontSize: 9, color: sub)),
            if (maxVal > 0) Text(_fmtAmount(maxVal, currency), style: const TextStyle(fontFamily: 'TenorSans', fontSize: 9, color: Color(0xFF60A5FA))),
            Text(dates.isNotEmpty ? dates.last  : '', style: TextStyle(fontFamily: 'TenorSans', fontSize: 9, color: sub)),
          ]),
        ]),
      ),
    ]);
  }
}

class _AreaPainter extends CustomPainter {
  final List<double> values;
  static const _lineColor = Color(0xFF60A5FA);

  const _AreaPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = maxV == minV ? maxV : maxV - minV;
    final vPad = size.height * 0.1;

    Offset pt(int i) => Offset(
      i / (values.length - 1) * size.width,
      vPad + (size.height - vPad * 2) * (1 - (values[i] - minV) / range),
    );

    final pts = List.generate(values.length, pt);

    // Grid lines
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.04)..strokeWidth = 0.8;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), gridPaint);
    }

    // Fill
    final fill = Path()..moveTo(pts.first.dx, size.height)..lineTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cx = (pts[i - 1].dx + pts[i].dx) / 2;
      fill.cubicTo(cx, pts[i - 1].dy, cx, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    fill.lineTo(pts.last.dx, size.height);
    fill.close();

    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_lineColor.withOpacity(0.3), _lineColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill);

    // Line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cx = (pts[i - 1].dx + pts[i].dx) / 2;
      line.cubicTo(cx, pts[i - 1].dy, cx, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(line, Paint()
      ..color = _lineColor..strokeWidth = 2.0
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);

    // Dots (only few points)
    if (values.length <= 16) {
      for (final p in pts) {
        canvas.drawCircle(p, 3.0, Paint()..color = _lineColor);
        canvas.drawCircle(p, 3.0, Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) => old.values != values;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtDate(String? date) {
  if (date == null || date.isEmpty) return '';
  try {
    final d = DateTime.parse(date);
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  } catch (_) {
    return date.length >= 10 ? date.substring(5, 10) : date;
  }
}

String _fmtAmount(double v, String? currency) {
  final c = currency ?? 'USD';
  final n = v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toStringAsFixed(2);
  switch (c) {
    case 'USD': return '\$$n';
    case 'SAR': return '$n ر.س';
    case 'AED': return '$n د.إ';
    case 'KWD': return '$n د.ك';
    case 'QAR': return '$n ر.ق';
    case 'BHD': return '$n د.ب';
    case 'OMR': return '$n ر.ع';
    default:    return '$n $c';
  }
}

// ─── Product Row ─────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> item;
  final Color text, sub, card;
  const _ProductRow({required this.rank, required this.item, required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    final sold        = (item['total_sold']    as num?)?.toInt() ?? 0;
    final revenue     = (item['revenue']       as num?)?.toDouble() ?? 0;
    final returnCount = (item['return_count']  as num?)?.toInt() ?? 0;
    final currency    = item['currency']       as String?;
    final date        = _fmtDate(item['last_ordered_at'] as String?);
    final imageUrl    = Product.getFullImageUrl(item['image_url'] as String? ?? '');
    final returnPct   = sold > 0 ? '${(returnCount / sold * 100).toStringAsFixed(0)}%' : '0%';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: text.withOpacity(0.06)),
      ),
      child: Row(children: [
        SizedBox(width: 22, child: Text('#$rank', style: TextStyle(
          fontFamily: 'TenorSans', fontSize: 11, fontWeight: FontWeight.w700,
          color: rank <= 3 ? Colors.amber.shade600 : sub))),
        _Thumb(url: imageUrl, sub: sub, text: text),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['product_name']?.toString() ?? '',
            style: TextStyle(fontFamily: 'TenorSans', fontSize: 12, fontWeight: FontWeight.w600, color: text),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            Text('$sold sold · ${_fmtAmount(revenue, currency)}',
              style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub)),
            if (date.isNotEmpty) ...[
              Text('  ·  ', style: TextStyle(color: sub, fontSize: 10)),
              Text(date, style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub.withOpacity(0.6))),
            ],
          ]),
        ])),
        if (returnCount > 0) ...[
          const SizedBox(width: 8),
          _Badge('↩ $returnPct', Colors.red.shade400),
        ],
      ]),
    );
  }
}

// ─── Return Row ──────────────────────────────────────────────────────────────

class _ReturnRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color text, sub, card;
  const _ReturnRow({required this.item, required this.text, required this.sub, required this.card});

  @override
  Widget build(BuildContext context) {
    final count    = (item['return_count']   as num?)?.toInt() ?? 0;
    final currency = item['currency']        as String?;
    final date     = _fmtDate(item['last_returned_at'] as String?);
    final reasons  = (item['reasons']        as List?) ?? [];
    final imageUrl = Product.getFullImageUrl(item['image_url'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade400.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Thumb(url: imageUrl, sub: sub, text: text),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(item['product_name']?.toString() ?? '',
              style: TextStyle(fontFamily: 'TenorSans', fontSize: 12, fontWeight: FontWeight.w600, color: text),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            _Badge('$count returns', Colors.red.shade400),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            if (date.isNotEmpty)
              Text(date, style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub.withOpacity(0.6))),
            if (date.isNotEmpty && currency != null)
              Text('  ·  ', style: TextStyle(color: sub, fontSize: 10)),
            if (currency != null)
              Text(currency, style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub.withOpacity(0.6))),
          ]),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...reasons.take(2).map((r) => Text('· ${r.toString()}',
              style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, color: sub),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ])),
      ]),
    );
  }
}

// ─── Shared ──────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final String url;
  final Color sub, text;
  const _Thumb({required this.url, required this.sub, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: text.withOpacity(0.05),
        image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      child: url.isEmpty ? Icon(Icons.image_not_supported_outlined, size: 15, color: sub) : null,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontFamily: 'TenorSans', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final Color sub;
  const _Label(this.text, this.sub);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: TextStyle(
      fontFamily: 'TenorSans', fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1.5));
  }
}
