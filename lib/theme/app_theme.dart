import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Fresh, lively palette
  static const Color primaryColor = Color(0xFFFF7F50); // Coral Orange
  static const Color secondaryColor = Color(0xFF4ECDC4); // Medium Turquoise
  static const Color accentColor = Color(0xFFFFD93D); // Vibrant Yellow
  static const Color backgroundColor = Color(0xFFF7F9FC); // Cool White/Grey
  static const Color surfaceColor = Colors.white;
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textLight = Color(0xFF9599B3);
  
  // Dark Mode Palette
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color textDarkPrimary = Colors.white;
  static const Color textDarkSecondary = Color(0xFFAAAAAA);

  static const double borderRadius = 30.0;

  static ThemeData getLightTheme(Color seedColor) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        primary: seedColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        // background: backgroundColor, // Deprecated
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      primaryColor: seedColor,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.outfit(
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 34,
        ),
        headlineMedium: GoogleFonts.outfit(
          color: textDark,
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
        titleLarge: GoogleFonts.dmSans(
          color: textDark,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
        bodyLarge: GoogleFonts.dmSans(
          color: textDark,
          fontSize: 18,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.dmSans(
          color: textDark,
          fontSize: 15,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: seedColor.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
        iconTheme: const IconThemeData(color: textDark),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: seedColor,
        unselectedItemColor: textLight,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 12),
        elevation: 20,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        elevation: 10,
      ),
    );
  }

  static ThemeData getDarkTheme(Color seedColor) {
    // Premium Fintech Palette
    const Color premiumBackground = Color(0xFF1C1A27);
    const Color premiumSurface = Color(0xFF322E40); // User specified
    const Color premiumTextPrimary = Colors.white;
    const Color premiumTextSecondary = Colors.white70;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
        primary: seedColor, // Use user selected color as primary
        secondary: seedColor,
        surface: premiumSurface,
        onPrimary: Colors.white, // Contrast on user color
        onSecondary: Colors.white,
        onSurface: premiumTextPrimary,
        surfaceContainer: premiumSurface, // Ensure surfaces use the tinted charcoal
      ),
      primaryColor: seedColor,
      scaffoldBackgroundColor: premiumBackground,
      cardColor: premiumSurface,
      
      // Card Theme for premium feel
      cardTheme: CardThemeData(
        color: premiumSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(
            color: Colors.white.withOpacity(0.05), // Subtle border
            width: 1,
          ),
        ),
      ),

      textTheme: TextTheme(
        displayLarge: GoogleFonts.outfit(
          color: premiumTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 34,
        ),
        headlineMedium: GoogleFonts.outfit(
          color: premiumTextPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
        titleLarge: GoogleFonts.dmSans(
          color: premiumTextPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
        bodyLarge: GoogleFonts.dmSans(
          color: premiumTextSecondary, // Colors.white70
          fontSize: 18,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.dmSans(
          color: premiumTextSecondary, // Colors.white70
          fontSize: 15,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.outfit(
          color: premiumTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
         style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white, // White text on user color
          elevation: 4, // Softer elevation
          shadowColor: seedColor.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          color: premiumTextPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
        iconTheme: const IconThemeData(color: premiumTextSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: premiumBackground, // Match scaffold background
        selectedItemColor: seedColor, // Monochromatic Dark Theme
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 12),
        elevation: 0, // Flat premium look
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        elevation: 8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: premiumSurface,
        modalBackgroundColor: premiumSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
        ),
      ),
    );
  }
}
