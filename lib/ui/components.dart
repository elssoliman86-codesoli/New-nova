import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import '../data/models.dart';
import 'glass.dart';
import 'neu.dart';

/// Page frame: safe-area aware header (back button, title, actions) and a
/// body. Pages are transparent so the shared ambient background shows.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.showBack,
    this.floating,
    this.resizeForKeyboard = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Defaults to true when the page can be popped.
  final bool? showBack;
  final Widget body;

  /// Optional widget pinned above the bottom (for example a primary button).
  final Widget? floating;
  final bool resizeForKeyboard;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final back = showBack ?? canPop;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: resizeForKeyboard,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NovaLayout.pagePad - 4,
                NovaSpace.md,
                NovaLayout.pagePad,
                NovaSpace.sm,
              ),
              child: Row(
                children: [
                  if (back)
                    Padding(
                      padding: const EdgeInsets.only(right: NovaSpace.sm),
                      child: NeuIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    )
                  else
                    const SizedBox(width: NovaSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaType.caption,
                          ),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaType.title,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.only(left: NovaSpace.sm),
                      child: action,
                    ),
                ],
              ),
            ),
            Expanded(child: body),
            if (floating != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  NovaLayout.pagePad,
                  NovaSpace.sm,
                  NovaLayout.pagePad,
                  math.max(MediaQuery.of(context).padding.bottom, NovaSpace.lg),
                ),
                child: floating,
              ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, NovaSpace.xl, 4, NovaSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: NovaType.headline),
            ),
          ),
          if (actionLabel != null)
            Pressable(
              onTap: onAction,
              semanticLabel: actionLabel,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: NovaLayout.minTap),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    actionLabel!,
                    style: NovaType.label.copyWith(color: NovaColors.accent2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small selectable pill (filters, durations).
class NovaChip extends StatelessWidget {
  const NovaChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? NovaColors.accent2;
    final duration = motionDuration(context, NovaDurations.fast);
    final chip = AnimatedContainer(
      duration: duration,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NovaRadius.pill),
        color: selected ? accent.withValues(alpha: 0.16) : NovaColors.white(0.04),
        border: Border.all(
          color: selected ? accent.withValues(alpha: 0.5) : NovaColors.white(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: selected ? accent : NovaColors.textDim),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: NovaType.label.copyWith(
              color: selected ? accent : NovaColors.textDim,
            ),
          ),
        ],
      ),
    );

    // The visible chip is 36px; the tap target is padded to 44px.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: chip,
        ),
      ),
    );
  }
}

Color priorityColor(Priority priority) {
  switch (priority) {
    case Priority.low:
      return NovaColors.textDim;
    case Priority.medium:
      return NovaColors.accent;
    case Priority.high:
      return NovaColors.warning;
  }
}

class PriorityDot extends StatelessWidget {
  const PriorityDot({super.key, required this.priority, this.size = 8});

  final Priority priority;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: priority == Priority.high
            ? NovaShadows.glow(color, alpha: 0.5, blur: 6)
            : null,
      ),
    );
  }
}

/// Row for a task. Uses a solid glass surface (no blur) because lists can
/// contain many of these.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onTap,
    this.onLongPress,
  });

  final TaskItem task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = !task.done && task.due != null && isOverdue(task.due!, now);
    final dueColor = overdue ? NovaColors.danger : NovaColors.textDim;

    final meta = <Widget>[
      PriorityDot(priority: task.priority, size: 7),
      const SizedBox(width: 6),
      Text(task.priority.label, style: NovaType.caption),
      if (task.due != null) ...[
        const SizedBox(width: 10),
        Icon(Icons.event_rounded, size: 13, color: dueColor),
        const SizedBox(width: 4),
        Text(
          formatDue(task.due, now: now),
          style: NovaType.caption.copyWith(color: dueColor),
        ),
      ],
      if (task.focusMinutes > 0) ...[
        const SizedBox(width: 10),
        const Icon(Icons.timer_outlined, size: 13, color: NovaColors.textDim),
        const SizedBox(width: 4),
        Text(formatMinutes(task.focusMinutes), style: NovaType.caption),
      ],
    ];

    return Pressable(
      pressedScale: 0.985,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: '${task.title}, ${task.done ? 'completed' : 'open'}',
      child: GlassSurface.solid(
        radius: NovaRadius.md,
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        child: Row(
          children: [
            NeuCheck(
              checked: task.done,
              onChanged: onToggle,
              semanticLabel: task.done ? 'Mark as open' : 'Mark as done',
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: motionDuration(context, NovaDurations.base),
                      style: NovaType.bodyStrong.copyWith(
                        color: task.done ? NovaColors.textDim : NovaColors.text,
                        decoration:
                            task.done ? TextDecoration.lineThrough : TextDecoration.none,
                        decorationColor: NovaColors.textDim,
                      ),
                      child: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(children: meta),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: NovaColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Compact metric card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.color = NovaColors.accent2,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      child: ExcludeSemantics(
        child: GlassSurface.solid(
          radius: NovaRadius.md,
          padding: const EdgeInsets.all(NovaSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaType.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NovaSpace.md),
              Text(value, style: NovaType.metric),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.caption.copyWith(color: NovaColors.textFaint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular progress. The arc eases to new values.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 96,
    this.strokeWidth = 9,
    this.child,
    this.color = NovaColors.accent2,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final Widget? child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final target = clampDouble(progress, 0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: motionDuration(context, const Duration(milliseconds: 600)),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RingPainter(value, strokeWidth, color),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress, this.strokeWidth, this.color);

  final double progress;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = NovaColors.white(0.07);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [NovaColors.accent, color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.strokeWidth != strokeWidth;
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 56});

  final String name;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Avatar for $name',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [NovaColors.accent2, NovaColors.accentDeep],
            ),
            border: Border.all(color: NovaColors.white(0.25)),
            boxShadow: NovaShadows.glow(NovaColors.accent, alpha: 0.3),
          ),
          child: Text(
            _initials,
            style: NovaType.headline.copyWith(
              color: Colors.white,
              fontSize: size * 0.36,
            ),
          ),
        ),
      ),
    );
  }
}

/// Row used in Settings and Profile. Pass [trailing] for a toggle or value;
/// without it a chevron is shown when [onTap] is set.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color = NovaColors.accent2,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? NovaColors.danger : color;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NovaSpace.lg, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NovaRadius.sm - 2),
                color: tint.withValues(alpha: 0.14),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: NovaSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: NovaType.bodyStrong.copyWith(
                      color: danger ? NovaColors.danger : NovaColors.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: NovaType.caption),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20, color: NovaColors.textFaint),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Pressable(
      pressedScale: 0.99,
      onTap: onTap,
      semanticLabel: title,
      child: row,
    );
  }
}

/// A group of rows on one glass card with hairline dividers.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(Divider(
          height: 1,
          thickness: 1,
          indent: 64,
          color: NovaColors.white(0.06),
        ));
      }
      items.add(children[i]);
    }
    return GlassSurface.solid(
      radius: NovaRadius.lg,
      child: Column(children: items),
    );
  }
}

/// Bottom padding a scrolling tab page needs so content clears the floating
/// navigation bar and the system gesture area.
double navClearance(BuildContext context) {
  return NovaLayout.navReserve + MediaQuery.of(context).padding.bottom;
}

/// Fades and slides a child in once. Skipped when motion is reduced.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (UiPrefs.motionReduced(context)) return child;
    final total = const Duration(milliseconds: 420) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: child,
    );
  }
}
