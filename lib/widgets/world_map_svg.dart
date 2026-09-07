import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WorldMapSvg extends StatelessWidget {
  final Map<String, int> countryVisits;

  const WorldMapSvg({super.key, required this.countryVisits});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DefaultAssetBundle.of(context).loadString('assets/images/world.svg'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 24),
              const SizedBox(height: 8),
              Text('Error loading map',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ));
        }

        if (!snapshot.hasData) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
          );
        }

        String svgContent = snapshot.data!;

        try {
          for (var entry in countryVisits.entries) {
            final country = entry.key;
            final visits = entry.value;
            String color = visits >= 6
                ? "#1976D2"
                : visits >= 3
                    ? "#42A5F5"
                    : "#90CAF9";

            // Robust regex to find path/g elements with matching name attribute
            final patternString =
                '<path[^>]*\\b(?:name|class|id)=["\']${RegExp.escape(country)}["\'][^>]*>';
            final tagPattern = RegExp(patternString, caseSensitive: false);

            svgContent = svgContent.replaceAllMapped(tagPattern, (match) {
              String tag = match.group(0)!;
              // Check if fill already exists
              if (tag.contains('fill=')) {
                return tag.replaceAll(RegExp("fill=(?:\"[^\"]*\"|'[^']*')"), 'fill="$color"');
              } else {
                // Insert fill before the closing >
                return tag.replaceFirst('>', ' fill="$color">');
              }
            });
          }
        } catch (e) {
          debugPrint('Error modifying SVG: $e');
        }

        return SvgPicture.string(
          svgContent,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }
}
