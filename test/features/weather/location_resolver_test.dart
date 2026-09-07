import 'package:aiwellnesspal/features/weather/data/location_resolver.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_models.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake WeatherService that returns canned search results.
class _FakeWeatherService implements WeatherService {
  final List<LocationSearchResult> results;
  final bool throwErr;
  const _FakeWeatherService(this.results, {this.throwErr = false});

  @override
  Future<WeatherData> getCurrentWeather(
          {required double latitude, required double longitude}) =>
      throw UnimplementedError();

  @override
  Future<List<LocationSearchResult>> searchLocations(String query,
      {String? countryCode}) async {
    if (throwErr) throw const WeatherServiceException('boom');
    return results;
  }
}

void main() {
  group('LocationResolver.isValidPostalCode', () {
    test('accepts common formats', () {
      expect(LocationResolver.isValidPostalCode('80000'), isTrue);
      expect(LocationResolver.isValidPostalCode('SW1A 1AA'), isTrue);
      expect(LocationResolver.isValidPostalCode('K1A-0B1'), isTrue);
    });

    test('rejects empty / bad formats', () {
      expect(LocationResolver.isValidPostalCode(''), isFalse);
      expect(LocationResolver.isValidPostalCode('   '), isFalse);
      expect(LocationResolver.isValidPostalCode('!!'), isFalse);
    });
  });

  group('LocationResolver.resolvePostalCode', () {
    const galle = LocationSearchResult(
      name: 'Galle',
      admin1: 'Southern Province',
      country: 'Sri Lanka',
      countryCode: 'LK',
      latitude: 6.03,
      longitude: 80.21,
    );

    test('returns country-matched results', () async {
      final r = LocationResolver(const _FakeWeatherService([galle]));
      final results = await r.resolvePostalCode('80000', countryCode: 'LK');
      expect(results.length, 1);
      expect(results.first.name, 'Galle');
    });

    test('invalid postal code short-circuits to empty (no guessing)',
        () async {
      final r = LocationResolver(const _FakeWeatherService([galle]));
      final results = await r.resolvePostalCode('', countryCode: 'LK');
      expect(results, isEmpty);
    });

    test('filters out results from other countries', () async {
      const other = LocationSearchResult(
        name: 'Galle',
        country: 'India',
        countryCode: 'IN',
        latitude: 1,
        longitude: 2,
      );
      final r = LocationResolver(const _FakeWeatherService([galle, other]));
      final results = await r.resolvePostalCode('80000', countryCode: 'LK');
      expect(results.every((e) => e.countryCode == 'LK'), isTrue);
    });
  });

  group('LocationSearchResult.toLocation', () {
    test('maps to a WeatherLocation with source', () {
      const r = LocationSearchResult(
        name: 'Galle',
        admin1: 'Southern Province',
        country: 'Sri Lanka',
        countryCode: 'LK',
        latitude: 6.03,
        longitude: 80.21,
      );
      final loc = r.toLocation(postalCodeOverride: '80000', source: 'postal_code');
      expect(loc.city, 'Galle');
      expect(loc.postalCode, '80000');
      expect(loc.source, 'postal_code');
      expect(loc.latitude, 6.03);
    });
  });
}
