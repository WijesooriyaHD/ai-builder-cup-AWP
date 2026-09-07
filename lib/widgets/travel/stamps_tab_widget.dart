import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui' as ui;

import '../../providers/app_state.dart';
import '../../services/auth_service.dart';
import '../../models/travel_memory.dart';
import '../passport_bottom_sheet.dart';
import '../world_map_sheet.dart';

class StampsTabWidget extends StatefulWidget {
  final Function(int) onSwitchTab;

  const StampsTabWidget({super.key, required this.onSwitchTab});

  @override
  State<StampsTabWidget> createState() => _StampsTabWidgetState();
}

class _StampsTabWidgetState extends State<StampsTabWidget> {
  void _showWorldMapBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WorldMapSheet(),
    );
  }

  void _showPassportBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PassportBottomSheet(),
    );
  }

  String _extractCountry(String place) {
    // Simple extraction - take last part after comma, or whole string
    if (place.contains(',')) {
      return place.split(',').last.trim();
    }
    return place;
  }

  String _getCountryFlag(String country) {
    // Simple flag mapping for common countries
    final flags = {
      'France': '🇫🇷',
      'Paris': '🇫🇷',
      'USA': '🇺🇸',
      'United States': '🇺🇸',
      'Japan': '🇯🇵',
      'Tokyo': '🇯🇵',
      'UK': '🇬🇧',
      'United Kingdom': '🇬🇧',
      'London': '🇬🇧',
      'Italy': '🇮🇹',
      'Rome': '🇮🇹',
      'Spain': '🇪🇸',
      'Germany': '🇩🇪',
      'India': '🇮🇳',
      'China': '🇨🇳',
      'Australia': '🇦🇺',
      'Canada': '🇨🇦',
      'Brazil': '🇧🇷',
      'Mexico': '🇲🇽',
    };
    return flags[country] ?? '🌍';
  }

  Widget _buildStampCard(BuildContext context, String country, int visitCount) {
    final colors = [
      Colors.indigo,
      Colors.deepPurple,
      Colors.teal,
      Colors.amber,
      Colors.deepOrange,
      Colors.pink,
    ];
    final color = colors[country.hashCode % colors.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: color.withOpacity(isDark ? 0.2 : 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Stamp pattern background
            Positioned(
              right: -10,
              bottom: -10,
              child: RotationTransition(
                turns: const AlwaysStoppedAnimation(15 / 360),
                child: Icon(
                  Icons.public,
                  size: 80,
                  color: color.withOpacity(0.05),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _getCountryFlag(country),
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    country,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$visitCount ${visitCount == 1 ? 'STAMP' : 'STAMPS'}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.travelMemories.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.travel_explore_rounded,
                        size: 100,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.2)),
                  ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                   .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 2.seconds, curve: Curves.easeInOut),
                  const SizedBox(height: 48),
                  Text('Start Your Journey',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Text(
                      'Every country you visit adds a unique digital stamp to your passport. Collect them all!',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 16, height: 1.5),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => widget.onSwitchTab(0), // Index 0 is Map tab
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Go to Map',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 800.ms);
        }

        // Group memories by country
        Map<String, List<TravelMemory>> countriesMap = {};
        for (var memory in appState.travelMemories) {
          String country = _extractCountry(memory.place);
          if (!countriesMap.containsKey(country)) {
            countriesMap[country] = [];
          }
          countriesMap[country]!.add(memory);
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: IntrinsicHeight(
                  child: GestureDetector(
                    onTap: () => _showPassportBottomSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.badge_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final user = AuthService().currentUser;
                                    final metadataName = user?.displayName;
                                    final displayName =
                                        (metadataName != null && metadataName.trim().isNotEmpty)
                                            ? metadataName.toUpperCase()
                                            : (user?.email?.split('@').first ?? 'TRAVELER')
                                                .toUpperCase();
                                    return Text(
                                      displayName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5),
                                    );
                                  },
                                ),
                                Text(
                                  'VIEW DIGITAL PASSPORT',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showWorldMapBottomSheet(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.1)),
                              ),
                              child: const Icon(Icons.map_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.95, 0.95)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final country = countriesMap.keys.elementAt(index);
                    final memories = countriesMap[country]!;
                    return _buildStampCard(context, country, memories.length)
                        .animate(delay: (100 * index).ms)
                        .fadeIn(duration: 500.ms)
                        .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack);
                  },
                  childCount: countriesMap.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StampPatternPainter extends CustomPainter {
  final Color color;

  StampPatternPainter({required this.color});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw perforated edge pattern
    const spacing = 12.0;
    const radius = 3.0;

    // Top edge
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawCircle(Offset(x, 0), radius, paint);
    }
    // Bottom edge
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawCircle(Offset(x, size.height), radius, paint);
    }
    // Left edge
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawCircle(Offset(0, y), radius, paint);
    }
    // Right edge
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawCircle(Offset(size.width, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
