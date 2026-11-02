import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/models.dart';
import '../ui/components.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';

/// Opens the add / edit task sheet. Pass [task] to edit it.
Future<void> showTaskEditor(BuildContext context, {TaskItem? task}) {
  return showNovaSheet<void>(
    context,
    builder: (ctx) => TaskEditorSheet(task: task),
  );
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({super.key, this.task});

  final TaskItem? task;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.task?.notes ?? '');
  late Priority _priority = widget.task?.priority ?? Priority.medium;
  // New tasks default to today; existing tasks keep their own date (or none).
  late DateTime? _due =
      widget.task == null ? startOfDay(DateTime.now()) : widget.task!.due;

  bool get _editing => widget.task != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _due ?? startOfDay(now);
    final first = initial.isBefore(now) ? initial : startOfDay(now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _due = startOfDay(picked));
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final store = AppScope.read(context);
    final existing = widget.task;
    if (existing == null) {
      store.addTask(
        title: _title.text,
        notes: _notes.text,
        priority: _priority,
        due: _due,
      );
    } else {
      store.updateTask(existing.copyWith(
        title: _title.text.trim(),
        notes: _notes.text.trim(),
        priority: _priority,
        due: _due,
        clearDue: _due == null,
      ));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = startOfDay(now);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final due = _due;
    final isToday = due != null && isSameDay(due, today);
    final isTomorrow = due != null && isSameDay(due, tomorrow);
    final isOther = due != null && !isToday && !isTomorrow;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(_editing ? 'Edit task' : 'New task', style: NovaType.title),
          ),
          const SizedBox(height: NovaSpace.xl),
          NeuField(
            controller: _title,
            label: 'Title',
            hint: 'What needs to be done?',
            icon: Icons.edit_outlined,
            autofocus: !_editing,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Give the task a title' : null,
          ),
          const SizedBox(height: NovaSpace.lg),
          NeuField(
            controller: _notes,
            label: 'Notes',
            hint: 'Optional details',
            icon: Icons.notes_rounded,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: NovaSpace.xl),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Priority',
              style: NovaType.label.copyWith(color: NovaColors.textDim),
            ),
          ),
          NeuSegmented<Priority>(
            value: _priority,
            onChanged: (value) => setState(() => _priority = value),
            segments: [
              NeuSegment<Priority>(
                value: Priority.low,
                label: 'Low',
                color: priorityColor(Priority.low),
              ),
              NeuSegment<Priority>(
                value: Priority.medium,
                label: 'Medium',
                color: priorityColor(Priority.medium),
              ),
              NeuSegment<Priority>(
                value: Priority.high,
                label: 'High',
                color: priorityColor(Priority.high),
              ),
            ],
          ),
          const SizedBox(height: NovaSpace.xl),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Due',
              style: NovaType.label.copyWith(color: NovaColors.textDim),
            ),
          ),
          Wrap(
            spacing: NovaSpace.sm,
            runSpacing: 0,
            children: [
              NovaChip(
                label: 'No date',
                selected: due == null,
                onTap: () => setState(() => _due = null),
              ),
              NovaChip(
                label: 'Today',
                selected: isToday,
                onTap: () => setState(() => _due = today),
              ),
              NovaChip(
                label: 'Tomorrow',
                selected: isTomorrow,
                onTap: () => setState(() => _due = tomorrow),
              ),
              NovaChip(
                label: isOther ? formatDue(due, now: now) : 'Pick date',
                icon: Icons.calendar_today_rounded,
                selected: isOther,
                onTap: _pickDate,
              ),
            ],
          ),
          const SizedBox(height: NovaSpace.xxl),
          NeuButton(
            label: _editing ? 'Save changes' : 'Add task',
            icon: Icons.check_rounded,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
