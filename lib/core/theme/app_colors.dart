import 'package:flutter/material.dart';

/// SecureChat brand + neutral color ramps.
///
/// Primary brand: vivid blue `#2457FF` (sits next to the logo's own blue).
/// Accent: acid lime `#C8FF3D` — used only as a *fill* behind dark text
/// (its contrast on white is ~1.3:1, so it must never be body text).
/// Neutrals are blue-tinted so greys harmonize with the brand.
class AppPalette {
  AppPalette._();

  // Blue ramp (primary #2457FF at 600).
  static const Color blue50 = Color(0xFFEEF2FF);
  static const Color blue100 = Color(0xFFE9EEFF);
  static const Color blue200 = Color(0xFFD3DDFF);
  static const Color blue300 = Color(0xFFA7BCFF);
  static const Color blue400 = Color(0xFF7C9AFF);
  static const Color blue500 = Color(0xFF5079FF);
  static const Color blue600 = Color(0xFF2457FF);
  static const Color blue700 = Color(0xFF1D46CC);
  static const Color blue800 = Color(0xFF193DB3);
  static const Color blue900 = Color(0xFF163499);

  // Lime ramp (accent #C8FF3D at 400).
  static const Color lime50 = Color(0xFFF8FFE9);
  static const Color lime100 = Color(0xFFF1FFC8);
  static const Color lime200 = Color(0xFFE7FFA3);
  static const Color lime300 = Color(0xFFDBFF70);
  static const Color lime400 = Color(0xFFC8FF3D);
  static const Color lime500 = Color(0xFFB0E036);
  static const Color lime600 = Color(0xFF96BF2E);
  static const Color lime700 = Color(0xFF789925);
  static const Color lime800 = Color(0xFF5A731B);
  static const Color lime900 = Color(0xFF3C4D12);

  /// Dark text painted on top of lime fills (white on lime is ~2:1).
  static const Color onLime = Color(0xFF1A2405);

  /// Read-receipt tick green: single tick = sent, double tick = delivered,
  /// double tick in this green = seen. Kept distinct from the lime accent.
  static const Color readGreen = Color(0xFF22C55E);

  /// Muted olive fill for lime-tinted surfaces in dark mode.
  static const Color oliveContainer = Color(0xFF232E0A);

  // Blue-tinted neutral ramp.
  static const Color white = Color(0xFFFFFFFF);
  static const Color neutral25 = Color(0xFFFBFCFF);
  static const Color neutral50 = Color(0xFFF6F8FD);
  static const Color neutral100 = Color(0xFFEDF1F9);
  static const Color neutral200 = Color(0xFFE1E7F2);
  static const Color neutral300 = Color(0xFFCBD4E4);
  static const Color neutral400 = Color(0xFF97A3BC);
  static const Color neutral500 = Color(0xFF6B7793);
  static const Color neutral600 = Color(0xFF4E5871);
  static const Color neutral700 = Color(0xFF3A4257);
  static const Color neutral800 = Color(0xFF262D3D);
  static const Color neutral850 = Color(0xFF1C2230);
  static const Color neutral900 = Color(0xFF141926);
  static const Color neutral950 = Color(0xFF0B0F1A);

  // Danger (kept distinct from both brand colors).
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerBright = Color(0xFFFF6369);
  static const Color dangerContainerLight = Color(0xFFFDECEC);
  static const Color dangerContainerDark = Color(0xFF3A1416);
  static const Color onDangerContainerLight = Color(0xFF8F1D22);
  static const Color onDangerContainerDark = Color(0xFFFFB3B6);
}

/// Extra semantic colors that [ColorScheme] does not cover (chat-specific
/// roles and contrast-adjusted variants). Access via `context.appColors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color sentBubble;
  final Color onSentBubble;
  final Color receivedBubble;
  final Color onReceivedBubble;
  final Color presenceOnline;
  final Color presenceOffline;
  final Color storyRing;
  final Color storyRingSeen;
  final Color typingIndicator;
  final Color inputFill;

  /// Brand blue adjusted for *text/icons* (in dark mode the raw primary is
  /// only 3.5:1 on the background, so a lighter step is used for copy).
  final Color primaryEmphasis;

  const AppColors({
    required this.sentBubble,
    required this.onSentBubble,
    required this.receivedBubble,
    required this.onReceivedBubble,
    required this.presenceOnline,
    required this.presenceOffline,
    required this.storyRing,
    required this.storyRingSeen,
    required this.typingIndicator,
    required this.inputFill,
    required this.primaryEmphasis,
  });

  factory AppColors.light() => const AppColors(
        sentBubble: AppPalette.blue600,
        onSentBubble: AppPalette.white,
        receivedBubble: AppPalette.white,
        onReceivedBubble: AppPalette.neutral900,
        presenceOnline: AppPalette.lime600,
        presenceOffline: AppPalette.neutral400,
        storyRing: AppPalette.lime600,
        storyRingSeen: AppPalette.neutral300,
        typingIndicator: AppPalette.blue600,
        inputFill: AppPalette.neutral100,
        primaryEmphasis: AppPalette.blue600,
      );

  factory AppColors.dark() => const AppColors(
        sentBubble: AppPalette.blue600,
        onSentBubble: AppPalette.white,
        receivedBubble: AppPalette.neutral850,
        onReceivedBubble: AppPalette.neutral50,
        presenceOnline: AppPalette.lime400,
        presenceOffline: AppPalette.neutral500,
        storyRing: AppPalette.lime400,
        storyRingSeen: AppPalette.neutral700,
        typingIndicator: AppPalette.blue300,
        inputFill: AppPalette.neutral850,
        primaryEmphasis: AppPalette.blue300,
      );

  @override
  AppColors copyWith({
    Color? sentBubble,
    Color? onSentBubble,
    Color? receivedBubble,
    Color? onReceivedBubble,
    Color? presenceOnline,
    Color? presenceOffline,
    Color? storyRing,
    Color? storyRingSeen,
    Color? typingIndicator,
    Color? inputFill,
    Color? primaryEmphasis,
  }) {
    return AppColors(
      sentBubble: sentBubble ?? this.sentBubble,
      onSentBubble: onSentBubble ?? this.onSentBubble,
      receivedBubble: receivedBubble ?? this.receivedBubble,
      onReceivedBubble: onReceivedBubble ?? this.onReceivedBubble,
      presenceOnline: presenceOnline ?? this.presenceOnline,
      presenceOffline: presenceOffline ?? this.presenceOffline,
      storyRing: storyRing ?? this.storyRing,
      storyRingSeen: storyRingSeen ?? this.storyRingSeen,
      typingIndicator: typingIndicator ?? this.typingIndicator,
      inputFill: inputFill ?? this.inputFill,
      primaryEmphasis: primaryEmphasis ?? this.primaryEmphasis,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      sentBubble: Color.lerp(sentBubble, other.sentBubble, t)!,
      onSentBubble: Color.lerp(onSentBubble, other.onSentBubble, t)!,
      receivedBubble: Color.lerp(receivedBubble, other.receivedBubble, t)!,
      onReceivedBubble:
          Color.lerp(onReceivedBubble, other.onReceivedBubble, t)!,
      presenceOnline: Color.lerp(presenceOnline, other.presenceOnline, t)!,
      presenceOffline:
          Color.lerp(presenceOffline, other.presenceOffline, t)!,
      storyRing: Color.lerp(storyRing, other.storyRing, t)!,
      storyRingSeen: Color.lerp(storyRingSeen, other.storyRingSeen, t)!,
      typingIndicator:
          Color.lerp(typingIndicator, other.typingIndicator, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      primaryEmphasis:
          Color.lerp(primaryEmphasis, other.primaryEmphasis, t)!,
    );
  }
}
