import 'dart:async';

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/app_scope.dart';
import '../system/prayer_times.dart';
import '../ui/components.dart';
import '../ui/glass.dart';
import '../ui/neu.dart';

const Map<String, String> _arabic = {
  'Fajr': 'الفجر',
  'Sunrise': 'الشروق',
  'Dhuhr': 'الظهر',
  'Asr': 'العصر',
  'Maghrib': 'المغرب',
  'Isha': 'العشاء',
};

/// Prayer times worked out on the phone (no internet, no location needed),
/// with reminders that appear on the island.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final sys = store.systemSettings;
    final city = sys.city;
    final times = computePrayerTimes(
      latitude: city.latitude,
      longitude: city.longitude,
      date: _now,
      method: sys.method,
      hanafi: sys.hanafi,
    );
    final next = nextPrayer(
      now: _now,
      latitude: city.latitude,
      longitude: city.longitude,
      method: sys.method,
      hanafi: sys.hanafi,
    );

    return ScreenScaffold(
      title: 'Prayer times',
      subtitle: '${city.label} · ${sys.method.shortLabel}',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NovaLayout.pagePad,
          NovaSpace.sm,
          NovaLayout.pagePad,
          NovaSpace.xxxl + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          if (next != null)
            FadeIn(
              child: GlassSurface(
                radius: NovaRadius.xl,
                padding: const EdgeInsets.all(NovaSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Next prayer', style: NovaType.caption),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '${next.name} · ${_arabic[next.name] ?? ''}',
                            style: NovaType.title,
                          ),
                        ),
                        Text(formatClock(next.time), style: NovaType.headline),
                      ],
                    ),
                    const SizedBox(height: NovaSpace.sm),
                    Text(
                      'In ${formatCountdown(next.time.difference(_now))}',
                      style: NovaType.metric.copyWith(color: NovaColors.accent2),
                    ),
                  ],
                ),
              ),
            ),
          const SectionHeader(title: 'Today'),
          if (times == null)
            const Text('No prayer times for this place today.', style: NovaType.caption)
          else
            GlassSurface.solid(
              radius: NovaRadius.lg,
              child: Column(
                children: [
                  for (var i = 0; i < times.entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: NovaColors.white(0.06)),
                    _PrayerRow(
                      entry: times.entries[i],
                      highlighted: next != null && next.name == times.entries[i].name &&
                          isSameMoment(next.time, times.entries[i].time),
                      passed: times.entries[i].time.isBefore(_now),
                    ),
                  ],
                ],
              ),
            ),
          const SectionHeader(title: 'Reminders'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.notifications_active_outlined,
                title: 'Remind me on the island',
                subtitle: 'A pill appears above any app at prayer time',
                trailing: NeuToggle(
                  value: sys.prayerAlerts,
                  semanticLabel: 'Prayer reminders',
                  onChanged: (v) => store.updateSystemSettings(sys.copyWith(prayerAlerts: v)),
                ),
              ),
              SettingsRow(
                icon: Icons.school_outlined,
                title: 'Hanafi Asr',
                subtitle: 'Later Asr (shadow twice the height)',
                trailing: NeuToggle(
                  value: sys.hanafi,
                  semanticLabel: 'Hanafi Asr',
                  onChanged: (v) => store.updateSystemSettings(sys.copyWith(hanafi: v)),
                ),
              ),
            ],
          ),
          const SectionHeader(title: 'City'),
          Wrap(
            spacing: NovaSpace.sm,
            runSpacing: NovaSpace.sm,
            children: [
              for (var i = 0; i < prayerCities.length; i++)
                NovaChip(
                  label: prayerCities[i].name,
                  selected: sys.cityIndex == i,
                  onTap: () => store.updateSystemSettings(sys.copyWith(cityIndex: i)),
                ),
            ],
          ),
          const SectionHeader(title: 'Calculation method'),
          Wrap(
            spacing: NovaSpace.sm,
            runSpacing: NovaSpace.sm,
            children: [
              for (final m in PrayerMethod.values)
                NovaChip(
                  label: m.shortLabel,
                  selected: sys.method == m,
                  onTap: () => store.updateSystemSettings(sys.copyWith(methodIndex: m.index)),
                ),
            ],
          ),
          const SizedBox(height: NovaSpace.md),
          const Text(
            'Times are calculated on this phone and may differ by a minute or two '
            'from your local mosque timetable. The city also sets the weather shown on the island.',
            style: NovaType.caption,
          ),
        ],
      ),
    );
  }
}

bool isSameMoment(DateTime a, DateTime b) => a.isAtSameMomentAs(b);

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({required this.entry, required this.highlighted, required this.passed});

  final PrayerEntry entry;
  final bool highlighted;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? NovaColors.accent2
        : (passed ? NovaColors.textFaint : NovaColors.text);
    return Container(
      color: highlighted ? NovaColors.tint(NovaColors.accent, 0.10) : null,
      padding: const EdgeInsets.symmetric(horizontal: NovaSpace.lg, vertical: NovaSpace.md),
      child: Row(
        children: [
          Icon(
            entry.isPrayer ? Icons.mosque_outlined : Icons.wb_twilight_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: NovaSpace.md),
          Expanded(
            child: Text(
              '${entry.name}  ${_arabic[entry.name] ?? ''}',
              style: NovaType.bodyStrong.copyWith(color: color),
            ),
          ),
          Text(formatClock(entry.time), style: NovaType.bodyStrong.copyWith(color: color)),
        ],
      ),
    );
  }
}
