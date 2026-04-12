import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class QuexTheme {
  static const brandBlue = Color(0xFF2563EB);
  static const brandTeal = Color(0xFF0F766E);
  static const brandOrange = Color(0xFFF59E0B);
  static const brandRed = Color(0xFFEF4444);
  static const brandPurple = Color(0xFF7C3AED);

  static ThemeData get lightTheme => _theme(Brightness.light);
  static ThemeData get darkTheme => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: brightness,
      surface: brightness == Brightness.light
          ? const Color(0xFFF8FAFC)
          : const Color(0xFF0F172A),
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
          teal: brandTeal,
          orange: brandOrange,
          red: brandRed,
          purple: brandPurple,
        ),
      ],
    );
  }
}

@immutable
class QuexColors extends ThemeExtension<QuexColors> {
  final Color? teal;
  final Color? orange;
  final Color? red;
  final Color? purple;

  const QuexColors({
    required this.teal,
    required this.orange,
    required this.red,
    required this.purple,
  });

  @override
  QuexColors copyWith({Color? teal, Color? orange, Color? red, Color? purple}) {
    return QuexColors(
      teal: teal ?? this.teal,
      orange: orange ?? this.orange,
      red: red ?? this.red,
      purple: purple ?? this.purple,
    );
  }

  @override
  QuexColors lerp(ThemeExtension<QuexColors>? other, double t) {
    if (other is! QuexColors) return this;
    return QuexColors(
      teal: Color.lerp(teal, other.teal, t),
      orange: Color.lerp(orange, other.orange, t),
      red: Color.lerp(red, other.red, t),
      purple: Color.lerp(purple, other.purple, t),
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
