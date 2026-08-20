// lib/widgets/product_media_gallery.dart
//
// Shared product image/video gallery — same peek-carousel motion as the
// customer Home screen's video carousel (center item large, neighbors
// peeking smaller on each side), plus explicit left/right arrows and a
// dot-count indicator, since a product photo set benefits from precise
// navigation the way a passive video reel doesn't. Used by both the
// store-owner and customer product detail screens (inline and fullscreen),
// so the two never drift apart.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ProductMediaEntry {
  final String url;
  final bool isVideo;
  const ProductMediaEntry(this.url, {this.isVideo = false});
}

class ProductMediaGallery extends StatefulWidget {
  final List<ProductMediaEntry> media;
  final bool isDark;
  final double height;
  // Tapping an image opens the fullscreen viewer at that index — omit to
  // disable (e.g. the fullscreen viewer itself doesn't re-nest).
  final ValueChanged<int>? onTapImage;

  const ProductMediaGallery({
    super.key,
    required this.media,
    required this.isDark,
    this.height = 380,
    this.onTapImage,
  });

  @override
  State<ProductMediaGallery> createState() => _ProductMediaGalleryState();
}

class _ProductMediaGalleryState extends State<ProductMediaGallery> {
  late final PageController _pageController;
  int _index = 0;
  bool _hasPrecached = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasPrecached) return;
    _hasPrecached = true;
    // Without this, each photo only started downloading the moment its
    // own page actually scrolled into view — swiping to the next one
    // showed a blank placeholder that popped into the image a beat later.
    // Precaching every photo the moment the gallery mounts means by the
    // time someone swipes, it's already sitting in Flutter's image cache.
    for (final entry in widget.media) {
      if (!entry.isVideo) {
        precacheImage(NetworkImage(entry.url), context);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.media.length - 1);
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media.isEmpty) return _placeholder();

    // A single photo/video needs no navigation chrome at all.
    if (media.length == 1) {
      return SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _mediaTile(media[0], 0, isCenter: true),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: media.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      double page = _index.toDouble();
                      if (_pageController.hasClients && _pageController.position.haveDimensions) {
                        page = _pageController.page ?? _index.toDouble();
                      }
                      final delta = (page - i).clamp(-1.0, 1.0);
                      final scale = 1 - delta.abs() * 0.14;
                      final opacity = 1 - delta.abs() * 0.45;
                      return Center(
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Transform.scale(scale: scale, child: child),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _mediaTile(media[i], i, isCenter: i == _index),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 4,
                child: _arrow(Icons.chevron_left_rounded, _index > 0 ? () => _go(-1) : null),
              ),
              Positioned(
                right: 4,
                child: _arrow(Icons.chevron_right_rounded, _index < media.length - 1 ? () => _go(1) : null),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(media.length, (i) {
            final isActive = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: (widget.isDark ? Colors.white : Colors.black).withOpacity(isActive ? 0.9 : 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _mediaTile(ProductMediaEntry entry, int i, {required bool isCenter}) {
    if (entry.isVideo) {
      return ProductVideoTile(url: entry.url, autoplay: isCenter);
    }
    return GestureDetector(
      onTap: widget.onTapImage == null ? null : () => widget.onTapImage!(i),
      child: Image.network(
        entry.url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(color: widget.isDark ? Colors.white10 : Colors.black12);
        },
        errorBuilder: (_, __, ___) => Container(
          color: widget.isDark ? Colors.white10 : Colors.black12,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return SizedBox(
      height: widget.height,
      child: Container(
        color: widget.isDark ? Colors.white10 : Colors.black12,
        child: const Center(child: Icon(Icons.image_outlined, size: 48)),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) {
    if (onTap == null) return const SizedBox.shrink();
    return _GlassArrow(icon: icon, onTap: onTap);
  }
}

class _GlassArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────── Fullscreen Viewer ───────────────
// Same navigation (arrows + dots) as the inline gallery, plus pinch-zoom
// per image. Opened by tapping an image in ProductMediaGallery above.
class ProductMediaFullscreenViewer extends StatefulWidget {
  final List<ProductMediaEntry> media;
  final int initialIndex;

  const ProductMediaFullscreenViewer({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });

  @override
  State<ProductMediaFullscreenViewer> createState() => _ProductMediaFullscreenViewerState();
}

class _ProductMediaFullscreenViewerState extends State<ProductMediaFullscreenViewer> {
  late final PageController _pageController;
  late int _index;
  bool _hasPrecached = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasPrecached) return;
    _hasPrecached = true;
    // Usually already cached by ProductMediaGallery (this viewer only
    // opens from there), so normally a no-op — kept as a safety net for
    // any other caller.
    for (final entry in widget.media) {
      if (!entry.isVideo) {
        precacheImage(NetworkImage(entry.url), context);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.media.length - 1);
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final entry = media[i];
              if (entry.isVideo) {
                return Center(child: ProductVideoTile(url: entry.url, autoplay: i == _index));
              }
              return Hero(
                tag: 'product_media_$i',
                child: InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      entry.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (media.length > 1) ...[
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _index > 0
                    ? _GlassArrow(icon: Icons.chevron_left_rounded, onTap: () => _go(-1))
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _index < media.length - 1
                    ? _GlassArrow(icon: Icons.chevron_right_rounded, onTap: () => _go(1))
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(media.length, (i) {
                  final isActive = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(isActive ? 0.9 : 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
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
          ),
        ],
      ),
    );
  }
}

// ─────────────── Video Tile ───────────────
// A product's optional video — plays with sound, loops, tap to
// pause/resume. Deliberately no scrub bar: this is a preview, not a
// full media player.
class ProductVideoTile extends StatefulWidget {
  final String url;
  final bool autoplay;
  const ProductVideoTile({super.key, required this.url, this.autoplay = true});

  @override
  State<ProductVideoTile> createState() => _ProductVideoTileState();
}

class _ProductVideoTileState extends State<ProductVideoTile> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      if (widget.autoplay) controller.play();
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant ProductVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.autoplay && !controller.value.isPlaying) {
      controller.play();
    } else if (!widget.autoplay && controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 40),
        ),
      );
    }
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        controller.value.isPlaying ? controller.pause() : controller.play();
      }),
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            if (!controller.value.isPlaying)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
          ],
        ),
      ),
    );
  }
}
