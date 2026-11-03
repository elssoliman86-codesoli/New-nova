import 'package:flutter_test/flutter_test.dart';
import 'package:nova/system/system_models.dart';
import 'package:nova/system/system_settings.dart';

void main() {
  test('snapshot parses the Android map and tolerates missing fields', () {
    final s = SystemSnapshot.fromMap({
      'device': 'Google Pixel',
      'sdk': 34,
      'permissions': {'overlay': true, 'notificationAccess': false, 'microphone': true},
      'service': {'running': true, 'overlayAttached': true, 'eventsShown': 3},
      'media': {'active': true, 'playing': true, 'title': 'Song', 'artist': 'Artist', 'app': 'YouTube'},
      'battery': {'level': 82, 'charging': true, 'temperature': 31.5},
      'storage': {'total': 1000, 'free': 250},
      'memory': {'total': 4000, 'free': 1000},
      'audioDevices': [
        {'kind': 'Bluetooth', 'name': 'Buds'},
      ],
      'screenTime': {
        'available': true,
        'totalMs': 3600000,
        'apps': [
          {'name': 'YouTube', 'package': 'com.google.android.youtube', 'ms': 1800000},
        ],
      },
    });
    expect(s.device, 'Google Pixel');
    expect(s.permissions.overlay, isTrue);
    expect(s.permissions.notificationAccess, isFalse);
    expect(s.permissions.usageAccess, isFalse);
    expect(s.service.running, isTrue);
    expect(s.media.title, 'Song');
    expect(s.batteryLevel, 82);
    expect(s.storageUsedFraction, closeTo(0.75, 1e-9));
    expect(s.memoryUsedFraction, closeTo(0.75, 1e-9));
    expect(s.audioDevices.single.label, 'Buds (Bluetooth)');
    expect(s.screenTimeToday, const Duration(hours: 1));
    expect(s.topApps.single.name, 'YouTube');
    // Missing sections fall back to safe defaults.
    expect(s.assistant.on, isFalse);
    expect(s.weather, '');
  });

  test('empty snapshot does not throw', () {
    final s = SystemSnapshot.fromMap(const {});
    expect(s.batteryLevel, -1);
    expect(s.topApps, isEmpty);
    expect(s.audioDevices, isEmpty);
  });

  test('formatters', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    expect(formatDuration(const Duration(minutes: 135)), '2h 15m');
    expect(formatDuration(const Duration(minutes: 7)), '7m');
  });

  test('system settings round trip and module toggles', () {
    const base = SystemSettings();
    final changed = base
        .withModule('network', false)
        .copyWith(aiEnabled: true, aiKey: 'nvapi-x', aiModel: 'a/b', cityIndex: 2);
    final back = SystemSettings.fromJson(changed.toJson());
    expect(back.moduleOn('network'), isFalse);
    expect(back.moduleOn('media'), isTrue);
    expect(back.aiEnabled, isTrue);
    expect(back.aiKey, 'nvapi-x');
    expect(back.aiModel, 'a/b');
    expect(back.city.name, 'Alexandria');
    expect(back.withModule('network', true).moduleOn('network'), isTrue);
  });

  test('bad saved data falls back to defaults', () {
    final s = SystemSettings.fromJson({'cityIndex': 999, 'methodIndex': -3, 'aiModel': ''});
    expect(s.city.name, 'Cairo');
    expect(s.aiModel, defaultAiModel);
    expect(s.method.name, 'egyptian');
  });

  test('old Nova settings migrate to Soli and auto language', () {
    final old = SystemSettings.fromJson(<String, dynamic>{
      'wakeWords': 'نوفا,nova',
      'aiLanguage': 'ar-EG',
    });
    expect(old.wakeWords, defaultWakeWords);
    expect(old.aiLanguage, 'auto');
    expect(old.quietWhileWatching, isTrue);
    final custom = SystemSettings.fromJson(<String, dynamic>{'wakeWords': 'jarvis'});
    expect(custom.wakeWords, 'jarvis');
  });
}
