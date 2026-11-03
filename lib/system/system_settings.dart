import 'package:flutter/material.dart';

import 'prayer_times.dart';

/// One kind of event the island can announce.
class IslandModule {
  const IslandModule(this.key, this.title, this.subtitle, this.icon);

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

const List<IslandModule> islandModules = [
  IslandModule('media', 'Music and video', 'Song or video playing in any app',
      Icons.music_note_rounded),
  IslandModule('notification', 'Notifications', 'Messages and alerts from other apps',
      Icons.notifications_active_outlined),
  IslandModule('battery', 'Battery', 'Charging, full and low battery',
      Icons.battery_charging_full_rounded),
  IslandModule('audio', 'Headphones', 'Bluetooth and wired audio devices',
      Icons.headphones_rounded),
  IslandModule('call', 'Calls', 'Incoming and ongoing calls', Icons.call_rounded),
  IslandModule('apps', 'App switching', 'A small animation when you move between apps',
      Icons.swap_horiz_rounded),
  IslandModule('network', 'Network', 'Wi-Fi and mobile data changes',
      Icons.wifi_rounded),
  IslandModule('prayer', 'Prayer times', 'A reminder at each prayer',
      Icons.mosque_outlined),
  IslandModule('calendar', 'Appointments', 'Reminders from your calendar',
      Icons.event_rounded),
];

const String defaultAiModel = 'meta/llama-3.3-70b-instruct';
const String defaultAiBaseUrl = 'https://integrate.api.nvidia.com/v1';
const String defaultWakeWords = 'soli,solly,sully,سولي,سولى';

/// Settings for the system island, prayer times and the voice assistant.
/// Stored with the rest of the app data and pushed to the native service.
class SystemSettings {
  const SystemSettings({
    this.disabledModules = const <String>[],
    this.mediaMini = false,
    this.idlePill = true,
    this.cityIndex = 0,
    this.methodIndex = 0,
    this.hanafi = false,
    this.prayerAlerts = true,
    this.aiEnabled = false,
    this.aiKey = '',
    this.aiModel = defaultAiModel,
    this.aiBaseUrl = defaultAiBaseUrl,
    this.wakeWords = defaultWakeWords,
    this.aiLanguage = 'auto',
    this.aiSpeak = true,
    this.requireWake = true,
    this.quietWhileWatching = true,
  });

  final List<String> disabledModules;

  /// Keep a small media pill visible while something is playing.
  final bool mediaMini;

  /// Always show time, date and weather in a small pill.
  final bool idlePill;
  final int cityIndex;
  final int methodIndex;
  final bool hanafi;
  final bool prayerAlerts;

  final bool aiEnabled;
  final String aiKey;
  final String aiModel;
  final String aiBaseUrl;
  final String wakeWords;
  final String aiLanguage;
  final bool aiSpeak;
  final bool requireWake;

  /// Hold notifications and messages while a video is playing.
  final bool quietWhileWatching;

  PrayerCity get city =>
      prayerCities[cityIndex < 0 || cityIndex >= prayerCities.length ? 0 : cityIndex];

  PrayerMethod get method => PrayerMethod
      .values[methodIndex < 0 || methodIndex >= PrayerMethod.values.length ? 0 : methodIndex];

  bool moduleOn(String key) => !disabledModules.contains(key);

  SystemSettings withModule(String key, bool on) {
    final next = disabledModules.where((k) => k != key).toList();
    if (!on) next.add(key);
    return copyWith(disabledModules: next);
  }

  SystemSettings copyWith({
    List<String>? disabledModules,
    bool? mediaMini,
    bool? idlePill,
    int? cityIndex,
    int? methodIndex,
    bool? hanafi,
    bool? prayerAlerts,
    bool? aiEnabled,
    String? aiKey,
    String? aiModel,
    String? aiBaseUrl,
    String? wakeWords,
    String? aiLanguage,
    bool? aiSpeak,
    bool? requireWake,
    bool? quietWhileWatching,
  }) {
    return SystemSettings(
      disabledModules: disabledModules ?? this.disabledModules,
      mediaMini: mediaMini ?? this.mediaMini,
      idlePill: idlePill ?? this.idlePill,
      cityIndex: cityIndex ?? this.cityIndex,
      methodIndex: methodIndex ?? this.methodIndex,
      hanafi: hanafi ?? this.hanafi,
      prayerAlerts: prayerAlerts ?? this.prayerAlerts,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiKey: aiKey ?? this.aiKey,
      aiModel: aiModel ?? this.aiModel,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      wakeWords: wakeWords ?? this.wakeWords,
      aiLanguage: aiLanguage ?? this.aiLanguage,
      aiSpeak: aiSpeak ?? this.aiSpeak,
      requireWake: requireWake ?? this.requireWake,
      quietWhileWatching: quietWhileWatching ?? this.quietWhileWatching,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'disabledModules': disabledModules,
        'mediaMini': mediaMini,
        'idlePill': idlePill,
        'cityIndex': cityIndex,
        'methodIndex': methodIndex,
        'hanafi': hanafi,
        'prayerAlerts': prayerAlerts,
        'aiEnabled': aiEnabled,
        'aiKey': aiKey,
        'aiModel': aiModel,
        'aiBaseUrl': aiBaseUrl,
        'wakeWords': wakeWords,
        'aiLanguage': aiLanguage,
        'aiSpeak': aiSpeak,
        'requireWake': requireWake,
        'quietWhileWatching': quietWhileWatching,
      };

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    bool b(String k, bool d) => json[k] is bool ? json[k] as bool : d;
    int i(String k, int d) => json[k] is num ? (json[k] as num).toInt() : d;
    String s(String k, String d) =>
        json[k] is String && (json[k] as String).isNotEmpty ? json[k] as String : d;
    final disabled = json['disabledModules'];
    return SystemSettings(
      disabledModules: disabled is List
          ? disabled.whereType<String>().toList()
          : const <String>[],
      mediaMini: b('mediaMini', false),
      idlePill: b('idlePill', true),
      cityIndex: i('cityIndex', 0),
      methodIndex: i('methodIndex', 0),
      hanafi: b('hanafi', false),
      prayerAlerts: b('prayerAlerts', true),
      aiEnabled: b('aiEnabled', false),
      aiKey: json['aiKey'] is String ? json['aiKey'] as String : '',
      aiModel: s('aiModel', defaultAiModel),
      aiBaseUrl: s('aiBaseUrl', defaultAiBaseUrl),
      wakeWords: _migrateWake(s('wakeWords', defaultWakeWords)),
      aiLanguage: _migrateLanguage(s('aiLanguage', 'auto')),
      aiSpeak: b('aiSpeak', true),
      requireWake: b('requireWake', true),
      quietWhileWatching: b('quietWhileWatching', true),
    );
  }
}

/// The assistant was called Nova before it became Soli.
String _migrateWake(String value) => value == 'نوفا,nova' ? defaultWakeWords : value;

/// The old default was a single Arabic dialect; the new default understands all three languages.
String _migrateLanguage(String value) => value == 'ar-EG' ? 'auto' : value;
