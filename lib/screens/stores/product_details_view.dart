import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/store_admin_widgets.dart';
import '../../models/currency.dart';

// دالة للحصول على رمز العملة الصحيح
String getCurrencySymbol(String? currencyCode) {
  if (currencyCode == null || currencyCode.isEmpty) return '';
  final currency = Currency.fromCode(currencyCode);
  return currency?.symbol ?? '';
}

class ProductDetailsView extends StatefulWidget {
  final ProductS product;
  const ProductDetailsView({super.key, required this.product});

  @override
  State<ProductDetailsView> createState() => _ProductDetailsViewState();
}

class _ProductDetailsViewState extends State<ProductDetailsView>
    with TickerProviderStateMixin {
  late final List<String> _media;
  late final AnimationController _priceCtrl;
  late final Animation<double> _priceAnim;
  final PageController _pageController = PageController();
  int _index = 0;
  Offset _hoverOffset = Offset.zero;

  bool get isDesktop => MediaQuery.of(context).size.width > 900;

  @override
  void initState() {
    super.initState();
    _media = [widget.product.imageUrl];
    _priceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _priceAnim = CurvedAnimation(parent: _priceCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction(onInvoke: (_) => Navigator.pop(context)),
        },
        child: Scaffold(
          backgroundColor: dark ? const Color(0xFF0E0E10) : const Color(0xFFF5F5F7),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ─────────────── IMAGE HEADER ───────────────
              SliverAppBar(
                expandedHeight: 560,
                pinned: true,
                backgroundColor: dark ? const Color(0xFF0E0E10) : Colors.white,
                leading: _glassBtn(
                  Icons.arrow_back_ios_new,
                  () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: _gallery(dark),
                ),
              ),

              // ─────────────── CONTENT ───────────────
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 140),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(42),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _titleRow(dark),
                      const SizedBox(height: 30),
                      _section('Description'),
                      const SizedBox(height: 12),
                      Text(
                        widget.product.description,
                        style: TextStyle(
                          height: 1.7,
                          fontSize: 16,
                          color: dark ? Colors.grey.shade400 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _section('Details'),
                      const SizedBox(height: 16),
                      _buildDetailsSection(dark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── Details Section - Clean & Organized ───────────────
  Widget _buildDetailsSection(bool dark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        //  Glass effect background
        color: dark 
            ? Colors.white.withOpacity(0.05) 
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark 
              ? Colors.white.withOpacity(0.1) 
              : Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _detailRow(
            icon: Icons.store_outlined,
            label: 'Store',
            value: widget.product.storeName ?? '—',
            dark: dark,
          ),
          _divider(dark),
          _detailRow(
            icon: Icons.email_outlined,
            label: 'Contact',
            value: widget.product.storeOwnerEmail ?? '—',
            dark: dark,
          ),
          _divider(dark),
          _detailRow(
            icon: Icons.tag,
            label: 'Product ID',
            value: (widget.product.id ?? '').isNotEmpty
                ? '${widget.product.id.substring(0, min(8, widget.product.id.length))}'
                : '—',
            dark: dark,
          ),
          _divider(dark),
          _detailRow(
            icon: Icons.inventory_2_outlined,
            label: 'In Stock',
            value: widget.product.stock?.toString() ?? '—',
            dark: dark,
            valueColor: (widget.product.stock ?? 0) > 10 
                ? Colors.green 
                : (widget.product.stock ?? 0) > 0 
                    ? Colors.orange 
                    : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool dark,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Icon with glass background
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dark 
                  ? Colors.white.withOpacity(0.08) 
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: dark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(width: 16),
          // Label
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: dark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          // Value
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: valueColor ?? (dark ? Colors.white : Colors.black87),
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool dark) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
    );
  }

  // ─────────────── Gallery ───────────────
  Widget _gallery(bool dark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        //  Dynamic blur background
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: CachedNetworkImage(
            imageUrl: _media[_index],
            fit: BoxFit.cover,
          ),
        ),
        PageView.builder(
          controller: _pageController,
          itemCount: _media.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            return MouseRegion(
              onHover: (e) {
                if (!isDesktop) return;
                final size = context.size!;
                setState(() {
                  _hoverOffset = Offset(
                    (e.localPosition.dx - size.width / 2) * .015,
                    (e.localPosition.dy - size.height / 2) * .015,
                  );
                });
              },
              onExit: (_) => setState(() => _hoverOffset = Offset.zero),
              child: GestureDetector(
                onTap: () => _openFullscreen(i),
                child: Center(
                  child: Transform.translate(
                    offset: _hoverOffset,
                    child: Hero(
                      tag: 'media_$i',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: CachedNetworkImage(
                          imageUrl: _media[i],
                          fit: BoxFit.cover,
                          width: isDesktop ? 420 : 300,
                          height: isDesktop ? 520 : 380,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ─────────────── UI ───────────────
  Widget _glassBtn(IconData icon, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface.withOpacity(0.06)
                : Colors.black.withOpacity(0.06),
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  Widget _titleRow(bool dark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product Name
        Expanded(
          child: Text(
            widget.product.name,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Price & Stock Badge
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Price
            ScaleTransition(
              scale: _priceAnim,
              child: Builder(builder: (context) {
                // product.price may be a String or a number; normalize to double safely
                final dynamic raw = widget.product.price;
                final double priceVal = (raw is num)
                    ? (raw as num).toDouble()
                    : double.tryParse(raw?.toString() ?? '') ?? 0.0;
                return Text(
                  '${getCurrencySymbol(widget.product.currency)}${priceVal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            //  Apple-style Glass Stock Badge
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.black.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: dark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: dark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.product.stock ?? 0} in stock',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      );

  // ─────────────── Fullscreen ───────────────
  void _openFullscreen(int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenGallery(media: _media, index: index),
      ),
    );
  }
}

// ─────────────── Fullscreen Viewer ───────────────
class _FullscreenGallery extends StatelessWidget {
  final List<String> media;
  final int index;

  const _FullscreenGallery({required this.media, required this.index});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: PageController(initialPage: index),
            itemCount: media.length,
            itemBuilder: (_, i) {
              return Hero(
                tag: 'media_$i',
                child: InteractiveViewer(
                  child: CachedNetworkImage(
                    imageUrl: media[i],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}