import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatefulWidget {
  final double size;
  const BrandMark({this.size = 72, super.key});

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s + 28,
      height: s + 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft pulsing ring
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final v = _ctrl.value;
              final scale = 1 + v * 0.35;
              final opacity = (1 - v) * 0.45;
              return Container(
                width: s * scale,
                height: s * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.teal.withValues(alpha: opacity),
                    width: 1.2,
                  ),
                ),
              );
            },
          ),
          // Outer static ring
          Container(
            width: s + 12,
            height: s + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.teal.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
          ),
          // Monogram squircle
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s * 0.32),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFE8F2EF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.teal.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.7),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Center(
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.teal, AppTheme.primaryDark],
                ).createShader(rect),
                child: Text(
                  'm',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s * 0.5,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -1.5,
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
