import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/theme/wellness_themes.dart';
import 'package:aiwellnesspal/exceptions/premium_feature_exception.dart';

void main() {
  group('PremiumFeatureException', () {
    test('stores feature id', () {
      const exception = PremiumFeatureException('theme:lavender');
      expect(exception.featureId, 'theme:lavender');
    });

    test('toString includes feature id', () {
      const exception = PremiumFeatureException('theme:pilates_studio');
      expect(exception.toString(), contains('pilates_studio'));
    });

    test('implements Exception', () {
      const exception = PremiumFeatureException('theme:morning_glow');
      expect(exception, isA<Exception>());
    });
  });

  group('WellnessThemeConfig', () {
    test('free themes: Serenity and Soft Sand are not premium', () {
      final serenity = wellnessThemes.firstWhere((t) => t.id == 'serenity');
      final softSand = wellnessThemes.firstWhere((t) => t.id == 'soft_sand');
      expect(serenity.isPremium, isFalse);
      expect(softSand.isPremium, isFalse);
    });

    test('premium themes: Lavender, Morning Glow, Pilates Studio', () {
      final lavender = wellnessThemes.firstWhere((t) => t.id == 'lavender');
      final morningGlow = wellnessThemes.firstWhere((t) => t.id == 'morning_glow');
      final pilatesStudio = wellnessThemes.firstWhere((t) => t.id == 'pilates_studio');
      expect(lavender.isPremium, isTrue);
      expect(morningGlow.isPremium, isTrue);
      expect(pilatesStudio.isPremium, isTrue);
    });

    test('exactly 5 wellness themes exist', () {
      expect(wellnessThemes.length, 5);
    });

    test('each theme has a non-empty id and name', () {
      for (final theme in wellnessThemes) {
        expect(theme.id, isNotEmpty);
        expect(theme.name, isNotEmpty);
      }
    });

    test('each theme has distinct seed colors', () {
      final colors = wellnessThemes.map((t) => t.seedColor.toARGB32()).toSet();
      expect(colors.length, 5);
    });
  });
}
