import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/tokens.dart';
import '../ui/floating_nav.dart';
import 'device_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'tasks_screen.dart';

/// Main frame: four tabs with the floating glass navigation bar.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  static const List<NavItem> _items = [
    NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    NavItem(
      icon: Icons.check_circle_outline_rounded,
      activeIcon: Icons.check_circle_rounded,
      label: 'Tasks',
    ),
    NavItem(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded,
      label: 'Insights',
    ),
    NavItem(
      icon: Icons.phone_android_rounded,
      activeIcon: Icons.phone_android_rounded,
      label: 'Device',
    ),
    NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  int _index = 0;

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;

    return PopScope(
      // Back goes to Home first, then leaves the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: [
                HomeScreen(onGoToTab: _go),
                const TasksScreen(),
                const InsightsScreen(),
                DeviceScreen(active: _index == 3),
                const ProfileScreen(),
              ],
            ),
          ),
          Positioned(
            left: NovaLayout.pagePad - 4,
            right: NovaLayout.pagePad - 4,
            bottom: math.max(media.padding.bottom, 0) + NovaLayout.navGap,
            child: IgnorePointer(
              ignoring: keyboardOpen,
              child: AnimatedSlide(
                duration: motionDuration(context, NovaDurations.base),
                curve: Curves.easeOutCubic,
                offset: keyboardOpen ? const Offset(0, 2) : Offset.zero,
                child: FloatingNavBar(
                  items: _items,
                  currentIndex: _index,
                  onChanged: _go,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
