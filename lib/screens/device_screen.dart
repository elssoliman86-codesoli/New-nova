import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../data/app_store.dart';
import '../platform/system_island_bridge.dart';
import '../system/prayer_times.dart';
import '../system/system_models.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';
import '../ui/states.dart';
import 'assistant_screen.dart';
import 'prayer_screen.dart';

enum _Status { ok, warn, info }

class _Check {
  const _Check({
    required this.icon,
    required this.title,
    required this.status,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final _Status status;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Live view of what Nova can see on this phone, with the permission each
/// feature needs. This is the place to confirm the island really works.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.active});

  /// Only poll the phone while this tab is visible.
  final bool active;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with WidgetsBindingObserver {
  AppStore? _store;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store ??= AppScope.read(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant DeviceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _store?.system.refresh();
      _sync();
    } else if (_watching) {
      _store?.system.unwatch();
      _watching = false;
    }
  }

  void _sync() {
    final system = _store?.system;
    if (system == null) return;
    if (widget.active && !_watching) {
      system.watch();
      _watching = true;
    } else if (!widget.active && _watching) {
      system.unwatch();
      _watching = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_watching) _store?.system.unwatch();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    final store = AppScope.read(context);
    final error = await store.system.run(action);
    if (error != null && mounted) {
      store.island.toast(error, icon: Icons.error_outline_rounded, tint: NovaColors.danger);
    }
  }

  List<_Check> _checks(SystemSnapshot s, AppStore store) {
    final p = s.permissions;
    final sys = store.systemSettings;
    final next = nextPrayer(
      now: DateTime.now(),
      latitude: sys.city.latitude,
      longitude: sys.city.longitude,
      method: sys.method,
      hanafi: sys.hanafi,
    );
    final nextText = next == null
        ? 'No prayer time for this city'
        : '${next.name} at ${formatClock(next.time)} · in ${formatCountdown(next.time.difference(DateTime.now()))}';
    final media = s.media;

    return [
      _Check(
        icon: Icons.layers_rounded,
        title: 'Island above all apps',
        status: p.overlay && s.service.running && s.service.overlayAttached
            ? _Status.ok
            : _Status.warn,
        detail: !p.overlay
            ? 'Needs "Display over other apps".'
            : !s.service.running
                ? 'Service is stopped. Tap Start.'
                : s.service.overlayAttached
                    ? 'The pill is on screen right now.'
                    : 'Service runs but the pill is hidden (swipe-dismissed or turned off).',
        actionLabel: !p.overlay ? 'Allow' : (!s.service.running ? 'Start' : null),
        onAction: !p.overlay
            ? () => _act(SystemIslandBridge.openOverlaySettings)
            : (!s.service.running ? () => _act(SystemIslandBridge.start) : null),
      ),
      _Check(
        icon: Icons.notifications_active_outlined,
        title: 'Notifications',
        status: p.notificationAccess ? _Status.ok : _Status.warn,
        detail: !p.notificationAccess
            ? 'Needs notification access to read alerts and see what media plays.'
            : s.notificationsSeen == 0
                ? 'Allowed. None received yet: send yourself a message to test.'
                : '${s.notificationsSeen} received · last from ${s.lastNotificationApp}',
        actionLabel: p.notificationAccess ? null : 'Allow',
        onAction: p.notificationAccess
            ? null
            : () => _act(SystemIslandBridge.openNotificationSettings),
      ),
      _Check(
        icon: Icons.music_note_rounded,
        title: 'Songs and videos (YouTube, Spotify…)',
        status: !p.notificationAccess
            ? _Status.warn
            : (media.active ? _Status.ok : _Status.info),
        detail: !p.notificationAccess
            ? 'Needs notification access (Android shares media sessions through it).'
            : media.active
                ? '${media.playing ? 'Playing' : 'Paused'}: ${media.title}'
                    '${media.artist.isEmpty ? '' : ' · ${media.artist}'}'
                    '${media.app.isEmpty ? '' : ' (${media.app})'}'
                : 'Nothing playing. Start a song or video in any app.',
      ),
      _Check(
        icon: Icons.headphones_rounded,
        title: 'Headphones and Bluetooth',
        status: p.bluetooth ? _Status.ok : _Status.warn,
        detail: !p.bluetooth
            ? 'Needs the Nearby devices permission.'
            : s.audioDevices.isEmpty
                ? 'No headphones connected.'
                : s.audioDevices.map((d) => d.label).join(', '),
        actionLabel: p.bluetooth ? null : 'Allow',
        onAction: p.bluetooth
            ? null
            : () => _act(() => SystemIslandBridge.requestPermissions(const ['island'])),
      ),
      _Check(
        icon: Icons.call_rounded,
        title: 'Calls',
        status: p.phoneState ? _Status.ok : _Status.warn,
        detail: p.phoneState ? 'Incoming and ongoing calls are announced.' : 'Needs the Phone permission.',
        actionLabel: p.phoneState ? null : 'Allow',
        onAction: p.phoneState
            ? null
            : () => _act(() => SystemIslandBridge.requestPermissions(const ['island'])),
      ),
      _Check(
        icon: Icons.battery_full_rounded,
        title: 'Battery',
        status: s.batteryLevel >= 0 ? _Status.ok : _Status.warn,
        detail: s.batteryLevel < 0
            ? 'Unavailable'
            : '${s.batteryLevel}%'
                '${s.charging ? ' · charging${s.chargeSource.isEmpty ? '' : ' (${s.chargeSource})'}' : ''}'
                ' · ${s.batteryTemp.toStringAsFixed(1)}°C',
      ),
      _Check(
        icon: Icons.sd_storage_outlined,
        title: 'Storage',
        status: s.storageTotal > 0 ? _Status.ok : _Status.warn,
        detail: s.storageTotal <= 0
            ? 'Unavailable'
            : '${formatBytes(s.storageFree)} free of ${formatBytes(s.storageTotal)}',
      ),
      _Check(
        icon: Icons.memory_rounded,
        title: 'Memory',
        status: s.memoryTotal > 0 ? _Status.ok : _Status.warn,
        detail: s.memoryTotal <= 0
            ? 'Unavailable'
            : '${formatBytes(s.memoryFree)} free of ${formatBytes(s.memoryTotal)}',
      ),
      _Check(
        icon: Icons.apps_rounded,
        title: 'Running app',
        status: p.usageAccess ? _Status.ok : _Status.warn,
        detail: !p.usageAccess
            ? 'Needs Usage access. Android only reveals the app in front, not every background app.'
            : s.foregroundName.isEmpty
                ? 'No app in front right now.'
                : 'In front: ${s.foregroundName}',
        actionLabel: p.usageAccess ? null : 'Allow',
        onAction: p.usageAccess ? null : () => _act(SystemIslandBridge.openUsageSettings),
      ),
      _Check(
        icon: Icons.timelapse_rounded,
        title: 'Screen time today',
        status: p.usageAccess && s.screenTimeAvailable ? _Status.ok : _Status.warn,
        detail: p.usageAccess && s.screenTimeAvailable
            ? '${formatDuration(s.screenTimeToday)} across ${s.topApps.length}+ apps'
            : 'Needs Usage access.',
        actionLabel: p.usageAccess ? null : 'Allow',
        onAction: p.usageAccess ? null : () => _act(SystemIslandBridge.openUsageSettings),
      ),
      _Check(
        icon: Icons.mosque_outlined,
        title: 'Prayer times',
        status: s.prayersScheduled > 0 && sys.prayerAlerts ? _Status.ok : _Status.info,
        detail: '$nextText · ${sys.city.name}'
            '${sys.prayerAlerts ? ' · ${s.prayersScheduled} reminders set' : ' · reminders off'}'
            '${p.exactAlarms ? '' : ' · reminders may be a few minutes late (allow exact alarms)'}',
        actionLabel: !p.exactAlarms && s.sdk >= 31 ? 'Exact' : null,
        onAction: !p.exactAlarms && s.sdk >= 31 ? () => _act(SystemIslandBridge.openExactAlarmSettings) : null,
      ),
      _Check(
        icon: Icons.wb_sunny_outlined,
        title: 'Weather',
        status: s.weather.isEmpty ? _Status.info : _Status.ok,
        detail: s.weather.isEmpty
            ? 'Not loaded yet. Needs internet and the island running.'
            : '${s.weather} in ${sys.city.name}',
      ),
      _Check(
        icon: Icons.keyboard_voice_rounded,
        title: 'Voice assistant',
        status: s.assistant.on && p.microphone ? _Status.ok : _Status.info,
        detail: !sys.aiEnabled
            ? 'Turned off. Open AI Assistant to set it up.'
            : !p.microphone
                ? 'Needs the Microphone permission.'
                : !s.assistant.hasKey
                    ? 'Needs your NVIDIA API key.'
                    : s.assistant.error.isNotEmpty
                        ? s.assistant.error
                        : 'State: ${s.assistant.state}${s.assistant.heard.isEmpty ? '' : ' · heard: ${s.assistant.heard}'}',
      ),
      _Check(
        icon: Icons.accessibility_new_rounded,
        title: 'Read screen and type for you',
        status: p.accessibility ? _Status.ok : _Status.info,
        detail: p.accessibility
            ? 'Accessibility service is on.'
            : 'Optional. Needed to read/translate the page and to type what you dictate.',
        actionLabel: p.accessibility ? null : 'Allow',
        onAction: p.accessibility ? null : () => _act(SystemIslandBridge.openAccessibilitySettings),
      ),
      _Check(
        icon: Icons.bolt_rounded,
        title: 'Stay alive in background',
        status: p.ignoringBatteryOptimizations ? _Status.ok : _Status.warn,
        detail: p.ignoringBatteryOptimizations
            ? 'Battery optimisation is off for Nova.'
            : 'Android may stop the island to save power. Exempt Nova.',
        actionLabel: p.ignoringBatteryOptimizations ? null : 'Allow',
        onAction: p.ignoringBatteryOptimizations ? null : () => _act(SystemIslandBridge.requestIgnoreBattery),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final system = store.system;

    return ScreenScaffold(
      showBack: false,
      title: 'Device',
      subtitle: system.snapshot?.device,
      body: ListenableBuilder(
        listenable: system,
        builder: (context, _) {
          final snapshot = system.snapshot;
          final pad = EdgeInsets.fromLTRB(
            NovaLayout.pagePad,
            NovaSpace.sm,
            NovaLayout.pagePad,
            navClearance(context),
          );

          if (!system.supported) {
            return ListView(
              padding: pad,
              children: const [
                EmptyState(
                  icon: Icons.android_rounded,
                  title: 'Android only',
                  message: 'The floating island, media, notifications and device '
                      'readings need the Android app.',
                  compact: true,
                ),
              ],
            );
          }
          if (snapshot == null) {
            return ListView(
              padding: pad,
              children: [
                if (system.error != null)
                  SizedBox(
                    height: 320,
                    child: ErrorState(
                      message: system.error!,
                      onRetry: system.refresh,
                    ),
                  )
                else
                  const SizedBox(height: 260, child: LoadingState()),
              ],
            );
          }

          final checks = _checks(snapshot, store);
          final okCount = checks.where((c) => c.status == _Status.ok).length;

          return ListView(
            padding: pad,
            children: [
              FadeIn(child: _ServiceCard(snapshot: snapshot, onAct: _act)),
              if (!snapshot.permissions.notificationAccess && snapshot.sdk >= 33)
                Padding(
                  padding: const EdgeInsets.only(top: NovaSpace.md),
                  child: _Tip(
                    text: 'If the notification or accessibility switch is greyed out, '
                        'Android blocks apps installed outside the Play Store: open '
                        'App info, tap the ⋮ menu and choose "Allow restricted settings".',
                    label: 'Open App info',
                    onTap: () => _act(SystemIslandBridge.openAppSettings),
                  ),
                ),
              SectionHeader(title: 'Live checks · $okCount of ${checks.length} working'),
              GlassSurface.solid(
                radius: NovaRadius.lg,
                child: Column(
                  children: [
                    for (var i = 0; i < checks.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: NovaColors.white(0.06)),
                      _CheckTile(check: checks[i]),
                    ],
                  ],
                ),
              ),
              if (snapshot.media.active) ...[
                const SectionHeader(title: 'Now playing'),
                _NowPlaying(media: snapshot.media, onControl: (a) => _act(() => SystemIslandBridge.mediaControl(a))),
              ],
              const SectionHeader(title: 'Phone'),
              _Meters(snapshot: snapshot),
              if (snapshot.permissions.usageAccess && snapshot.topApps.isNotEmpty) ...[
                const SectionHeader(title: 'Most used today'),
                _TopApps(apps: snapshot.topApps),
              ],
              const SectionHeader(title: 'More'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Assistant',
                    subtitle: 'Voice commands, NVIDIA model, wake word',
                    trailing: const Icon(Icons.chevron_right_rounded, color: NovaColors.textDim),
                    onTap: () => pushNova(context, (_) => const AssistantScreen()),
                  ),
                  SettingsRow(
                    icon: Icons.mosque_outlined,
                    title: 'Prayer times',
                    subtitle: 'City, method and reminders on the island',
                    trailing: const Icon(Icons.chevron_right_rounded, color: NovaColors.textDim),
                    onTap: () => pushNova(context, (_) => const PrayerScreen()),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.snapshot, required this.onAct});

  final SystemSnapshot snapshot;
  final Future<void> Function(Future<void> Function()) onAct;

  @override
  Widget build(BuildContext context) {
    final running = snapshot.service.running;
    final lastAt = snapshot.service.lastEventAt;
    final last = snapshot.service.lastEventTitle;

    return GlassSurface(
      radius: NovaRadius.xl,
      padding: const EdgeInsets.all(NovaSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running ? NovaColors.success : NovaColors.textFaint,
                ),
              ),
              const SizedBox(width: NovaSpace.sm),
              Expanded(
                child: Text(
                  running ? 'Island is running' : 'Island is stopped',
                  style: NovaType.headline,
                ),
              ),
              Text('Android ${snapshot.sdk}', style: NovaType.caption),
            ],
          ),
          const SizedBox(height: NovaSpace.sm),
          Text(
            running
                ? (last.isEmpty
                    ? 'Waiting for the first event.'
                    : 'Last: $last${lastAt == null ? '' : ' · ${_ago(lastAt)}'} · ${snapshot.service.eventsShown} shown')
                : 'Start it to show time, weather, music, calls and notifications above every app.',
            style: NovaType.caption,
          ),
          const SizedBox(height: NovaSpace.lg),
          Row(
            children: [
              Expanded(
                child: NeuButton(
                  label: running ? 'Stop' : 'Start island',
                  icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  kind: running ? NeuButtonKind.secondary : NeuButtonKind.primary,
                  onPressed: () => onAct(running
                      ? SystemIslandBridge.stop
                      : (snapshot.permissions.overlay
                          ? SystemIslandBridge.start
                          : SystemIslandBridge.openOverlaySettings)),
                ),
              ),
              const SizedBox(width: NovaSpace.md),
              Expanded(
                child: NeuButton(
                  label: 'Test island',
                  icon: Icons.auto_awesome_rounded,
                  kind: NeuButtonKind.secondary,
                  onPressed: () => onAct(() => SystemIslandBridge.testEvent(
                        title: 'Nova Island works',
                        body: 'You should see this above any app',
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text, required this.label, required this.onTap});

  final String text;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface.solid(
      radius: NovaRadius.md,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: NovaColors.warning),
              const SizedBox(width: NovaSpace.sm),
              Expanded(child: Text(text, style: NovaType.caption)),
            ],
          ),
          const SizedBox(height: NovaSpace.md),
          NeuButton(
            label: label,
            kind: NeuButtonKind.secondary,
            compact: true,
            expand: false,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final _Check check;

  @override
  Widget build(BuildContext context) {
    final color = switch (check.status) {
      _Status.ok => NovaColors.success,
      _Status.warn => NovaColors.warning,
      _Status.info => NovaColors.textDim,
    };
    final badge = switch (check.status) {
      _Status.ok => Icons.check_circle_rounded,
      _Status.warn => Icons.error_outline_rounded,
      _Status.info => Icons.radio_button_unchecked_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NovaSpace.lg, vertical: NovaSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(check.icon, size: 22, color: NovaColors.accent2),
          const SizedBox(width: NovaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(check.title, style: NovaType.bodyStrong)),
                    Icon(badge, size: 18, color: color),
                  ],
                ),
                const SizedBox(height: 2),
                Text(check.detail, style: NovaType.caption),
                if (check.actionLabel != null) ...[
                  const SizedBox(height: NovaSpace.sm),
                  NeuButton(
                    label: check.actionLabel!,
                    kind: NeuButtonKind.secondary,
                    compact: true,
                    expand: false,
                    onPressed: check.onAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.media, required this.onControl});

  final MediaState media;
  final ValueChanged<String> onControl;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: NovaRadius.lg,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  [media.artist, media.app].where((e) => e.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaType.caption,
                ),
              ],
            ),
          ),
          NeuIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Previous',
            onPressed: () => onControl('previous'),
          ),
          const SizedBox(width: 6),
          NeuIconButton(
            icon: media.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: media.playing ? 'Pause' : 'Play',
            active: true,
            onPressed: () => onControl(media.playing ? 'pause' : 'play'),
          ),
          const SizedBox(width: 6),
          NeuIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next',
            onPressed: () => onControl('next'),
          ),
        ],
      ),
    );
  }
}

class _Meters extends StatelessWidget {
  const _Meters({required this.snapshot});

  final SystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    return GlassSurface.solid(
      radius: NovaRadius.lg,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Column(
        children: [
          _Meter(
            label: 'Battery',
            fraction: s.batteryLevel < 0 ? 0 : s.batteryLevel / 100,
            trailing: s.batteryLevel < 0 ? '—' : '${s.batteryLevel}%${s.charging ? ' ⚡' : ''}',
            color: s.batteryLevel >= 0 && s.batteryLevel <= 20 && !s.charging
                ? NovaColors.danger
                : NovaColors.success,
          ),
          const SizedBox(height: NovaSpace.lg),
          _Meter(
            label: 'Storage',
            fraction: s.storageUsedFraction,
            trailing: '${formatBytes(s.storageTotal - s.storageFree)} / ${formatBytes(s.storageTotal)}',
            color: s.storageUsedFraction > 0.9 ? NovaColors.danger : NovaColors.accent,
          ),
          const SizedBox(height: NovaSpace.lg),
          _Meter(
            label: 'Memory',
            fraction: s.memoryUsedFraction,
            trailing: '${formatBytes(s.memoryTotal - s.memoryFree)} / ${formatBytes(s.memoryTotal)}',
            color: s.memoryUsedFraction > 0.9 ? NovaColors.warning : NovaColors.accent2,
          ),
          const SizedBox(height: NovaSpace.lg),
          Row(
            children: [
              const Icon(Icons.wifi_rounded, size: 18, color: NovaColors.textDim),
              const SizedBox(width: NovaSpace.sm),
              const Expanded(child: Text('Network', style: NovaType.caption)),
              Text(s.network.isEmpty ? '—' : s.network, style: NovaType.label),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.fraction,
    required this.trailing,
    required this.color,
  });

  final String label;
  final double fraction;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return Semantics(
      label: '$label $trailing',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: NovaType.caption)),
              Text(trailing, style: NovaType.label),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(NovaRadius.pill),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: NovaColors.white(0.07),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopApps extends StatelessWidget {
  const _TopApps({required this.apps});

  final List<UsageApp> apps;

  @override
  Widget build(BuildContext context) {
    final maxMs = apps.fold<int>(1, (m, a) => a.millis > m ? a.millis : m);
    return GlassSurface.solid(
      radius: NovaRadius.lg,
      padding: const EdgeInsets.all(NovaSpace.lg),
      child: Column(
        children: [
          for (var i = 0; i < apps.length; i++) ...[
            if (i > 0) const SizedBox(height: NovaSpace.md),
            _Meter(
              label: apps[i].name,
              fraction: apps[i].millis / maxMs,
              trailing: formatDuration(Duration(milliseconds: apps[i].millis)),
              color: NovaColors.accent,
            ),
          ],
        ],
      ),
    );
  }
}
