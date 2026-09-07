import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import 'interactive_passport_card.dart';

class PassportBottomSheet extends StatefulWidget {
  const PassportBottomSheet({super.key});

  @override
  State<PassportBottomSheet> createState() => _PassportBottomSheetState();
}

class _PassportBottomSheetState extends State<PassportBottomSheet> {
  final GlobalKey _passportKey = GlobalKey();
  Color? _selectedColor;

  final List<Color> _passportColors = [
    const Color(0xFF1A1A1A), // Black (Almost black for better contrast)
    const Color(0xFF1E3A8A), // Navy Blue
    const Color(0xFF047857), // Emerald Green
    const Color(0xFFB91C1C), // Deep Red
    const Color(0xFFFF7F50), // Default Coral (Brand)
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedColor ??= Theme.of(context).colorScheme.primary;
  }

  Future<void> _savePassportAsImage() async {
    try {
      RenderRepaintBoundary? boundary = _passportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/bloom_passport.png').create();
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles([XFile(file.path)], text: 'Check out my AI Wellness Pal Travel Passport! 🌍✈️');
    } catch (e) {
      debugPrint('Error sharing passport: $e');
    }
  }

  String _extractCountry(String place) {
    if (place.contains(',')) {
      return place.split(',').last.trim();
    }
    return place;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Calculate country count
        Set<String> countries = {};
        for (var memory in appState.travelMemories) {
          countries.add(_extractCountry(memory.place));
        }

        return Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
              ),
              
              RepaintBoundary(
                key: _passportKey,
                child: InteractivePassportCard(
                  displayName: (() {
                    final name = AuthService().currentUser?.displayName;
                    return (name != null && name.trim().isNotEmpty ? name : (AuthService().currentUser?.email?.split('@').first ?? 'TRAVELER')).toUpperCase();
                  })(),
                  countriesCount: countries.length,
                  memoriesCount: appState.travelMemories.length,
                  passportKey: GlobalKey(),
                  cardColor: _selectedColor,
                ),
              ),
              
              const SizedBox(height: 24),

              // Color Picker
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ..._passportColors,
                    // Dynamic Theme Color
                    if (!_passportColors.contains(Theme.of(context).colorScheme.primary))
                      Theme.of(context).colorScheme.primary,
                  ].map((color) {
                    final isSelected = _selectedColor == color;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected 
                              ? Border.all(color: Colors.white, width: 3)
                              : Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                          ]
                        ),
                        child: isSelected 
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _savePassportAsImage,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('SAVE & SHARE PASSPORT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
