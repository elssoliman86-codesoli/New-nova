import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] that honours the "Haptic feedback"
/// setting. The app store keeps [enabled] in sync with the settings.
abstract final class Haptics {
  static bool enabled = true;

  /// Light tick for taps and toggles.
  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Slightly stronger feedback for selections and long presses.
  static void select() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Confirmation feedback (task completed, focus finished).
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }
}
