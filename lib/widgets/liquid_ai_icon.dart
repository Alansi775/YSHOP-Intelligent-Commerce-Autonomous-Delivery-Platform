import 'package:flutter/material.dart';
import 'dart:math' as math;

/// ═══════════════════════════════════════════════════════════════
/// ✨ LIQUID AI ICON — Organic Aurora Orb
/// A mesmerizing, alive-feeling icon that breathes and shifts
/// like a living organism. Inspired by Apple's Siri orb but
/// with a unique identity for YSHOP.
/// ═══════════════════════════════════════════════════════════════
class LiquidAIIcon extends StatefulWidget {
  final double size;
  final bool isActive;
  final bool isThinking;

  const LiquidAIIcon({
    Key? key,
    this.size = 36,
    this.isActive = false,
    this.isThinking = false,
  }) : super(key: key);

  @override
  State<LiquidAIIcon> createState() => _LiquidAIIconState();
}

class _LiquidAIIconState extends State<LiquidAIIcon>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _breatheController;
  late AnimationController _colorController;
  late AnimationController _thinkingController;

  // Premium color palette — deep, refined, not generic
  final List<Color> _colors = const [
    Color(0xFF2563EB), // Royal blue
    Color(0xFF7C3AED), // Deep violet
    Color(0xFF0EA5E9), // Sky blue
    Color(0xFF6366F1), // Indigo
  ];

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();

    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);

    _colorController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();

    _thinkingController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    if (widget.isThinking) {
      _thinkingController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LiquidAIIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking && !oldWidget.isThinking) {
      _thinkingController.repeat(reverse: true);
    } else if (!widget.isThinking && oldWidget.isThinking) {
      _thinkingController.stop();
      _thinkingController.value = 0;
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _breatheController.dispose();
    _colorController.dispose();
    _thinkingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rotationController,
          _breatheController,
          _colorController,
          _thinkingController,
        ]),
        builder: (context, _) {
          final breathe = 0.92 + (_breatheController.value * 0.08);
          final thinkScale = widget.isThinking
              ? 0.85 + (_thinkingController.value * 0.3)
              : 1.0;

          return Transform.scale(
            scale: breathe * thinkScale,
            child: CustomPaint(
              size: Size(s, s),
              painter: _AuroraOrbPainter(
                rotation: _rotationController.value,
                breathe: _breatheController.value,
                colorProgress: _colorController.value,
                colors: _colors,
                isActive: widget.isActive,
                isThinking: widget.isThinking,
                thinkingValue: _thinkingController.value,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuroraOrbPainter extends CustomPainter {
  final double rotation;
  final double breathe;
  final double colorProgress;
  final List<Color> colors;
  final bool isActive;
  final bool isThinking;
  final double thinkingValue;

  _AuroraOrbPainter({
    required this.rotation,
    required this.breathe,
    required this.colorProgress,
    required this.colors,
    required this.isActive,
    required this.isThinking,
    required this.thinkingValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── 1. Outer glow (very subtle) ──
    final glowRadius = radius * (1.0 + breathe * 0.15);
    final glowOpacity = isThinking ? 0.25 + thinkingValue * 0.15 : 0.15;
    final currentColor = _getCurrentColor();

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          currentColor.withOpacity(glowOpacity),
          currentColor.withOpacity(0),
        ],
        stops: const [0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius * 1.5));

    canvas.drawCircle(center, glowRadius * 1.5, glowPaint);

    // ── 2. Main orb with sweep gradient ──
    final sweepAngle = rotation * 2 * math.pi;
    final nextColor = _getNextColor();

    final orbPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          currentColor,
          Color.lerp(currentColor, nextColor, 0.5)!,
          nextColor,
          Color.lerp(nextColor, currentColor, 0.5)!,
          currentColor,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, orbPaint);

    // ── 3. Inner light spot (gives depth) ──
    final lightOffset = Offset(
      center.dx + math.cos(sweepAngle * 0.7) * radius * 0.25,
      center.dy + math.sin(sweepAngle * 0.7) * radius * 0.25,
    );

    final innerGlow = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (lightOffset.dx - center.dx) / radius,
          (lightOffset.dy - center.dy) / radius,
        ),
        colors: [
          Colors.white.withOpacity(0.35 + breathe * 0.1),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.7],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, innerGlow);

    // ── 4. Specular highlight (top-left) ──
    final specPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 0.6,
        colors: [
          Colors.white.withOpacity(0.25),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, specPaint);
  }

  Color _getCurrentColor() {
    final idx = (colorProgress * colors.length).floor() % colors.length;
    final nextIdx = (idx + 1) % colors.length;
    final t = (colorProgress * colors.length) - idx;
    return Color.lerp(colors[idx], colors[nextIdx], t)!;
  }

  Color _getNextColor() {
    final idx = ((colorProgress * colors.length).floor() + 1) % colors.length;
    final nextIdx = (idx + 1) % colors.length;
    final t = (colorProgress * colors.length) - idx.toDouble();
    return Color.lerp(colors[idx], colors[nextIdx], t.clamp(0, 1))!;
  }

  @override
  bool shouldRepaint(_AuroraOrbPainter old) => true;
}