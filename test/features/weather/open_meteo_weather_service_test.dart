import 'dart:async';

import 'package:aiwellnesspal/features/weather/data/open_meteo_weather_service.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OpenMeteoWeatherService.getCurrentWeather', () {
    test('parses a successful current-weather response', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'api.open-meteo.com');
        expect(req.url.queryParameters['timezone'], 'auto');
        return http.Response('''
{"current":{"time":"2024-01-01T12:00","temperature_2m":31.5,
"apparent_temperature":34.2,"relative_humidity_2m":78,
"precipitation":0.0,"weather_code":1}}''', 200);
      });
      final svc = OpenMeteoWeatherService(client: client);
      final w = await svc.getCurrentWeather(latitude: 6.03, longitude: 80.21);
      expect(w.temperatureCelsius, 31.5);
      expect(w.apparentTemperatureCelsius, 34.2);
      expect(w.relativeHumidity, 78);
      expect(w.weatherCode, 1);
      expect(w.latitude, 6.03);
    });

    test('throws friendly error on invalid coordinates', () async {
      final svc = OpenMeteoWeatherService(
          client: MockClient((_) async => http.Response('{}', 200)));
      expect(
        () => svc.getCurrentWeather(latitude: 999, longitude: 0),
        throwsA(isA<WeatherServiceException>()),
      );
    });

    test('throws friendly error on non-200', () async {
      final svc = OpenMeteoWeatherService(
          client: MockClient((_) async => http.Response('error', 500)));
      expect(
        () => svc.getCurrentWeather(latitude: 6, longitude: 80),
        throwsA(isA<WeatherServiceException>()),
      );
    });

    test('throws friendly error when required fields are missing', () async {
      final svc = OpenMeteoWeatherService(
          client: MockClient((_) async => http.Response('{"foo":1}', 200)));
      expect(
        () => svc.getCurrentWeather(latitude: 6, longitude: 80),
        throwsA(isA<WeatherServiceException>()),
      );
    });

    test('maps timeout to a friendly error', () async {
      final svc = OpenMeteoWeatherService(client: MockClient((_) async {
        throw TimeoutException('slow');
      }));
      expect(
        () => svc.getCurrentWeather(latitude: 6, longitude: 80),
        throwsA(isA<WeatherServiceException>()),
      );
    });
  });

  group('OpenMeteoWeatherService.searchLocations', () {
    test('parses results and filters by country code', () async {
      final client = MockClient((req) async {
        return http.Response('''
{"results":[
 {"name":"Galle","admin1":"Southern Province","country":"Sri Lanka",
  "country_code":"LK","latitude":6.03,"longitude":80.21},
 {"name":"Galle","admin1":"X","country":"India","country_code":"IN",
  "latitude":1.0,"longitude":2.0}
]}''', 200);
      });
      final svc = OpenMeteoWeatherService(client: client);
      final results = await svc.searchLocations('Galle', countryCode: 'LK');
      expect(results.length, 1);
      expect(results.first.country, 'Sri Lanka');
      expect(results.first.countryCode, 'LK');
    });

    test('empty query returns empty list without a network call', () async {
      var called = false;
      final svc = OpenMeteoWeatherService(client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));
      final results = await svc.searchLocations('   ');
      expect(results, isEmpty);
      expect(called, isFalse);
    });

    test('empty geocoding response yields empty list', () async {
      final svc = OpenMeteoWeatherService(
          client: MockClient((_) async => http.Response('{}', 200)));
      expect(await svc.searchLocations('Nowhereville'), isEmpty);
    });
  });
}
