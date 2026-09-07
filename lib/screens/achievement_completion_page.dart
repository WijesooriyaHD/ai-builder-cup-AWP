import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/achievement_service.dart';

class AchievementCompletionPage extends StatefulWidget {
  final Achievement achievement;

  const AchievementCompletionPage({super.key, required this.achievement});

  @override
  State<AchievementCompletionPage> createState() => _AchievementCompletionPageState();
}

class _AchievementCompletionPageState extends State<AchievementCompletionPage> with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _showFullScreenTrophy = true;
  bool _showAchievementDetails = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 5));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _shareScreenshot() async {
    try {
      final image = await _screenshotController.capture();
      if (image != null) {
        final directory = await getApplicationDocumentsDirectory();
        final imagePath = await File('${directory.path}/achievement_share.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: 'Check out my new achievement in AI Wellness Pal: ${widget.achievement.name}! 🌸✨',
        );
      }
    } catch (e) {
      debugPrint('Error sharing achievement: $e');
    }
  }

  Path drawStar(Size size) {
    // Method to convert degree to radians
    double degToRad(double deg) => deg * (math.pi / 180.0);

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
      path.lineTo(halfWidth + externalRadius * math.cos(step),
          halfWidth + externalRadius * math.sin(step));
      path.lineTo(halfWidth + internalRadius * math.cos(step + halfDegreesPerStep),
          halfWidth + internalRadius * math.sin(step + halfDegreesPerStep));
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    // Theme-aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 1. Achievements Details (Main Content)
          if (_showAchievementDetails)
          SafeArea(
            child: Column(
              children: [
                // Centered Content Area
                Expanded(
                  child: Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Achievement Icon/Emoji
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark ? Theme.of(context).cardColor : Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.4),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  widget.achievement.emoji,
                                  style: const TextStyle(fontSize: 48),
                                ),
                              ),
                              
                              const SizedBox(height: 32),
                              
                              Text(
                                widget.achievement.name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.achievement.description,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                                  fontSize: 16,
                                ),
                              ),
                              
                              const SizedBox(height: 32),

                              // Achievement Lottie Animation
                              SizedBox(
                                height: 200,
                                width: 600,
                                child: Lottie.asset(
                                  'assets/images/achievement.json',
                                  repeat: true,
                                  frameRate: FrameRate.composition,
                                ),
                              ),
                              const SizedBox(height: 32),

                              Text(
                                "ACHIEVEMENT UNLOCKED!",
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade800,
                                      letterSpacing: 1.5,
                                    ),
                              ),
                              const SizedBox(height: 16),
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
                  ),
                ),
                
                // Docked Buttons at the Bottom
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
                            "Awesome!",
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
                            "Share Achievement",
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

          // 2. Full Screen Trophy Intro
          if (_showFullScreenTrophy)
            Container(
              color: isDark ? Colors.black : Colors.white,
              child: Center(
                child: Lottie.asset(
                  'assets/images/Trophy.json',
                  repeat: false,
                  fit: BoxFit.contain,
                  onLoaded: (composition) {
                    Future.delayed(composition.duration, () {
                      if (mounted) {
                        setState(() {
                          _showFullScreenTrophy = false;
                          _showAchievementDetails = true;
                        });
                        _confettiController.play();
                      }
                    });
                  },
                ),
              ),
            ),

          // Confetti Overlay
          if (_showAchievementDetails)
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
                Colors.purple,
                Colors.amber,
              ],
              createParticlePath: drawStar,
            ),
          ),
        ],
      ),
    );
  }
}
