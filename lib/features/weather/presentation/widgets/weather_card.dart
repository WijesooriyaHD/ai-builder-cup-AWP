import 'package:flutter/material.dart';

import '../../domain/weather_models.dart';

const Color _accent = Color(0xFF3FA9F5);

/// Compact weather + hydration-adjustment card for the Hydration dashboard.
class WeatherCard extends StatelessWidget {
  final WeatherData weather;
  final WeatherLocation location;
  final WeatherHydrationAdjustment adjustment;
  final bool stale;
  final VoidCallback? onChangeLocation;

  const WeatherCard({
    super.key,
    required this.weather,
    required this.location,
    required this.adjustment,
    this.stale = false,
    this.onChangeLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [_accent.withOpacity(0.24), _accent.withOpacity(0.08)]
              : [_accent.withOpacity(0.18), _accent.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(weather.conditionEmoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Text('${weather.temperatureCelsius.round()}°C',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Feels like ${weather.apparentTemperatureCelsius.round()}°C',
                        style: theme.textTheme.bodySmall),
                    Text('Humidity ${weather.relativeHumidity}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (onChangeLocation != null)
                IconButton(
                  tooltip: 'Change location',
                  icon: const Icon(Icons.edit_location_alt_rounded,
                      color: _accent, size: 20),
                  onPressed: onChangeLocation,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_rounded, size: 14, color: _accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(location.displayLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              if (stale)
                Text('cached',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic)),
            ],
          ),
          if (adjustment.isActive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.water_drop_rounded,
                      color: _accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Weather adjustment  +${adjustment.adjustmentMl}ml',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(adjustment.reason,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
