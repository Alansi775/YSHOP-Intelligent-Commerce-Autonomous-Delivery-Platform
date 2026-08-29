import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

///  EXPLODED VIEW BURGER ASSEMBLY
/// كل طبقة تنفجر من مركزها مع تأثيرات 3D خرافية!
class BurgerAssemblyWidget extends StatefulWidget {
  final ValueNotifier<double> scrollNotifier;
  final double height;
  final String? storeName;
  final VoidCallback? onAssembled;
  final ValueNotifier<double>? welcomeOpacityNotifier;
  // The "DISCOVER EXCELLENCE / Scroll Down to Explore" welcome scene and
  // its scroll-driven reveal are generic and apply to every store type —
  // only the burger-pieces-exploding-into-place visual is restaurant
  // specific. Non-Food stores keep everything else (welcome text,
  // completion celebration, scroll mechanics) and just skip this one part.
  final bool showBurgerPieces;
  final String completionLabel;
  // How much scrolling it takes to reach the "assembled"/onAssembled
  // trigger. Defaults to the burger's own real pacing (6 layers x 180px).
  // Non-Food stores have nothing to watch during that scroll — no burger
  // pieces — so making them scroll the same distance felt like an empty
  // dead zone before the menu ever showed up; a store passing a shorter
  // value here gets straight to its products right after the welcome
  // text finishes its own fade (which always completes by scroll=300,
  // regardless of this value).
  final double totalScrollRange;

  const BurgerAssemblyWidget({
    Key? key,
    required this.scrollNotifier,
    this.height = 300,
    this.storeName,
    this.onAssembled,
    this.welcomeOpacityNotifier,
    this.showBurgerPieces = true,
    this.completionLabel = 'MASTERPIECE ASSEMBLED',
    this.totalScrollRange = 1080.0,
  }) : super(key: key);

  @override
  State<BurgerAssemblyWidget> createState() => _BurgerAssemblyWidgetState();
}

class _BurgerAssemblyWidgetState extends State<BurgerAssemblyWidget>
    with TickerProviderStateMixin {

  // 🎬 ANIMATION CONTROLLERS
  late AnimationController _breathingController;
  late AnimationController _shimmerController;
  late AnimationController _particleController;
  late AnimationController _lightRayController;  // 🆕 للشعاع

  // 📊 STATE MANAGEMENT
  double _assemblyProgress = 0.0;
  bool _isAssembled = false;
  late ValueNotifier<double> initialWelcomeOpacityNotifier;
  late List<double> _layerProgresses;
  late List<Particle> _particles;

  // 🎯 SCROLL CONFIGURATION
  final double _scrollRangePerLayer = 180.0;  // أقصر = أسرع
  final List<ScrollRange> _scrollRanges = [];
  double get _totalScrollRange => widget.totalScrollRange;  // default: 6 طبقات × 180px

  //  EXPLODED VIEW LAYERS
  final List<BurgerLayer> _layers = [
    // 1️⃣ Bottom Bun - ينفجر من الأسفل
    BurgerLayer(
      asset: 'assets/images/burger3D/bottom_bun.png',
      startAngle: math.pi / 2,  // من الأسفل
      explodeDistance: 400.0,
      glowColor: Color(0xFFFFD700),
      label: 'Golden Base',
      rotationMultiplier: 1.5,
      scaleStart: 0.5,
    ),
    // 2️⃣ Sauce - ينفجر من اليمين السفلي
    BurgerLayer(
      asset: 'assets/images/burger3D/sauce_layer.png',
      startAngle: math.pi / 3,  // يمين سفلي
      explodeDistance: 420.0,
      glowColor: Color(0xFFFF6347),
      label: 'Spicy Sauce',
      rotationMultiplier: -2.0,
      scaleStart: 0.4,
    ),
    // 3️⃣ Beef Patty - ينفجر من اليسار
    BurgerLayer(
      asset: 'assets/images/burger3D/beef_patty.png',
      startAngle: math.pi,  // من اليسار
      explodeDistance: 450.0,
      glowColor: Color(0xFF8B4513),
      label: 'Juicy Beef',
      rotationMultiplier: 2.5,
      scaleStart: 0.3,
    ),
    // 4️⃣ Cheese - ينفجر من اليمين
    BurgerLayer(
      asset: 'assets/images/burger3D/cheese_slice.png',
      startAngle: 0.0,  // من اليمين
      explodeDistance: 440.0,
      glowColor: Color(0xFFFFA500),
      label: 'Melted Cheese',
      rotationMultiplier: -1.8,
      scaleStart: 0.35,
    ),
    // 5️⃣ Lettuce - ينفجر من اليسار العلوي
    BurgerLayer(
      asset: 'assets/images/burger3D/lettuce.png',
      startAngle: -2 * math.pi / 3,  // يسار علوي
      explodeDistance: 460.0,
      glowColor: Color(0xFF90EE90),
      label: 'Fresh Lettuce',
      rotationMultiplier: 2.2,
      scaleStart: 0.4,
    ),
    // 6️⃣ Top Bun - ينفجر من الأعلى مع دوران كامل
    BurgerLayer(
      asset: 'assets/images/burger3D/top_bun.png',
      startAngle: -math.pi / 2,  // من الأعلى
      explodeDistance: 480.0,
      glowColor: Color(0xFFDAA520),
      label: 'Perfect Crown',
      rotationMultiplier: 1.2,  // 🆕 بطيء من 3.0
      scaleStart: 0.3,
    ),
  ];

  @override
  void initState() {
    super.initState();
    initialWelcomeOpacityNotifier = ValueNotifier<double>(1.0);
    _initializeScrollRanges();
    _initializeAnimations();
    _initializeParticles();
    widget.scrollNotifier.addListener(_handleScroll);
  }

  void _initializeScrollRanges() {
    for (int i = 0; i < _layers.length; i++) {
      _scrollRanges.add(ScrollRange(
        start: i * _scrollRangePerLayer,
        end: (i + 1) * _scrollRangePerLayer,
      ));
    }
  }

  void _initializeAnimations() {
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
    
    // 🆕 Light ray controller - بطيء وهادئ
    _lightRayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _layerProgresses = List.filled(_layers.length, 0.0);
  }

  void _initializeParticles() {
    final random = math.Random();
    _particles = List.generate(50, (i) => Particle(
      x: random.nextDouble() * 2 - 1,
      y: random.nextDouble() * 2 - 1,
      speed: 0.05 + random.nextDouble() * 0.1,
      size: 1.5 + random.nextDouble() * 3.5,
      color: _layers[random.nextInt(_layers.length)].glowColor,
      lifeShift: random.nextDouble(), // 🆕 توقيت خاص لكل نجمة
    ));
  }

  void _handleScroll() {
    final scroll = widget.scrollNotifier.value;
    
    // تحديث Welcome opacity
    if (scroll < 100) {
      initialWelcomeOpacityNotifier.value = 1.0;
    } else if (scroll < 300) {
      initialWelcomeOpacityNotifier.value = 1.0 - ((scroll - 100) / 200.0);
    } else {
      initialWelcomeOpacityNotifier.value = 0.0;
    }
    widget.welcomeOpacityNotifier?.value = initialWelcomeOpacityNotifier.value;

    // حساب progress كل طبقة
    bool changed = false;
    for (int i = 0; i < _layers.length; i++) {
      final range = _scrollRanges[i];
      double progress = 0.0;

      if (scroll <= range.start) {
        progress = 0.0;
      } else if (scroll >= range.end) {
        progress = 1.0;
      } else {
        final raw = (scroll - range.start) / (range.end - range.start);
        // استخدام curve قوي للـ exploded effect
        progress = Curves.easeOutBack.transform(raw);
      }

      if ((_layerProgresses[i] - progress).abs() > 0.01) {
        changed = true;
        _layerProgresses[i] = progress;
      }
    }

    if (changed && mounted) {
      setState(() {
        final avg = _layerProgresses.reduce((a, b) => a + b) / _layerProgresses.length;
        _assemblyProgress = avg.clamp(0.0, 1.0);
      });
    }

    // اكتمال البرغر
    if (scroll >= _totalScrollRange + 100 && !_isAssembled) {
      if (mounted) {
        setState(() => _isAssembled = true);
      }
      widget.onAssembled?.call();
    }
  }

  @override
  void dispose() {
    widget.scrollNotifier.removeListener(_handleScroll);
    initialWelcomeOpacityNotifier.dispose();
    _breathingController.dispose();
    _shimmerController.dispose();
    _particleController.dispose();
    _lightRayController.dispose();  // 🆕
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
          _buildBackground(),
          _buildParticleSystem(),
          
          if (_assemblyProgress <= 0.05) _buildInitialWelcomeText(),

          //  EXPLODED VIEW ASSEMBLY — burger pieces only; non-Food stores
          // still get the ambient glow/particles above and the welcome/
          // completion text around this, just not the burger PNGs.
          if (widget.showBurgerPieces) _buildExplodedView(),

          if (_isAssembled) _buildWelcomeToRestaurant(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final intensity = _assemblyProgress * 0.4;
        return Container(
          width: widget.height * 2.5,
          height: widget.height * 2.5,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Color(0xFF6366F1).withOpacity(0.15 * intensity),
                Color(0xFF8B5CF6).withOpacity(0.08 * intensity),
                Colors.transparent,
              ],
            ),
          ),
          child: CustomPaint(
            painter: BackgroundPainter(
              progress: _shimmerController.value,
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
      builder: (context, child) => CustomPaint(
        size: Size(widget.height * 2.5, widget.height * 2.5),
        painter: ParticlePainter(
          particles: _particles,
          progress: _particleController.value,
          assemblyProgress: _assemblyProgress,
        ),
      ),
    );
  }

  ///  EXPLODED VIEW - كل طبقة تنفجر وتتجمع
  Widget _buildExplodedView() {
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final breathScale = 1.0 + (math.sin(_breathingController.value * math.pi * 2) * 0.025);
        
        return Transform.scale(
          scale: breathScale * (1.0 + (_assemblyProgress * 0.12)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 🆕 Light ray behind burger - خفيف
              if (_assemblyProgress > 0.3)
                Opacity(
                  opacity: (_assemblyProgress * 0.3).clamp(0.0, 1.0),  // خفيف جداً
                  child: CustomPaint(
                    size: Size(widget.height * 2.5, widget.height * 2.5),
                    painter: LightRayPainter(
                      progress: _lightRayController.value,
                      intensity: _assemblyProgress * 0.4,  // خفيف
                      colors: _layers.map((l) => l.glowColor).toList(),
                    ),
                  ),
                ),
              
              // Burger layers
              ...List.generate(_layers.length, (i) => _buildExplodedLayer(i)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplodedLayer(int index) {
    final layer = _layers[index];
    final progress = _layerProgresses[index].clamp(0.0, 1.0);
    
    // 🎯 EXPLODED VIEW CALCULATION
    // في البداية: كل طبقة في مكانها المنفجر
    // مع الـ scroll: تتجمع في مكانها النهائي
    
    // المكان النهائي (stacked position)
    final stackOrder = _layers.length - 1 - index;
    final layerThickness = 16.0;
    final totalHeight = (_layers.length - 1) * layerThickness;
    final finalY = -(totalHeight / 2) + (stackOrder * layerThickness);
    
    // المكان الابتدائي (exploded position)
    final explodedX = math.cos(layer.startAngle) * layer.explodeDistance;
    final explodedY = math.sin(layer.startAngle) * layer.explodeDistance;
    
    // Interpolation من exploded إلى final
    final currentX = explodedX * (1 - progress);
    final currentY = explodedY * (1 - progress) + finalY * progress;
    
    // تأثيرات إضافية
    final rotation = layer.rotationMultiplier * math.pi * (1 - progress);  // دوران يقل تدريجياً
    final scale = layer.scaleStart + ((1.0 - layer.scaleStart) * progress);  // يكبر تدريجياً
    final opacity = progress < 0.1 ? progress * 10 : 1.0;
    
    // 3D Perspective
    final perspectiveValue = 0.002 * (1 - progress);  // يقل مع الاقتراب
    
    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, perspectiveValue)  // 3D perspective
          ..translate(currentX, currentY)
          ..rotateZ(rotation)
          ..rotateX((1 - progress) * 0.3)  // flip effect
          ..scale(scale),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glow effect قوي
            if (progress > 0.2 && progress < 0.95)
              Container(
                width: widget.height * 0.95,
                height: widget.height * 0.95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: layer.glowColor.withOpacity(0.25 * progress),
                      blurRadius: 35 * progress,
                      spreadRadius: 10 * progress,
                    )
                  ],
                ),
              ),
            
            // الصورة — every burger3D asset is a 1024x1024 PNG (~4MB
            // decoded, uncompressed) regardless of how small it's shown;
            // cacheWidth bounds the actual decoded bitmap to roughly what's
            // displayed instead of always paying for the full source
            // resolution. 6 layers load together on every single store
            // visit, so this adds up.
            Image.asset(
              layer.asset,
              width: widget.height * 1.5,
              cacheWidth: (widget.height * 1.5 * MediaQuery.of(context).devicePixelRatio).round(),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildInitialWelcomeText() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final double subtitleSize = isMobile ? 12 : 14;
    final double titleSize = isMobile ? 24 : 28;
    final double iconSize = isMobile ? 26 : 32;
    final double lineWidth = isMobile ? 120 : 180;
    final double spacing1 = isMobile ? 12 : 20;
    final double spacing2 = isMobile ? 16 : 30;
    final double letterSpacingSubtitle = isMobile ? 3 : 5;

    return ValueListenableBuilder<double>(
      valueListenable: initialWelcomeOpacityNotifier,
      builder: (context, opacity, _) => AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final shimmerOffset = (_shimmerController.value * 4.0) - 2.0;
          
          return AnimatedOpacity(
            opacity: opacity,
            duration: Duration(milliseconds: 300),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0), // 🆕 هوامش أمان للشاشات الصغيرة
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated subtitle
                  ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment(-1.0 + shimmerOffset, 0),
                        end: Alignment(1.0 + shimmerOffset, 0),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.9),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(bounds);
                    },
                    child: FittedBox( // 🆕 يمنع النص من النزول لسطر جديد
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'DISCOVER EXCELLENCE',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: letterSpacingSubtitle,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: spacing1),
                  
                  // Main animated welcome message with shimmer
                  ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment(-1.0 + shimmerOffset, 0),
                        end: Alignment(1.0 + shimmerOffset, 0),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.9),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(bounds);
                    },
                    child: FittedBox( // 🆕 السحر هنا
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Scroll Down to Explore',
                        maxLines: 1, // 🆕 إجبار النص على سطر واحد
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: spacing2),
                  
                  // Animated arrow
                  Transform.translate(
                    offset: Offset(0, math.sin(shimmerOffset * math.pi * 2) * 8),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: iconSize,
                      color: Color(0xFFFF6B35).withOpacity(0.8),
                    ),
                  ),
                  
                  SizedBox(height: 15),
                  
                  // Decorative shimmer line
                  Container(
                    width: lineWidth,
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      gradient: LinearGradient(
                        begin: Alignment(-1.0 + shimmerOffset, 0),
                        end: Alignment(1.0 + shimmerOffset, 0),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.9),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF6B35).withOpacity(0.5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeToRestaurant() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    
    final double titleSize = isMobile ? 28 : 40;
    final double subtitleSize = isMobile ? 9 : 12;
    final double letterSpacingSub = isMobile ? 3 : 5;

    return Positioned(
      bottom: -80,
      left: 0,
      right: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutBack,
        builder: (context, val, child) {
          final clampedVal = val.clamp(0.0, 1.0);
          return Transform.scale(
            scale: clampedVal,
            child: Opacity(
              opacity: clampedVal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox( // 🆕 إضافة FittedBox لاسم المطعم
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.storeName ?? "PARADISE",
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Color(0xFFFF6B35),
                              blurRadius: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    FittedBox( // 🆕 إضافة FittedBox للنص السفلي
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.completionLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'TenorSans',
                          color: Colors.white70,
                          letterSpacing: letterSpacingSub,
                          fontSize: subtitleSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

//  PAINTERS
class BackgroundPainter extends CustomPainter {
  final double progress, intensity;
  BackgroundPainter({required this.progress, required this.intensity});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final center = Offset(size.width / 2, size.height / 2);
    
    for (int i = 0; i < 7; i++) {
      final phase = (progress + (i * 0.14));
      final offset = (math.sin(phase * math.pi * 2) * 0.5) + 0.5;
      final radius = size.width * 0.18 + (i * size.width * 0.11) + (offset * size.width * 0.13);
      paint.color = Color(0xFF8B5CF6).withOpacity(
        ((1 - offset) * intensity * 0.18).clamp(0.0, 1.0),
      );
      canvas.drawCircle(center, radius, paint);
    }
  }
  
  @override
  bool shouldRepaint(BackgroundPainter old) => true;
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
    
    if (particles.isEmpty) return;
    
    for (var p in particles) {
      // 🧠 كل نجمة لها دورة حياة مستقلة
      final double progressSafe = progress ?? 0.0;
      final double lifeShiftSafe = p.lifeShift ?? 0.0;
      double t = (progressSafe + lifeShiftSafe) % 1.0;

      // 1️⃣ حساب الشفافية (Fade In/Out)
      double opacity = 0.0;
      if (t < 0.2) {
        opacity = t * 5;
      } else if (t > 0.8) {
        opacity = (1.0 - t) * 5;
      } else {
        opacity = 1.0;
      }
      
      opacity *= (0.6 + (assemblyProgress ?? 0.0) * 0.4);

      // 2️⃣ الحركة - دوران بطيء جداً في دائرة حول البرغر
      final speedSafe = p.speed ?? 0.2;
      final angle = (p.x * math.pi * 2) + (t * speedSafe * math.pi * 0.4);
      final radius = (size.width * 0.4) + (p.y * 20);
      
      final dx = math.cos(angle) * radius;
      final dy = math.sin(angle) * radius;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (p.size ?? 1.0) * 0.5);

      // رسم النجمة
      canvas.drawCircle(
        Offset(
          center.dx + dx,
          center.dy + dy,
        ),
        p.size ?? 1.0,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter old) => true;
}
// 🆕 Light Ray Painter - شعاع خفيف خلف البرغر
class LightRayPainter extends CustomPainter {
  final double progress;
  final double intensity;
  final List<Color> colors;

  LightRayPainter({
    required this.progress,
    required this.intensity,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16);

    for (int i = 0; i < 8; i++) {
      // 🆕 دوران بطيء جداً جداً - نقاط هادئة وأنيقة
      final angle = (i / 8) * math.pi * 2 + progress * math.pi * 0.15;
      final length = size.width * 0.32 * math.max(0.2, intensity);
      
      final gradient = RadialGradient(
        colors: [
          colors[i % colors.length].withOpacity(0.15 * intensity),
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
// 📦 MODELS
class ScrollRange {
  final double start;
  final double end;
  
  ScrollRange({required this.start, required this.end});
}

class BurgerLayer {
  final String asset;
  final double startAngle;  // زاوية البداية بالـ radians
  final double explodeDistance;  // مسافة الانفجار
  final Color glowColor;
  final String label;
  final double rotationMultiplier;  // مضاعف الدوران
  final double scaleStart;  // حجم البداية
  
  BurgerLayer({
    required this.asset,
    required this.startAngle,
    required this.explodeDistance,
    required this.glowColor,
    required this.label,
    required this.rotationMultiplier,
    required this.scaleStart,
  });
}

class Particle {
  final double x, y; // الموقع
  final double speed; // السرعة
  final double size; // الحجم
  final Color color; // اللون
  final double lifeShift; // 🆕 توقيت خاص لكل نجمة (Phase Shift)
  
  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.lifeShift,
  });
}