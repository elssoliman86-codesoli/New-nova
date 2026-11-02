import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova/data/app_store.dart';
import 'package:nova/data/models.dart';
import 'package:nova/data/storage.dart';

Future<AppStore> _newStore([Storage? storage]) async {
  final store = AppStore(storage: storage ?? MemoryStorage());
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Haptics call into the platform; answer "ok".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  group('tasks', () {
    test('add, complete, delete and undo', () async {
      final store = await _newStore();

      final task = store.addTask(title: '  Write report  ', priority: Priority.high);
      expect(task.title, 'Write report');
      expect(store.openTasks, hasLength(1));

      store.toggleTask(task.id);
      expect(store.openTasks, isEmpty);
      expect(store.doneTasks.single.id, task.id);
      expect(store.completedToday, 1);
      expect(store.completionRate, 1.0);

      store.deleteTask(task.id);
      expect(store.tasks, isEmpty);

      store.undoDelete();
      expect(store.tasks.single.id, task.id);

      store.dispose();
    });

    test('open tasks are ordered by due date then priority', () async {
      final store = await _newStore();
      final now = DateTime.now();

      store.addTask(title: 'later', due: DateTime(now.year, now.month, now.day + 3));
      store.addTask(title: 'today low', due: now, priority: Priority.low);
      store.addTask(title: 'today high', due: now, priority: Priority.high);
      store.addTask(title: 'no date');

      expect(
        store.openTasks.map((t) => t.title).toList(),
        ['today high', 'today low', 'later', 'no date'],
      );

      store.dispose();
    });

    test('streak counts consecutive active days', () async {
      final store = await _newStore();
      expect(store.streak, 0);

      final task = store.addTask(title: 'x');
      store.toggleTask(task.id);
      expect(store.streak, 1);

      store.dispose();
    });
  });

  group('persistence', () {
    test('state survives a restart', () async {
      final storage = MemoryStorage();

      final first = await _newStore(storage);
      await first.signUp(name: 'Sara Ahmed', email: 'Sara@Example.com');
      first.addTask(title: 'Persisted');
      first.setDailyGoal(90);
      await first.flush();
      first.dispose();

      final second = await _newStore(storage);
      expect(second.profile.signedIn, isTrue);
      expect(second.profile.email, 'sara@example.com');
      expect(second.profile.firstName, 'Sara');
      expect(second.tasks.map((t) => t.title), contains('Persisted'));
      expect(second.settings.dailyGoalMinutes, 90);
      second.dispose();
    });

    test('corrupt saved data does not block start up', () async {
      final storage = MemoryStorage();
      await storage.write('nova.state.v1', '{not json');

      final store = await _newStore(storage);
      expect(store.ready, isTrue);
      expect(store.tasks, isEmpty);
      store.dispose();
    });

    test('resetAll clears everything', () async {
      final store = await _newStore();
      await store.signUp(name: 'A', email: 'a@b.co');
      await store.resetAll();

      expect(store.tasks, isEmpty);
      expect(store.profile.signedIn, isFalse);
      store.dispose();
    });
  });

  group('focus', () {
    test('start, pause, resume and stop', () async {
      final store = await _newStore();

      store.startFocus(minutes: 25);
      expect(store.focusState.value.running, isTrue);
      expect(store.focusState.value.totalSeconds, 1500);
      expect(store.island.live.value, isNotNull);

      store.pauseFocus();
      expect(store.focusState.value.phase, FocusPhase.paused);

      store.resumeFocus();
      expect(store.focusState.value.running, isTrue);

      store.stopFocus();
      expect(store.focusState.value.active, isFalse);
      expect(store.island.live.value, isNull);

      store.dispose();
    });

    test('a second session cannot start while one is active', () async {
      final store = await _newStore();

      store.startFocus(minutes: 15);
      store.startFocus(minutes: 60);
      expect(store.focusState.value.totalSeconds, 900);

      store.stopFocus(silent: true);
      store.dispose();
    });
  });

  group('settings and notifications', () {
    test('daily goal is clamped', () async {
      final store = await _newStore();
      store.setDailyGoal(1);
      expect(store.settings.dailyGoalMinutes, 15);
      store.setDailyGoal(10000);
      expect(store.settings.dailyGoalMinutes, 240);
      store.dispose();
    });

    test('completing a task creates an unread notification', () async {
      final store = await _newStore();
      final task = store.addTask(title: 'Ship it');
      store.toggleTask(task.id);

      expect(store.unreadCount, 1);
      store.markAllRead();
      expect(store.unreadCount, 0);
      store.clearNotifications();
      expect(store.notifications, isEmpty);
      store.dispose();
    });
  });

  group('models', () {
    test('task JSON round trip', () {
      final task = TaskItem(
        id: 'a',
        title: 'Title',
        notes: 'Notes',
        priority: Priority.high,
        due: DateTime(2026, 11, 3),
        done: true,
        createdAt: DateTime(2026, 11, 1),
        completedAt: DateTime(2026, 11, 2),
        focusMinutes: 25,
      );
      final copy = TaskItem.fromJson(task.toJson());
      expect(copy.title, 'Title');
      expect(copy.priority, Priority.high);
      expect(copy.due, DateTime(2026, 11, 3));
      expect(copy.done, isTrue);
      expect(copy.focusMinutes, 25);
    });

    test('bad JSON falls back to safe defaults', () {
      final task = TaskItem.fromJson(<String, dynamic>{'priority': 99, 'done': 'yes'});
      expect(task.priority, Priority.high);
      expect(task.done, isFalse);
      expect(task.title, 'Untitled');
    });
  });
}
