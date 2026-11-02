import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Colour palette. Deep midnight navy surfaces, electric blue accent and
/// cyan highlights, kept restrained (no neon, no heavy gradients).
abstract final class NovaColors {
  static const Color bg = Color(0xFF080D19);
  static const Color bg2 = Color(0xFF0D1525);
  static const Color bg3 = Color(0xFF131E34);

  /// Raised neumorphic surface and recessed (inset) surface.
  static const Color surface = Color(0xFF101A2E);
  static const Color surfaceLow = Color(0xFF0A1120);

  static const Color accent = Color(0xFF398BFF);
  static const Color accentDeep = Color(0xFF2468DB);
  static const Color accent2 = Color(0xFF42C8FF);

  static const Color text = Color(0xFFF2F6FF);
  static const Color textDim = Color(0xFF8C9BB5);
  static const Color textFaint = Color(0xFF5F6E88);

  static const Color success = Color(0xFF3DDC97);
  static const Color warning = Color(0xFFFFB84D);
  static const Color danger = Color(0xFFFF6B7A);

  /// rgba(255,255,255,0.055) from the design brief.
  static const Color glassFill = Color(0x0EFFFFFF);

  /// Opaque stand-in for glass when blur is off (lists, reduced blur mode).
  static const Color glassSolid = Color(0xFF0F182B);

  static const Color shadowDark = Color(0xFF03060D);

  static Color white(double alpha) => Color.fromRGBO(255, 255, 255, alpha);
  static Color black(double alpha) => Color.fromRGBO(0, 0, 0, alpha);
  static Color tint(Color color, double alpha) => color.withValues(alpha: alpha);
}

/// Spacing scale (logical pixels).
abstract final class NovaSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// One consistent set of corner radii.
abstract final class NovaRadius {
  static const double sm = 12; // chips, small controls
  static const double md = 16; // buttons, fields, list tiles
  static const double lg = 22; // cards
  static const double xl = 28; // sheets, dialogs, navigation bar
  static const double pill = 999;
}

abstract final class NovaLayout {
  static const double pagePad = 20;
  static const double navHeight = 64;
  static const double navGap = 12;
  static const double minTap = 44;

  /// Bottom space a scrolling tab screen reserves for the floating nav bar.
  static const double navReserve = navHeight + navGap + 28;
}

/// Typographic scale. Font family comes from the theme (Inter).
abstract final class NovaType {
  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
    color: NovaColors.text,
  );
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: NovaColors.text,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: NovaColors.text,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: NovaColors.text,
  );
  static const TextStyle bodyDim = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: NovaColors.textDim,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: NovaColors.textDim,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: NovaColors.text,
  );
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.4,
    color: NovaColors.textDim,
  );
  static const TextStyle metric = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.4,
    color: NovaColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle timer = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.5,
    color: NovaColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class NovaShadows {
  /// Neumorphic raised surface: soft dark shadow bottom-right, faint light
  /// top-left.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x8C03060D), blurRadius: 14, offset: Offset(6, 6)),
    BoxShadow(color: Color(0x0AFFFFFF), blurRadius: 12, offset: Offset(-4, -4)),
  ];

  static const List<BoxShadow> raisedSmall = [
    BoxShadow(color: Color(0x8003060D), blurRadius: 8, offset: Offset(3, 3)),
    BoxShadow(color: Color(0x08FFFFFF), blurRadius: 6, offset: Offset(-2, -2)),
  ];

  static const List<BoxShadow> pressed = [
    BoxShadow(color: Color(0x6603060D), blurRadius: 4, offset: Offset(2, 2)),
    BoxShadow(color: Color(0x06FFFFFF), blurRadius: 4, offset: Offset(-1, -1)),
  ];

  /// Soft ambient shadow for floating glass.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 12)),
  ];

  static List<BoxShadow> glow(Color color, {double alpha = 0.35, double blur = 16}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: blur,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

abstract final class NovaDurations {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
}
