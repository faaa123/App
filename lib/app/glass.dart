import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Static deep backdrop with soft color glows, so translucent "glass"
/// surfaces have something to show through. Painted once (RepaintBoundary).
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  static const base = Color(0xFF0A0D1C);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(color: base),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Glow(Alignment(-0.9, -0.8), Color(0xFF3D4BD6), 0.9),
                _Glow(Alignment(1.0, -0.3), Color(0xFF0E8F95), 0.7),
                _Glow(Alignment(0.2, 1.1), Color(0xFF7A3FC0), 0.8),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.center, this.color, this.radius);

  final Alignment center;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: center,
        radius: radius,
        colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0)],
      ),
    ),
  );
}

/// Translucent glass surface: tinted fill, a light rim and a soft specular
/// highlight. With [blur] it also frosts what scrolls underneath (costlier;
/// use only on small floating chrome).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.tint,
    this.blur = false,
    this.padding,
  });

  final Widget child;
  final double radius;

  /// Fill color; defaults to a faint white.
  final Color? tint;
  final bool blur;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    // Fill first, then rim + highlight (a BoxDecoration ignores its color
    // when it also has a gradient).
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: tint ?? Colors.white.withValues(alpha: 0.07),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0, 0.45],
          ),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
    if (!blur) return surface;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: surface,
      ),
    );
  }
}
