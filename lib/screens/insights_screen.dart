import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../ui/charts.dart';
import '../ui/components.dart';
import '../ui/glass.dart';

/// Weekly focus chart, completion and goal rings, and key numbers.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final goal = store.settings.dailyGoalMinutes;
    final week = store.focusByDay(7);
    final weekTotal = week.fold<int>(0, (sum, d) => sum + d.value);
    final completion = store.completionRate;
    final todayMinutes = store.focusMinutesToday;
    final goalProgress = goal <= 0 ? 0.0 : todayMinutes / goal;
    final doneTasks = store.tasks.where((t) => t.done).length;

    return ScreenScaffold(
      showBack: false,
      title: 'Insights',
      subtitle: 'Last 7 days',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          navClearance(context),
        ),
        children: [
          FadeIn(
            child: GlassSurface(
              radius: NovaRadius.xl,
              padding: const EdgeInsets.all(NovaSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Focus time', style: NovaType.caption),
                            const SizedBox(height: 2),
                            Text(formatMinutes(weekTotal), style: NovaType.metric),
                          ],
                        ),
                      ),
                      Text(
                        'Goal ${formatMinutes(goal)} / day',
                        style: NovaType.caption.copyWith(color: NovaColors.accent2),
                      ),
                    ],
                  ),
                  const SizedBox(height: NovaSpace.xl),
                  WeekBarChart(days: week, goal: goal),
                  if (weekTotal == 0) ...[
                    const SizedBox(height: NovaSpace.md),
                    const Text(
                      'Start a focus session and your week will show up here.',
                      style: NovaType.caption,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: NovaSpace.lg),
          FadeIn(
            delay: const Duration(milliseconds: 60),
            child: IntrinsicHeight(child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _RingCard(
                    label: 'Completion',
                    caption: '$doneTasks of ${store.tasks.length} tasks',
                    progress: completion,
                  ),
                ),
                const SizedBox(width: NovaSpace.md),
                Expanded(
                  child: _RingCard(
                    label: 'Daily goal',
                    caption: '${formatMinutes(todayMinutes)} of ${formatMinutes(goal)}',
                    progress: goalProgress,
                  ),
                ),
              ],
            )),
          ),
          const SizedBox(height: NovaSpace.lg),
          FadeIn(
            delay: const Duration(milliseconds: 120),
            child: Column(
              children: [
                IntrinsicHeight(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Streak',
                        value: '${store.streak}',
                        icon: Icons.local_fire_department_outlined,
                        caption: store.streak == 1 ? 'day' : 'days',
                        color: NovaColors.warning,
                      ),
                    ),
                    const SizedBox(width: NovaSpace.md),
                    Expanded(
                      child: StatTile(
                        label: 'Done this week',
                        value: '${store.completedInLastDays(7)}',
                        icon: Icons.check_circle_outline_rounded,
                        caption: 'tasks',
                        color: NovaColors.success,
                      ),
                    ),
                  ],
                )),
                const SizedBox(height: NovaSpace.md),
                IntrinsicHeight(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Total focus',
                        value: formatMinutes(store.totalFocusMinutes),
                        icon: Icons.timer_outlined,
                        caption: 'all time',
                      ),
                    ),
                    const SizedBox(width: NovaSpace.md),
                    Expanded(
                      child: StatTile(
                        label: 'Open tasks',
                        value: '${store.openTasks.length}',
                        icon: Icons.pending_actions_rounded,
                        caption: 'to do',
                        color: NovaColors.accent,
                      ),
                    ),
                  ],
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.label,
    required this.caption,
    required this.progress,
  });

  final String label;
  final String caption;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      container: true,
      label: '$label: $percent percent, $caption',
      child: ExcludeSemantics(
        child: GlassSurface.solid(
          radius: NovaRadius.lg,
          padding: const EdgeInsets.all(NovaSpace.lg),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(label, style: NovaType.caption),
              ),
              const SizedBox(height: NovaSpace.md),
              ProgressRing(
                progress: progress,
                size: 84,
                strokeWidth: 9,
                child: Text('$percent%', style: NovaType.headline),
              ),
              const SizedBox(height: NovaSpace.md),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaType.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
