import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/models.dart';
import '../ui/components.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';

/// Opens the "start a focus session" sheet. If a session is already running
/// it expands the island instead.
Future<void> showFocusSheet(BuildContext context, {String? taskId}) async {
  final store = AppScope.read(context);
  if (store.focusState.value.active) {
    store.island.expandLive();
    return;
  }
  await showNovaSheet<void>(
    context,
    builder: (ctx) => FocusSheet(initialTaskId: taskId),
  );
}

class FocusSheet extends StatefulWidget {
  const FocusSheet({super.key, this.initialTaskId});

  final String? initialTaskId;

  @override
  State<FocusSheet> createState() => _FocusSheetState();
}

class _FocusSheetState extends State<FocusSheet> {
  static const List<int> _durations = [15, 25, 45, 60];
  static const int _maxTasks = 5;

  int _minutes = 25;
  late String? _taskId = widget.initialTaskId;

  void _start() {
    final store = AppScope.read(context);
    store.startFocus(minutes: _minutes, taskId: _taskId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final open = store.openTasks;

    // Keep the chosen task visible even if it is not among the first few.
    final shown = open.take(_maxTasks).toList();
    final selected = _taskId == null ? null : store.taskById(_taskId!);
    if (selected != null && !selected.done && !shown.any((t) => t.id == selected.id)) {
      shown.insert(0, selected);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: const Text('Start focus', style: NovaType.title),
        ),
        const SizedBox(height: NovaSpace.xs),
        const Text('Pick a length and, if you like, a task.', style: NovaType.bodyDim),
        const SizedBox(height: NovaSpace.xl),
        Wrap(
          spacing: NovaSpace.sm,
          children: [
            for (final minutes in _durations)
              NovaChip(
                label: formatMinutes(minutes),
                icon: Icons.timer_outlined,
                selected: _minutes == minutes,
                onTap: () => setState(() => _minutes = minutes),
              ),
          ],
        ),
        const SizedBox(height: NovaSpace.xl),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Working on',
            style: NovaType.label.copyWith(color: NovaColors.textDim),
          ),
        ),
        _TaskChoice(
          title: 'No specific task',
          selected: _taskId == null,
          onTap: () => setState(() => _taskId = null),
        ),
        for (final task in shown) ...[
          const SizedBox(height: NovaSpace.sm),
          _TaskChoice(
            title: task.title,
            priority: task.priority,
            selected: _taskId == task.id,
            onTap: () => setState(() => _taskId = task.id),
          ),
        ],
        const SizedBox(height: NovaSpace.xxl),
        NeuButton(
          label: 'Start ${formatMinutes(_minutes)} session',
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
      ],
    );
  }
}

class _TaskChoice extends StatelessWidget {
  const _TaskChoice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.priority,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Priority? priority;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: NovaSpace.lg, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NovaRadius.md),
            color: selected
                ? NovaColors.accent.withValues(alpha: 0.14)
                : NovaColors.white(0.04),
            border: Border.all(
              color: selected
                  ? NovaColors.accent.withValues(alpha: 0.5)
                  : NovaColors.white(0.07),
            ),
          ),
          child: Row(
            children: [
              if (priority != null) ...[
                PriorityDot(priority: priority!),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.body.copyWith(
                    color: selected ? NovaColors.text : NovaColors.textDim,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, size: 20, color: NovaColors.accent2),
            ],
          ),
        ),
      ),
    );
  }
}
