/// Centralized Open-Meteo endpoints and tuning constants.
///
/// No API key is required for Open-Meteo. URLs live only here so they are never
/// scattered across the app.
class OpenMeteoConfig {
  OpenMeteoConfig._();

  static const String forecastBaseUrl =
      'https://api.open-meteo.com/v1/forecast';
  static const String geocodingBaseUrl =
      'https://geocoding-api.open-meteo.com/v1/search';

  /// Network timeout for all Open-Meteo requests.
  static const Duration requestTimeout = Duration(seconds: 12);

  /// How long a cached weather reading stays fresh before a refresh is needed.
  static const Duration cacheDuration = Duration(minutes: 60);
}

/// Configurable weather → hydration heuristics. These are wellness-product
/// nudges, NOT medical prescriptions. Kept here so there are no magic numbers
/// scattered through the code.
class HydrationWeatherThresholds {
  HydrationWeatherThresholds._();

  // Temperature bands (based on apparent/feels-like °C).
  static const double warmC = 27.0;
  static const double hotC = 32.0;
  static const double extremeC = 38.0;

  // Extra water for each band (ml).
  static const int warmMl = 300;
  static const int hotMl = 500;
  static const int extremeMl = 800;

  // Humidity band.
  static const int highHumidityPct = 70;
  static const int highHumidityMl = 300;

  // Cap the total weather adjustment so it never dominates the base goal.
  static const int maxAdjustmentMl = 1000;
}
