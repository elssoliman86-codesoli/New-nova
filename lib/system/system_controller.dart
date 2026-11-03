import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/system_island_bridge.dart';
import 'prayer_times.dart';
import 'system_models.dart';
import 'system_settings.dart';

const Map<String, String> _arabicPrayer = {
  'Fajr': 'الفجر',
  'Dhuhr': 'الظهر',
  'Asr': 'العصر',
  'Maghrib': 'المغرب',
  'Isha': 'العشاء',
};

/// Talks to the Android side: reads the live device snapshot, pushes the
/// settings and runs actions. Everything is safe on platforms without the
/// native layer (tests, desktop): calls simply do nothing.
class SystemController extends ChangeNotifier {
  SystemSnapshot? _snapshot;
  bool _supported = true;
  String? _error;
  Timer? _timer;
  int _watchers = 0;
  bool _disposed = false;
  bool _refreshing = false;

  SystemSnapshot? get snapshot => _snapshot;

  /// False when the native layer is missing (not running on Android).
  bool get supported => _supported;
  String? get error => _error;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      final raw = await SystemIslandBridge.snapshot();
      _snapshot = SystemSnapshot.fromMap(raw);
      _supported = true;
      _error = null;
    } on MissingPluginException {
      _supported = false;
    } on PlatformException catch (e) {
      _error = e.message ?? e.code;
    } catch (e) {
      _error = e.toString();
    } finally {
      _refreshing = false;
    }
    notifyListeners();
  }

  /// Starts polling while a screen that shows live data is open.
  void watch() {
    _watchers++;
    if (_timer == null) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    }
  }

  void unwatch() {
    _watchers = _watchers > 0 ? _watchers - 1 : 0;
    if (_watchers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Runs a native action. Returns an error message, or null on success.
  Future<String?> run(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
      return null;
    } on MissingPluginException {
      return 'This works only on Android.';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _quiet(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Not on Android, or the service is not available: nothing to push to.
    }
  }

  /// Restarts the island after Nova is opened again if the user had it on.
  Future<void> autoStart() async {
    await refresh();
    final s = _snapshot;
    if (s == null) return;
    if (s.service.autostart && !s.service.running && s.permissions.overlay) {
      await _quiet(SystemIslandBridge.start);
      await refresh();
    }
  }

  Future<void> pushConfig(SystemSettings s, {int tasksToday = 0, String nextTask = ''}) {
    return _quiet(() => SystemIslandBridge.setConfig(<String, Object?>{
          'disabled': s.disabledModules,
          'mediaMini': s.mediaMini,
          'idle': s.idlePill,
          'latitude': s.city.latitude,
          'longitude': s.city.longitude,
          'city': s.city.name,
          'tasksToday': tasksToday,
          'nextTask': nextTask,
          'enabled': s.aiEnabled,
          'apiKey': s.aiKey,
          'model': s.aiModel,
          'baseUrl': s.aiBaseUrl,
          'wakeWords': s.wakeWords,
          'language': s.aiLanguage,
          'speak': s.aiSpeak,
          'requireWake': s.requireWake,
        }));
  }

  /// Sends the next two weeks of prayer times so the phone can remind the
  /// user even when Nova is closed.
  Future<void> pushPrayers(SystemSettings s) {
    final city = s.city;
    final upcoming = upcomingPrayers(
      now: DateTime.now(),
      latitude: city.latitude,
      longitude: city.longitude,
      method: s.method,
      hanafi: s.hanafi,
      days: 14,
    );
    final items = upcoming
        .map((e) => <String, Object?>{
              'at': e.time.millisecondsSinceEpoch,
              'label': '${e.name} · ${_arabicPrayer[e.name] ?? e.name}',
              'body': 'حان وقت الصلاة · ${formatClock(e.time)}',
            })
        .toList();
    return _quiet(() => SystemIslandBridge.schedulePrayers(<String, Object?>{
          'alerts': s.prayerAlerts,
          'items': items,
        }));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
