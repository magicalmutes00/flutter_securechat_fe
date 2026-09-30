import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// SecureChat theme: vivid blue `#2457FF` primary, acid lime `#C8FF3D`
/// accent, Inter type scale, light + dark.
///
/// The legacy `*Color` statics below are kept so existing screens keep
/// compiling while they are migrated to tokens; new code must use
/// `context.colors`, `context.text` and `context.appColors` instead.
class AppTheme {
  AppTheme._();

  // Legacy aliases (migration shims — do not use in new code).
  static const Color primaryColor = AppPalette.blue600;
  static const Color secondaryColor = AppPalette.blue600;
  static const Color accentColor = AppPalette.lime400;
  static const Color backgroundColor = AppPalette.neutral50;
  static const Color chatBubbleColor = AppPalette.white;
  static const Color sentMessageColor = AppPalette.blue100;
  static const Color receivedMessageColor = AppPalette.white;
  static const Color onlineStatusColor = AppPalette.blue600;
  static const Color offlineStatusColor = AppPalette.neutral400;
  static const Color errorColor = AppPalette.danger;
  static const Color successColor = AppPalette.lime600;

  static const String fontFamily = 'Inter';

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: AppPalette.blue600,
      onPrimary: AppPalette.white,
      primaryContainer: AppPalette.blue100,
      onPrimaryContainer: AppPalette.blue900,
      secondary: AppPalette.lime400,
      onSecondary: AppPalette.onLime,
      secondaryContainer: AppPalette.lime100,
      onSecondaryContainer: AppPalette.lime900,
      tertiary: AppPalette.blue400,
      onTertiary: AppPalette.white,
      tertiaryContainer: AppPalette.blue50,
      onTertiaryContainer: AppPalette.blue800,
      error: AppPalette.danger,
      onError: AppPalette.white,
      errorContainer: AppPalette.dangerContainerLight,
      onErrorContainer: AppPalette.onDangerContainerLight,
      surface: AppPalette.white,
      onSurface: AppPalette.neutral900,
      surfaceContainerLowest: AppPalette.white,
      surfaceContainerLow: AppPalette.neutral25,
      surfaceContainer: AppPalette.neutral50,
      surfaceContainerHigh: AppPalette.neutral100,
      surfaceContainerHighest: AppPalette.neutral200,
      onSurfaceVariant: AppPalette.neutral600,
      outline: AppPalette.neutral300,
      outlineVariant: AppPalette.neutral200,
      shadow: AppPalette.neutral900,
      scrim: AppPalette.neutral950,
      inverseSurface: AppPalette.neutral900,
      onInverseSurface: AppPalette.neutral50,
      inversePrimary: AppPalette.blue300,
      surfaceTint: AppPalette.blue600,
    ),
    appColors: AppColors.light(),
    scaffoldBackground: AppPalette.neutral50,
    snackAction: AppPalette.lime400,
    tabLabel: AppPalette.blue600,
  );

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: AppPalette.blue600,
      onPrimary: AppPalette.white,
      primaryContainer: AppPalette.blue800,
      onPrimaryContainer: AppPalette.blue100,
      secondary: AppPalette.lime400,
      onSecondary: AppPalette.onLime,
      secondaryContainer: AppPalette.oliveContainer,
      onSecondaryContainer: AppPalette.lime200,
      tertiary: AppPalette.blue300,
      onTertiary: AppPalette.neutral950,
      tertiaryContainer: AppPalette.blue900,
      onTertiaryContainer: AppPalette.blue200,
      error: AppPalette.dangerBright,
      onError: AppPalette.neutral950,
      errorContainer: AppPalette.dangerContainerDark,
      onErrorContainer: AppPalette.onDangerContainerDark,
      surface: AppPalette.neutral900,
      onSurface: AppPalette.neutral50,
      surfaceContainerLowest: AppPalette.neutral950,
      surfaceContainerLow: AppPalette.neutral900,
      surfaceContainer: AppPalette.neutral850,
      surfaceContainerHigh: AppPalette.neutral800,
      surfaceContainerHighest: AppPalette.neutral700,
      onSurfaceVariant: AppPalette.neutral400,
      outline: AppPalette.neutral700,
      outlineVariant: AppPalette.neutral800,
      shadow: AppPalette.neutral950,
      scrim: AppPalette.neutral950,
      inverseSurface: AppPalette.neutral50,
      onInverseSurface: AppPalette.neutral900,
      inversePrimary: AppPalette.blue600,
      surfaceTint: AppPalette.blue600,
    ),
    appColors: AppColors.dark(),
    scaffoldBackground: AppPalette.neutral950,
    snackAction: AppPalette.blue600,
    tabLabel: AppPalette.blue300,
  );

  static TextTheme _type(Color ink) => TextTheme(
        displayLarge: TextStyle(
            fontSize: 32,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: ink),
        displayMedium: TextStyle(
            fontSize: 28,
            height: 1.22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            color: ink),
        headlineLarge: TextStyle(
            fontSize: 24, height: 1.34, fontWeight: FontWeight.w700, color: ink),
        headlineMedium: TextStyle(
            fontSize: 20, height: 1.4, fontWeight: FontWeight.w700, color: ink),
        titleLarge: TextStyle(
            fontSize: 18, height: 1.34, fontWeight: FontWeight.w600, color: ink),
        titleMedium: TextStyle(
            fontSize: 16,
            height: 1.38,
            fontWeight: FontWeight.w600,
            color: ink),
        titleSmall: TextStyle(
            fontSize: 14,
            height: 1.43,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: ink),
        bodyLarge: TextStyle(
            fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: ink),
        bodyMedium: TextStyle(
            fontSize: 14, height: 1.43, fontWeight: FontWeight.w400, color: ink),
        bodySmall: TextStyle(
            fontSize: 13, height: 1.39, fontWeight: FontWeight.w400, color: ink),
        labelLarge: TextStyle(
            fontSize: 14,
            height: 1.43,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: ink),
        labelMedium: TextStyle(
            fontSize: 12,
            height: 1.34,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.25,
            color: ink),
        labelSmall: TextStyle(
            fontSize: 11,
            height: 1.28,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: ink),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppColors appColors,
    required Color scaffoldBackground,
    required Color snackAction,
    required Color tabLabel,
  }) {
    final textTheme = _type(scheme.onSurface);
    final isDark = brightness == Brightness.dark;
    final disabledBg =
        isDark ? AppPalette.neutral700 : AppPalette.neutral200;
    final disabledFg =
        isDark ? AppPalette.neutral500 : AppPalette.neutral400;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[appColors],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: AppPalette.lime400,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            );
          }
          return textTheme.labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppPalette.onLime);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppPalette.blue600,
        foregroundColor: AppPalette.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.blue600,
          foregroundColor: AppPalette.white,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tabLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tabLabel,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppPalette.lime400;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppPalette.onLime;
            }
            return scheme.onSurfaceVariant;
          }),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: appColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppPalette.blue600, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topSheet),
        showDragHandle: true,
        dragHandleColor: scheme.outline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle:
            textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: snackAction,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tabLabel,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: tabLabel,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        dividerColor: Colors.transparent,
        overlayColor:
            WidgetStatePropertyAll(AppPalette.blue600.withValues(alpha: 0.08)),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: AppPalette.lime400,
        textColor: AppPalette.onLime,
        textStyle: textTheme.labelSmall,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        largeSize: 18,
        smallSize: 8,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tabLabel,
        circularTrackColor: scheme.outlineVariant,
        linearTrackColor: scheme.outlineVariant,
      ),
    );
  }
}
