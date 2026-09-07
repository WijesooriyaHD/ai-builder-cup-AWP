import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/weather_config.dart';
import '../domain/weather_models.dart';
import '../domain/weather_service.dart';

/// [WeatherService] backed by Open-Meteo (no API key, no GPS).
///
/// - Current weather: Open-Meteo Forecast API with `timezone=auto`.
/// - Location search / postal-code resolution: Open-Meteo Geocoding API.
///
/// Only latitude/longitude (or a search string) are ever sent — never any
/// personal or health data.
class OpenMeteoWeatherService implements WeatherService {
  final http.Client _client;

  OpenMeteoWeatherService({http.Client? client})
      : _client = client ?? http.Client();

  static const Map<String, String> _headers = {
    'User-Agent': 'AIWellnessPal/1.0 (hydration coach)',
  };

  @override
  Future<WeatherData> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    if (latitude.abs() > 90 || longitude.abs() > 180) {
      throw const WeatherServiceException('That location looks invalid.');
    }
    final uri = Uri.parse(OpenMeteoConfig.forecastBaseUrl).replace(
      queryParameters: {
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code',
        'timezone': 'auto',
      },
    );

    try {
      final resp = await _client
          .get(uri, headers: _headers)
          .timeout(OpenMeteoConfig.requestTimeout);
      if (resp.statusCode != 200) {
        throw const WeatherServiceException(
            'Weather service is unavailable right now.');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map || decoded['current'] is! Map) {
        throw const WeatherServiceException('Weather data was incomplete.');
      }
      final c = Map<String, dynamic>.from(decoded['current'] as Map);
      return WeatherData(
        temperatureCelsius: _d(c['temperature_2m']),
        apparentTemperatureCelsius: _d(c['apparent_temperature']),
        relativeHumidity: _i(c['relative_humidity_2m']),
        precipitationMm: _d(c['precipitation']),
        weatherCode: _i(c['weather_code']),
        timestamp: DateTime.tryParse(c['time']?.toString() ?? '') ??
            DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      );
    } on WeatherServiceException {
      rethrow;
    } on TimeoutException {
      throw const WeatherServiceException(
          'Weather request timed out. Please try again.');
    } catch (e) {
      debugPrint('❌ OpenMeteo getCurrentWeather: $e');
      throw const WeatherServiceException(
          "We couldn't reach the weather service.");
    }
  }

  @override
  Future<List<LocationSearchResult>> searchLocations(
    String query, {
    String? countryCode,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse(OpenMeteoConfig.geocodingBaseUrl).replace(
      queryParameters: {
        'name': q,
        'count': '10',
        'language': 'en',
        'format': 'json',
      },
    );

    try {
      final resp = await _client
          .get(uri, headers: _headers)
          .timeout(OpenMeteoConfig.requestTimeout);
      if (resp.statusCode != 200) {
        throw const WeatherServiceException(
            'Location search is unavailable right now.');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return [];
      final raw = (decoded['results'] as List<dynamic>?) ?? const [];
      var results = raw
          .whereType<Map>()
          .map((m) => _parseResult(Map<String, dynamic>.from(m)))
          .whereType<LocationSearchResult>()
          .toList();

      // Prefer/filter to the selected country when provided.
      if (countryCode != null && countryCode.isNotEmpty) {
        final cc = countryCode.toUpperCase();
        final filtered =
            results.where((r) => r.countryCode.toUpperCase() == cc).toList();
        if (filtered.isNotEmpty) results = filtered;
      }
      return results;
    } on WeatherServiceException {
      rethrow;
    } on TimeoutException {
      throw const WeatherServiceException(
          'Location search timed out. Please try again.');
    } catch (e) {
      debugPrint('❌ OpenMeteo searchLocations: $e');
      throw const WeatherServiceException(
          "We couldn't search for that location.");
    }
  }

  LocationSearchResult? _parseResult(Map<String, dynamic> m) {
    final lat = (m['latitude'] as num?)?.toDouble();
    final lon = (m['longitude'] as num?)?.toDouble();
    final name = m['name'] as String?;
    if (lat == null || lon == null || name == null || name.isEmpty) {
      return null;
    }
    // Open-Meteo geocoding may return a postcodes list.
    String? postal;
    final postcodes = m['postcodes'];
    if (postcodes is List && postcodes.isNotEmpty) {
      postal = postcodes.first.toString();
    }
    return LocationSearchResult(
      name: name,
      admin1: m['admin1'] as String?,
      country: m['country'] as String? ?? '',
      countryCode: m['country_code'] as String? ?? '',
      postalCode: postal,
      latitude: lat,
      longitude: lon,
    );
  }

  static double _d(dynamic v) => (v is num) ? v.toDouble() : 0.0;
  static int _i(dynamic v) => (v is num) ? v.round() : 0;
}
