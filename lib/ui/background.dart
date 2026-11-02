import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// Midnight gradient with two very soft light pools. Painted once and never
/// animated, so it costs nothing while scrolling. It sits behind the whole
/// navigator; glass surfaces blur it.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [NovaColors.bg, NovaColors.bg2],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    _glow(
      canvas,
      Offset(size.width * 0.92, size.height * 0.06),
      size.width * 0.85,
      NovaColors.accent,
      0.16,
    );
    _glow(
      canvas,
      Offset(size.width * 0.05, size.height * 0.88),
      size.width * 0.75,
      NovaColors.accent2,
      0.07,
    );
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
