// lib/widgets/liquid_orb_visualizer.dart
//
// 🌫️ SMOKE ORB — Real fog trapped in glass
//
// Massive, spread-out clouds of black & white fog.
// NOT dots. NOT circles. REAL FOG — huge, blurred, atmospheric.
// Each cloud is 60-85% of the sphere size with heavy blur.
// They drift slowly like weather inside a crystal ball.

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';

enum VoicePhase { idle, listening, thinking, speaking }

class LiquidOrbVisualizer extends StatefulWidget {
  final double size;
  final VoicePhase phase;
  final double audioLevel;
  final bool colorful; // when false -> use grayscale (for call/connection)

  const LiquidOrbVisualizer({
    Key? key,
    this.size = 200,
    this.phase = VoicePhase.idle,
    this.audioLevel = 0.0,
    this.colorful = true,
  }) : super(key: key);

  @override
  State<LiquidOrbVisualizer> createState() => _LiquidOrbVisualizerState();
}

class _LiquidOrbVisualizerState extends State<LiquidOrbVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _drift1;
  late AnimationController _drift2;
  late AnimationController _drift3;
  late AnimationController _breathe;
  late AnimationController _wind;
  late AnimationController _colorShift; // very slow color cycling

  double _smoothAudio = 0.0;

  @override
  void initState() {
    super.initState();
    _OrbSync.ensureStarted();
    _drift1 = AnimationController(vsync: this, duration: const Duration(seconds: 37))..repeat();
    _drift2 = AnimationController(vsync: this, duration: const Duration(seconds: 29))..repeat();
    _drift3 = AnimationController(vsync: this, duration: const Duration(seconds: 43))..repeat();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))..repeat(reverse: true);
    _wind = AnimationController(vsync: this, duration: const Duration(seconds: 53))..repeat();
    _colorShift = AnimationController(vsync: this, duration: const Duration(seconds: 160))..repeat();
  }

  @override
  void dispose() {
    _drift1.dispose();
    _drift2.dispose();
    _drift3.dispose();
    _breathe.dispose();
    _wind.dispose();
    _colorShift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_drift1, _drift2, _drift3, _breathe, _wind, _colorShift, _OrbSync.time]),
        builder: (_, __) {
          final target = widget.audioLevel;
          if (target > _smoothAudio) {
            _smoothAudio = _smoothAudio * 0.4 + target * 0.6;
          } else {
            _smoothAudio = _smoothAudio * 0.85 + target * 0.15;
          }
          // compute synchronized drift values from shared global clock
          final now = _OrbSync.time.value; // seconds
          final sd1 = ((now / 37.0) % 1.0);
          final sd2 = ((now / 29.0) % 1.0);
          final sd3 = ((now / 43.0) % 1.0);

          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _FogPainter(
              d1: sd1,
              d2: sd2,
              d3: sd3,
              breathe: _breathe.value,
              wind: _wind.value,
              phase: widget.phase,
              audio: _smoothAudio,
              colorful: widget.colorful,
              colorShift: _colorShift.value,
            ),
          );
        },
      ),
    );
  }
}

// Global clock so multiple LiquidOrbVisualizer instances stay in sync.
class _OrbSync {
  static final ValueNotifier<double> time = ValueNotifier<double>(0.0);
  static bool _started = false;

  static void ensureStarted() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addPersistentFrameCallback((Duration ts) {
      time.value = ts.inMilliseconds / 1000.0;
    });
  }
}

class _FogPainter extends CustomPainter {
  final double d1, d2, d3, breathe, wind;
  final VoicePhase phase;
  final double audio;
  final bool colorful;
  final double colorShift; // 0..1 slow

  _FogPainter({
    required this.d1, required this.d2, required this.d3,
    required this.breathe, required this.wind,
    required this.phase, required this.audio,
    required this.colorful,
    required this.colorShift,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final isSpeaking = phase == VoicePhase.speaking;
    final isListening = phase == VoicePhase.listening;
    final isActive = isSpeaking || isListening;
    final isThinking = phase == VoicePhase.thinking;

    double energy;
    if (isSpeaking) {
      energy = 0.4 + audio * 0.6;
    } else if (isListening) {
      energy = 0.2 + audio * 0.4;
    } else if (isThinking) {
      energy = 0.12 + breathe * 0.08;
    } else {
      energy = 0.05 + breathe * 0.05;
    }

    // Clip to sphere
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // ═══════════════════════════════
    // 1. WHITE GLASS BACKGROUND
    // ═══════════════════════════════
    canvas.drawCircle(c, r, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 1.0,
        colors: const [
          Color(0xFFF8F8FC),
          Color(0xFFF0F0F5),
          Color(0xFFE8E8F0),
          Color(0xFFDADAE2),
        ],
        stops: const [0.0, 0.3, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)));

    // Wind — slow global direction shift
    final windAngle = wind * math.pi * 2;
    final wx = math.sin(windAngle) * r * 0.05;
    final wy = math.cos(windAngle * 0.7) * r * 0.04;

    // ═══════════════════════════════
    // 2. FOG MASSES — HUGE BLURRED CLOUDS
    //    Each cloud is 60-85% of sphere
    //    Blur is 30-40% of radius
    // ═══════════════════════════════

    // ── DARK CLOUD A — enormous background fog ──
    _fog(canvas, c, r,
      ox: math.sin(d1 * _tau) * r * 0.14 + math.sin(d2 * _tau * 0.6) * r * 0.07 + wx,
      oy: math.cos(d1 * _tau * 0.8) * r * 0.12 + math.cos(d3 * _tau * 0.4) * r * 0.06 + wy,
      sx: r * 0.85, sy: r * 0.72,
      rot: math.sin(d1 * _tau * 0.3) * 0.15,
      op: 0.32 + energy * 0.12,
      blur: r * 0.38,
      dark: true,
    );

    // ── WHITE CLOUD A — large bright mist (opposite drift) ──
    _fog(canvas, c, r,
      ox: math.cos(d1 * _tau * 0.8 + 3.5) * r * 0.16 + math.sin(d3 * _tau * 0.5 + 2.0) * r * 0.08 - wx,
      oy: math.sin(d1 * _tau * 0.6 + 1.0) * r * 0.13 + math.cos(d2 * _tau * 0.3 + 4.0) * r * 0.07 - wy,
      sx: r * 0.75, sy: r * 0.62,
      rot: math.cos(d1 * _tau * 0.2 + 0.5) * 0.2,
      op: 0.20 + energy * 0.08,
      blur: r * 0.35,
      dark: false,
    );

    // ── DARK CLOUD B — dense core that wanders ──
    _fog(canvas, c, r,
      ox: math.cos(d2 * _tau * 1.3 + 1.2) * r * 0.20 + math.sin(d3 * _tau * 0.5 + 0.8) * r * 0.09 + wx,
      oy: math.sin(d2 * _tau * 0.9 + 0.7) * r * 0.17 + math.cos(d1 * _tau * 0.4 + 2.1) * r * 0.08 + wy,
      sx: r * 0.60, sy: r * 0.52,
      rot: math.cos(d2 * _tau * 0.25 + 1.0) * 0.25,
      op: 0.40 + energy * 0.15,
      blur: r * 0.30,
      dark: true,
    );

    // ── WHITE CLOUD B — smaller, independent ──
    _fog(canvas, c, r,
      ox: math.sin(d2 * _tau * 1.2 + 4.5) * r * 0.22 + math.cos(d1 * _tau * 0.4 + 3.0) * r * 0.10 - wx * 0.8,
      oy: math.cos(d2 * _tau * 0.7 + 2.5) * r * 0.18 + math.sin(d3 * _tau * 0.5 + 1.5) * r * 0.08 - wy * 0.8,
      sx: r * 0.55, sy: r * 0.45,
      rot: math.sin(d2 * _tau * 0.15 + 3.5) * 0.25,
      op: 0.16 + energy * 0.07,
      blur: r * 0.30,
      dark: false,
    );

    // ── DARK CLOUD C — third independent mass ──
    _fog(canvas, c, r,
      ox: math.sin(d3 * _tau * 1.5 + 2.5) * r * 0.24 + math.cos(d1 * _tau * 0.7 + 1.8) * r * 0.11 + wx * 1.2,
      oy: math.cos(d3 * _tau * 1.1 + 1.7) * r * 0.20 + math.sin(d2 * _tau * 0.6 + 3.0) * r * 0.09 + wy * 1.1,
      sx: r * 0.50, sy: r * 0.42,
      rot: math.sin(d3 * _tau * 0.2 + 2.0) * 0.3,
      op: 0.28 + energy * 0.10,
      blur: r * 0.26,
      dark: true,
    );

    // ── DARK CLOUD D — extra depth layer ──
    _fog(canvas, c, r,
      ox: math.cos(d1 * _tau * 1.7 + 5.0) * r * 0.26 + math.sin(d2 * _tau * 0.8 + 0.5) * r * 0.11 + wx * 0.5,
      oy: math.sin(d1 * _tau * 1.3 + 3.5) * r * 0.22 + math.cos(d3 * _tau * 0.6 + 2.5) * r * 0.09 + wy * 0.7,
      sx: r * 0.45, sy: r * 0.38,
      rot: math.cos(d3 * _tau * 0.18 + 1.0) * 0.35,
      op: 0.24 + energy * 0.10,
      blur: r * 0.24,
      dark: true,
    );

    // ── WHITE CLOUD C — ethereal wisp ──
    _fog(canvas, c, r,
      ox: math.sin(d3 * _tau * 0.9 + 1.5) * r * 0.22 + math.cos(d2 * _tau * 1.1 + 5.0) * r * 0.09 - wx * 1.2,
      oy: math.cos(d1 * _tau * 1.4 + 4.0) * r * 0.18 + math.sin(d3 * _tau * 0.3 + 0.5) * r * 0.08 - wy * 1.1,
      sx: r * 0.42, sy: r * 0.35,
      rot: math.sin(d1 * _tau * 0.12 + 2.5) * 0.3,
      op: 0.13 + energy * 0.06,
      blur: r * 0.28,
      dark: false,
    );

    // ═══════════════════════════════
    // 3. SPEAKING — extra fog surge
    // ═══════════════════════════════
    if (isSpeaking && audio > 0.15) {
      // Dark surge — expands with voice
      _fog(canvas, c, r,
        ox: math.sin(d1 * _tau * 3 + d2 * _tau * 2) * r * audio * 0.22,
        oy: math.cos(d2 * _tau * 2.5 + d3 * _tau * 1.5) * r * audio * 0.20,
        sx: r * (0.55 + audio * 0.30),
        sy: r * (0.48 + audio * 0.25),
        rot: d1 * _tau * 0.5,
        op: audio * 0.32,
        blur: r * (0.22 + audio * 0.12),
        dark: true,
      );

      // White counter-surge
      _fog(canvas, c, r,
        ox: -math.cos(d1 * _tau * 2.5 + d3 * _tau * 1.5) * r * audio * 0.20,
        oy: -math.sin(d2 * _tau * 2 + d1 * _tau) * r * audio * 0.17,
        sx: r * (0.45 + audio * 0.22),
        sy: r * (0.38 + audio * 0.18),
        rot: -d2 * _tau * 0.4,
        op: audio * 0.20,
        blur: r * (0.24 + audio * 0.10),
        dark: false,
      );
    }

    // ═══════════════════════════════
    // 4. GLASS REFLECTIONS
    // ═══════════════════════════════
    _drawGlass(canvas, c, r);

    canvas.restore();

    // 5. RIM
    _drawRim(canvas, c, r);
  }

  static const double _tau = math.pi * 2;

  // ─────────────────────────────────────
  // FOG — single massive blurred cloud
  // ─────────────────────────────────────
  void _fog(Canvas canvas, Offset c, double r, {
    required double ox, required double oy,
    required double sx, required double sy,
    required double rot, required double op,
    required double blur, required bool dark,
  }) {
    final breathScale = 1.0 + breathe * 0.06;
    final fsx = sx * breathScale;
    final fsy = sy * breathScale;
    final fop = (op * (1.0 + math.sin(d2 * _tau * 2 + ox) * 0.06)).clamp(0.0, 0.95);

    canvas.save();
    canvas.translate(c.dx + ox, c.dy + oy);
    canvas.rotate(rot);

    final rect = Rect.fromCenter(center: Offset.zero, width: fsx * 2, height: fsy * 2);

    // Main fog body
    canvas.drawOval(rect, Paint()
      ..shader = RadialGradient(
        colors: _fogColors(dark, fop, ox, oy, rot),
        stops: const [0.0, 0.22, 0.48, 0.74, 1.0],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));

    // Dense inner core
    final inner = Rect.fromCenter(center: Offset.zero, width: fsx * 1.1, height: fsy * 1.0);
    canvas.drawOval(inner, Paint()
      ..shader = RadialGradient(
        colors: _innerColors(dark, fop, ox, oy, rot),
        stops: const [0.0, 0.45, 1.0],
      ).createShader(inner)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.6));

    canvas.restore();
  }

  // ─────────────────────────────────────
  // GLASS
  // ─────────────────────────────────────
  void _drawGlass(Canvas canvas, Offset c, double r) {
    final specC = Offset(c.dx - r * 0.25, c.dy - r * 0.30);
    canvas.drawOval(
      Rect.fromCenter(center: specC, width: r * 0.58, height: r * 0.30),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.40),
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCenter(center: specC, width: r * 0.58, height: r * 0.30)),
    );

    canvas.drawCircle(
      Offset(c.dx - r * 0.16, c.dy - r * 0.40),
      r * 0.032,
      Paint()..color = Colors.white.withOpacity(0.55),
    );

    canvas.drawCircle(
      Offset(c.dx - r * 0.32, c.dy - r * 0.20),
      r * 0.015,
      Paint()..color = Colors.white.withOpacity(0.28),
    );

    final btm = Offset(c.dx + r * 0.04, c.dy + r * 0.38);
    canvas.drawOval(
      Rect.fromCenter(center: btm, width: r * 0.60, height: r * 0.09),
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.0)],
        ).createShader(Rect.fromCenter(center: btm, width: r * 0.60, height: r * 0.09)),
    );
  }

  // ─────────────────────────────────────
  // RIM
  // ─────────────────────────────────────
  void _drawRim(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r - 0.5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.22),
          Colors.black.withOpacity(0.04),
          Colors.white.withOpacity(0.07),
          Colors.black.withOpacity(0.03),
          Colors.white.withOpacity(0.22),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(d1 * _tau),
      ).createShader(Rect.fromCircle(center: c, radius: r)));

    canvas.drawCircle(c, r + 2, Paint()
      ..color = Colors.black.withOpacity(0.04)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);
  }

  // ------- Palette helpers -------
  List<Color> _fogColors(bool dark, double fop, double ox, double oy, double rot) {
    final seed = (ox + oy + rot) * 0.0007 + d1 * 0.2 + colorShift;
    final c0 = _samplePalette(seed + 0.00);
    final c1 = _samplePalette(seed + 0.18);
    final c2 = _samplePalette(seed + 0.36);
    final c3 = _samplePalette(seed + 0.54);
    final c4 = _samplePalette(seed + 0.72);

    List<Color> cols = [c0, c1, c2, c3, c4].map((c) => c.withOpacity((c.opacity * fop).clamp(0.0, 1.0))).toList();

    if (!colorful) {
      cols = cols.map((c) => _toGray(c)).toList();
      if (dark) cols = cols.map((c) => c.withOpacity((c.opacity).clamp(0.0, 0.95))).toList();
    } else {
      if (dark) cols = cols.map((c) => _blend(c, const Color(0xFF0E0E14), 0.18)).toList();
    }
    return cols;
  }

  List<Color> _innerColors(bool dark, double fop, double ox, double oy, double rot) {
    final seed = (ox - oy - rot) * 0.0009 + d2 * 0.25 + colorShift;
    final a = _samplePalette(seed + 0.05).withOpacity((fop * 0.45).clamp(0.0, 1.0));
    final b = _samplePalette(seed + 0.25).withOpacity((fop * 0.18).clamp(0.0, 1.0));
    final c = _samplePalette(seed + 0.45).withOpacity(0.0);
    var cols = [a, b, c];
    if (!colorful) cols = cols.map(_toGray).toList();
    if (dark) cols = cols.map((c) => _blend(c, const Color(0xFF0A0A10), 0.10)).toList();
    return cols;
  }

  Color _samplePalette(double t) {
    final tt = (t % 1.0 + 1.0) % 1.0;
    final stops = [0.0, 0.35, 0.65, 1.0];
    final colors = [
      const Color(0xFF6FF0F8),
      const Color(0xFF4B9BFF),
      const Color(0xFF6B5BFF),
      const Color(0xFFB47AFF),
    ];
    for (var i = 0; i < stops.length - 1; i++) {
      if (tt >= stops[i] && tt <= stops[i + 1]) {
        final local = (tt - stops[i]) / (stops[i + 1] - stops[i]);
        return _lerpColor(colors[i], colors[i + 1], local);
      }
    }
    return colors.last;
  }

  Color _toGray(Color c) {
    final r = c.red / 255.0;
    final g = c.green / 255.0;
    final b = c.blue / 255.0;
    final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    final v = (lum.clamp(0.0, 1.0) * 255).round();
    return Color.fromRGBO(v, v, v, c.opacity);
  }

  Color _lerpColor(Color a, Color b, double t) {
    return Color.fromARGB(
      (a.alpha + (b.alpha - a.alpha) * t).round(),
      (a.red + (b.red - a.red) * t).round(),
      (a.green + (b.green - a.green) * t).round(),
      (a.blue + (b.blue - a.blue) * t).round(),
    );
  }

  Color _blend(Color a, Color b, double t) => _lerpColor(a, b, t.clamp(0.0, 1.0));

  @override
  bool shouldRepaint(_FogPainter old) => true;
}