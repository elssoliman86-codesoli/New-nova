import 'package:flutter_test/flutter_test.dart';
import 'package:nova/core/formatters.dart';

void main() {
  test('timer formatting', () {
    expect(formatTimerSeconds(0), '00:00');
    expect(formatTimerSeconds(125), '02:05');
    expect(formatTimerSeconds(1500), '25:00');
    expect(formatTimerSeconds(-5), '00:00');
  });

  test('minutes formatting', () {
    expect(formatMinutes(25), '25m');
    expect(formatMinutes(60), '1h');
    expect(formatMinutes(90), '1h 30m');
  });

  test('due date labels', () {
    final now = DateTime(2026, 11, 1, 10);
    expect(formatDue(null, now: now), 'No date');
    expect(formatDue(DateTime(2026, 11, 1), now: now), 'Today');
    expect(formatDue(DateTime(2026, 11, 2), now: now), 'Tomorrow');
    expect(formatDue(DateTime(2026, 10, 31), now: now), 'Yesterday');
    expect(formatDue(DateTime(2026, 11, 5), now: now), 'Thu, 5 Nov');
  });

  test('greeting follows the hour', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 14)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 19)), 'Good evening');
    expect(greetingFor(DateTime(2026, 1, 1, 23)), 'Good night');
  });

  test('overdue ignores the time of day', () {
    final now = DateTime(2026, 11, 1, 23, 59);
    expect(isOverdue(DateTime(2026, 11, 1), now), isFalse);
    expect(isOverdue(DateTime(2026, 10, 31), now), isTrue);
  });

  test('day keys are stable', () {
    expect(dayKey(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
  });
}
