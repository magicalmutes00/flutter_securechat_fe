import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 4pt spacing scale. Prefer these over inline literals.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

/// Corner-radius scale.
class AppRadius {
  AppRadius._();

  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double pill = 999.0;

  static BorderRadius get xsRadius => BorderRadius.circular(xs);
  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
  static BorderRadius get pillRadius => BorderRadius.circular(pill);

  static BorderRadius get topSheet =>
      const BorderRadius.vertical(top: Radius.circular(lg));
}

/// Soft blue-tinted shadows (light) / deep shadows (dark).
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> cardLight = [
    BoxShadow(
      color: Color(0x0F141926),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> popLight = [
    BoxShadow(
      color: Color(0x14141926),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> popDark = [
    BoxShadow(
      color: Color(0xCC000000),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];

  static List<BoxShadow> card(Brightness brightness) =>
      brightness == Brightness.dark ? cardDark : cardLight;

  static List<BoxShadow> pop(Brightness brightness) =>
      brightness == Brightness.dark ? popDark : popLight;
}

/// Standard motion durations.
class AppDurations {
  AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// Ergonomic theme access: `context.colors`, `context.text`,
/// `context.appColors`.
extension AppThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
