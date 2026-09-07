import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';

class WorldMapSheet extends StatefulWidget {
  const WorldMapSheet({super.key});

  @override
  State<WorldMapSheet> createState() => _WorldMapSheetState();
}

class _WorldMapSheetState extends State<WorldMapSheet> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _mapKey = GlobalKey();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _captureAndShareMap(GlobalKey key) async {
    try {
      RenderRepaintBoundary? boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/bloom_travel_map.png').create();
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles([XFile(file.path)], text: 'Check out my travel map from AI Wellness Pal! 🌍');
    } catch (e) {
      debugPrint('Error sharing map: $e');
    }
  }

  void _handleZoom(double scaleFactor) {
    final currentMatrix = _controller.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    
    double nextScale = currentScale * scaleFactor;
    
    // Limits
    if (nextScale < 1.0) nextScale = 1.0;
    if (nextScale > 6.0) nextScale = 6.0;
    
    if (nextScale == currentScale) return;
    
    final double factor = nextScale / currentScale;
    setState(() {
      _controller.value = currentMatrix.clone()..scale(factor);
    });
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
      ],
    );
  }

  String _extractCountry(String place) {
    if (place.contains(',')) {
      return place.split(',').last.trim();
    }
    return place;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          
          Expanded(
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                if (appState.travelMemories.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.public_rounded, size: 80, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
                          const SizedBox(height: 24),
                          Text('No Countries Visited', style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text('Start adding places to see your world map!', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }

                // Count visits per country
                Map<String, int> countryVisits = {};
                for (var memory in appState.travelMemories) {
                  String country = _extractCountry(memory.place);
                  countryVisits[country] = (countryVisits[country] ?? 0) + 1;
                }

                return FutureBuilder<String>(
                  future: DefaultAssetBundle.of(context).loadString('assets/images/world.svg'),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Center(child: Text('Error loading map'));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    String svgContent = snapshot.data!;
                    try {
                      for (var entry in countryVisits.entries) {
                        final country = entry.key;
                        final visits = entry.value;
                        String color = visits >= 6 ? "#1976D2" : visits >= 3 ? "#42A5F5" : "#90CAF9";
                        final patternString = '<path[^>]*\\b(?:name|class|id)=["\']${RegExp.escape(country)}["\'][^>]*>';
                        final tagPattern = RegExp(patternString, caseSensitive: false);
                        svgContent = svgContent.replaceAllMapped(tagPattern, (match) {
                          String tag = match.group(0)!;
                          if (tag.contains('fill=')) {
                            final fillRegex = RegExp('fill=["\'][^"\']*["\']');
                            return tag.replaceAll(fillRegex, 'fill="$color"');
                          } else {
                            final tagEndRegex = RegExp(r'(\s*)(/?>)');
                            return tag.replaceFirstMapped(tagEndRegex, (m) {
                              return ' fill="$color"${m.group(1)}${m.group(2)}';
                            });
                          }
                        });
                      }
                    } catch (e) {
                      debugPrint('Error coloring SVG map: $e');
                    }
                    
                    return Column(
                      children: [
                        Expanded(
                          child: RepaintBoundary(
                            key: _mapKey,
                            child: Container(
                              color: Theme.of(context).cardColor,
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'WORLD TRAVEL MAP',
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                          ),
                                          Text(
                                            '${countryVisits.length} COUNTRIES VISITED',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, letterSpacing: 1.0),
                                          ),
                                        ],
                                      ),
                                      Icon(Icons.public_rounded, color: Theme.of(context).colorScheme.primary.withOpacity(0.2), size: 32),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Legend
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _buildLegendItem('1-2 visits', const Color(0xFF90CAF9)),
                                        const SizedBox(width: 12),
                                        _buildLegendItem('3-5 visits', const Color(0xFF42A5F5)),
                                        const SizedBox(width: 12),
                                        _buildLegendItem('6+ visits', const Color(0xFF1976D2)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Expanded(
                                    child: InteractiveViewer(
                                      transformationController: _controller,
                                      minScale: 1.0,
                                      maxScale: 6.0,
                                      child: Center(
                                        child: SvgPicture.string(
                                          svgContent,
                                          width: MediaQuery.of(context).size.width,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        // Action Footer
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 60,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _captureAndShareMap(_mapKey),
                                    icon: const Icon(Icons.share_rounded),
                                    label: const Text('SAVE & SHARE MAP'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 48, width: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: IconButton(
                                      onPressed: () => _handleZoom(1.5),
                                      icon: const Icon(Icons.add_rounded, size: 20),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 48, width: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: IconButton(
                                      onPressed: () => _handleZoom(1/1.5),
                                      icon: const Icon(Icons.remove_rounded, size: 20),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 48, width: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _controller.value = Matrix4.identity();
                                        });
                                      },
                                      icon: const Icon(Icons.refresh_rounded, size: 20),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
