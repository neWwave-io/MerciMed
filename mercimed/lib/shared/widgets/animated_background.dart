import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Soft sky→mint diagonal gradient with large, heavily blurred gradient
/// "bubbles" that drift across the screen for ambient depth.
///
/// Base gradient (170deg): #e6f0f5 0% → #d4e6df 55% → #cce0d6 100%
class AnimatedBackground extends StatefulWidget {
  final Widget child;

  /// Retained for source compatibility; bubbles are always rendered.
  final bool showBlobs;

  const AnimatedBackground({
    required this.child,
    this.showBlobs = true,
    super.key,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  late final AnimationController _gradientCtrl;
  late final AnimationController _blobCtrl;
  late final Animation<double> _gradient;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    _gradient = CurvedAnimation(parent: _gradientCtrl, curve: Curves.easeInOut);

    // Long, slow cycle so bubbles drift like clouds.
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    _blobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _gradient,
            builder: (_, _) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(0.17, -1),
                    end: const Alignment(-0.17, 1),
                    stops: const [0.0, 0.55, 1.0],
                    colors: [
                      Color.lerp(
                        const Color(0xFFE6F0F5),
                        const Color(0xFFEAF2F5),
                        _gradient.value,
                      )!,
                      Color.lerp(
                        const Color(0xFFD4E6DF),
                        const Color(0xFFD9E8E2),
                        _gradient.value,
                      )!,
                      Color.lerp(
                        const Color(0xFFCCE0D6),
                        const Color(0xFFD0E2DA),
                        _gradient.value,
                      )!,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Flying gradient bubbles
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _blobCtrl,
              builder: (_, _) => CustomPaint(
                painter: _BubblesPainter(t: _blobCtrl.value),
              ),
            ),
          ),
        ),
        // Content
        widget.child,
      ],
    );
  }
}

class _Bubble {
  /// Two color pairs (inner, outer). The painter lerps between palette A
  /// and palette B over the animation cycle so the blue subtly shifts.
  final List<Color> paletteA;
  final List<Color> paletteB;
  final double radiusFactor; // relative to screen width
  final double cxBase; // 0..1
  final double cyBase; // 0..1
  final double cxAmp; // 0..1
  final double cyAmp; // 0..1
  final double speed; // cycles per full controller cycle
  final double phase;

  const _Bubble({
    required this.paletteA,
    required this.paletteB,
    required this.radiusFactor,
    required this.cxBase,
    required this.cyBase,
    required this.cxAmp,
    required this.cyAmp,
    required this.speed,
    required this.phase,
  });
}

class _BubblesPainter extends CustomPainter {
  final double t;
  _BubblesPainter({required this.t});

  static const List<_Bubble> _bubbles = [
    // Sky blue ↔ periwinkle · top-right
    _Bubble(
      paletteA: [Color(0xFFA8C8E6), Color(0xFFC4DCEE)],
      paletteB: [Color(0xFFB7C9EA), Color(0xFFCBD7F0)],
      radiusFactor: 0.85,
      cxBase: 0.85,
      cyBase: 0.05,
      cxAmp: 0.35,
      cyAmp: 0.12,
      speed: 1.0,
      phase: 0.0,
    ),
    // Periwinkle ↔ pale teal-blue · top-left
    _Bubble(
      paletteA: [Color(0xFFB6CFEA), Color(0xFFD4E4F2)],
      paletteB: [Color(0xFFA5C4DD), Color(0xFFCAE0EC)],
      radiusFactor: 0.95,
      cxBase: 0.10,
      cyBase: 0.10,
      cxAmp: 0.40,
      cyAmp: 0.15,
      speed: 0.85,
      phase: 1.4,
    ),
    // Slate blue ↔ soft cornflower · top-center
    _Bubble(
      paletteA: [Color(0xFF9FBDDC), Color(0xFFCBDDEE)],
      paletteB: [Color(0xFF8FB3D8), Color(0xFFB9D0E8)],
      radiusFactor: 0.75,
      cxBase: 0.55,
      cyBase: 0.22,
      cxAmp: 0.30,
      cyAmp: 0.18,
      speed: 1.15,
      phase: 2.6,
    ),
    // Ice blue ↔ powder blue · upper-mid
    _Bubble(
      paletteA: [Color(0xFFC8DEEE), Color(0xFFAFCAE3)],
      paletteB: [Color(0xFFB8D3EA), Color(0xFFA0BDDD)],
      radiusFactor: 0.70,
      cxBase: 0.30,
      cyBase: 0.30,
      cxAmp: 0.30,
      cyAmp: 0.20,
      speed: 0.7,
      phase: 3.9,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Heavy global blur on the bubble layer for that soft "glow" feel.
    final blurredLayer = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 90,
        sigmaY: 90,
        tileMode: TileMode.decal,
      );
    canvas.saveLayer(Offset.zero & size, blurredLayer);

    for (final b in _bubbles) {
      final angle = t * 2 * math.pi * b.speed + b.phase;
      final cx = (b.cxBase + math.sin(angle) * b.cxAmp) * w;
      final cy = (b.cyBase + math.cos(angle * 0.85 + b.phase) * b.cyAmp) * h;
      final radius = w * b.radiusFactor;

      // Animated color blend — independent phase per bubble so the palette
      // shimmers asynchronously across the screen.
      final blend = 0.5 + 0.5 * math.sin(t * 2 * math.pi + b.phase * 0.7);
      final inner = Color.lerp(b.paletteA[0], b.paletteB[0], blend)!;
      final outer = Color.lerp(b.paletteA[1], b.paletteB[1], blend)!;

      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

      // Multi-stop radial gradient = the "gradient bubble" feel.
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            inner.withValues(alpha: 0.40),
            outer.withValues(alpha: 0.22),
            outer.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect);

      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BubblesPainter old) => old.t != t;
}
