import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/haptics.dart';
import '../core/tokens.dart';
import '../ui/island.dart';
import 'models.dart';
import 'storage.dart';

enum FocusPhase { idle, running, paused }

/// Snapshot of the focus timer. Kept in its own [ValueNotifier] so the
/// once-per-second tick only rebuilds the widgets that show the timer.
class FocusState {
  const FocusState({
    required this.phase,
    required this.totalSeconds,
    required this.remainingSeconds,
    this.taskId,
  });

  static const FocusState idle = FocusState(
    phase: FocusPhase.idle,
    totalSeconds: 0,
    remainingSeconds: 0,
  );

  final FocusPhase phase;
  final int totalSeconds;
  final int remainingSeconds;
  final String? taskId;

  bool get active => phase != FocusPhase.idle;
  bool get running => phase == FocusPhase.running;

  /// 0 at the start of a session, 1 when it is finished.
  double get progress {
    if (totalSeconds <= 0) return 0;
    return clampDouble(1 - remainingSeconds / totalSeconds, 0, 1);
  }

  FocusState copyWith({FocusPhase? phase, int? remainingSeconds}) {
    return FocusState(
      phase: phase ?? this.phase,
      totalSeconds: totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      taskId: taskId,
    );
  }
}

/// Single source of truth for the app: account, tasks, focus sessions,
/// notifications and settings. Persists to [Storage] (debounced).
///
/// Every user-visible action also tells the [island] what to show, which is
/// how the floating notifications are wired to the data layer.
class AppStore extends ChangeNotifier {
  AppStore({Storage? storage}) : _storage = storage ?? PrefsStorage() {
    focusState.addListener(_syncLive);
  }

  static const String _stateKey = 'nova.state.v1';

  final Storage _storage;

  /// Floating island notifications and live activity.
  final IslandController island = IslandController();

  /// Focus timer state (ticks once per second while a session is running).
  final ValueNotifier<FocusState> focusState =
      ValueNotifier<FocusState>(FocusState.idle);

  bool _ready = false;
  Object? _loadError;
  UserProfile _profile = const UserProfile.guest();
  AppSettings _settings = const AppSettings();
  List<TaskItem> _tasks = <TaskItem>[];
  List<FocusLog> _logs = <FocusLog>[];
  List<NovaNotification> _notifications = <NovaNotification>[];

  TaskItem? _lastDeleted;
  int _lastDeletedIndex = 0;

  Timer? _saveTimer;
  Timer? _focusTimer;
  DateTime? _focusEnd;
  int _seq = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------- state

  bool get ready => _ready;
  Object? get loadError => _loadError;
  UserProfile get profile => _profile;
  AppSettings get settings => _settings;
  List<TaskItem> get tasks => UnmodifiableListView<TaskItem>(_tasks);
  List<FocusLog> get logs => UnmodifiableListView<FocusLog>(_logs);
  List<NovaNotification> get notifications =>
      UnmodifiableListView<NovaNotification>(_notifications);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // -------------------------------------------------------- load and save

  /// Loads saved data. Safe to call again after a failure.
  Future<void> init() async {
    _loadError = null;
    try {
      final raw = await _storage.read(_stateKey);
      if (raw != null && raw.isNotEmpty) {
        _restore(raw);
      }
      _ready = true;
      _applySettings();
    } catch (error) {
      _loadError = error;
      _ready = false;
    }
    notifyListeners();
  }

  void _restore(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final profile = UserProfile.fromJson(jsonMap(data['profile']));
      final settings = AppSettings.fromJson(jsonMap(data['settings']));
      final tasks = jsonList(data['tasks'])
          .map((e) => TaskItem.fromJson(jsonMap(e)))
          .toList();
      final logs = jsonList(data['logs'])
          .map((e) => FocusLog.fromJson(jsonMap(e)))
          .toList();
      final notes = jsonList(data['notifications'])
          .map((e) => NovaNotification.fromJson(jsonMap(e)))
          .toList();
      _profile = profile;
      _settings = settings;
      _tasks = tasks;
      _logs = logs;
      _notifications = notes;
    } catch (_) {
      // Corrupt saved data: start clean instead of blocking the app.
    }
  }

  String _encode() {
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'profile': _profile.toJson(),
      'settings': _settings.toJson(),
      'tasks': _tasks.map((t) => t.toJson()).toList(),
      'logs': _logs.map((l) => l.toJson()).toList(),
      'notifications': _notifications.map((n) => n.toJson()).toList(),
    });
  }

  Future<void> _save() async {
    try {
      await _storage.write(_stateKey, _encode());
    } catch (_) {
      // Saving is best effort; the in-memory state stays valid.
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      _save();
    });
  }

  /// Saves immediately (used before sign out and when leaving the app).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _save();
  }

  void _changed() {
    _scheduleSave();
    notifyListeners();
  }

  // -------------------------------------------------------------- account

  /// Local demo account: nothing is sent to a server.
  Future<void> signUp({required String name, required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();
    _profile = UserProfile(
      name: cleanName.isEmpty ? _nameFromEmail(cleanEmail) : cleanName,
      email: cleanEmail,
      signedIn: true,
    );
    if (_tasks.isEmpty) _seedStarterTasks();
    _notify(
      'Welcome to Nova',
      'Your workspace is ready. Add a task or start a focus session.',
      NotifKind.system,
    );
    _changed();
    await flush();
    island.toast(
      'Welcome, ${_profile.firstName}',
      subtitle: 'Your workspace is ready',
      icon: Icons.check_circle_rounded,
      tint: NovaColors.success,
    );
  }

  Future<void> signIn({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (_profile.email == cleanEmail) {
      _profile = _profile.copyWith(signedIn: true);
    } else {
      _profile = UserProfile(
        name: _nameFromEmail(cleanEmail),
        email: cleanEmail,
        signedIn: true,
      );
    }
    _changed();
    await flush();
    island.toast(
      'Welcome back, ${_profile.firstName}',
      icon: Icons.login_rounded,
      tint: NovaColors.accent2,
    );
  }

  Future<void> signOut() async {
    stopFocus(silent: true);
    island.dismiss();
    _profile = _profile.copyWith(signedIn: false);
    _changed();
    await flush();
  }

  void updateName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    _profile = _profile.copyWith(name: clean);
    _changed();
    island.toast('Name updated', icon: Icons.check_circle_rounded);
  }

  /// Deletes every task, log and notification and signs out.
  Future<void> resetAll() async {
    stopFocus(silent: true);
    island.dismiss();
    _saveTimer?.cancel();
    _saveTimer = null;
    _tasks = <TaskItem>[];
    _logs = <FocusLog>[];
    _notifications = <NovaNotification>[];
    _settings = const AppSettings();
    _profile = const UserProfile.guest();
    _lastDeleted = null;
    try {
      await _storage.remove(_stateKey);
    } catch (_) {
      // Nothing to do: in-memory state is already clean.
    }
    _applySettings();
    notifyListeners();
  }

  String _nameFromEmail(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    if (local.isEmpty) return 'Friend';
    final cleaned = local.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Friend';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  void _seedStarterTasks() {
    final now = DateTime.now();
    _tasks = <TaskItem>[
      TaskItem(
        id: _newId(),
        title: 'Plan your week',
        notes: 'List the three things that matter most this week.',
        priority: Priority.high,
        due: startOfDay(now),
        createdAt: now,
      ),
      TaskItem(
        id: _newId(),
        title: 'Try a 25 minute focus session',
        notes: 'Open Home and tap Start focus. Notice the island at the top.',
        priority: Priority.medium,
        due: startOfDay(now),
        createdAt: now,
      ),
      TaskItem(
        id: _newId(),
        title: 'Make Nova yours in Settings',
        priority: Priority.low,
        due: DateTime(now.year, now.month, now.day + 1),
        createdAt: now,
      ),
    ];
  }

  // ---------------------------------------------------------------- tasks

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$stamp${(_seq++).toRadixString(36)}';
  }

  TaskItem? taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  TaskItem addTask({
    required String title,
    String notes = '',
    Priority priority = Priority.medium,
    DateTime? due,
  }) {
    final task = TaskItem(
      id: _newId(),
      title: title.trim(),
      notes: notes.trim(),
      priority: priority,
      due: due == null ? null : startOfDay(due),
      createdAt: DateTime.now(),
    );
    _tasks = <TaskItem>[task, ..._tasks];
    _changed();
    island.toast(
      'Task added',
      subtitle: task.title,
      icon: Icons.add_task_rounded,
      tint: NovaColors.accent2,
    );
    return task;
  }

  void updateTask(TaskItem updated) {
    final index = _tasks.indexWhere((t) => t.id == updated.id);
    if (index < 0) return;
    _tasks = List<TaskItem>.of(_tasks)..[index] = updated;
    _changed();
    island.toast('Changes saved', icon: Icons.check_circle_rounded);
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    final list = List<TaskItem>.of(_tasks);
    if (task.done) {
      list[index] = task.copyWith(done: false, clearCompletedAt: true);
      _tasks = list;
      _changed();
      island.toast('Task reopened', icon: Icons.undo_rounded);
    } else {
      list[index] = task.copyWith(done: true, completedAt: DateTime.now());
      _tasks = list;
      Haptics.success();
      _notify('Task completed', task.title, NotifKind.task);
      _changed();
      island.toast(
        'Task completed',
        subtitle: task.title,
        icon: Icons.check_circle_rounded,
        tint: NovaColors.success,
      );
    }
  }

  /// Removes a task and offers Undo through the island.
  void deleteTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final list = List<TaskItem>.of(_tasks);
    final removed = list.removeAt(index);
    _tasks = list;
    _lastDeleted = removed;
    _lastDeletedIndex = index;
    _changed();
    island.toast(
      'Task deleted',
      subtitle: removed.title,
      icon: Icons.delete_outline_rounded,
      tint: NovaColors.danger,
      action: IslandAction(
        label: 'Undo',
        icon: Icons.undo_rounded,
        onTap: undoDelete,
      ),
    );
  }

  void undoDelete() {
    final task = _lastDeleted;
    if (task == null) return;
    final list = List<TaskItem>.of(_tasks);
    list.insert(math.min(_lastDeletedIndex, list.length), task);
    _tasks = list;
    _lastDeleted = null;
    _changed();
    island.toast('Task restored', icon: Icons.restore_rounded);
  }

  // ------------------------------------------------------ derived values

  static int _compareTasks(TaskItem a, TaskItem b) {
    final ad = a.due;
    final bd = b.due;
    if (ad != null && bd != null) {
      final byDate = ad.compareTo(bd);
      if (byDate != 0) return byDate;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    final byPriority = b.priority.weight.compareTo(a.priority.weight);
    if (byPriority != 0) return byPriority;
    return a.createdAt.compareTo(b.createdAt);
  }

  /// Open tasks ordered by due date, then priority.
  List<TaskItem> get openTasks {
    final list = _tasks.where((t) => !t.done).toList();
    list.sort(_compareTasks);
    return list;
  }

  List<TaskItem> get doneTasks {
    final list = _tasks.where((t) => t.done).toList();
    list.sort((a, b) {
      final ac = a.completedAt ?? a.createdAt;
      final bc = b.completedAt ?? b.createdAt;
      return bc.compareTo(ac);
    });
    return list;
  }

  List<TaskItem> upNext(int count) => openTasks.take(count).toList();

  int get completedToday {
    final now = DateTime.now();
    return _tasks.where((t) {
      final c = t.completedAt;
      return c != null && isSameDay(c, now);
    }).length;
  }

  int completedInLastDays(int days) {
    final today = startOfDay(DateTime.now());
    final from = DateTime(today.year, today.month, today.day - (days - 1));
    return _tasks.where((t) {
      final c = t.completedAt;
      return c != null && !c.isBefore(from);
    }).length;
  }

  /// Share of all tasks that are done, 0 to 1.
  double get completionRate {
    if (_tasks.isEmpty) return 0;
    return _tasks.where((t) => t.done).length / _tasks.length;
  }

  int focusMinutesOn(DateTime day) {
    var total = 0;
    for (final log in _logs) {
      if (isSameDay(log.at, day)) total += log.minutes;
    }
    return total;
  }

  int get focusMinutesToday => focusMinutesOn(DateTime.now());

  int get totalFocusMinutes {
    var total = 0;
    for (final log in _logs) {
      total += log.minutes;
    }
    return total;
  }

  /// Focus minutes for the last [days] days, oldest first.
  List<DayValue> focusByDay(int days) {
    final today = startOfDay(DateTime.now());
    return List<DayValue>.generate(days, (i) {
      final day = DateTime(today.year, today.month, today.day - (days - 1 - i));
      return DayValue(day, focusMinutesOn(day));
    });
  }

  /// Consecutive days with any activity (a completed task or a focus
  /// session). Today does not break the streak until the day is over.
  int get streak {
    final days = <String>{};
    for (final task in _tasks) {
      final c = task.completedAt;
      if (c != null) days.add(dayKey(c));
    }
    for (final log in _logs) {
      days.add(dayKey(log.at));
    }
    var cursor = startOfDay(DateTime.now());
    if (!days.contains(dayKey(cursor))) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    var count = 0;
    while (days.contains(dayKey(cursor))) {
      count++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  // ---------------------------------------------------------------- focus

  void startFocus({required int minutes, String? taskId}) {
    if (focusState.value.active) return;
    final total = minutes * 60;
    _focusEnd = DateTime.now().add(Duration(seconds: total));
    focusState.value = FocusState(
      phase: FocusPhase.running,
      totalSeconds: total,
      remainingSeconds: total,
      taskId: taskId,
    );
    _startTicker();
    Haptics.success();
    final task = taskId == null ? null : taskById(taskId);
    island.toast(
      'Focus started',
      subtitle: task?.title ?? '$minutes minutes',
      icon: Icons.timer_rounded,
      tint: NovaColors.accent2,
    );
  }

  void pauseFocus() {
    final state = focusState.value;
    if (!state.running) return;
    final remaining = _remainingNow();
    _focusTimer?.cancel();
    _focusTimer = null;
    _focusEnd = null;
    focusState.value = state.copyWith(
      phase: FocusPhase.paused,
      remainingSeconds: remaining,
    );
  }

  void resumeFocus() {
    final state = focusState.value;
    if (state.phase != FocusPhase.paused) return;
    _focusEnd = DateTime.now().add(Duration(seconds: state.remainingSeconds));
    focusState.value = state.copyWith(phase: FocusPhase.running);
    _startTicker();
  }

  /// Ends the session early. Elapsed whole minutes are logged unless
  /// [silent] is true.
  void stopFocus({bool silent = false}) {
    final state = focusState.value;
    if (!state.active) return;
    final remaining =
        state.running ? _remainingNow() : state.remainingSeconds;
    final elapsedMinutes = math.max(0, state.totalSeconds - remaining) ~/ 60;
    _focusTimer?.cancel();
    _focusTimer = null;
    _focusEnd = null;
    focusState.value = FocusState.idle;
    if (silent) return;
    if (elapsedMinutes > 0) {
      _logFocus(elapsedMinutes, state.taskId);
      _changed();
      island.toast(
        'Focus stopped',
        subtitle: '$elapsedMinutes min logged',
        icon: Icons.stop_circle_outlined,
      );
    } else {
      island.toast('Focus stopped', icon: Icons.stop_circle_outlined);
    }
  }

  /// Mirrors the focus timer onto the island's live activity.
  void _syncLive() {
    final state = focusState.value;
    if (!state.active) {
      island.live.value = null;
      island.collapseLive();
      return;
    }
    final id = state.taskId;
    final task = id == null ? null : taskById(id);
    island.live.value = IslandLive(
      title: task?.title ?? 'Focus session',
      timeText: formatTimerSeconds(state.remainingSeconds),
      progress: state.progress,
      running: state.running,
      onToggle: () {
        if (focusState.value.running) {
          pauseFocus();
        } else {
          resumeFocus();
        }
      },
      onStop: stopFocus,
    );
  }

  int _remainingNow() {
    final end = _focusEnd;
    if (end == null) return focusState.value.remainingSeconds;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    return math.max(0, (ms / 1000).ceil());
  }

  void _startTicker() {
    _focusTimer?.cancel();
    _focusTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_focusEnd == null) return;
    final remaining = _remainingNow();
    if (remaining <= 0) {
      _completeFocus();
      return;
    }
    if (remaining != focusState.value.remainingSeconds) {
      focusState.value = focusState.value.copyWith(remainingSeconds: remaining);
    }
  }

  void _completeFocus() {
    final state = focusState.value;
    _focusTimer?.cancel();
    _focusTimer = null;
    _focusEnd = null;
    focusState.value = FocusState.idle;
    final minutes = state.totalSeconds ~/ 60;
    final goal = _settings.dailyGoalMinutes;
    final before = focusMinutesToday;
    _logFocus(minutes, state.taskId);
    Haptics.success();
    _notify('Focus complete', '$minutes minutes of deep work.', NotifKind.focus);
    if (before < goal && focusMinutesToday >= goal) {
      _notify(
        'Daily goal reached',
        'You hit your $goal minute focus goal today.',
        NotifKind.focus,
      );
    }
    _changed();
    island.toast(
      'Focus complete',
      subtitle: '$minutes minutes logged',
      icon: Icons.check_circle_rounded,
      tint: NovaColors.success,
    );
  }

  void _logFocus(int minutes, String? taskId) {
    if (minutes <= 0) return;
    _logs = <FocusLog>[
      ..._logs,
      FocusLog(at: DateTime.now(), minutes: minutes, taskId: taskId),
    ];
    if (taskId != null) {
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index >= 0) {
        final list = List<TaskItem>.of(_tasks);
        list[index] = list[index]
            .copyWith(focusMinutes: list[index].focusMinutes + minutes);
        _tasks = list;
      }
    }
  }

  // -------------------------------------------------------- notifications

  int get unreadCount => _notifications.where((n) => !n.read).length;

  void _notify(String title, String body, NotifKind kind) {
    final note = NovaNotification(
      id: _newId(),
      title: title,
      body: body,
      kind: kind,
      at: DateTime.now(),
    );
    final list = <NovaNotification>[note, ..._notifications];
    _notifications = list.length > 100 ? list.sublist(0, 100) : list;
  }

  void markAllRead() {
    if (unreadCount == 0) return;
    _notifications =
        _notifications.map((n) => n.copyWith(read: true)).toList();
    _changed();
  }

  void clearNotifications() {
    if (_notifications.isEmpty) return;
    _notifications = <NovaNotification>[];
    _changed();
  }

  // ------------------------------------------------------------- settings

  void _applySettings() {
    Haptics.enabled = _settings.haptics;
    island.enabled = _settings.island;
  }

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _applySettings();
    _changed();
  }

  void setHaptics(bool value) =>
      updateSettings(_settings.copyWith(haptics: value));

  void setIslandEnabled(bool value) =>
      updateSettings(_settings.copyWith(island: value));

  void setReduceBlur(bool value) =>
      updateSettings(_settings.copyWith(reduceBlur: value));

  void setReduceMotion(bool value) =>
      updateSettings(_settings.copyWith(reduceMotion: value));

  void setDailyGoal(int minutes) {
    final clamped = minutes < 15 ? 15 : (minutes > 240 ? 240 : minutes);
    updateSettings(_settings.copyWith(dailyGoalMinutes: clamped));
  }

  // ------------------------------------------------------------- lifecycle

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _focusTimer?.cancel();
    focusState.removeListener(_syncLive);
    focusState.dispose();
    island.dispose();
    super.dispose();
  }
}
