import '../domain/weather_config.dart';
import '../domain/weather_models.dart';

/// Turns factual [WeatherData] into a hydration adjustment using the
/// configurable thresholds in [HydrationWeatherThresholds]. These are wellness
/// nudges, not medical advice.
class WeatherHydrationAdjustmentService {
  const WeatherHydrationAdjustmentService();

  WeatherHydrationAdjustment compute(WeatherData? weather) {
    if (weather == null) {
      return const WeatherHydrationAdjustment();
    }
    final feels = weather.apparentTemperatureCelsius;
    final humidity = weather.relativeHumidity;

    var ml = 0;
    var severity = 'none';
    final reasons = <String>[];

    // Temperature band (uses feels-like temperature).
    if (feels >= HydrationWeatherThresholds.extremeC) {
      ml += HydrationWeatherThresholds.extremeMl;
      severity = 'extreme';
      reasons.add('extreme heat');
    } else if (feels >= HydrationWeatherThresholds.hotC) {
      ml += HydrationWeatherThresholds.hotMl;
      severity = 'hot';
      reasons.add('hot weather');
    } else if (feels >= HydrationWeatherThresholds.warmC) {
      ml += HydrationWeatherThresholds.warmMl;
      severity = 'warm';
      reasons.add('warm weather');
    }

    // High humidity adds a little more (compounds heat).
    if (humidity >= HydrationWeatherThresholds.highHumidityPct &&
        feels >= HydrationWeatherThresholds.warmC) {
      ml += HydrationWeatherThresholds.highHumidityMl;
      if (severity == 'none') severity = 'humid';
      reasons.add('high humidity');
    }

    if (ml > HydrationWeatherThresholds.maxAdjustmentMl) {
      ml = HydrationWeatherThresholds.maxAdjustmentMl;
    }

    final reason = _reasonText(severity, reasons, feels, humidity);
    return WeatherHydrationAdjustment(
      adjustmentMl: ml,
      reason: reason,
      severity: severity,
    );
  }

  String _reasonText(
      String severity, List<String> reasons, double feels, int humidity) {
    switch (severity) {
      case 'extreme':
        return 'Extreme heat detected. Consider carrying water with you.';
      case 'hot':
        return "Today's temperature is high. Aim for a little more water today.";
      case 'warm':
        if (reasons.contains('high humidity')) {
          return 'Warm and humid today. Keep water nearby and sip regularly.';
        }
        return 'Warm weather detected. Remember to stay hydrated.';
      case 'humid':
        return 'Humidity is elevated today. Keep water nearby and sip regularly.';
      default:
        return 'Cool weather today. Your standard hydration target applies.';
    }
  }
}
