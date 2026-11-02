import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../platform/system_island_bridge.dart';
import '../ui/components.dart';
import '../ui/neu.dart';
import '../ui/overlays.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String _version = '1.0.0';

  Future<void> _clearData(BuildContext context) async {
    final store = AppScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await showNovaConfirm(
      context,
      title: 'Clear all data?',
      message: 'This deletes every task, focus session and notification on '
          'this device and signs you out. It cannot be undone.',
      confirmLabel: 'Clear everything',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    navigator.popUntil((route) => route.isFirst);
    await store.resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final settings = store.settings;

    return ScreenScaffold(
      title: 'Settings',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          const _GroupTitle('System-wide Dynamic Island'),
          const _SystemIslandPanel(),
          const _GroupTitle('Feedback'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.vibration_rounded,
                title: 'Haptic feedback',
                subtitle: 'Gentle taps on buttons and toggles',
                trailing: NeuToggle(
                  value: settings.haptics,
                  semanticLabel: 'Haptic feedback',
                  onChanged: store.setHaptics,
                ),
              ),
              SettingsRow(
                icon: Icons.bubble_chart_rounded,
                title: 'Floating notifications',
                subtitle: 'Show updates on the island at the top',
                trailing: NeuToggle(
                  value: settings.island,
                  semanticLabel: 'Floating notifications',
                  onChanged: (value) {
                    store.setIslandEnabled(value);
                    if (value) {
                      store.island.toast(
                        'Floating notifications on',
                        subtitle: 'Updates will appear here',
                        icon: Icons.bubble_chart_rounded,
                        tint: NovaColors.accent2,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const _GroupTitle('Display'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.blur_off_rounded,
                title: 'Reduce blur',
                subtitle: 'Solid surfaces, easier on older phones',
                trailing: NeuToggle(
                  value: settings.reduceBlur,
                  semanticLabel: 'Reduce blur',
                  onChanged: store.setReduceBlur,
                ),
              ),
              SettingsRow(
                icon: Icons.motion_photos_off_outlined,
                title: 'Reduce motion',
                subtitle: 'Skip transitions and animations',
                trailing: NeuToggle(
                  value: settings.reduceMotion,
                  semanticLabel: 'Reduce motion',
                  onChanged: store.setReduceMotion,
                ),
              ),
            ],
          ),
          const _GroupTitle('Focus'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.flag_outlined,
                title: 'Daily focus goal',
                subtitle: 'Used on Home and Insights',
                trailing: _GoalStepper(
                  minutes: settings.dailyGoalMinutes,
                  onChanged: store.setDailyGoal,
                ),
              ),
            ],
          ),
          const _GroupTitle('Data'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.delete_forever_rounded,
                title: 'Clear all data',
                subtitle: 'Tasks, sessions and notifications',
                danger: true,
                onTap: () => _clearData(context),
              ),
            ],
          ),
          const SizedBox(height: NovaSpace.xxl),
          const Center(
            child: Text('Nova $_version', style: NovaType.caption),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, NovaSpace.xl, 4, NovaSpace.sm),
      child: Semantics(
        header: true,
        child: Text(
          title.toUpperCase(),
          style: NovaType.micro,
        ),
      ),
    );
  }
}

class _GoalStepper extends StatelessWidget {
  const _GoalStepper({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  static const int _step = 15;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeuIconButton(
          icon: Icons.remove_rounded,
          tooltip: 'Decrease goal',
          size: NovaLayout.minTap,
          onPressed: minutes <= 15 ? null : () => onChanged(minutes - _step),
        ),
        SizedBox(
          width: 64,
          child: Text(
            formatMinutes(minutes),
            textAlign: TextAlign.center,
            style: NovaType.bodyStrong,
          ),
        ),
        NeuIconButton(
          icon: Icons.add_rounded,
          tooltip: 'Increase goal',
          size: NovaLayout.minTap,
          onPressed: minutes >= 240 ? null : () => onChanged(minutes + _step),
        ),
      ],
    );
  }
}


class _SystemIslandPanel extends StatefulWidget {
  const _SystemIslandPanel();

  @override
  State<_SystemIslandPanel> createState() => _SystemIslandPanelState();
}

class _SystemIslandPanelState extends State<_SystemIslandPanel> {
  late Future<SystemIslandStatus> _status = SystemIslandBridge.status();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _status = SystemIslandBridge.status());
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Android permission action failed')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NovaSpace.lg),
      decoration: BoxDecoration(
        color: NovaColors.surface,
        borderRadius: BorderRadius.circular(NovaRadius.lg),
        border: Border.all(color: NovaColors.stroke),
      ),
      child: FutureBuilder<SystemIslandStatus>(
        future: _status,
        builder: (context, snapshot) {
          final status = snapshot.data;
          final ready = status?.ready == true;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Show Nova above other apps and mirror supported phone notifications.',
                style: NovaType.body,
              ),
              const SizedBox(height: NovaSpace.md),
              _PermissionLine(
                label: 'Display over other apps',
                granted: status?.overlayGranted == true,
              ),
              const SizedBox(height: NovaSpace.sm),
              _PermissionLine(
                label: 'Notification access',
                granted: status?.notificationAccessGranted == true,
              ),
              const SizedBox(height: NovaSpace.md),
              Wrap(
                spacing: NovaSpace.sm,
                runSpacing: NovaSpace.sm,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(SystemIslandBridge.openOverlaySettings),
                    child: const Text('Overlay permission'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(SystemIslandBridge.openNotificationSettings),
                    child: const Text('Notification access'),
                  ),
                  FilledButton(
                    onPressed: _busy || !ready ? null : () => _run(SystemIslandBridge.start),
                    child: const Text('Start Island'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _run(SystemIslandBridge.stop),
                    child: const Text('Stop'),
                  ),
                ],
              ),
              if (status == null && snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(top: NovaSpace.sm),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: NovaSpace.sm),
              Text(
                ready
                    ? 'Permissions ready. Start Island to keep the floating pill active.'
                    : 'Grant both Android permissions, then return here and start Island.',
                style: NovaType.caption,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 18,
          color: granted ? NovaColors.success : NovaColors.muted,
        ),
        const SizedBox(width: NovaSpace.sm),
        Expanded(child: Text(label, style: NovaType.body)),
        Text(
          granted ? 'Granted' : 'Required',
          style: NovaType.caption.copyWith(
            color: granted ? NovaColors.success : NovaColors.muted,
          ),
        ),
      ],
    );
  }
}
