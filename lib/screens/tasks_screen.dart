import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/components.dart';
import '../ui/island.dart';
import '../ui/neu.dart';
import '../ui/states.dart';
import 'focus_sheet.dart';
import 'task_detail_screen.dart';
import 'task_editor_sheet.dart';

enum _Filter { all, open, done, high }

extension on _Filter {
  String get label {
    switch (this) {
      case _Filter.all:
        return 'All';
      case _Filter.open:
        return 'Open';
      case _Filter.done:
        return 'Done';
      case _Filter.high:
        return 'High priority';
    }
  }
}

/// One entry in the grouped list: either a section title or a task.
class _Row {
  const _Row.header(this.title) : task = null;
  const _Row.task(this.task) : title = null;

  final String? title;
  final TaskItem? task;
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TextEditingController _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _groupFor(TaskItem task, DateTime now) {
    final due = task.due;
    if (due == null) return 'No date';
    final today = startOfDay(now);
    final day = startOfDay(due);
    final diff = day.difference(today).inDays;
    if (diff < 0) return 'Overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return 'Upcoming';
  }

  List<_Row> _rows(AppStore store) {
    final q = _query.trim().toLowerCase();
    bool matches(TaskItem t) =>
        q.isEmpty ||
        t.title.toLowerCase().contains(q) ||
        t.notes.toLowerCase().contains(q);

    final open = _filter == _Filter.done
        ? <TaskItem>[]
        : store.openTasks
            .where(matches)
            .where((t) => _filter != _Filter.high || t.priority == Priority.high)
            .toList();
    final done = (_filter == _Filter.all || _filter == _Filter.done)
        ? store.doneTasks.where(matches).toList()
        : <TaskItem>[];

    final now = DateTime.now();
    final rows = <_Row>[];
    String? lastGroup;
    for (final task in open) {
      final group = _groupFor(task, now);
      if (group != lastGroup) {
        rows.add(_Row.header(group));
        lastGroup = group;
      }
      rows.add(_Row.task(task));
    }
    if (done.isNotEmpty) {
      rows.add(const _Row.header('Completed'));
      for (final task in done) {
        rows.add(_Row.task(task));
      }
    }
    return rows;
  }

  void _openMenu(BuildContext context, AppStore store, TaskItem task) {
    store.island.showMenu(
      title: task.title,
      actions: [
        IslandAction(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onTap: () => showTaskEditor(context, task: task),
        ),
        if (!task.done)
          IslandAction(
            label: 'Start focus',
            icon: Icons.timer_outlined,
            onTap: () => showFocusSheet(context, taskId: task.id),
          ),
        IslandAction(
          label: task.done ? 'Mark as open' : 'Mark as done',
          icon: task.done ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
          onTap: () => store.toggleTask(task.id),
        ),
        IslandAction(
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          onTap: () => store.deleteTask(task.id),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final rows = _rows(store);
    final hasTasks = store.tasks.isNotEmpty;

    return ScreenScaffold(
      showBack: false,
      title: 'Tasks',
      subtitle: '${store.openTasks.length} open',
      actions: [
        NeuIconButton(
          icon: Icons.add_rounded,
          tooltip: 'Add task',
          active: true,
          onPressed: () => showTaskEditor(context),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NovaLayout.pagePad,
              NovaSpace.sm,
              NovaLayout.pagePad,
              NovaSpace.xs,
            ),
            child: NeuField(
              controller: _search,
              hint: 'Search tasks',
              icon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              suffix: _query.isEmpty
                  ? null
                  : Pressable(
                      semanticLabel: 'Clear search',
                      onTap: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      child: const SizedBox(
                        width: NovaLayout.minTap,
                        height: NovaLayout.minTap,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: NovaColors.textDim,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: NovaLayout.pagePad),
              itemCount: _Filter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: NovaSpace.sm),
              itemBuilder: (context, index) {
                final filter = _Filter.values[index];
                return NovaChip(
                  label: filter.label,
                  selected: _filter == filter,
                  onTap: () => setState(() => _filter = filter),
                );
              },
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? (hasTasks
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matches',
                        message: 'Try a different search or filter.',
                      )
                    : EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'No tasks yet',
                        message: 'Capture what you need to do and Nova will keep it organised.',
                        actionLabel: 'Add task',
                        onAction: () => showTaskEditor(context),
                      ))
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      NovaLayout.pagePad,
                      NovaSpace.xs,
                      NovaLayout.pagePad,
                      navClearance(context),
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final title = row.title;
                      if (title != null) {
                        return SectionHeader(title: title);
                      }
                      final task = row.task!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: NovaSpace.md),
                        child: Dismissible(
                          key: ValueKey<String>('task-${task.id}'),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => store.deleteTask(task.id),
                          background: const _DeleteBackground(),
                          child: TaskTile(
                            task: task,
                            onToggle: (_) => store.toggleTask(task.id),
                            onTap: () => pushNova(
                              context,
                              (_) => TaskDetailScreen(taskId: task.id),
                            ),
                            onLongPress: () => _openMenu(context, store, task),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: NovaSpace.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NovaRadius.md),
        color: NovaColors.danger.withValues(alpha: 0.18),
        border: Border.all(color: NovaColors.danger.withValues(alpha: 0.4)),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: NovaColors.danger),
    );
  }
}
