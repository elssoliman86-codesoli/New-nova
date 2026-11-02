import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';
import '../ui/states.dart';
import 'focus_sheet.dart';
import 'task_editor_sheet.dart';

/// Full details of one task with edit, delete, complete and focus actions.
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  Future<void> _confirmDelete(BuildContext context) async {
    final store = AppScope.read(context);
    final ok = await showNovaConfirm(
      context,
      title: 'Delete this task?',
      message: 'You can undo this right after from the notification at the top.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !context.mounted) return;
    Navigator.of(context).pop();
    store.deleteTask(taskId);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final task = store.taskById(taskId);

    if (task == null) {
      return const ScreenScaffold(
        title: 'Task',
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Task not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final now = DateTime.now();
    final overdue = !task.done && task.due != null && isOverdue(task.due!, now);

    return ScreenScaffold(
      title: 'Task',
      actions: [
        NeuIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit task',
          onPressed: () => showTaskEditor(context, task: task),
        ),
        NeuIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Delete task',
          onPressed: () => _confirmDelete(context),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
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
                    children: [
                      NovaChip(
                        label: task.done ? 'Done' : 'Open',
                        icon: task.done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        selected: true,
                        color: task.done ? NovaColors.success : NovaColors.accent2,
                      ),
                    ],
                  ),
                  const SizedBox(height: NovaSpace.md),
                  Text(
                    task.title,
                    style: NovaType.title.copyWith(
                      decoration:
                          task.done ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: NovaColors.textDim,
                    ),
                  ),
                  const SizedBox(height: NovaSpace.md),
                  Text(
                    task.notes.isEmpty ? 'No notes.' : task.notes,
                    style: task.notes.isEmpty
                        ? NovaType.bodyDim.copyWith(color: NovaColors.textFaint)
                        : NovaType.body,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NovaSpace.lg),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.flag_outlined,
                title: 'Priority',
                color: priorityColor(task.priority),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PriorityDot(priority: task.priority),
                    const SizedBox(width: 8),
                    Text(task.priority.label, style: NovaType.bodyDim),
                  ],
                ),
              ),
              SettingsRow(
                icon: Icons.event_rounded,
                title: 'Due',
                color: overdue ? NovaColors.danger : NovaColors.accent2,
                trailing: Text(
                  formatDue(task.due, now: now),
                  style: NovaType.bodyDim.copyWith(
                    color: overdue ? NovaColors.danger : NovaColors.textDim,
                  ),
                ),
              ),
              SettingsRow(
                icon: Icons.timer_outlined,
                title: 'Focus time',
                trailing: Text(
                  task.focusMinutes == 0 ? 'None yet' : formatMinutes(task.focusMinutes),
                  style: NovaType.bodyDim,
                ),
              ),
              SettingsRow(
                icon: Icons.history_rounded,
                title: task.done ? 'Completed' : 'Created',
                trailing: Text(
                  formatDate(task.done ? (task.completedAt ?? task.createdAt) : task.createdAt),
                  style: NovaType.bodyDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: NovaSpace.xxl),
          if (!task.done) ...[
            NeuButton(
              label: 'Focus on this task',
              icon: Icons.play_arrow_rounded,
              onPressed: () => showFocusSheet(context, taskId: task.id),
            ),
            const SizedBox(height: NovaSpace.md),
          ],
          NeuButton(
            label: task.done ? 'Mark as open' : 'Mark as done',
            icon: task.done ? Icons.undo_rounded : Icons.check_rounded,
            kind: NeuButtonKind.secondary,
            onPressed: () => store.toggleTask(task.id),
          ),
        ],
      ),
    );
  }
}
