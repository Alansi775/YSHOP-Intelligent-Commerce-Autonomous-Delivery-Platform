import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 🔥 ULTRA MODERN BURGER ASSEMBLY - REDESIGNED WITH INSANE CREATIVITY
/// Features: Particle effects, holographic glow, magnetic assembly, quantum transitions
class BurgerAssemblyWidget extends StatefulWidget {
  final ValueNotifier<double> scrollNotifier;
  final double height;
  final String? storeName;
  final VoidCallback? onAssembled;

  const BurgerAssemblyWidget({
    Key? key,
    required this.scrollNotifier,
    this.height = 300,
    this.storeName,
    this.onAssembled,
  }) : super(key: key);

  @override
  State<BurgerAssemblyWidget> createState() => _BurgerAssemblyWidgetState();
}

class _BurgerAssemblyWidgetState extends State<BurgerAssemblyWidget>
    with TickerProviderStateMixin {
  // 🎯 PHYSICS CONSTANTS - OPTIMIZED FOR SMOOTHNESS
  static const double kAssemblyThreshold = 280.0;
  static const double kMagneticSnapDistance = 40.0;
  // fewer particles for calmer effect
  static const double kParticleCount = 14.0;

  // 🎬 ANIMATION CONTROLLERS
  late AnimationController _masterController;
  late AnimationController _breathingController;
  late AnimationController _holographicController;
  late AnimationController _particleController;
  late AnimationController _explosionController;
  late AnimationController _finalRevealController;
  late List<AnimationController> _layerControllers;

  // 📊 STATE MANAGEMENT
  double _scrollOffset = 0.0;
  double _assemblyProgress = 0.0;
  bool _isAssembled = false;
  bool _isRevealing = false;
  late List<double> _layerProgresses;
  late List<Particle> _particles;

  // 🎨 LAYER DEFINITIONS WITH ENHANCED PROPERTIES
  final List<BurgerLayer> _layers = [
    BurgerLayer(
      asset: 'assets/images/burger3D/bottom_bun.png',
      entryAngle: math.pi * 0.25,
      spinSpeed: 2.0,
      glowColor: Color(0xFFFFD700),
      magneticStrength: 1.2,
    ),
    BurgerLayer(
      asset: 'assets/images/burger3D/beef_patty.png',
      entryAngle: -math.pi * 0.3,
      spinSpeed: -1.5,
      glowColor: Color(0xFFFF4500),
      magneticStrength: 1.0,
    ),
    BurgerLayer(
      asset: 'assets/images/burger3D/cheese_slice.png',
      entryAngle: math.pi * 0.4,
      spinSpeed: 1.8,
      glowColor: Color(0xFFFFA500),
      magneticStrength: 0.9,
    ),
    BurgerLayer(
      asset: 'assets/images/burger3D/lettuce.png',
      entryAngle: -math.pi * 0.2,
      spinSpeed: -2.2,
      glowColor: Color(0xFF32CD32),
      magneticStrength: 0.8,
    ),
    BurgerLayer(
      asset: 'assets/images/burger3D/sauce_layer.png',
      entryAngle: math.pi * 0.35,
      spinSpeed: 1.3,
      glowColor: Color(0xFFFF6347),
      magneticStrength: 0.7,
    ),
    BurgerLayer(
      asset: 'assets/images/burger3D/top_bun.png',
      entryAngle: -math.pi * 0.15,
      spinSpeed: -1.7,
      glowColor: Color(0xFFFFD700),
      magneticStrength: 1.1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeParticles();
    widget.scrollNotifier.addListener(_handleScroll);
  }

  void _initializeAnimations() {
    // Master timeline controller
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

        // Breathing life effect (much slower now for a calm scene)
        _breathingController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 9000),
        )..repeat(reverse: true);

    // Holographic shimmer
        // Holographic shimmer - very slow drift to reduce visual noise
        _holographicController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 20000),
        )..repeat();

    // Particle system
        // Particle system - slower one-shot bursts for gentle motion
        _particleController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2000),
        );

    // Explosion effect on completion
    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Final reveal animation - slower and more dramatic
    _finalRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Individual layer controllers - MUCH SLOWER for better viewing
    _layerControllers = List.generate(
      _layers.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1200 + (i * 150)), // Slower base + more stagger
      ),
    );

    // Initialize layer progresses
    _layerProgresses = List.filled(_layers.length, 0.0);

    // Add listeners for automatic progression
    for (int i = 0; i < _layerControllers.length; i++) {
      _layerControllers[i].addListener(() {
        if (mounted) {
          setState(() {
            // CRITICAL: Clamp to prevent floating-point errors
            _layerProgresses[i] = _layerControllers[i].value.clamp(0.0, 1.0);
            _updateAssemblyProgress();
          });
        }
      });

      _layerControllers[i].addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          // Trigger next layer with LONGER delay for better viewing
          if (i < _layers.length - 1) {
            Future.delayed(Duration(milliseconds: 300), () {
              if (mounted && !_isAssembled) {
                _layerControllers[i + 1].forward();
              }
            });
          } else if (!_isAssembled) {
            // All layers complete - wait a bit before final sequence
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted) _triggerFinalSequence();
            });
          }
        }
      });
    }
  }

  void _initializeParticles() {
    final random = math.Random();
    _particles = List.generate(
      kParticleCount.toInt(),
      (i) => Particle(
        x: random.nextDouble() * 2 - 1,
        y: random.nextDouble() * 2 - 1,
        speed: 0.12 + random.nextDouble() * 0.36,
        size: 1.0 + random.nextDouble() * 3.0,
        opacity: 0.4 + random.nextDouble() * 0.4,
        color: _layers[random.nextInt(_layers.length)].glowColor,
      ),
    );
  }

  void _handleScroll() {
    if (_isAssembled || _isRevealing) return;

    final newOffset = widget.scrollNotifier.value;
    final rawProgress = (newOffset / kAssemblyThreshold).clamp(0.0, 1.0);
    
    setState(() {
      _scrollOffset = newOffset;
    });

    // Trigger layer animations based on scroll thresholds
    final layerCount = _layers.length;
    for (int i = 0; i < layerCount; i++) {
      final threshold = (i + 1) / (layerCount + 1);
      
      if (rawProgress >= threshold && _layerProgresses[i] < 1.0) {
        if (!_layerControllers[i].isAnimating) {
          // Magnetic snap effect when close
          final snapProgress = ((rawProgress - threshold) * 3).clamp(0.0, 1.0);
          if (snapProgress > 0.3) {
            _layerControllers[i].forward();
          } else {
            // Preview mode - keep clamped
            _layerProgresses[i] = (snapProgress * 0.5).clamp(0.0, 0.3);
          }
        }
      }
    }

    _updateAssemblyProgress();
  }

  void _updateAssemblyProgress() {
    final avg = _layerProgresses.reduce((a, b) => a + b) / _layerProgresses.length;
    _assemblyProgress = avg.clamp(0.0, 1.0);
  }

  void _triggerFinalSequence() async {
    if (_isRevealing) return;
    
    setState(() {
      _isRevealing = true;
    });

    // Explosion effect
    await _explosionController.forward(from: 0.0);
    
    // Small pause for impact
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Final reveal with cinematic timing
    await _finalRevealController.forward();
    
    setState(() {
      _isAssembled = true;
    });

    // Notify parent after elegant delay
    await Future.delayed(const Duration(milliseconds: 800));
    widget.onAssembled?.call();
  }

  @override
  void dispose() {
    widget.scrollNotifier.removeListener(_handleScroll);
    _masterController.dispose();
    _breathingController.dispose();
    _holographicController.dispose();
    _particleController.dispose();
    _explosionController.dispose();
    _finalRevealController.dispose();
    for (var controller in _layerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height * 1.8,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 🌌 Holographic background
          _buildHolographicBackground(),
          
          // ✨ Particle system
          _buildParticleSystem(),
          
          // 🍔 Assembly view (fades out when complete)
          AnimatedOpacity(
            opacity: _isAssembled ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 1000),
            child: _buildAssemblyView(),
          ),
          
          // 🎭 Final hero view (fades in when ALMOST complete - later timing)
          if (_assemblyProgress > 0.96)
            AnimatedOpacity(
              opacity: (((_assemblyProgress - 0.96) / 0.04) * _finalRevealController.value).clamp(0.0, 1.0),
              duration: const Duration(milliseconds: 300),
              child: _buildHeroView(),
            ),
          
          // 💥 Explosion overlay
          if (_explosionController.value > 0)
            _buildExplosionEffect(),
          
          // 📝 Welcome text
          if (_isAssembled)
            _buildWelcomeText(),
        ],
      ),
    );
  }

  Widget _buildHolographicBackground() {
    return AnimatedBuilder(
      animation: _holographicController,
      builder: (context, child) {
        // Subtle during assembly, strong at reveal
        final intensity = _assemblyProgress < 0.95 
            ? _assemblyProgress * 0.3  // Very subtle during assembly
            : _assemblyProgress;       // Full intensity when complete
            
        return Container(
          width: widget.height * 2,
          height: widget.height * 2,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Color(0xFF6366F1).withOpacity(0.1 * intensity),
                Color(0xFF8B5CF6).withOpacity(0.05 * intensity),
                Colors.transparent,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: CustomPaint(
            painter: HolographicPainter(
              progress: _holographicController.value,
              intensity: intensity,
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticleSystem() {
    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.height * 2, widget.height * 2),
          painter: ParticlePainter(
            particles: _particles,
            progress: _particleController.value,
            assemblyProgress: _assemblyProgress,
          ),
        );
      },
    );
  }

  Widget _buildAssemblyView() {
    return Transform.scale(
      scale: 1.0 + (_assemblyProgress * 0.15),
      child: Stack(
        alignment: Alignment.center,
        children: _layers.asMap().entries.map((entry) {
          final index = entry.key;
          final layer = entry.value;
          final progress = _layerProgresses[index];

          return _buildLayer(index, layer, progress);
        }).toList(),
      ),
    );
  }

  Widget _buildLayer(int index, BurgerLayer layer, double progress) {
    // CRITICAL: Clamp progress to prevent floating-point precision errors
    progress = progress.clamp(0.0, 1.0);
    
    // Calculate entry position - layers come straight down from above
    final startHeight = 700.0; // Start from top
    // Each layer needs to stop at a specific height to stack properly
    // Bottom layers (index 0) at bottom, top layers at top
    final stackOrder = _layers.length - 1 - index; // Reverse: 0 = top bun, 5 = bottom bun
    // How far apart the layers should be when stacked. Increase to avoid overlap.
    final layerThickness = 12.0;
    // Center the whole stack vertically around Y=0 so layers align visually
    final totalStackHeight = (_layers.length - 1) * layerThickness;
    final baseTop = - (totalStackHeight / 2);
    final targetY = baseTop + (stackOrder * layerThickness);
    
    // Remove 3D perspective and rotation so layers stack straight
    // Keep translations only on Y so layers align vertically on top of each other
    final depthOffset = 0.0; // no Z offset
    final perspectiveY = 0.0; // no extra Y perspective shift
    
    // Smooth single descent - no bounce, just clean easeOut
    final descendCurve = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    
    final currentY = startHeight * (1 - descendCurve) + targetY * descendCurve;

    // No rotation for stacked appearance
    final rotation = 0.0;
    
    // Simple scale - no bounce
    // Disable per-layer width scaling so all layers align vertically
    final perspectiveScale = 1.0;
    final scale = (0.85 + (progress * 0.15)) * perspectiveScale;

    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final breathOffset = progress >= 0.98 
            ? math.sin(_breathingController.value * math.pi * 2) * 2.0
            : 0.0;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(0.0, currentY + breathOffset, 0.0)
            ..scale(scale),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Very subtle glow during assembly (only when progress > 0.6)
              if (progress > 0.6 && progress < 0.95)
                Container(
                  width: widget.height * 0.7,
                  height: widget.height * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: layer.glowColor.withOpacity(0.12 * (progress - 0.6)),
                        blurRadius: 20 * (progress - 0.6),
                        spreadRadius: 3 * (progress - 0.6),
                      ),
                    ],
                  ),
                ),
              
              // Layer image with shader
              ShaderMask(
                shaderCallback: (bounds) {
                  return RadialGradient(
                    colors: [
                      Colors.white,
                      Colors.white.withOpacity(0.95),
                    ],
                  ).createShader(bounds);
                },
                            child: Image.asset(
                              layer.asset,
                              width: widget.height * 1.5,
                              fit: BoxFit.contain,
                            ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroView() {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathingController, _finalRevealController]),
      builder: (context, child) {
        final breathScale = 1.0 + (math.sin(_breathingController.value * math.pi * 2) * 0.025);
        final floatY = math.sin(_breathingController.value * math.pi * 2) * 8.0;
        final revealScale = Curves.elasticOut.transform(_finalRevealController.value);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(0.0, floatY - 50)
            ..scale(breathScale * revealScale),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Epic glow aura
              Container(
                width: widget.height * 1.2,
                height: widget.height * 1.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xFFFF6B35).withOpacity(0.5),
                      Color(0xFFFFC837).withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF6B35).withOpacity(0.6),
                      blurRadius: 80,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
              
              // 3D perspective burger
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(math.sin(_breathingController.value * math.pi) * 0.08)
                  ..rotateX(math.cos(_breathingController.value * math.pi * 0.5) * 0.03),
                child: Image.asset(
                  'assets/images/burger3D/full2.png',
                  width: widget.height * 1.5,
                  fit: BoxFit.contain,
                ),
              ),
              
              // Light rays
              CustomPaint(
                size: Size(widget.height * 2, widget.height * 2),
                painter: LightRayPainter(
                  progress: _breathingController.value,
                  intensity: _finalRevealController.value,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplosionEffect() {
    return CustomPaint(
      size: Size(widget.height * 3, widget.height * 3),
      painter: ExplosionPainter(
        progress: _explosionController.value,
      ),
    );
  }

  Widget _buildWelcomeText() {
    return Positioned(
      bottom: 40,
      child: FadeTransition(
        opacity: _finalRevealController,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(
              parent: _finalRevealController,
              curve: Curves.elasticOut,
            ),
          ),
          child: Column(
            children: [
              // Subtitle
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFFC837)],
                ).createShader(bounds),
                child: Text(
                  'CRAFTED WITH PASSION',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
              ),
              
              SizedBox(height: 12),
              
              // Main title with gradient
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    Colors.white,
                    Color(0xFFFFC837),
                    Color(0xFFFF6B35),
                  ],
                ).createShader(bounds),
                child: Text(
                  'Welcome to ${widget.storeName ?? "Paradise"}',
                  style: TextStyle(
                    fontFamily: 'TenorSans',
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Color(0xFFFF6B35).withOpacity(0.8),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 15),
              
              // Decorative line
              Container(
                width: 200,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Color(0xFFFF6B35),
                      Color(0xFFFFC837),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF6B35).withOpacity(0.6),
                      blurRadius: 10,
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
}

// 🎨 CUSTOM PAINTERS FOR VISUAL EFFECTS

class HolographicPainter extends CustomPainter {
  final double progress;
  final double intensity;

  HolographicPainter({required this.progress, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final center = Offset(size.width / 2, size.height / 2);
    // Use a slow sinusoidal phase per ring so rings drift gently without sharp wrap
    for (int i = 0; i < 5; i++) {
      final phase = (progress + (i * 0.18));
      // smooth -1..1 then normalize to 0..1
      final offset = (math.sin(phase * math.pi * 2) * 0.5) + 0.5;
      final baseRadius = size.width * 0.18 + (i * size.width * 0.06);
      final radius = baseRadius + (offset * size.width * 0.12);
      final opacity = ((1 - offset) * intensity * 0.15).clamp(0.0, 1.0);

      paint.color = Color(0xFF8B5CF6).withOpacity(opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(HolographicPainter oldDelegate) => true;
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;
  final double assemblyProgress;

  ParticlePainter({
    required this.particles,
    required this.progress,
    required this.assemblyProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    for (var particle in particles) {
      final angle = particle.x * math.pi * 2 + progress * math.pi * 2;
      final radius = (particle.y.abs() * size.width * 0.4) * (1 + progress * 0.5);
      
      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;
      
      final paint = Paint()
        ..color = particle.color.withOpacity(particle.opacity * assemblyProgress)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, particle.size);
      
      canvas.drawCircle(
        Offset(x, y),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) => true;
}

class LightRayPainter extends CustomPainter {
  final double progress;
  final double intensity;

  LightRayPainter({required this.progress, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16);

    for (int i = 0; i < 8; i++) {
      // slower rotation (half speed) and softer length so rays are calmer
      final angle = (i / 8) * math.pi * 2 + progress * math.pi;
      final length = size.width * 0.32 * math.max(0.2, intensity);
      
      final gradient = RadialGradient(
        colors: [
          Color(0xFFFFC837).withOpacity(0.22 * intensity),
          Colors.transparent,
        ],
      );
      
      paint.shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: length),
      );
      
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(angle) * length,
          center.dy + math.sin(angle) * length,
        )
        ..lineTo(
          center.dx + math.cos(angle + 0.1) * length,
          center.dy + math.sin(angle + 0.1) * length,
        )
        ..close();
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(LightRayPainter oldDelegate) => true;
}

class ExplosionPainter extends CustomPainter {
  final double progress;

  ExplosionPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2;
      final distance = size.width * 0.5 * progress;
      final opacity = (1 - progress) * 0.8;
      
      paint.color = Color(0xFFFF6B35).withOpacity(opacity);
      
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(angle) * distance,
          center.dy + math.sin(angle) * distance,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ExplosionPainter oldDelegate) => true;
}

// 🎯 DATA MODELS

class BurgerLayer {
  final String asset;
  final double entryAngle;
  final double spinSpeed;
  final Color glowColor;
  final double magneticStrength;

  BurgerLayer({
    required this.asset,
    required this.entryAngle,
    required this.spinSpeed,
    required this.glowColor,
    required this.magneticStrength,
  });
}

class Particle {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double opacity;
  final Color color;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.color,
  });
}