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
  State<AchievementCompletionPage> createState() =>
      _AchievementCompletionPageState();
}

class _AchievementCompletionPageState extends State<AchievementCompletionPage>
    with TickerProviderStateMixin {
  // Three confetti cannons:
  //  • top-center  — star particles cascade downward
  //  • bottom-left — circular particles shoot up-right
  //  • bottom-right— circular particles shoot up-left
  late final ConfettiController _topController;
  late final ConfettiController _bottomLeftController;
  late final ConfettiController _bottomRightController;

  final ScreenshotController _screenshotController = ScreenshotController();
  bool _showFullScreenTrophy = true;
  bool _showAchievementDetails = false;

  @override
  void initState() {
    super.initState();
    _topController =
        ConfettiController(duration: const Duration(seconds: 5));
    _bottomLeftController =
        ConfettiController(duration: const Duration(seconds: 5));
    _bottomRightController =
        ConfettiController(duration: const Duration(seconds: 5));
  }

  @override
  void dispose() {
    _topController.dispose();
    _bottomLeftController.dispose();
    _bottomRightController.dispose();
    super.dispose();
  }

  /// Fire all three cannons — top fires first, bottom pair follows 150 ms
  /// later so they cascade rather than start on the same frame.
  void _fireConfetti() {
    _topController.play();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _bottomLeftController.play();
        _bottomRightController.play();
      }
    });
  }

  Future<void> _shareScreenshot() async {
    try {
      final image = await _screenshotController.capture();
      if (image != null) {
        final directory = await getApplicationDocumentsDirectory();
        final imagePath =
            await File('${directory.path}/achievement_share.png').create();
        await imagePath.writeAsBytes(image);
        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text:
              'Check out my new achievement in AI Wellness Pal: '
              '${widget.achievement.name}! 🌸✨',
        );
      }
    } catch (e) {
      debugPrint('Error sharing achievement: $e');
    }
  }

  /// Five-pointed star used for the top cannon particles.
  Path _drawStar(Size size) {
    double degToRad(double deg) => deg * (math.pi / 180.0);
    const points = 5;
    final half = size.width / 2;
    final outer = half;
    final inner = half / 2.5;
    final step = degToRad(360 / points);
    final halfStep = step / 2;
    final path = Path();
    path.moveTo(size.width, half);
    for (double a = 0; a < degToRad(360); a += step) {
      path.lineTo(half + outer * math.cos(a), half + outer * math.sin(a));
      path.lineTo(
          half + inner * math.cos(a + halfStep),
          half + inner * math.sin(a + halfStep));
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    const confettiColors = [
      Colors.amber,
      Colors.orange,
      Color(0xFFFF6B9D), // pink
      Color(0xFF56C2A1), // teal-green
      Color(0xFF7B9FFF), // periwinkle
      Colors.yellow,
      Colors.white,
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── 1. Achievement details (shown after Trophy intro) ───────────────
          if (_showAchievementDetails)
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Screenshot(
                      controller: _screenshotController,
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Center(
                          child: SingleChildScrollView(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Glowing emoji badge
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? Theme.of(context).cardColor
                                        : Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withOpacity(0.45),
                                        blurRadius: 32,
                                        spreadRadius: 6,
                                      ),
                                      BoxShadow(
                                        color:
                                            Colors.amber.withOpacity(0.3),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    widget.achievement.emoji,
                                    style: const TextStyle(fontSize: 52),
                                  ),
                                ),

                                const SizedBox(height: 32),

                                Text(
                                  widget.achievement.name,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.achievement.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                    fontSize: 16,
                                    height: 1.5,
                                  ),
                                ),

                                const SizedBox(height: 32),

                                // Lottie badge animation
                                SizedBox(
                                  height: 200,
                                  width: double.infinity,
                                  child: Lottie.asset(
                                    'assets/images/achievement.json',
                                    repeat: true,
                                    frameRate: FrameRate.composition,
                                  ),
                                ),

                                const SizedBox(height: 24),

                                Text(
                                  'ACHIEVEMENT UNLOCKED!',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade700,
                                        letterSpacing: 1.5,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                SvgPicture.asset(
                                  'assets/images/aiwellnesspal.svg',
                                  height: 40,
                                  colorFilter: ColorFilter.mode(
                                    isDark
                                        ? Colors.white70
                                        : Colors.black26,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Docked action buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.black,
                              foregroundColor:
                                  isDark ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'On to the Next One!',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _shareScreenshot,
                            icon:
                                const Icon(Icons.share_rounded, size: 20),
                            label: const Text(
                              'Share Achievement',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isDark ? Colors.white : Colors.black87,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300,
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

          // ── 2. Full-screen Trophy intro ─────────────────────────────────────
          if (_showFullScreenTrophy)
            Container(
              color: isDark ? Colors.black : Colors.white,
              child: Center(
                child: Lottie.asset(
                  'assets/images/Trophy.json',
                  repeat: false,
                  fit: BoxFit.contain,
                  onLoaded: (composition) {
                    // Wait for the Trophy Lottie to finish, then reveal the
                    // details and fire all three confetti cannons.
                    Future.delayed(composition.duration, () {
                      if (mounted) {
                        setState(() {
                          _showFullScreenTrophy = false;
                          _showAchievementDetails = true;
                        });
                        _fireConfetti();
                      }
                    });
                  },
                ),
              ),
            ),

          // ── 3. Confetti cannons ─────────────────────────────────────────────
          if (_showAchievementDetails) ...[
            // Top-center — star particles rain downward.
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _topController,
                // Blast downward only so stars don't fly off-screen upward.
                blastDirection: math.pi / 2,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.06,
                numberOfParticles: 18,
                maxBlastForce: 30,
                minBlastForce: 12,
                gravity: 0.25,
                shouldLoop: false,
                colors: confettiColors,
                createParticlePath: _drawStar,
              ),
            ),

            // Bottom-left — circular particles shoot up and to the right.
            Align(
              alignment: Alignment.bottomLeft,
              child: ConfettiWidget(
                confettiController: _bottomLeftController,
                blastDirection: -math.pi / 4, // ~315° up-right
                emissionFrequency: 0.05,
                numberOfParticles: 22,
                maxBlastForce: 55,
                minBlastForce: 30,
                gravity: 0.18,
                shouldLoop: false,
                colors: confettiColors,
              ),
            ),

            // Bottom-right — circular particles shoot up and to the left.
            Align(
              alignment: Alignment.bottomRight,
              child: ConfettiWidget(
                confettiController: _bottomRightController,
                blastDirection: -math.pi * 3 / 4, // ~225° up-left
                emissionFrequency: 0.05,
                numberOfParticles: 22,
                maxBlastForce: 55,
                minBlastForce: 30,
                gravity: 0.18,
                shouldLoop: false,
                colors: confettiColors,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
