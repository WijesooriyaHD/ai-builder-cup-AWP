import 'weather_models.dart';

/// Provider-agnostic weather contract. The Hydration Coach depends on this,
/// never on a concrete provider, so another source can be swapped in later.
abstract class WeatherService {
  /// Fetches current weather for resolved coordinates. Never sends any personal
  /// data — only latitude/longitude.
  Future<WeatherData> getCurrentWeather({
    required double latitude,
    required double longitude,
  });

  /// Searches for locations by free-text [query] (city/town/municipality),
  /// optionally filtered to a [countryCode]. Used for postal-code resolution
  /// and the city fallback search.
  Future<List<LocationSearchResult>> searchLocations(
    String query, {
    String? countryCode,
  });
}

/// A friendly, user-facing weather/location error (never raw API text).
class WeatherServiceException implements Exception {
  final String message;
  const WeatherServiceException(this.message);
  @override
  String toString() => 'WeatherServiceException: $message';
}
