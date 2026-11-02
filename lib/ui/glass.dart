import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/ui_prefs.dart';

/// A frosted glass panel: background blur, a faint white fill, a thin
/// light-catching edge and a soft ambient shadow.
///
/// Blur is the expensive part, so use [blurred] = false (or
/// [GlassSurface.solid]) for items repeated in lists. When the user turns on
/// "Reduce blur" every surface falls back to an opaque tint automatically.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = NovaRadius.lg,
    this.padding,
    this.blur = 18,
    this.blurred = true,
    this.elevated = true,
    this.fill,
  });

  /// Glass without blur, for list items and other repeated elements.
  const GlassSurface.solid({
    super.key,
    required this.child,
    this.radius = NovaRadius.lg,
    this.padding,
    this.elevated = false,
    this.fill,
  })  : blur = 0,
        blurred = false;

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final bool blurred;
  final bool elevated;

  /// Overrides the fill colour (sheets and dialogs use a denser tint).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final reduced = UiPrefs.blurReduced(context);
    final useBlur = blurred && !reduced && blur > 0;
    final borderRadius = BorderRadius.circular(radius);

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: fill ?? (useBlur ? NovaColors.glassFill : NovaColors.glassSolid),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NovaColors.white(useBlur ? 0.07 : 0.045),
            NovaColors.white(0),
          ],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (useBlur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.mirror,
        ),
        child: content,
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: elevated ? NovaShadows.floating : null,
        ),
        child: CustomPaint(
          foregroundPainter: _GlassEdgePainter(radius),
          child: ClipRRect(borderRadius: borderRadius, child: content),
        ),
      ),
    );
  }
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(bounds, Radius.circular(radius)).deflate(0.5);

    // Thin edge: brighter at the top-left where light would hit the glass.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          NovaColors.white(0.26),
          NovaColors.white(0.06),
          NovaColors.white(0.12),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(bounds);
    canvas.drawRRect(rrect, edge);

    // Soft highlight along the top edge.
    final lineWidth = math.max(0.0, size.width - radius * 2);
    if (lineWidth > 0) {
      final line = Rect.fromLTWH(radius, 0.5, lineWidth, 1);
      final highlight = Paint()
        ..shader = LinearGradient(
          colors: [
            NovaColors.white(0),
            NovaColors.white(0.22),
            NovaColors.white(0),
          ],
        ).createShader(line);
      canvas.drawRect(line, highlight);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter oldDelegate) =>
      oldDelegate.radius != radius;
}
