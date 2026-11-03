import 'package:flutter/services.dart';

class SystemIslandStatus {
  const SystemIslandStatus({
    required this.overlayGranted,
    required this.notificationAccessGranted,
  });

  final bool overlayGranted;
  final bool notificationAccessGranted;

  bool get ready => overlayGranted && notificationAccessGranted;

  factory SystemIslandStatus.fromMap(Map<Object?, Object?> map) {
    return SystemIslandStatus(
      overlayGranted: map['overlayGranted'] == true,
      notificationAccessGranted: map['notificationAccessGranted'] == true,
    );
  }
}

class SystemIslandBridge {
  static const MethodChannel _channel =
      MethodChannel('com.codesoli.nova/system_island');

  static Future<SystemIslandStatus> status() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
    return SystemIslandStatus.fromMap(result ?? const {});
  }

  static Future<void> openOverlaySettings() =>
      _channel.invokeMethod<void>('openOverlaySettings');

  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  static Future<void> start() =>
      _channel.invokeMethod<void>('startIsland');

  static Future<void> stop() =>
      _channel.invokeMethod<void>('stopIsland');

  static Future<Map<Object?, Object?>> snapshot() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('snapshot');
    return result ?? const <Object?, Object?>{};
  }

  static Future<void> openUsageSettings() =>
      _channel.invokeMethod<void>('openUsageSettings');

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  static Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  static Future<void> requestIgnoreBattery() =>
      _channel.invokeMethod<void>('requestIgnoreBattery');

  static Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');

  /// [groups] can contain `island` and `assistant`.
  static Future<void> requestPermissions(List<String> groups) =>
      _channel.invokeMethod<void>('requestPermissions', {'groups': groups});

  static Future<void> setConfig(Map<String, Object?> config) =>
      _channel.invokeMethod<void>('setConfig', config);

  static Future<void> schedulePrayers(Map<String, Object?> payload) =>
      _channel.invokeMethod<void>('schedulePrayers', payload);

  static Future<void> testEvent({String? kind, String? title, String? body}) =>
      _channel.invokeMethod<void>('testEvent', {
        if (kind != null) 'kind': kind,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      });

  static Future<void> mediaControl(String action) =>
      _channel.invokeMethod<void>('mediaControl', {'action': action});

  static Future<void> assistantSubmit(String text) =>
      _channel.invokeMethod<void>('assistantSubmit', {'text': text});

  static Future<void> assistantListen() =>
      _channel.invokeMethod<void>('assistantListen');

  /// Facts the assistant saved about the user. They live only on this phone.
  static Future<List<Map<Object?, Object?>>> memoryList() async {
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>('memoryList');
    return result ?? const <Map<Object?, Object?>>[];
  }

  static Future<bool> memoryAdd(String text) async =>
      (await _channel.invokeMethod<bool>('memoryAdd', {'text': text})) ?? false;

  static Future<void> memoryDelete(int id) =>
      _channel.invokeMethod<void>('memoryDelete', {'id': id});

  static Future<void> memoryClear() => _channel.invokeMethod<void>('memoryClear');
}
