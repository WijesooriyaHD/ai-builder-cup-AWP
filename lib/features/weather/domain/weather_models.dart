import 'dart:convert';

/// A factual current-weather reading from the weather provider (Open-Meteo).
class WeatherData {
  final double temperatureCelsius;
  final double apparentTemperatureCelsius;
  final int relativeHumidity;
  final double precipitationMm;
  final int weatherCode;
  final DateTime timestamp;
  final double latitude;
  final double longitude;

  const WeatherData({
    required this.temperatureCelsius,
    required this.apparentTemperatureCelsius,
    required this.relativeHumidity,
    required this.precipitationMm,
    required this.weatherCode,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });

  /// A simple label + emoji for the WMO weather code (subset).
  String get conditionEmoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 3) return '⛅';
    if (weatherCode <= 48) return '🌫️';
    if (weatherCode <= 67) return '🌧️';
    if (weatherCode <= 77) return '🌨️';
    if (weatherCode <= 82) return '🌦️';
    if (weatherCode <= 99) return '⛈️';
    return '🌡️';
  }

  Map<String, dynamic> toMap() => {
        'temperatureCelsius': temperatureCelsius,
        'apparentTemperatureCelsius': apparentTemperatureCelsius,
        'relativeHumidity': relativeHumidity,
        'precipitationMm': precipitationMm,
        'weatherCode': weatherCode,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      };

  factory WeatherData.fromMap(Map<String, dynamic> m) => WeatherData(
        temperatureCelsius:
            (m['temperatureCelsius'] as num?)?.toDouble() ?? 0,
        apparentTemperatureCelsius:
            (m['apparentTemperatureCelsius'] as num?)?.toDouble() ?? 0,
        relativeHumidity: (m['relativeHumidity'] as num?)?.round() ?? 0,
        precipitationMm: (m['precipitationMm'] as num?)?.toDouble() ?? 0,
        weatherCode: (m['weatherCode'] as num?)?.round() ?? 0,
        timestamp: DateTime.tryParse(m['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
      );

  String toJson() => jsonEncode(toMap());
  factory WeatherData.fromJson(String s) =>
      WeatherData.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A resolved current weather location. This is the user's *current* place —
/// never their nationality. Stored (single, current only) in Firebase.
class WeatherLocation {
  final String? postalCode;
  final String city;
  final String? region;
  final String country;
  final String countryCode;
  final double latitude;
  final double longitude;

  /// How the location was resolved: 'postal_code' or 'manual_city'.
  final String source;
  final DateTime updatedAt;

  const WeatherLocation({
    this.postalCode,
    required this.city,
    this.region,
    required this.country,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.updatedAt,
  });

  String get displayLine {
    final parts = [city, if (region != null && region!.isNotEmpty) region!, country];
    return parts.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'postalCode': postalCode,
        'city': city,
        'region': region,
        'country': country,
        'countryCode': countryCode,
        'latitude': latitude,
        'longitude': longitude,
        'source': source,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WeatherLocation.fromMap(Map<String, dynamic> m) => WeatherLocation(
        postalCode: m['postalCode'] as String?,
        city: m['city'] as String? ?? '',
        region: m['region'] as String?,
        country: m['country'] as String? ?? '',
        countryCode: m['countryCode'] as String? ?? '',
        latitude: (m['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (m['longitude'] as num?)?.toDouble() ?? 0,
        source: m['source'] as String? ?? 'manual_city',
        updatedAt: DateTime.tryParse(m['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());
  factory WeatherLocation.fromJson(String s) =>
      WeatherLocation.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A candidate location returned from the geocoding search (city fallback or
/// postal-code resolution).
class LocationSearchResult {
  final String name; // city / town / municipality
  final String? admin1; // region / province / state
  final String country;
  final String countryCode;
  final String? postalCode;
  final double latitude;
  final double longitude;

  const LocationSearchResult({
    required this.name,
    this.admin1,
    required this.country,
    required this.countryCode,
    this.postalCode,
    required this.latitude,
    required this.longitude,
  });

  String get displayLine {
    final parts = [
      name,
      if (admin1 != null && admin1!.isNotEmpty) admin1!,
      country,
    ];
    return parts.join(', ');
  }

  /// Converts a confirmed search result into a stored [WeatherLocation].
  WeatherLocation toLocation({String? postalCodeOverride, required String source}) {
    return WeatherLocation(
      postalCode: postalCodeOverride ?? postalCode,
      city: name,
      region: admin1,
      country: country,
      countryCode: countryCode,
      latitude: latitude,
      longitude: longitude,
      source: source,
      updatedAt: DateTime.now(),
    );
  }
}

/// A computed weather-driven hydration adjustment.
class WeatherHydrationAdjustment {
  final int adjustmentMl;
  final String reason;
  final String severity; // none / warm / hot / extreme / humid

  const WeatherHydrationAdjustment({
    this.adjustmentMl = 0,
    this.reason = '',
    this.severity = 'none',
  });

  bool get isActive => adjustmentMl > 0;
}
