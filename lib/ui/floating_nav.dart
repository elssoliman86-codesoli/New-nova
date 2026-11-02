import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui_prefs.dart';
import 'glass.dart';

class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

final Curve _navCurve = SpringCurve(NovaSpring.soft);

/// Floating translucent tab bar. The active tab is marked by a soft blue
/// pill that glides between tabs on a spring.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const double _pad = 6;

  @override
  Widget build(BuildContext context) {
    final duration = UiPrefs.motionReduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 460);

    return SizedBox(
      height: NovaLayout.navHeight,
      child: GlassSurface(
        radius: NovaRadius.xl,
        blur: 22,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - _pad * 2) / items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: duration,
                  curve: _navCurve,
                  left: _pad + currentIndex * itemWidth,
                  top: _pad,
                  width: itemWidth,
                  height: NovaLayout.navHeight - _pad * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NovaRadius.lg - 4),
                      color: NovaColors.accent.withValues(alpha: 0.14),
                      border: Border.all(
                        color: NovaColors.accent.withValues(alpha: 0.32),
                      ),
                      boxShadow: NovaShadows.glow(
                        NovaColors.accent,
                        alpha: 0.2,
                        blur: 14,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(_pad),
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavButton(
                            item: items[i],
                            selected: i == currentIndex,
                            onTap: () {
                              if (i != currentIndex) Haptics.tap();
                              onChanged(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(context, NovaDurations.base);
    final color = selected ? NovaColors.accent2 : NovaColors.textDim;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: duration,
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOut,
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey<bool>(selected),
                  size: 22,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: NovaType.micro.copyWith(
                color: color,
                letterSpacing: 0.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
