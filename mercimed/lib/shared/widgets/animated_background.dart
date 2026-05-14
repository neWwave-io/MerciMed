import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final bool showBlobs;

  const AnimatedBackground({
    required this.child,
    this.showBlobs = false,
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
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _gradient = CurvedAnimation(parent: _gradientCtrl, curve: Curves.easeInOut);

    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
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
    return AnimatedBuilder(
      animation: _gradient,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                const Color(0xFFF5FAF8),
                const Color(0xFFEBF3EF),
                _gradient.value,
              )!,
              Color.lerp(
                AppTheme.background,
                const Color(0xFFB5C9C5),
                _gradient.value * 0.6,
              )!,
            ],
          ),
        ),
        child: child,
      ),
      child: widget.showBlobs
          ? Stack(
              children: [
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
                widget.child,
              ],
            )
          : widget.child,
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

    // Three slow-drifting orbs at different depths.
    _blob(
      canvas,
      Offset(
        w * 0.18 + math.sin(t * 2 * math.pi) * 18,
        h * 0.16 + math.cos(t * 2 * math.pi) * 14,
      ),
      radius: w * 0.55,
      color: const Color(0xFF9FC5BE).withValues(alpha: 0.45),
    );
    _blob(
      canvas,
      Offset(
        w * 1.05 + math.cos(t * 2 * math.pi + 1) * 20,
        h * 0.42 + math.sin(t * 2 * math.pi + 1) * 22,
      ),
      radius: w * 0.7,
      color: const Color(0xFF7FB3AC).withValues(alpha: 0.32),
    );
    _blob(
      canvas,
      Offset(
        w * 0.25 + math.sin(t * 2 * math.pi + 2) * 26,
        h * 1.05 + math.cos(t * 2 * math.pi + 2) * 18,
      ),
      radius: w * 0.75,
      color: const Color(0xFFC4DDD7).withValues(alpha: 0.55),
    );
  }

  void _blob(Canvas canvas, Offset center,
      {required double radius, required Color color}) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobsPainter old) => old.t != t;
}
