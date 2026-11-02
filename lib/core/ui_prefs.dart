import 'package:flutter/widgets.dart';

/// Visual preferences shared with the whole widget tree.
///
/// Kept separate from the app store so that toggling "reduce blur" or
/// "reduce motion" only rebuilds the widgets that depend on it.
class UiPrefs extends InheritedWidget {
  const UiPrefs({
    super.key,
    required this.reduceBlur,
    required this.reduceMotion,
    required super.child,
  });

  final bool reduceBlur;
  final bool reduceMotion;

  static UiPrefs? _lookup(BuildContext context, {required bool listen}) {
    return listen
        ? context.dependOnInheritedWidgetOfExactType<UiPrefs>()
        : context.getInheritedWidgetOfExactType<UiPrefs>();
  }

  /// True when blur should be replaced by solid surfaces. Rebuilds on change.
  static bool blurReduced(BuildContext context) {
    return _lookup(context, listen: true)?.reduceBlur ?? false;
  }

  /// True when animations should be skipped, either because the user turned
  /// on "reduce motion" or because Android's "remove animations" is on.
  static bool motionReduced(BuildContext context) {
    final prefs = _lookup(context, listen: true)?.reduceMotion ?? false;
    final system = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return prefs || system;
  }

  /// Same as [motionReduced] but safe to call from event handlers
  /// (does not register a dependency).
  static bool motionReducedNow(BuildContext context) {
    final prefs = _lookup(context, listen: false)?.reduceMotion ?? false;
    final system = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return prefs || system;
  }

  @override
  bool updateShouldNotify(UiPrefs oldWidget) {
    return reduceBlur != oldWidget.reduceBlur ||
        reduceMotion != oldWidget.reduceMotion;
  }
}
