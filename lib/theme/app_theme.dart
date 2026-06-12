import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Brand Colors ─── Premium Obsidian Dark
  static Color get background => Color(getColorValue('background'));
  static Color get surface => Color(getColorValue('surface'));
  static Color get surfaceLight => Color(getColorValue('surfaceLight'));
  static Color get surfaceElevated => Color(getColorValue('surfaceElevated'));

  static Color get accentOrange => Color(getColorValue('accentOrange'));
  static Color get accentWarm => Color(getColorValue('accentWarm'));
  static Color get accentPurple => Color(getColorValue('accentPurple'));
  static Color get accentCyan => Color(getColorValue('accentCyan'));

  static Color get textPrimary => Color(getColorValue('textPrimary'));
  static Color get textSecondary => Color(getColorValue('textSecondary'));
  static Color get textMuted => Color(getColorValue('textMuted'));
  static Color get glassBorder => Color(getColorValue('glassBorder'));
  static Color get glowColor => Color(getColorValue('glowColor'));

  static Color get darkGlassStart => Color(getColorValue('darkGlassStart'));
  static Color get darkGlassEnd => Color(getColorValue('darkGlassEnd'));

  static String _currentTheme = 'obsidian';
  static final ValueNotifier<String> themeNotifier = ValueNotifier('obsidian');

  static final Map<String, Map<String, int>> _themeColors = {
    'obsidian': {
      'background': 0xFF030306,
      'surface': 0xFF0C0C14,
      'surfaceLight': 0xFF16162A,
      'surfaceElevated': 0xFF1A1A2E,
      'accentOrange': 0xFFFF4500,
      'accentWarm': 0xFFFF6B35,
      'accentPurple': 0xFF7C3AED,
      'accentCyan': 0xFF06B6D4,
      'textPrimary': 0xFFF9FAFB,
      'textSecondary': 0xFF6B7280,
      'textMuted': 0xFF4B5563,
      'glassBorder': 0x14FFFFFF,
      'glowColor': 0x40FF4500,
      'darkGlassStart': 0x800C0C14,
      'darkGlassEnd': 0xCC030306,
    },
    'amoled': {
      'background': 0xFF000000,
      'surface': 0xFF0A0A0A,
      'surfaceLight': 0xFF121212,
      'surfaceElevated': 0xFF181818,
      'accentOrange': 0xFFFF4500,
      'accentWarm': 0xFFFF6B35,
      'accentPurple': 0xFF7C3AED,
      'accentCyan': 0xFF06B6D4,
      'textPrimary': 0xFFF9FAFB,
      'textSecondary': 0xFF6B7280,
      'textMuted': 0xFF4B5563,
      'glassBorder': 0x14FFFFFF,
      'glowColor': 0x40FF4500,
      'darkGlassStart': 0x800A0A0A,
      'darkGlassEnd': 0xCC000000,
    },
    'navy': {
      'background': 0xFF020617,
      'surface': 0xFF0B1329,
      'surfaceLight': 0xFF1E293B,
      'surfaceElevated': 0xFF334155,
      'accentOrange': 0xFF3B82F6,
      'accentWarm': 0xFF60A5FA,
      'accentPurple': 0xFF8B5CF6,
      'accentCyan': 0xFF06B6D4,
      'textPrimary': 0xFFF9FAFB,
      'textSecondary': 0xFF94A3B8,
      'textMuted': 0xFF64748B,
      'glassBorder': 0x14FFFFFF,
      'glowColor': 0x403B82F6,
      'darkGlassStart': 0x800B1329,
      'darkGlassEnd': 0xCC020617,
    },
    'forest': {
      'background': 0xFF020804,
      'surface': 0xFF052E16,
      'surfaceLight': 0xFF14532D,
      'surfaceElevated': 0xFF166534,
      'accentOrange': 0xFF22C55E,
      'accentWarm': 0xFF4ADE80,
      'accentPurple': 0xFF8B5CF6,
      'accentCyan': 0xFF22D3EE,
      'textPrimary': 0xFFF0FDF4,
      'textSecondary': 0xFF86EFAC,
      'textMuted': 0xFF4ADE80,
      'glassBorder': 0x14FFFFFF,
      'glowColor': 0x4022C55E,
      'darkGlassStart': 0x80052E16,
      'darkGlassEnd': 0xCC020804,
    },
    'crimson': {
      'background': 0xFF050102,
      'surface': 0xFF4C0519,
      'surfaceLight': 0xFF881337,
      'surfaceElevated': 0xFF9F1239,
      'accentOrange': 0xFFF43F5E,
      'accentWarm': 0xFFFB7185,
      'accentPurple': 0xFFC084FC,
      'accentCyan': 0xFF38BDF8,
      'textPrimary': 0xFFFFF1F2,
      'textSecondary': 0xFFFDA4AF,
      'textMuted': 0xFFFB7185,
      'glassBorder': 0x14FFFFFF,
      'glowColor': 0x40F43F5E,
      'darkGlassStart': 0x804C0519,
      'darkGlassEnd': 0xCC050102,
    },
  };

  static void selectTheme(String themeName) {
    if (_themeColors.containsKey(themeName)) {
      _currentTheme = themeName;
      themeNotifier.value = themeName;
    }
  }

  static int getColorValue(String name) {
    final themeData = _themeColors[_currentTheme] ?? _themeColors['obsidian']!;
    return themeData[name] ?? 0xFF000000;
  }

  // ─── Gradients
  static Gradient get brandGradient => LinearGradient(
        colors: [accentOrange, const Color(0xFFE6007A), accentPurple],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get warmGradient => LinearGradient(
        colors: [accentOrange, accentWarm],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get purpleGradient => LinearGradient(
        colors: [accentPurple, const Color(0xFF9333EA)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get darkGlassGradient => LinearGradient(
        colors: [
          darkGlassStart,
          darkGlassEnd,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static const Gradient cinematicScrim = LinearGradient(
    colors: [
      Colors.transparent,
      Color(0x1A000000),
      Color(0x99000000),
    ],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Border Radius Tokens
  static const double radiusSm = 12.0;
  static const double radiusMd = 16.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 100.0;

  // ─── Spacing Tokens
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;
  static const double spacingXxl = 32.0;

  // ─── Glass Decoration helper
  static BoxDecoration glassDecoration({
    double opacity = 0.06,
    double borderRadius = radiusLg,
    double borderWidth = 0.5,
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: glassBorder, width: borderWidth),
    );
  }

  static BoxDecoration cardDecoration({
    Color? color,
    double borderRadius = radiusLg,
  }) {
    return BoxDecoration(
      color: color ?? surfaceLight,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: glassBorder, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // ─── ThemeData
  static ThemeData get darkTheme {
    final interTextTheme = GoogleFonts.interTextTheme();
    final outfitTextTheme = GoogleFonts.outfitTextTheme();

    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: accentOrange,
      scaffoldBackgroundColor: background,
      canvasColor: Colors.transparent,
      colorScheme: ColorScheme.dark(
        primary: accentOrange,
        secondary: accentPurple,
        tertiary: accentCyan,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: TextTheme(
        // Headlines — Outfit (geometric, bold)
        displayLarge: outfitTextTheme.displayLarge!.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -1.0,
          height: 1.1,
        ),
        displayMedium: outfitTextTheme.displayMedium!.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.8,
          height: 1.15,
        ),
        headlineMedium: outfitTextTheme.headlineMedium!.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: outfitTextTheme.titleLarge!.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: outfitTextTheme.titleMedium!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.1,
        ),
        titleSmall: outfitTextTheme.titleSmall!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        // Body — Inter (humanist, readable)
        bodyLarge: interTextTheme.bodyLarge!.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          height: 1.5,
          letterSpacing: -0.1,
        ),
        bodyMedium: interTextTheme.bodyMedium!.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.4,
        ),
        bodySmall: interTextTheme.bodySmall!.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: textMuted,
          height: 1.3,
        ),
        // Labels
        labelLarge: interTextTheme.labelLarge!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        labelMedium: interTextTheme.labelMedium!.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: interTextTheme.labelSmall!.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textMuted,
          letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: outfitTextTheme.titleLarge!.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: glassBorder, width: 0.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: accentOrange,
        secondarySelectedColor: accentPurple,
        labelStyle: interTextTheme.labelMedium!.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        secondaryLabelStyle: interTextTheme.labelMedium!.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: BorderSide(color: glassBorder, width: 0.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: accentOrange,
        unselectedItemColor: textSecondary,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: BorderSide(color: glassBorder, width: 0.5),
        ),
        titleTextStyle: outfitTextTheme.titleLarge!.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        contentTextStyle: interTextTheme.bodyLarge!.copyWith(
          fontSize: 14,
          color: textSecondary,
          height: 1.5,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: interTextTheme.bodyMedium!.copyWith(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: accentOrange,
          shadowColor: glowColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: interTextTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        hintStyle:
            interTextTheme.bodyMedium!.copyWith(color: textMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: glassBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: glassBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: accentOrange, width: 1.0),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: glassBorder,
        thickness: 0.5,
        space: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor:
            WidgetStateProperty.all(Colors.white.withValues(alpha: 0.08)),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(3),
      ),
    );
  }
}
