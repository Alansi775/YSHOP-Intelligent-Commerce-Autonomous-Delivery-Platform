// lib/widgets/liquid_orb_visualizer.dart
//
// 🖤 FERROFLUID ORB — Magnetic liquid visualization
//
// A white/clear glass sphere containing a black ferrofluid blob.
// The blob is alive — it morphs, extends tendrils, and scatters
// droplets in response to audio input.
//
// Palette: Black ferrofluid, white/clear sphere, minimal color.
// Inspired by real ferrofluid (Fe3O4 + oil in water).

import 'package:flutter/material.dart';
import 'dart:math' as math;

enum VoicePhase { idle, listening, thinking, speaking }

class LiquidOrbVisualizer extends StatefulWidget {
  final double size;
  final VoicePhase phase;
  final double audioLevel;

  const LiquidOrbVisualizer({
    Key? key,
    this.size = 200,
    this.phase = VoicePhase.idle,
    this.audioLevel = 0.0,
  }) : super(key: key);

  @override
  State<LiquidOrbVisualizer> createState() => _LiquidOrbVisualizerState();
}

class _LiquidOrbVisualizerState extends State<LiquidOrbVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _slowDrift;
  late AnimationController _morph;
  late AnimationController _breathe;

  double _smoothAudio = 0.0;

  @override
  void initState() {
    super.initState();
    _slowDrift = AnimationController(
      vsync: this, duration: const Duration(seconds: 25),
    )..repeat();
    _morph = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat();
    _breathe = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _slowDrift.dispose();
    _morph.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_slowDrift, _morph, _breathe]),
        builder: (_, __) {
          _smoothAudio = _smoothAudio * 0.65 + widget.audioLevel * 0.35;
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _FerrofluidPainter(
              drift: _slowDrift.value,
              morph: _morph.value,
              breathe: _breathe.value,
              phase: widget.phase,
              audio: _smoothAudio,
            ),
          );
        },
      ),
    );
  }
}

class _FerrofluidPainter extends CustomPainter {
  final double drift;
  final double morph;
  final double breathe;
  final VoicePhase phase;
  final double audio;

  static const _ferro = Color(0xFF0A0A0A);     // pure black ferro
  static const _ferroEdge = Color(0xFF1A1A2E);  // slight blue-black edge
  static const _sphereBg = Color(0xFFF0F0F5);   // off-white sphere
  static const _sphereInner = Color(0xFFE0E0E8); // slightly darker center

  _FerrofluidPainter({
    required this.drift,
    required this.morph,
    required this.breathe,
    required this.phase,
    required this.audio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final isActive = phase == VoicePhase.listening || phase == VoicePhase.speaking;
    final energy = isActive ? 0.3 + audio * 0.7 : 0.05 + breathe * 0.08;

    // ── Clip to sphere ──
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // ══════════════════════════════════════
    // 1. GLASS SPHERE BACKGROUND (white)
    // ══════════════════════════════════════
    // Radial gradient for depth
    canvas.drawCircle(c, r, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 1.0,
        colors: const [
          Color(0xFFFAFAFC),
          _sphereBg,
          _sphereInner,
          Color(0xFFD0D0D8),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)));

    // ══════════════════════════════════════
    // 2. MAIN FERROFLUID BLOB
    // ══════════════════════════════════════
    _drawMainBlob(canvas, c, r, energy, isActive);

    // ══════════════════════════════════════
    // 3. SCATTERED DROPLETS
    // ══════════════════════════════════════
    _drawDroplets(canvas, c, r, energy, isActive);

    // ══════════════════════════════════════
    // 4. TENDRILS (when active)
    // ══════════════════════════════════════
    if (isActive && energy > 0.2) {
      _drawTendrils(canvas, c, r, energy);
    }

    // ══════════════════════════════════════
    // 5. GLASS REFLECTIONS (on top of everything)
    // ══════════════════════════════════════
    _drawGlassOverlay(canvas, c, r);

    canvas.restore();

    // ══════════════════════════════════════
    // 6. RIM / EDGE (outside clip)
    // ══════════════════════════════════════
    _drawRim(canvas, c, r);
  }

  // ─────────────────────────────────────────
  // MAIN BLOB — organic ferrofluid mass
  // ─────────────────────────────────────────
  void _drawMainBlob(Canvas canvas, Offset c, double r, double energy, bool isActive) {
    final path = Path();
    final blobR = r * (0.22 + energy * 0.12);
    final cx = c.dx + math.sin(drift * math.pi * 2) * r * 0.04;
    final cy = c.dy + math.cos(drift * math.pi * 1.5) * r * 0.05 + r * 0.03;

    // Generate organic shape with many points
    final points = 60;
    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * math.pi * 2;

      // Base radius with organic distortion
      double pr = blobR;

      // Slow organic morph (always)
      pr += math.sin(angle * 3 + morph * math.pi * 2) * blobR * 0.15;
      pr += math.cos(angle * 5 + drift * math.pi * 4) * blobR * 0.08;

      // Audio-reactive spikes
      if (isActive && audio > 0.15) {
        final spikeFreq = 7.0 + audio * 5;
        final spikeAmp = audio * blobR * 0.4;
        pr += math.sin(angle * spikeFreq + morph * math.pi * 6) * spikeAmp;
        // Occasional big spikes
        pr += math.max(0, math.sin(angle * 3 + morph * math.pi * 8) - 0.5) *
            audio * blobR * 0.6;
      }

      // Breathing (when idle)
      if (!isActive) {
        pr += math.sin(angle * 2 + breathe * math.pi * 2) * blobR * 0.06;
      }

      pr = pr.clamp(blobR * 0.5, blobR * 2.0);

      final px = cx + math.cos(angle) * pr;
      final py = cy + math.sin(angle) * pr;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    // Main blob fill — very dark
    canvas.drawPath(path, Paint()
      ..color = _ferro
      ..style = PaintingStyle.fill);

    // Subtle glossy highlight on blob
    canvas.drawPath(path, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 1.5,
        colors: [
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: blobR))
      ..style = PaintingStyle.fill);

    // Edge highlight (very subtle blue-black sheen)
    canvas.drawPath(path, Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.2, 0.3),
        radius: 1.0,
        colors: [
          _ferroEdge.withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: blobR))
      ..style = PaintingStyle.fill);
  }

  // ─────────────────────────────────────────
  // DROPLETS — scattered small blobs
  // ─────────────────────────────────────────
  void _drawDroplets(Canvas canvas, Offset c, double r, double energy, bool isActive) {
    final count = isActive ? 12 + (audio * 10).round() : 4;
    final rng = math.Random(42); // fixed seed for consistency

    for (int i = 0; i < count; i++) {
      final seed = i * 1.618;
      final angle = (morph + seed * 0.1) * math.pi * 2;
      final driftAngle = drift * math.pi * 2 + seed;

      // Distance from center — further when active
      final baseDist = isActive
          ? r * (0.25 + energy * 0.35 + rng.nextDouble() * 0.15)
          : r * (0.15 + breathe * 0.1 + rng.nextDouble() * 0.1);

      final dx = c.dx + math.cos(angle + driftAngle * 0.3) * baseDist +
          math.sin(driftAngle * 1.5) * r * energy * 0.1;
      final dy = c.dy + math.sin(angle + driftAngle * 0.4) * baseDist * 0.85 +
          math.cos(driftAngle) * r * energy * 0.08;

      // Stay inside sphere
      final distFromCenter = (Offset(dx, dy) - c).distance;
      if (distFromCenter > r * 0.88) continue;

      // Droplet size
      final dropR = r * (0.008 + rng.nextDouble() * 0.02 + energy * 0.015);

      // Draw droplet
      canvas.drawCircle(Offset(dx, dy), dropR, Paint()..color = _ferro);

      // Tiny highlight on droplet
      if (dropR > r * 0.012) {
        canvas.drawCircle(
          Offset(dx - dropR * 0.3, dy - dropR * 0.3),
          dropR * 0.3,
          Paint()..color = Colors.white.withOpacity(0.15),
        );
      }
    }
  }

  // ─────────────────────────────────────────
  // TENDRILS — spiky extensions from main blob
  // ─────────────────────────────────────────
  void _drawTendrils(Canvas canvas, Offset c, double r, double energy) {
    final cx = c.dx + math.sin(drift * math.pi * 2) * r * 0.04;
    final cy = c.dy + math.cos(drift * math.pi * 1.5) * r * 0.05 + r * 0.03;

    final tendrilCount = 5 + (audio * 4).round();
    for (int i = 0; i < tendrilCount; i++) {
      final angle = morph * math.pi * 2 + i * (math.pi * 2 / tendrilCount);
      final length = r * (0.15 + energy * 0.25) * (0.5 + math.sin(i * 1.3 + morph * math.pi * 4) * 0.5);

      final startR = r * 0.2;
      final start = Offset(
        cx + math.cos(angle) * startR,
        cy + math.sin(angle) * startR,
      );
      final end = Offset(
        cx + math.cos(angle) * (startR + length),
        cy + math.sin(angle) * (startR + length),
      );

      // Tendril tapers from thick to thin
      final thickness = r * 0.02 * energy;

      canvas.drawLine(start, end, Paint()
        ..color = _ferro.withOpacity(0.8)
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.5));

      // Droplet at end of tendril
      if (length > r * 0.1) {
        canvas.drawCircle(end, thickness * 0.8, Paint()..color = _ferro);
      }
    }
  }

  // ─────────────────────────────────────────
  // GLASS OVERLAY — reflections on top
  // ─────────────────────────────────────────
  void _drawGlassOverlay(Canvas canvas, Offset c, double r) {
    // Main specular highlight (top-left)
    final specC = Offset(c.dx - r * 0.28, c.dy - r * 0.32);
    canvas.drawOval(
      Rect.fromCenter(center: specC, width: r * 0.55, height: r * 0.3),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.45),
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCenter(center: specC, width: r * 0.55, height: r * 0.3)),
    );

    // Small bright spot
    canvas.drawCircle(
      Offset(c.dx - r * 0.18, c.dy - r * 0.42),
      r * 0.04,
      Paint()..color = Colors.white.withOpacity(0.6),
    );

    // Bottom edge soft light
    final bottomC = Offset(c.dx + r * 0.05, c.dy + r * 0.38);
    canvas.drawOval(
      Rect.fromCenter(center: bottomC, width: r * 0.7, height: r * 0.12),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(Rect.fromCenter(center: bottomC, width: r * 0.7, height: r * 0.12)),
    );
  }

  // ─────────────────────────────────────────
  // RIM — subtle edge ring
  // ─────────────────────────────────────────
  void _drawRim(Canvas canvas, Offset c, double r) {
    // Thin subtle rim
    canvas.drawCircle(c, r - 0.5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.black.withOpacity(0.08),
          Colors.white.withOpacity(0.1),
          Colors.black.withOpacity(0.05),
          Colors.white.withOpacity(0.3),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(drift * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: r)));

    // Very subtle outer shadow
    canvas.drawCircle(c, r + 3, Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6);
  }

  @override
  bool shouldRepaint(_FerrofluidPainter old) => true;
}