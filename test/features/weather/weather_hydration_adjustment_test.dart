import 'package:aiwellnesspal/features/weather/data/weather_hydration_adjustment_service.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_config.dart';
import 'package:aiwellnesspal/features/weather/domain/weather_models.dart';
import 'package:flutter_test/flutter_test.dart';

WeatherData _w({required double feels, int humidity = 40}) => WeatherData(
      temperatureCelsius: feels,
      apparentTemperatureCelsius: feels,
      relativeHumidity: humidity,
      precipitationMm: 0,
      weatherCode: 0,
      timestamp: DateTime(2024, 1, 1, 12),
      latitude: 6,
      longitude: 80,
    );

void main() {
  const svc = WeatherHydrationAdjustmentService();

  test('null weather → no adjustment', () {
    final a = svc.compute(null);
    expect(a.adjustmentMl, 0);
    expect(a.severity, 'none');
  });

  test('cool weather → standard target, no adjustment', () {
    final a = svc.compute(_w(feels: 20));
    expect(a.adjustmentMl, 0);
    expect(a.severity, 'none');
  });

  test('warm weather → warm adjustment', () {
    final a = svc.compute(_w(feels: 28));
    expect(a.adjustmentMl, HydrationWeatherThresholds.warmMl);
    expect(a.severity, 'warm');
  });

  test('hot weather → hot adjustment', () {
    final a = svc.compute(_w(feels: 33));
    expect(a.adjustmentMl, HydrationWeatherThresholds.hotMl);
    expect(a.severity, 'hot');
  });

  test('extreme heat → extreme adjustment', () {
    final a = svc.compute(_w(feels: 40));
    expect(a.adjustmentMl, HydrationWeatherThresholds.extremeMl);
    expect(a.severity, 'extreme');
  });

  test('high humidity compounds warm heat', () {
    final warmDry = svc.compute(_w(feels: 28, humidity: 40));
    final warmHumid = svc.compute(_w(feels: 28, humidity: 80));
    expect(warmHumid.adjustmentMl, greaterThan(warmDry.adjustmentMl));
    expect(warmHumid.adjustmentMl,
        HydrationWeatherThresholds.warmMl + HydrationWeatherThresholds.highHumidityMl);
  });

  test('adjustment never exceeds the configured max', () {
    final a = svc.compute(_w(feels: 45, humidity: 95));
    expect(a.adjustmentMl,
        lessThanOrEqualTo(HydrationWeatherThresholds.maxAdjustmentMl));
  });

  test('reason text is non-clinical and present when active', () {
    final a = svc.compute(_w(feels: 40));
    expect(a.reason, isNotEmpty);
    expect(a.reason.toLowerCase(), isNot(contains('dehydrated')));
  });
}
