import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/dream.dart';

class DreamCompletionPage extends StatefulWidget {
  final Dream dream;

  const DreamCompletionPage({super.key, required this.dream});

  @override
  State<DreamCompletionPage> createState() => _DreamCompletionPageState();
}

class _DreamCompletionPageState extends State<DreamCompletionPage> with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  final ScreenshotController _screenshotController = ScreenshotController();
  AnimationController? _spotlightController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 5));
    _initSpotlightController();
    
    // Start confetti immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiController.play();
    });
  }

  void _initSpotlightController() {
    _spotlightController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _spotlightController?.dispose();
    super.dispose();
  }

  Future<void> _shareScreenshot() async {
    try {
      final image = await _screenshotController.capture();
      if (image != null) {
        final directory = await getApplicationDocumentsDirectory();
        final imagePath = await File('${directory.path}/vision_share.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: 'I just achieved my vision in AI Wellness Pal: ${widget.dream.title}! 🌸✨🚀',
        );
      }
    } catch (e) {
      debugPrint('Error sharing vision: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Content + Overlays inside Screenshot
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Screenshot(
                    controller: _screenshotController,
                    child: Stack(
                      children: [
                        // Background & Content
                        Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Super-women Lottie Animation
                                  SizedBox(
                                    height: 380,
                                    child: Lottie.asset(
                                      'assets/images/super-women.json',
                                      repeat: true,
                                      frameRate: FrameRate.composition,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  Text(
                                    "CONGRATULATIONS!",
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade800,
                                          letterSpacing: 1.5,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "You've achieved your vision:",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.dream.title,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                  ),
                                  const SizedBox(height: 24),
                                  SvgPicture.asset(
                                    'assets/images/aiwellnesspal.svg',
                                    height: 40,
                                    colorFilter: ColorFilter.mode(
                                      isDark ? Colors.white70 : Colors.black26, 
                                      BlendMode.srcIn
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Spotlights Overlay (Captured in screenshot)
                        if (_spotlightController != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _spotlightController!,
                                builder: (context, child) {
                                  return CustomPaint(
                                    painter: _SpotlightPainter(
                                      animationValue: _spotlightController!.value,
                                      isDark: isDark,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        
                        // Confetti Overlay (Captured in screenshot)
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConfettiWidget(
                            confettiController: _confettiController,
                            blastDirectionality: BlastDirectionality.explosive,
                            shouldLoop: true,
                            colors: const [
                              Colors.green,
                              Colors.blue,
                              Colors.pink,
                              Colors.orange,
                              Colors.purple
                            ],
                            createParticlePath: drawStar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Docked Buttons at the Bottom (NOT in screenshot)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Theme.of(context).colorScheme.primary : Colors.black,
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Keep Growing",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _shareScreenshot,
                          icon: const Icon(Icons.share_rounded, size: 20),
                          label: const Text(
                            "Share Vision",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : Colors.black87,
                            side: BorderSide(
                              color: isDark ? Colors.white24 : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Path drawStar(Size size) {
    // Method to convert degree to radians
    double degToRad(double deg) => deg * (3.1415926535897932 / 180);

    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);

    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(halfWidth + externalRadius * math.cos(step), halfWidth + externalRadius * math.sin(step));
      path.lineTo(halfWidth + internalRadius * math.cos(step + halfDegreesPerStep), halfWidth + internalRadius * math.sin(step + halfDegreesPerStep));
    }
    path.close();
    return path;
  }
}

class _SpotlightPainter extends CustomPainter {
  final double animationValue;
  final bool isDark;

  _SpotlightPainter({required this.animationValue, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    _drawSpotlight(
      canvas, 
      size, 
      const Color(0xFFFFD700), // Gold
      -0.5 + (animationValue * 1.0), // Swing range
      0, // Bottom-left corner
    );
    _drawSpotlight(
      canvas, 
      size, 
      const Color(0xFFC0C0C0), // Silver
      0.5 - (animationValue * 1.0), // Opposite swing
      size.width, // Bottom-right corner
    );
  }

  void _drawSpotlight(Canvas canvas, Size size, Color color, double angle, double startX) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isDark ? 0.3 : 0.15),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, size.height * 0.2, size.width, size.height * 0.6));

    final path = Path();
    final bottomY = size.height; // Actual bottom corner
    final topY = 0.0; // Top of screen
    
    // Beam width calculations
    const beamWidthBottom = 10.0;
    const beamWidthTop = 150.0;
    
    final centerX = size.width / 2 + (math.sin(angle * math.pi) * (size.width / 2));

    path.moveTo(startX - beamWidthBottom / 2, bottomY);
    path.lineTo(startX + beamWidthBottom / 2, bottomY);
    path.lineTo(centerX + beamWidthTop / 2, topY);
    path.lineTo(centerX - beamWidthTop / 2, topY);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => 
      oldDelegate.animationValue != animationValue;
}
