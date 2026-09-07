import 'package:aiwellnesspal/features/hydration/data/gemini_hydration_coach_service.dart';
import 'package:aiwellnesspal/features/hydration/domain/hydration_models.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeatherData / WeatherLocation serialization (cache round-trip)', () {
    test('WeatherData survives toJson/fromJson', () {
      final w = WeatherData(
        temperatureCelsius: 31.5,
        apparentTemperatureCelsius: 34.2,
        relativeHumidity: 78,
        precipitationMm: 0.2,
        weatherCode: 3,
        timestamp: DateTime(2024, 1, 1, 12),
        latitude: 6.03,
        longitude: 80.21,
      );
      final back = WeatherData.fromJson(w.toJson());
      expect(back.temperatureCelsius, w.temperatureCelsius);
      expect(back.relativeHumidity, w.relativeHumidity);
      expect(back.latitude, w.latitude);
    });

    test('WeatherLocation keeps source + coords', () {
      final loc = WeatherLocation(
        postalCode: '80000',
        city: 'Galle',
        region: 'Southern Province',
        country: 'Sri Lanka',
        countryCode: 'LK',
        latitude: 6.03,
        longitude: 80.21,
        source: 'postal_code',
        updatedAt: DateTime(2024, 1, 1),
      );
      final back = WeatherLocation.fromJson(loc.toJson());
      expect(back.source, 'postal_code');
      expect(back.city, 'Galle');
      expect(back.longitude, 80.21);
    });
  });

  group('Hydration goal = base + exercise + weather', () {
    test('weather adjustment adds to the base goal', () async {
      // calculateGoal is a pure heuristic (no AI/network).
      final service = GeminiHydrationCoachService();
      final base = await service.calculateGoal(
        const HydrationProfile(weightKg: 70, gender: 'female'),
      );
      final withWeather = await service.calculateGoal(
        const HydrationProfile(weightKg: 70, gender: 'female'),
        weather: const WeatherAdjustment(extraMl: 300, description: 'warm'),
      );
      expect(withWeather.totalMl, base.totalMl + 300);
    });

    test('exercise minutes add to the goal', () async {
      final service = GeminiHydrationCoachService();
      final rest = await service.calculateGoal(
        const HydrationProfile(weightKg: 70),
      );
      final active = await service.calculateGoal(
        const HydrationProfile(weightKg: 70, exerciseMinutesToday: 60),
      );
      expect(active.totalMl, greaterThan(rest.totalMl));
    });
  });
}
