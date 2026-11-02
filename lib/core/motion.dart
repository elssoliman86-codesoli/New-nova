import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'ui_prefs.dart';

/// Spring presets used for the island, the navigation indicator and other
/// interactive motion.
abstract final class NovaSpring {
  /// Slight overshoot, snappy: used by the floating island.
  static const SpringDescription island =
      SpringDescription(mass: 1, stiffness: 420, damping: 30);

  /// Calmer, no visible overshoot.
  static const SpringDescription soft =
      SpringDescription(mass: 1, stiffness: 300, damping: 34);
}

/// Curve that follows a damped spring: a small overshoot, then it settles.
/// Use it with implicit animations (AnimatedPositioned, AnimatedContainer).
class SpringCurve extends Curve {
  SpringCurve([SpringDescription spring = NovaSpring.island])
      : _sim = SpringSimulation(spring, 0, 1, 0);

  static const double _seconds = 0.5;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) {
    if (t >= 1) return 1;
    return _sim.x(t * _seconds);
  }
}

/// Animates [controller] to [target] with a spring, carrying over the current
/// velocity so interrupted motion stays continuous.
///
/// Use an [AnimationController.unbounded] if the spring may overshoot.
void springTo(
  AnimationController controller,
  double target, {
  SpringDescription spring = NovaSpring.island,
  bool instant = false,
}) {
  if (instant) {
    controller.stop();
    controller.value = target;
    return;
  }
  controller.animateWith(
    SpringSimulation(spring, controller.value, target, controller.velocity),
  );
}

/// [normal] unless motion is reduced, in which case it is zero.
Duration motionDuration(BuildContext context, Duration normal) {
  return UiPrefs.motionReduced(context) ? Duration.zero : normal;
}

/// Scales its child down slightly while pressed and reports taps.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) {
      setState(() => _down = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final scaled = AnimatedScale(
      scale: (_down && enabled) ? widget.pressedScale : 1.0,
      duration: motionDuration(context, const Duration(milliseconds: 110)),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );
    if (!enabled) return scaled;
    return Semantics(
      button: true,
      enabled: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: scaled,
      ),
    );
  }
}

/// Fade plus a small upward slide. Instant when [reduceMotion] is true.
class NovaPageRoute<T> extends PageRouteBuilder<T> {
  NovaPageRoute({
    required WidgetBuilder builder,
    bool reduceMotion = false,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          reverseTransitionDuration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
