import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Brand Colors ─── Premium Obsidian Dark
  static const Color background = Color(0xFF030306);
  static const Color surface = Color(0xFF0C0C14);
  static const Color surfaceLight = Color(0xFF16162A);
  static const Color surfaceElevated = Color(0xFF1A1A2E);

  static const Color accentOrange = Color(0xFFFF4500);
  static const Color accentWarm = Color(0xFFFF6B35);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color accentCyan = Color(0xFF06B6D4);

  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF4B5563);
  static const Color glassBorder = Color(0x14FFFFFF);
  static const Color glowColor = Color(0x40FF4500);

  // ─── Gradients
  static const Gradient brandGradient = LinearGradient(
    colors: [accentOrange, Color(0xFFE6007A), accentPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient warmGradient = LinearGradient(
    colors: [accentOrange, accentWarm],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient purpleGradient = LinearGradient(
    colors: [accentPurple, Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient darkGlassGradient = LinearGradient(
    colors: [
      Color(0x800C0C14),
      Color(0xCC030306),
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
      colorScheme: const ColorScheme.dark(
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
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: glassBorder, width: 0.5),
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
          side: const BorderSide(color: glassBorder, width: 0.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
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
          side: const BorderSide(color: glassBorder, width: 0.5),
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
          borderSide: const BorderSide(color: glassBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: glassBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accentOrange, width: 1.0),
        ),
      ),
      dividerTheme: const DividerThemeData(
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
