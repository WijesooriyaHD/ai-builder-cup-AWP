import 'package:flutter/material.dart';

/// Configuration for a wellness theme defining seed color, background overrides,
/// and premium gating status.
class WellnessThemeConfig {
  final String id;
  final String name;
  final Color seedColor;
  final Color lightBackground;
  final Color darkBackground;
  final bool isPremium;

  const WellnessThemeConfig({
    required this.id,
    required this.name,
    required this.seedColor,
    required this.lightBackground,
    required this.darkBackground,
    required this.isPremium,
  });
}

/// All available wellness themes. Free themes are accessible to all users;
/// premium themes require an active subscription.
const List<WellnessThemeConfig> wellnessThemes = [
  WellnessThemeConfig(
    id: 'serenity',
    name: 'Serenity',
    seedColor: Color(0xFF6B9FD4),
    lightBackground: Color(0xFFF0F5FC),
    darkBackground: Color(0xFF1A2233),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'lavender',
    name: 'Lavender',
    seedColor: Color(0xFF9B89C4),
    lightBackground: Color(0xFFF5F0FB),
    darkBackground: Color(0xFF201A33),
    isPremium: true,
  ),
  WellnessThemeConfig(
    id: 'soft_sand',
    name: 'Soft Sand',
    seedColor: Color(0xFFD4956B),
    lightBackground: Color(0xFFFBF5EF),
    darkBackground: Color(0xFF33241A),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'morning_glow',
    name: 'Morning Glow',
    seedColor: Color(0xFFE8A84C),
    lightBackground: Color(0xFFFCF5E8),
    darkBackground: Color(0xFF332B1A),
    isPremium: true,
  ),
  WellnessThemeConfig(
    id: 'pilates_studio',
    name: 'Pilates Studio',
    seedColor: Color(0xFF7AAE8B),
    lightBackground: Color(0xFFF0F7F2),
    darkBackground: Color(0xFF1A2B1F),
    isPremium: true,
  ),

  // Classic accent colors (previously the "Accent Color" swatches). Kept free
  // so existing users don't lose any color they were using.
  WellnessThemeConfig(
    id: 'coral',
    name: 'Coral',
    seedColor: Color(0xFFFF7F50),
    lightBackground: Color(0xFFFDF3EF),
    darkBackground: Color(0xFF33211A),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'turquoise',
    name: 'Turquoise',
    seedColor: Color(0xFF4ECDC4),
    lightBackground: Color(0xFFEEFAF9),
    darkBackground: Color(0xFF163330),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'sunny',
    name: 'Sunny',
    seedColor: Color(0xFFFFD93D),
    lightBackground: Color(0xFFFEFBEB),
    darkBackground: Color(0xFF33300F),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'violet',
    name: 'Violet',
    seedColor: Color(0xFF6C63FF),
    lightBackground: Color(0xFFF2F1FE),
    darkBackground: Color(0xFF1E1C33),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'blossom',
    name: 'Blossom',
    seedColor: Color(0xFFFF6B9D),
    lightBackground: Color(0xFFFDF0F5),
    darkBackground: Color(0xFF331A24),
    isPremium: false,
  ),
  WellnessThemeConfig(
    id: 'ocean',
    name: 'Ocean',
    seedColor: Color(0xFF2E86DE),
    lightBackground: Color(0xFFEEF5FD),
    darkBackground: Color(0xFF152435),
    isPremium: false,
  ),
];
