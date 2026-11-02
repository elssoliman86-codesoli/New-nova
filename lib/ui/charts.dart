import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import '../data/models.dart';

/// Seven-day bar chart with a dashed daily goal line. Bars grow once when the
/// chart appears; nothing animates afterwards.
class WeekBarChart extends StatelessWidget {
  const WeekBarChart({
    super.key,
    required this.days,
    required this.goal,
    this.height = 170,
  });

  final List<DayValue> days;
  final int goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final duration = UiPrefs.motionReduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 700);

    final total = days.fold<int>(0, (sum, d) => sum + d.value);
    final summary = 'Focus time over the last ${days.length} days: '
        '${formatMinutes(total)} in total. Daily goal ${formatMinutes(goal)}.';

    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            return SizedBox(
              height: height,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WeekPainter(days: days, goal: goal, t: t),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeekPainter extends CustomPainter {
  const _WeekPainter({required this.days, required this.goal, required this.t});

  final List<DayValue> days;
  final int goal;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const labelHeight = 22.0;
    final chartHeight = size.height - labelHeight;
    var maxValue = goal.toDouble();
    for (final d in days) {
      if (d.value > maxValue) maxValue = d.value.toDouble();
    }
    maxValue = maxValue * 1.15;
    if (maxValue <= 0) maxValue = 1;

    final slot = size.width / days.length;
    final barWidth = clampTo(slot * 0.46, 10.0, 30.0);
    final today = DateTime.now();

    final trackPaint = Paint()..color = NovaColors.white(0.05);
    final barPaint = Paint();
    final goalLine = Paint()
      ..color = NovaColors.accent2.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final cx = slot * i + slot / 2;
      final isToday = isSameDay(day.day, today);

      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barWidth / 2, 0, barWidth, chartHeight),
        const Radius.circular(8),
      );
      canvas.drawRRect(track, trackPaint);

      final h = chartHeight * (day.value / maxValue) * t;
      if (h > 0.5) {
        final bar = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barWidth / 2, chartHeight - h, barWidth, h),
          const Radius.circular(8),
        );
        barPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isToday
              ? const [NovaColors.accent2, NovaColors.accent]
              : [
                  NovaColors.accent.withValues(alpha: 0.75),
                  NovaColors.accentDeep.withValues(alpha: 0.75),
                ],
        ).createShader(bar.outerRect);
        canvas.drawRRect(bar, barPaint);
      }

      final label = TextPainter(
        text: TextSpan(
          text: weekdayShort(day.day),
          style: NovaType.micro.copyWith(
            color: isToday ? NovaColors.accent2 : NovaColors.textDim,
            fontFamily: 'Inter',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(cx - label.width / 2, chartHeight + 6));
    }

    // Dashed goal line.
    final goalY = chartHeight - chartHeight * (goal / maxValue);
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, goalY), Offset(clampTo(x + 5, 0, size.width), goalY), goalLine);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _WeekPainter old) =>
      old.t != t || old.goal != goal || old.days != days;
}
