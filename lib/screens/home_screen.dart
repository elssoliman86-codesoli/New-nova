import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/app_store.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/states.dart';
import 'focus_sheet.dart';
import 'notifications_screen.dart';
import 'task_detail_screen.dart';
import 'task_editor_sheet.dart';

/// Today at a glance: focus card, quick stats and the next tasks.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGoToTab});

  /// Switches the main tab (used by "See all").
  final ValueChanged<int> onGoToTab;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final now = DateTime.now();
    final next = store.upNext(3);

    return ScreenScaffold(
      showBack: false,
      subtitle: formatDate(now),
      title: '${greetingFor(now)}, ${store.profile.firstName}',
      actions: [
        NeuIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: store.unreadCount > 0
              ? 'Notifications, ${store.unreadCount} unread'
              : 'Notifications',
          badgeCount: store.unreadCount,
          onPressed: () => pushNova(context, (_) => const NotificationsScreen()),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          navClearance(context),
        ),
        children: [
          const FadeIn(child: _FocusCard()),
          const SizedBox(height: NovaSpace.lg),
          FadeIn(
            delay: const Duration(milliseconds: 60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Done today',
                    value: '${store.completedToday}',
                    icon: Icons.check_circle_outline_rounded,
                    caption: '${store.openTasks.length} still open',
                    color: NovaColors.success,
                  ),
                ),
                const SizedBox(width: NovaSpace.md),
                Expanded(
                  child: StatTile(
                    label: 'Day streak',
                    value: '${store.streak}',
                    icon: Icons.local_fire_department_outlined,
                    caption: store.streak == 1 ? 'day in a row' : 'days in a row',
                    color: NovaColors.warning,
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: 'Up next',
            actionLabel: store.tasks.isEmpty ? 'Add task' : 'See all',
            onAction: () {
              if (store.tasks.isEmpty) {
                showTaskEditor(context);
              } else {
                onGoToTab(1);
              }
            },
          ),
          if (next.isEmpty)
            GlassSurface.solid(
              radius: NovaRadius.lg,
              child: EmptyState(
                compact: true,
                icon: Icons.task_alt_rounded,
                title: store.tasks.isEmpty ? 'No tasks yet' : 'All clear',
                message: store.tasks.isEmpty
                    ? 'Add your first task to get started.'
                    : 'Nothing left to do. Enjoy the break.',
                actionLabel: store.tasks.isEmpty ? 'Add task' : null,
                onAction: () => showTaskEditor(context),
              ),
            )
          else
            for (var i = 0; i < next.length; i++) ...[
              if (i > 0) const SizedBox(height: NovaSpace.md),
              TaskTile(
                key: ValueKey<String>(next[i].id),
                task: next[i],
                onToggle: (_) => store.toggleTask(next[i].id),
                onTap: () => pushNova(
                  context,
                  (_) => TaskDetailScreen(taskId: next[i].id),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// Focus summary. Idle: today's progress towards the goal and a start
/// button. Active: the live countdown with pause and stop.
class _FocusCard extends StatelessWidget {
  const _FocusCard();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return GlassSurface(
      radius: NovaRadius.xl,
      padding: const EdgeInsets.all(NovaSpace.xl),
      child: ValueListenableBuilder<FocusState>(
        valueListenable: store.focusState,
        builder: (context, focus, _) {
          return AnimatedSwitcher(
            duration: motionDuration(context, NovaDurations.base),
            child: focus.active
                ? _ActiveFocus(key: const ValueKey<String>('active'), focus: focus)
                : const _IdleFocus(key: ValueKey<String>('idle')),
          );
        },
      ),
    );
  }
}

class _IdleFocus extends StatelessWidget {
  const _IdleFocus({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final goal = store.settings.dailyGoalMinutes;
    final done = store.focusMinutesToday;
    final progress = goal <= 0 ? 0.0 : done / goal;

    return Row(
      children: [
        ProgressRing(
          progress: progress,
          size: 88,
          strokeWidth: 9,
          child: Text('${(progress.clamp(0.0, 1.0) * 100).round()}%', style: NovaType.headline),
        ),
        const SizedBox(width: NovaSpace.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Focus today', style: NovaType.caption),
              const SizedBox(height: 2),
              Text(
                '${formatMinutes(done)} of ${formatMinutes(goal)}',
                style: NovaType.headline,
              ),
              const SizedBox(height: NovaSpace.md),
              NeuButton(
                label: 'Start focus',
                icon: Icons.play_arrow_rounded,
                compact: true,
                onPressed: () => showFocusSheet(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveFocus extends StatelessWidget {
  const _ActiveFocus({super.key, required this.focus});

  final FocusState focus;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.read(context);
    final task = focus.taskId == null ? null : store.taskById(focus.taskId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              focus.running ? Icons.timer_rounded : Icons.pause_circle_outline_rounded,
              size: 18,
              color: focus.running ? NovaColors.accent2 : NovaColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task?.title ?? 'Focus session',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaType.label.copyWith(color: NovaColors.textDim),
              ),
            ),
            Text(focus.running ? 'Running' : 'Paused', style: NovaType.caption),
          ],
        ),
        const SizedBox(height: NovaSpace.md),
        Center(
          child: Semantics(
            liveRegion: false,
            label: '${formatTimerSeconds(focus.remainingSeconds)} remaining',
            child: ExcludeSemantics(
              child: Text(formatTimerSeconds(focus.remainingSeconds), style: NovaType.timer),
            ),
          ),
        ),
        const SizedBox(height: NovaSpace.lg),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: focus.progress,
            minHeight: 6,
            backgroundColor: NovaColors.white(0.08),
            color: NovaColors.accent2,
          ),
        ),
        const SizedBox(height: NovaSpace.lg),
        Row(
          children: [
            Expanded(
              child: NeuButton(
                label: focus.running ? 'Pause' : 'Resume',
                icon: focus.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                kind: NeuButtonKind.secondary,
                compact: true,
                onPressed: focus.running ? store.pauseFocus : store.resumeFocus,
              ),
            ),
            const SizedBox(width: NovaSpace.md),
            Expanded(
              child: NeuButton(
                label: 'Stop',
                icon: Icons.stop_rounded,
                kind: NeuButtonKind.danger,
                compact: true,
                onPressed: store.stopFocus,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
