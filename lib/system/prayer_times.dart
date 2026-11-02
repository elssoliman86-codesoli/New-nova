import 'dart:math' as math;

/// Prayer time calculation (no network, no plugins).
///
/// Uses the same astronomical method as PrayTimes.org: sun position from the
/// Julian date, then the hour angle for each sun altitude. Results can differ
/// by a minute or two from a local mosque timetable.

enum PrayerMethod { egyptian, ummAlQura, mwl, karachi, isna }

extension PrayerMethodX on PrayerMethod {
  String get label {
    switch (this) {
      case PrayerMethod.egyptian:
        return 'Egyptian General Authority';
      case PrayerMethod.ummAlQura:
        return 'Umm al-Qura (Makkah)';
      case PrayerMethod.mwl:
        return 'Muslim World League';
      case PrayerMethod.karachi:
        return 'University of Karachi';
      case PrayerMethod.isna:
        return 'ISNA (North America)';
    }
  }

  String get shortLabel {
    switch (this) {
      case PrayerMethod.egyptian:
        return 'Egyptian';
      case PrayerMethod.ummAlQura:
        return 'Umm al-Qura';
      case PrayerMethod.mwl:
        return 'MWL';
      case PrayerMethod.karachi:
        return 'Karachi';
      case PrayerMethod.isna:
        return 'ISNA';
    }
  }
}

class _MethodParams {
  const _MethodParams(this.fajr, this.isha, {this.ishaMinutesAfterMaghrib = 0});

  final double fajr;
  final double isha;

  /// When above zero, Isha is this many minutes after Maghrib (Umm al-Qura).
  final int ishaMinutesAfterMaghrib;
}

const Map<PrayerMethod, _MethodParams> _params = {
  PrayerMethod.egyptian: _MethodParams(19.5, 17.5),
  PrayerMethod.mwl: _MethodParams(18, 17),
  PrayerMethod.ummAlQura: _MethodParams(18.5, 0, ishaMinutesAfterMaghrib: 90),
  PrayerMethod.karachi: _MethodParams(18, 18),
  PrayerMethod.isna: _MethodParams(15, 15),
};

class PrayerCity {
  const PrayerCity(this.name, this.country, this.latitude, this.longitude);

  final String name;
  final String country;
  final double latitude;
  final double longitude;

  String get label => '$name, $country';
}

const List<PrayerCity> prayerCities = [
  PrayerCity('Cairo', 'Egypt', 30.0444, 31.2357),
  PrayerCity('Giza', 'Egypt', 30.0131, 31.2089),
  PrayerCity('Alexandria', 'Egypt', 31.2001, 29.9187),
  PrayerCity('Mansoura', 'Egypt', 31.0409, 31.3785),
  PrayerCity('Tanta', 'Egypt', 30.7865, 31.0004),
  PrayerCity('Port Said', 'Egypt', 31.2565, 32.2841),
  PrayerCity('Suez', 'Egypt', 29.9668, 32.5498),
  PrayerCity('Asyut', 'Egypt', 27.1809, 31.1837),
  PrayerCity('Luxor', 'Egypt', 25.6872, 32.6396),
  PrayerCity('Aswan', 'Egypt', 24.0889, 32.8998),
  PrayerCity('Makkah', 'Saudi Arabia', 21.3891, 39.8579),
  PrayerCity('Madinah', 'Saudi Arabia', 24.5247, 39.5692),
  PrayerCity('Riyadh', 'Saudi Arabia', 24.7136, 46.6753),
  PrayerCity('Jeddah', 'Saudi Arabia', 21.4858, 39.1925),
  PrayerCity('Dubai', 'UAE', 25.2048, 55.2708),
  PrayerCity('Amman', 'Jordan', 31.9454, 35.9284),
  PrayerCity('Istanbul', 'Turkey', 41.0082, 28.9784),
  PrayerCity('London', 'United Kingdom', 51.5074, -0.1278),
];

class PrayerTimes {
  const PrayerTimes({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// All six times in order, with their display names.
  List<PrayerEntry> get entries => [
        PrayerEntry('Fajr', fajr),
        PrayerEntry('Sunrise', sunrise, isPrayer: false),
        PrayerEntry('Dhuhr', dhuhr),
        PrayerEntry('Asr', asr),
        PrayerEntry('Maghrib', maghrib),
        PrayerEntry('Isha', isha),
      ];

  /// Only the five obligatory prayers (no sunrise).
  List<PrayerEntry> get prayers => entries.where((e) => e.isPrayer).toList();
}

class PrayerEntry {
  const PrayerEntry(this.name, this.time, {this.isPrayer = true});

  final String name;
  final DateTime time;
  final bool isPrayer;
}

// -------------------------------------------------------------- astronomy

double _dtr(double d) => d * math.pi / 180;
double _rtd(double r) => r * 180 / math.pi;
double _sin(double d) => math.sin(_dtr(d));
double _cos(double d) => math.cos(_dtr(d));
double _tan(double d) => math.tan(_dtr(d));
double _arcsin(double x) => _rtd(math.asin(x));
double _arccos(double x) => _rtd(math.acos(x));
double _arctan2(double y, double x) => _rtd(math.atan2(y, x));
double _arccot(double x) => _rtd(math.atan(1 / x));

double _fix(double a, double mode) {
  final r = a - mode * (a / mode).floorToDouble();
  return r < 0 ? r + mode : r;
}

double _fixAngle(double a) => _fix(a, 360);
double _fixHour(double a) => _fix(a, 24);

double _julian(int year, int month, int day) {
  var y = year;
  var m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floorToDouble() +
      (30.6001 * (m + 1)).floorToDouble() +
      day +
      b -
      1524.5;
}

class _Sun {
  const _Sun(this.declination, this.equation);

  final double declination;
  final double equation;
}

_Sun _sunPosition(double jd) {
  final d = jd - 2451545.0;
  final g = _fixAngle(357.529 + 0.98560028 * d);
  final q = _fixAngle(280.459 + 0.98564736 * d);
  final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
  final e = 23.439 - 0.00000036 * d;
  final ra = _arctan2(_cos(e) * _sin(l), _cos(l)) / 15;
  final eqt = q / 15 - _fixHour(ra);
  final decl = _arcsin(_sin(e) * _sin(l));
  return _Sun(decl, eqt);
}

class _Calc {
  _Calc(this.jd, this.lat);

  final double jd;
  final double lat;

  double midDay(double t) {
    final eqt = _sunPosition(jd + t).equation;
    return _fixHour(12 - eqt);
  }

  /// Time when the sun is [angle] degrees below the horizon.
  /// NaN when it never gets that low (high latitudes).
  double sunAngleTime(double angle, double t, {bool ccw = false}) {
    final decl = _sunPosition(jd + t).declination;
    final noon = midDay(t);
    final v = (-_sin(angle) - _sin(decl) * _sin(lat)) / (_cos(decl) * _cos(lat));
    if (v.isNaN || v < -1 || v > 1) return double.nan;
    final dt = _arccos(v) / 15;
    return noon + (ccw ? -dt : dt);
  }

  double asrTime(double factor, double t) {
    final decl = _sunPosition(jd + t).declination;
    final angle = -_arccot(factor + _tan((lat - decl).abs()));
    return sunAngleTime(angle, t);
  }
}

/// Computes the prayer times for [date] at the given coordinates.
///
/// [utcOffsetHours] defaults to the device's current offset for that date.
/// Returns null only for polar regions where the sun does not rise or set.
PrayerTimes? computePrayerTimes({
  required double latitude,
  required double longitude,
  required DateTime date,
  PrayerMethod method = PrayerMethod.egyptian,
  bool hanafi = false,
  double? utcOffsetHours,
}) {
  final p = _params[method]!;
  final tz = utcOffsetHours ??
      DateTime(date.year, date.month, date.day, 12).timeZoneOffset.inMinutes / 60;

  final calc = _Calc(
    _julian(date.year, date.month, date.day) - longitude / (15 * 24),
    latitude,
  );
  const riseSetAngle = 0.833;

  var fajr = calc.sunAngleTime(p.fajr, 5 / 24, ccw: true);
  var sunrise = calc.sunAngleTime(riseSetAngle, 6 / 24, ccw: true);
  var dhuhr = calc.midDay(12 / 24);
  var asr = calc.asrTime(hanafi ? 2 : 1, 13 / 24);
  var sunset = calc.sunAngleTime(riseSetAngle, 18 / 24);
  if (sunrise.isNaN || sunset.isNaN) return null;

  var maghrib = sunset;
  var isha = p.ishaMinutesAfterMaghrib > 0
      ? maghrib + p.ishaMinutesAfterMaghrib / 60
      : calc.sunAngleTime(p.isha, 18 / 24);

  // Convert from solar hours to local clock hours.
  final shift = tz - longitude / 15;
  fajr += shift;
  sunrise += shift;
  dhuhr += shift;
  asr += shift;
  maghrib += shift;
  isha += shift;
  sunset += shift;

  // Far from the equator the sun may never reach Fajr/Isha depression:
  // fall back to 90 minutes from sunrise / sunset.
  if (fajr.isNaN) fajr = sunrise - 1.5;
  if (isha.isNaN) isha = maghrib + 1.5;

  final midnight = DateTime(date.year, date.month, date.day);
  DateTime at(double hours) {
    final minutes = (_fixHour(hours) * 60).round();
    return midnight.add(Duration(minutes: minutes));
  }

  return PrayerTimes(
    fajr: at(fajr),
    sunrise: at(sunrise),
    dhuhr: at(dhuhr),
    asr: at(asr),
    maghrib: at(maghrib),
    isha: at(isha),
  );
}

/// The next prayer after [now] (skipping sunrise), looking into tomorrow.
PrayerEntry? nextPrayer({
  required DateTime now,
  required double latitude,
  required double longitude,
  PrayerMethod method = PrayerMethod.egyptian,
  bool hanafi = false,
}) {
  for (var offset = 0; offset < 3; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final times = computePrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: day,
      method: method,
      hanafi: hanafi,
    );
    if (times == null) continue;
    for (final entry in times.prayers) {
      if (entry.time.isAfter(now)) return entry;
    }
  }
  return null;
}

/// Prayers (no sunrise) for the next [days] days that are still in the
/// future. Used to schedule the alarms on the device.
List<PrayerEntry> upcomingPrayers({
  required DateTime now,
  required double latitude,
  required double longitude,
  PrayerMethod method = PrayerMethod.egyptian,
  bool hanafi = false,
  int days = 7,
}) {
  final result = <PrayerEntry>[];
  for (var offset = 0; offset < days; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final times = computePrayerTimes(
      latitude: latitude,
      longitude: longitude,
      date: day,
      method: method,
      hanafi: hanafi,
    );
    if (times == null) continue;
    for (final entry in times.prayers) {
      if (entry.time.isAfter(now)) result.add(entry);
    }
  }
  return result;
}

/// `3:21 PM` style label.
String formatClock(DateTime time) {
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// `1h 05m` / `12m` countdown label.
String formatCountdown(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes % 60;
  final s = total.inSeconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}
