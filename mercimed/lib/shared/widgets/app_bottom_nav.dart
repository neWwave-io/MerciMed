import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    const pillH = 64.0;
    const fabSize = 52.0;
    const fabLift = 18.0; // how much FAB rises above pill top
    // Tuck the pill closer to the bottom edge — overlap into the safe area
    // a bit since the floating pill itself reads as the "edge" UI.
    final navBottom = (bottomPad - 18).clamp(6.0, 80.0);

    return SizedBox(
      height: pillH + fabLift + navBottom + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Floating glass pill (with notch around MERCI) ─────
          Positioned(
            left: 20,
            right: 20,
            bottom: navBottom,
            height: pillH,
            child: _NotchedGlassPill(
              cornerRadius: 40,
              notchRadius: fabSize / 2 + 4,
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: 'HOME',
                      isActive: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                  ),
                  // Centre gap reserved for FAB
                  const SizedBox(width: fabSize + 20),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person_rounded,
                      label: 'PROFILE',
                      isActive: currentIndex == 2,
                      onTap: () => onTap(2),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Elevated FAB (MERCIE) ─────────────────────────────
          Positioned(
            bottom: navBottom + (pillH - fabSize) / 2 + fabLift / 2,
            left: 0,
            right: 0,
            child: Center(
              child: _MercieButton(
                size: fabSize,
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── MERCI (AI) button ───────────────────────────────────────────────────────

class _MercieButton extends StatefulWidget {
  final double size;
  final bool isActive;
  final VoidCallback onTap;

  const _MercieButton({
    required this.size,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_MercieButton> createState() => _MercieButtonState();
}

class _MercieButtonState extends State<_MercieButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // AI-feeling palette: brand teal → deep navy → a hint of violet.
  static const _gradColors = [
    Color(0xFF3DA39A), // bright teal highlight
    Color(0xFF2D6B6B), // brand teal
    Color(0xFF1A2E35), // brand primaryDark
    Color(0xFF2A2150), // violet hint for the AI vibe
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final isActive = widget.isActive;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              // Breathing 0 → 1 → 0 via sine for smooth ease in/out.
              final t = (math.sin(_ctrl.value * math.pi * 2) + 1) / 2;
              final haloAlpha = (isActive ? 0.55 : 0.36) * (0.55 + 0.45 * t);
              final innerHaloAlpha = (isActive ? 0.85 : 0.55) * (0.6 + 0.4 * t);
              final sparkleAlpha = 0.55 + 0.45 * t;

              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Outer soft halo (animated) — shadows extend naturally
                    // beyond the box bounds via the parent's Clip.none stack.
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3DA39A)
                                .withValues(alpha: haloAlpha * 0.5),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: const Color(0xFF7B5BE8)
                                .withValues(alpha: haloAlpha * 0.45),
                            blurRadius: 22,
                            spreadRadius: -1,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: AppTheme.primaryDark
                                .withValues(alpha: innerHaloAlpha * 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                    // Gradient orb with thin highlight ring.
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _gradColors,
                          stops: [0.0, 0.42, 0.78, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 24,
                          shadows: [
                            Shadow(
                              color: Color(0x66FFFFFF),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Tiny twinkling sparkle accent (top-right of orb).
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Opacity(
                        opacity: sparkleAlpha,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Colors.white, Color(0xFFB8E8E0)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white
                                    .withValues(alpha: 0.9 * sparkleAlpha),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (rect) {
              final base = isActive
                  ? const [Color(0xFF2D6B6B), Color(0xFF7B5BE8)]
                  : [AppTheme.muted, AppTheme.muted];
              return LinearGradient(
                colors: base,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(rect);
            },
            child: const Text(
              'MERCI',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Colors.white, // Replaced by ShaderMask.
              ),
            ),
          ),
          if (isActive)
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: AppTheme.teal,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ── Notched glass pill ──────────────────────────────────────────────────────

class _NotchedGlassPill extends StatelessWidget {
  final double notchRadius;
  final double cornerRadius;
  final Widget child;

  const _NotchedGlassPill({
    required this.notchRadius,
    required this.cornerRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final shape = _NotchedPillBorder(
          cornerRadius: cornerRadius,
          notchRadius: notchRadius,
          notchCenterX: constraints.maxWidth / 2,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.7),
            width: 1,
          ),
        );
        final shadowShape = shape.copyWith(side: BorderSide.none);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Soft drop shadow (outside the clip).
            DecoratedBox(
              decoration: ShapeDecoration(
                shape: shadowShape,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
            // Glass blur + translucent fill, clipped to the notched shape.
            ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: Colors.white.withValues(alpha: 0.55),
                  child: child,
                ),
              ),
            ),
            // Hairline border drawn on top — outside the clip so the notch
            // edge gets a clean outline too.
            IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(shape: shape),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NotchedPillBorder extends OutlinedBorder {
  final double cornerRadius;
  final double notchRadius;
  final double notchCenterX;

  const _NotchedPillBorder({
    required this.cornerRadius,
    required this.notchRadius,
    required this.notchCenterX,
    super.side,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _buildPath(Rect rect) {
    final cx = rect.left + notchCenterX;
    final rounded = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
      );
    final notch = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx, rect.top),
          radius: notchRadius,
        ),
      );
    return Path.combine(PathOperation.difference, rounded, notch);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect.deflate(side.width));

  @override
  ShapeBorder scale(double t) => _NotchedPillBorder(
        cornerRadius: cornerRadius * t,
        notchRadius: notchRadius * t,
        notchCenterX: notchCenterX * t,
        side: side.scale(t),
      );

  @override
  _NotchedPillBorder copyWith({BorderSide? side}) => _NotchedPillBorder(
        cornerRadius: cornerRadius,
        notchRadius: notchRadius,
        notchCenterX: notchCenterX,
        side: side ?? this.side,
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final paint = Paint()
      ..color = side.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width;
    canvas.drawPath(_buildPath(rect), paint);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isActive ? activeIcon : icon,
            size: 22,
            color: isActive ? AppTheme.primaryDark : AppTheme.muted,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: isActive ? AppTheme.primaryDark : AppTheme.muted,
            ),
          ),
          if (isActive)
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: AppTheme.teal,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}
