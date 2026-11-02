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
}
