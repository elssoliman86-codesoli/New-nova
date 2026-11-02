import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/tokens.dart';
import '../data/app_scope.dart';
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
