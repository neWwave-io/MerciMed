import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft sky→mint diagonal gradient with three ambient radial blobs layered
/// on top for depth. Used as the global page background.
///
/// Spec (170deg): #e6f0f5 0% → #d4e6df 55% → #cce0d6 100%
/// Blobs: light blue top-right, soft mint bottom-left, mint bottom-center.
class AnimatedBackground extends StatefulWidget {
  final Widget child;

  /// Retained for source compatibility; no longer required. Blobs are part
  /// of the gradient spec now and always render.
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

    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
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
                  // ~170deg: nearly top→bottom with a slight leftward tilt.
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
        // Ambient radial blobs
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _blobCtrl,
              builder: (_, _) => CustomPaint(
                painter: _BlobsPainter(t: _blobCtrl.value),
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

class _BlobsPainter extends CustomPainter {
  final double t;
  _BlobsPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final phase = t * 2 * math.pi;

    // Light blue · top-right
    _blob(
      canvas,
      Offset(
        w * 0.92 + math.sin(phase) * 14,
        h * 0.10 + math.cos(phase) * 12,
      ),
      radius: w * 0.62,
      color: const Color(0xFFC9DEE8).withValues(alpha: 0.55),
    );

    // Soft mint · bottom-left
    _blob(
      canvas,
      Offset(
        w * 0.05 + math.cos(phase + 1.1) * 16,
        h * 0.92 + math.sin(phase + 1.1) * 14,
      ),
      radius: w * 0.65,
      color: const Color(0xFFBED8CD).withValues(alpha: 0.50),
    );

    // Mint · bottom-center
    _blob(
      canvas,
      Offset(
        w * 0.50 + math.sin(phase + 2.2) * 20,
        h * 1.02 + math.cos(phase + 2.2) * 14,
      ),
      radius: w * 0.70,
      color: const Color(0xFFC2DAD0).withValues(alpha: 0.55),
    );
  }

  void _blob(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobsPainter old) => old.t != t;
}
