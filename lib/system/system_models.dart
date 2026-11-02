/// Typed view of the map the Android side returns from `snapshot`.
/// Every reader is defensive: a missing field never throws.

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, Object?>{};
}

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : d;
bool _bool(Object? v, [bool d = false]) => v is bool ? v : d;
String _str(Object? v, [String d = '']) => v is String ? v : d;

class PermissionState {
  const PermissionState(this.values);

  final Map<String, Object?> values;

  bool _has(String k) => _bool(values[k]);

  bool get overlay => _has('overlay');
  bool get notificationAccess => _has('notificationAccess');
  bool get usageAccess => _has('usageAccess');
  bool get ignoringBatteryOptimizations => _has('ignoringBatteryOptimizations');
  bool get exactAlarms => _has('exactAlarms');
  bool get bluetooth => _has('bluetooth');
  bool get phoneState => _has('phoneState');
  bool get microphone => _has('microphone');
  bool get contacts => _has('contacts');
  bool get callPhone => _has('callPhone');
  bool get accessibility => _has('accessibility');
}

class ServiceState {
  const ServiceState(this.m);

  final Map<String, Object?> m;

  bool get running => _bool(m['running']);
  bool get overlayAttached => _bool(m['overlayAttached']);
  bool get listenerConnected => _bool(m['listenerConnected']);
  bool get autostart => _bool(m['autostart']);
  int get eventsShown => _int(m['eventsShown']);
  String get lastEventTitle => _str(m['lastEventTitle']);
  String get lastEventBody => _str(m['lastEventBody']);
  DateTime? get lastEventAt {
    final ms = _int(m['lastEventAt']);
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

class MediaState {
  const MediaState(this.m);

  final Map<String, Object?> m;

  bool get active => _bool(m['active']);
  bool get playing => _bool(m['playing']);
  String get title => _str(m['title']);
  String get artist => _str(m['artist']);
  String get app => _str(m['app']);
}

class AudioDevice {
  const AudioDevice(this.kind, this.name);

  final String kind;
  final String name;

  String get label => name.isEmpty ? kind : '$name ($kind)';
}

class UsageApp {
  const UsageApp(this.name, this.package, this.millis);

  final String name;
  final String package;
  final int millis;
}

class AssistantInfo {
  const AssistantInfo(this.m);

  final Map<String, Object?> m;

  bool get on => _bool(m['on']);
  String get state => _str(m['state'], 'off');
  String get heard => _str(m['heard']);
  String get reply => _str(m['reply']);
  String get error => _str(m['error']);
  bool get hasKey => _bool(m['hasKey']);
  String get model => _str(m['model']);
}

class SystemSnapshot {
  SystemSnapshot(Map<String, Object?> raw)
      : device = _str(raw['device']),
        sdk = _int(raw['sdk']),
        permissions = PermissionState(_map(raw['permissions'])),
        service = ServiceState(_map(raw['service'])),
        media = MediaState(_map(raw['media'])),
        assistant = AssistantInfo(_map(raw['assistant'])),
        network = _str(raw['network']),
        weather = _str(_map(raw['weather'])['text']),
        _raw = raw;

  factory SystemSnapshot.fromMap(Map<Object?, Object?> raw) =>
      SystemSnapshot(raw.map((k, v) => MapEntry(k.toString(), v)));

  final Map<String, Object?> _raw;
  final String device;
  final int sdk;
  final PermissionState permissions;
  final ServiceState service;
  final MediaState media;
  final AssistantInfo assistant;
  final String network;
  final String weather;

  int get notificationsSeen => _int(_map(_raw['notifications'])['seen']);
  String get lastNotificationApp => _str(_map(_raw['notifications'])['lastApp']);

  int get batteryLevel => _int(_map(_raw['battery'])['level'], -1);
  bool get charging => _bool(_map(_raw['battery'])['charging']);
  bool get batteryFull => _bool(_map(_raw['battery'])['full']);
  String get chargeSource => _str(_map(_raw['battery'])['source']);
  double get batteryTemp => _dbl(_map(_raw['battery'])['temperature']);

  int get storageTotal => _int(_map(_raw['storage'])['total']);
  int get storageFree => _int(_map(_raw['storage'])['free']);
  double get storageUsedFraction =>
      storageTotal <= 0 ? 0 : (storageTotal - storageFree) / storageTotal;

  int get memoryTotal => _int(_map(_raw['memory'])['total']);
  int get memoryFree => _int(_map(_raw['memory'])['free']);
  double get memoryUsedFraction =>
      memoryTotal <= 0 ? 0 : (memoryTotal - memoryFree) / memoryTotal;

  List<AudioDevice> get audioDevices {
    final list = _raw['audioDevices'];
    if (list is! List) return const <AudioDevice>[];
    return list.map((e) {
      final m = _map(e);
      return AudioDevice(_str(m['kind']), _str(m['name']));
    }).toList();
  }

  String get foregroundName => _str(_map(_raw['foreground'])['name']);
  String get foregroundPackage => _str(_map(_raw['foreground'])['package']);

  bool get screenTimeAvailable => _bool(_map(_raw['screenTime'])['available']);
  Duration get screenTimeToday =>
      Duration(milliseconds: _int(_map(_raw['screenTime'])['totalMs']));

  List<UsageApp> get topApps {
    final list = _map(_raw['screenTime'])['apps'];
    if (list is! List) return const <UsageApp>[];
    return list.map((e) {
      final m = _map(e);
      return UsageApp(_str(m['name']), _str(m['package']), _int(m['ms']));
    }).toList();
  }

  int get prayersScheduled => _int(_map(_raw['prayer'])['scheduled']);
  String get nextPrayerLabel => _str(_map(_raw['prayer'])['nextLabel']);
  bool get exactAlarmsInUse => _bool(_map(_raw['prayer'])['exactAlarms']);
}

/// `12.4 GB` style size.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// `2h 05m` / `14m` for screen time.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${m}m';
}
