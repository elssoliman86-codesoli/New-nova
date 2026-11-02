// Plain data classes with JSON (de)serialisation. No Flutter imports.

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Object?> jsonList(Object? value) {
  if (value is List) return List<Object?>.from(value);
  return <Object?>[];
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

bool _asBool(Object? value, bool fallback) => value is bool ? value : fallback;

String _asString(Object? value, String fallback) =>
    value is String ? value : fallback;

DateTime? _asDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

enum Priority { low, medium, high }

extension PriorityX on Priority {
  String get label {
    switch (this) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
    }
  }

  /// Higher means more important; used for sorting.
  int get weight => index;
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.notes = '',
    this.priority = Priority.medium,
    this.due,
    this.done = false,
    required this.createdAt,
    this.completedAt,
    this.focusMinutes = 0,
  });

  final String id;
  final String title;
  final String notes;
  final Priority priority;
  final DateTime? due;
  final bool done;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int focusMinutes;

  TaskItem copyWith({
    String? title,
    String? notes,
    Priority? priority,
    DateTime? due,
    bool clearDue = false,
    bool? done,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? focusMinutes,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      due: clearDue ? null : (due ?? this.due),
      done: done ?? this.done,
      createdAt: createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      focusMinutes: focusMinutes ?? this.focusMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'notes': notes,
        'priority': priority.index,
        'due': due?.millisecondsSinceEpoch,
        'done': done,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'focusMinutes': focusMinutes,
      };

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final p = _asInt(json['priority'], Priority.medium.index);
    final priorityIndex = p < 0 ? 0 : (p > 2 ? 2 : p);
    return TaskItem(
      id: _asString(json['id'], DateTime.now().microsecondsSinceEpoch.toString()),
      title: _asString(json['title'], 'Untitled'),
      notes: _asString(json['notes'], ''),
      priority: Priority.values[priorityIndex],
      due: _asDate(json['due']),
      done: _asBool(json['done'], false),
      createdAt: _asDate(json['createdAt']) ?? DateTime.now(),
      completedAt: _asDate(json['completedAt']),
      focusMinutes: _asInt(json['focusMinutes'], 0),
    );
  }
}

/// A finished (or stopped) focus session.
class FocusLog {
  const FocusLog({required this.at, required this.minutes, this.taskId});

  final DateTime at;
  final int minutes;
  final String? taskId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at.millisecondsSinceEpoch,
        'minutes': minutes,
        'taskId': taskId,
      };

  factory FocusLog.fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'];
    return FocusLog(
      at: _asDate(json['at']) ?? DateTime.now(),
      minutes: _asInt(json['minutes'], 0),
      taskId: taskId is String ? taskId : null,
    );
  }
}

/// One bar of the weekly chart.
class DayValue {
  const DayValue(this.day, this.value);

  final DateTime day;
  final int value;
}

enum NotifKind { task, focus, system }

class NovaNotification {
  const NovaNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.at,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final NotifKind kind;
  final DateTime at;
  final bool read;

  NovaNotification copyWith({bool? read}) => NovaNotification(
        id: id,
        title: title,
        body: body,
        kind: kind,
        at: at,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'kind': kind.index,
        'at': at.millisecondsSinceEpoch,
        'read': read,
      };

  factory NovaNotification.fromJson(Map<String, dynamic> json) {
    final k = _asInt(json['kind'], NotifKind.system.index);
    final kindIndex = k < 0 ? 0 : (k >= NotifKind.values.length ? 0 : k);
    return NovaNotification(
      id: _asString(json['id'], DateTime.now().microsecondsSinceEpoch.toString()),
      title: _asString(json['title'], ''),
      body: _asString(json['body'], ''),
      kind: NotifKind.values[kindIndex],
      at: _asDate(json['at']) ?? DateTime.now(),
      read: _asBool(json['read'], false),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.signedIn,
  });

  const UserProfile.guest()
      : name = '',
        email = '',
        signedIn = false;

  final String name;
  final String email;
  final bool signedIn;

  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  UserProfile copyWith({String? name, String? email, bool? signedIn}) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      signedIn: signedIn ?? this.signedIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'email': email,
        'signedIn': signedIn,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: _asString(json['name'], ''),
      email: _asString(json['email'], ''),
      signedIn: _asBool(json['signedIn'], false),
    );
  }
}

class AppSettings {
  const AppSettings({
    this.haptics = true,
    this.island = true,
    this.reduceBlur = false,
    this.reduceMotion = false,
    this.dailyGoalMinutes = 60,
  });

  final bool haptics;

  /// Floating (island) notifications. Undo prompts always show.
  final bool island;
  final bool reduceBlur;
  final bool reduceMotion;
  final int dailyGoalMinutes;

  AppSettings copyWith({
    bool? haptics,
    bool? island,
    bool? reduceBlur,
    bool? reduceMotion,
    int? dailyGoalMinutes,
  }) {
    return AppSettings(
      haptics: haptics ?? this.haptics,
      island: island ?? this.island,
      reduceBlur: reduceBlur ?? this.reduceBlur,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'haptics': haptics,
        'island': island,
        'reduceBlur': reduceBlur,
        'reduceMotion': reduceMotion,
        'dailyGoalMinutes': dailyGoalMinutes,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final goal = _asInt(json['dailyGoalMinutes'], 60);
    return AppSettings(
      haptics: _asBool(json['haptics'], true),
      island: _asBool(json['island'], true),
      reduceBlur: _asBool(json['reduceBlur'], false),
      reduceMotion: _asBool(json['reduceMotion'], false),
      dailyGoalMinutes: goal < 15 ? 15 : (goal > 240 ? 240 : goal),
    );
  }
}
