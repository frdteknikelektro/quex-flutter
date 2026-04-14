import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class QuexTheme {
  static const primaryBlue = Color(0xFF4A90E2);
  static const warmRed = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFFB347);

  static ThemeData get lightTheme => _theme(Brightness.light);
  static ThemeData get darkTheme => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    // Create completely custom ColorScheme to eliminate any generated mismatched tones
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryBlue,
      onPrimary: Colors.white,
      primaryContainer: brightness == Brightness.light
          ? const Color(0xFFD4E8F7)
          : const Color(0xFF2A4A6C),
      onPrimaryContainer: brightness == Brightness.light
          ? const Color(0xFF1A3A5C)
          : const Color(0xFFD4E8F7),
      secondary: warmRed,
      onSecondary: Colors.white,
      secondaryContainer: brightness == Brightness.light
          ? const Color(0xFFFFE5E5)
          : const Color(0xFF4A2C2C),
      onSecondaryContainer: brightness == Brightness.light
          ? const Color(0xFF4A2C2C)
          : const Color(0xFFFFE5E5),
      tertiary: amber,
      onTertiary: Colors.white,
      tertiaryContainer: brightness == Brightness.light
          ? const Color(0xFFFFF3E0)
          : const Color(0xFF4A3520),
      onTertiaryContainer: brightness == Brightness.light
          ? const Color(0xFF4A3520)
          : const Color(0xFFFFF3E0),
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: brightness == Brightness.light
          ? const Color(0xFFFEF7F0)
          : const Color(0xFF1C1816),
      onSurface: brightness == Brightness.light
          ? const Color(0xFF1C1B1F)
          : const Color(0xFFE6E1E5),
      surfaceContainerHighest: brightness == Brightness.light
          ? const Color(0xFFE1E3E8)
          : const Color(0xFF36343A),
      outline: brightness == Brightness.light
          ? const Color(0xFF74777F)
          : const Color(0xFF938F99),
      outlineVariant: brightness == Brightness.light
          ? const Color(0xFFC4C6CF)
          : const Color(0xFF47474F),
    );

    final textTheme = GoogleFonts.nunitoSansTextTheme(base.textTheme);

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: brightness == Brightness.light ? 0.65 : 0.35,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: colorScheme.primaryContainer,
        backgroundColor: colorScheme.surface,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        unselectedLabelTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.secondaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        labelStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: colorScheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      extensions: const [
        QuexColors(
          warmRed: warmRed,
          amber: amber,
        ),
      ],
    );
  }
}

@immutable
class QuexColors extends ThemeExtension<QuexColors> {
  final Color? warmRed;
  final Color? amber;

  const QuexColors({
    required this.warmRed,
    required this.amber,
  });

  @override
  QuexColors copyWith({Color? warmRed, Color? amber}) {
    return QuexColors(
      warmRed: warmRed ?? this.warmRed,
      amber: amber ?? this.amber,
    );
  }

  @override
  QuexColors lerp(ThemeExtension<QuexColors>? other, double t) {
    if (other is! QuexColors) return this;
    return QuexColors(
      warmRed: Color.lerp(warmRed, other.warmRed, t),
      amber: Color.lerp(amber, other.amber, t),
    );
  }
}

class Sp {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  static const edge = EdgeInsets.all(md);
  static const page = EdgeInsets.fromLTRB(md, md, md, 112);
}

class Br {
  static final sm = BorderRadius.circular(12);
  static final md = BorderRadius.circular(16);
  static final lg = BorderRadius.circular(24);
  static final full = BorderRadius.circular(999);
}
