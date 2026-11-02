import 'package:flutter_test/flutter_test.dart';
import 'package:nova/system/prayer_times.dart';

void main() {
  final cairo = prayerCities.first;

  PrayerTimes cairoTimes({PrayerMethod method = PrayerMethod.egyptian, bool hanafi = false}) {
    // Egypt is UTC+2 in November. The offset is explicit so the test does not
    // depend on the machine's time zone.
    return computePrayerTimes(
      latitude: cairo.latitude,
      longitude: cairo.longitude,
      date: DateTime(2026, 11, 2),
      method: method,
      hanafi: hanafi,
      utcOffsetHours: 2,
    )!;
  }

  int minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  void expectBetween(DateTime t, String from, String to) {
    int parse(String s) {
      final p = s.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final m = minutesOfDay(t);
    expect(m, inInclusiveRange(parse(from), parse(to)),
        reason: 'got ${t.hour}:${t.minute.toString().padLeft(2, '0')}');
  }

  test('Cairo in early November falls in the expected windows', () {
    final t = cairoTimes();
    expectBetween(t.fajr, '04:35', '05:00');
    expectBetween(t.sunrise, '06:05', '06:30');
    expectBetween(t.dhuhr, '11:30', '11:50');
    expectBetween(t.asr, '14:35', '14:58');
    expectBetween(t.maghrib, '16:45', '17:10');
    expectBetween(t.isha, '18:10', '18:45');
  });

  test('prayers are in chronological order', () {
    final t = cairoTimes();
    final list = t.entries.map((e) => e.time).toList();
    for (var i = 1; i < list.length; i++) {
      expect(list[i].isAfter(list[i - 1]), isTrue, reason: 'index $i');
    }
  });

  test('Hanafi Asr is later than the standard Asr', () {
    final standard = cairoTimes().asr;
    final hanafi = cairoTimes(hanafi: true).asr;
    expect(hanafi.isAfter(standard), isTrue);
  });

  test('Umm al-Qura sets Isha 90 minutes after Maghrib', () {
    final t = cairoTimes(method: PrayerMethod.ummAlQura);
    expect(t.isha.difference(t.maghrib).inMinutes, 90);
  });

  test('Egyptian Isha is later than the Muslim World League Isha', () {
    // 17.5 degrees vs 17 degrees below the horizon.
    final egyptian = cairoTimes().isha;
    final mwl = cairoTimes(method: PrayerMethod.mwl).isha;
    expect(egyptian.isAfter(mwl) || egyptian.isAtSameMomentAs(mwl), isTrue);
  });

  test('high latitude in summer still returns usable times', () {
    final london = prayerCities.firstWhere((c) => c.name == 'London');
    final t = computePrayerTimes(
      latitude: london.latitude,
      longitude: london.longitude,
      date: DateTime(2026, 6, 21),
      method: PrayerMethod.mwl,
      utcOffsetHours: 1,
    );
    expect(t, isNotNull);
    expect(t!.isha.isAfter(t.maghrib), isTrue);
    expect(t.fajr.isBefore(t.sunrise), isTrue);
  });

  test('next prayer after Isha is tomorrow\'s Fajr', () {
    final now = DateTime(2026, 11, 2, 23, 30);
    final next = nextPrayer(
      now: now,
      latitude: cairo.latitude,
      longitude: cairo.longitude,
    );
    expect(next, isNotNull);
    expect(next!.name, 'Fajr');
    expect(next.time.day, 3);
  });

  test('upcoming prayers only contain the future and skip sunrise', () {
    final now = DateTime(2026, 11, 2, 12, 0);
    final list = upcomingPrayers(
      now: now,
      latitude: cairo.latitude,
      longitude: cairo.longitude,
      days: 2,
    );
    expect(list.every((e) => e.time.isAfter(now)), isTrue);
    expect(list.any((e) => e.name == 'Sunrise'), isFalse);
    // Asr, Maghrib, Isha today + 5 prayers tomorrow.
    expect(list, hasLength(8));
  });

  test('clock and countdown formatting', () {
    expect(formatClock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
    expect(formatClock(DateTime(2026, 1, 1, 15, 21)), '3:21 PM');
    expect(formatCountdown(const Duration(hours: 1, minutes: 5)), '1h 05m');
    expect(formatCountdown(const Duration(minutes: 12, seconds: 3)), '12m 03s');
    expect(formatCountdown(const Duration(seconds: -4)), '0s');
  });
}
