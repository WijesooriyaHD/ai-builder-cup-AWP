import '../domain/weather_models.dart';
import '../domain/weather_service.dart';

/// Resolves a country + postal code (or a city query) into candidate
/// [LocationSearchResult]s using the provider-agnostic [WeatherService].
///
/// Open-Meteo geocoding is a place-name search, not a universal postal lookup,
/// so we search by the postal code string (filtered to the country) and, when
/// that yields nothing reliable, the caller falls back to a city search.
class LocationResolver {
  final WeatherService _weather;
  const LocationResolver(this._weather);

  /// Basic postal-code sanity check (2–10 alphanumeric incl. space/dash).
  static bool isValidPostalCode(String code) {
    final c = code.trim();
    if (c.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-]{0,9}$').hasMatch(c);
  }

  /// Attempts to resolve [postalCode] within [countryCode]. Returns matching
  /// results, or an empty list if nothing reliable was found (caller should
  /// then offer the city fallback via [searchCity]).
  Future<List<LocationSearchResult>> resolvePostalCode(
    String postalCode, {
    required String countryCode,
  }) async {
    final code = postalCode.trim();
    if (!isValidPostalCode(code)) {
      return const [];
    }
    final results =
        await _weather.searchLocations(code, countryCode: countryCode);
    // Keep only results in the requested country to avoid guessing.
    final cc = countryCode.toUpperCase();
    return results
        .where((r) => r.countryCode.toUpperCase() == cc)
        .toList();
  }

  /// City/town fallback search within a country.
  Future<List<LocationSearchResult>> searchCity(
    String query, {
    required String countryCode,
  }) {
    return _weather.searchLocations(query, countryCode: countryCode);
  }
}
