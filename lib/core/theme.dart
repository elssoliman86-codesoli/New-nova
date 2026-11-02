import 'package:flutter/material.dart';

import 'tokens.dart';

/// The single dark theme used by the whole app.
ThemeData buildNovaTheme() {
  const scheme = ColorScheme.dark(
    primary: NovaColors.accent,
    onPrimary: Colors.white,
    secondary: NovaColors.accent2,
    onSecondary: NovaColors.bg,
    surface: NovaColors.bg2,
    onSurface: NovaColors.text,
    error: NovaColors.danger,
    onError: NovaColors.bg,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
  );

  return base.copyWith(
    // Pages are transparent: the shared ambient background sits behind the
    // navigator (see app.dart), which is what the glass surfaces blur.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: NovaColors.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    dividerColor: NovaColors.white(0.06),
    iconTheme: const IconThemeData(color: NovaColors.text, size: 22),
    textTheme: base.textTheme.apply(
      bodyColor: NovaColors.text,
      displayColor: NovaColors.text,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: NovaColors.accent2,
      selectionColor: NovaColors.accent.withValues(alpha: 0.35),
      selectionHandleColor: NovaColors.accent2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: NovaColors.accent2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: NovaColors.bg3,
        borderRadius: BorderRadius.circular(NovaRadius.sm),
      ),
      textStyle: NovaType.caption.copyWith(color: NovaColors.text),
    ),
  );
}
