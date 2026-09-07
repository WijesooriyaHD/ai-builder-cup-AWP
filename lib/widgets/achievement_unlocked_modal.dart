import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math' as math;
import '../services/achievement_service.dart';

class AchievementUnlockedModal extends StatefulWidget {
  final Achievement achievement;

  const AchievementUnlockedModal({super.key, required this.achievement});

  @override
  State<AchievementUnlockedModal> createState() => _AchievementUnlockedModalState();
}

class _AchievementUnlockedModalState extends State<AchievementUnlockedModal> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _borderController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiController.play();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AnimatedBuilder(
          animation: _borderController,
          builder: (context, child) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
              child: CustomPaint(
                painter: NeonBorderPainter(
                  animationValue: _borderController.value,
                  borderColor: accentColor,
                  isDark: isDark,
                ),
                child: Container(
                  // margin removed here, handled by parent Padding
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? Theme.of(context).cardColor : Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "ACHIEVEMENT UNLOCKED!",
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Sun-ray effect
                          AnimatedBuilder(
                            animation: _borderController,
                            builder: (context, child) {
                              // Pulse intensity between 0.3 and 1.0
                              final pulse = 0.65 + 0.35 * math.sin(_borderController.value * 2 * math.pi);
                              return CustomPaint(
                                size: const Size(160, 160),
                                painter: SunRayPainter(
                                  color: accentColor,
                                  intensity: pulse,
                                ),
                              );
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Theme.of(context).cardColor : Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.4),
                                  blurRadius: 32,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              widget.achievement.emoji,
                              style: const TextStyle(fontSize: 48),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.achievement.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.achievement.description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white70 : Colors.grey.shade600,
                            ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark 
                                ? Theme.of(context).scaffoldBackgroundColor 
                                : Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text("Awesome!"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          top: -20,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: -3.14 / 2, // up
            emissionFrequency: 0.05,
            numberOfParticles: 20,
            maxBlastForce: 20,
            minBlastForce: 10,
          ),
        ),
      ],
    );
  }
}

class NeonBorderPainter extends CustomPainter {
  final double animationValue;
  final Color borderColor;
  final bool isDark;

  NeonBorderPainter({
    required this.animationValue,
    required this.borderColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(32));

    // Create a sweep gradient that rotates
    final Gradient gradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: 6.28, // 2 * PI
      colors: [
        Colors.transparent,
        borderColor.withOpacity(0.1),
        borderColor.withOpacity(0.5),
        borderColor, // The shining head
        borderColor.withOpacity(0.5),
        borderColor.withOpacity(0.1),
        Colors.transparent,
      ],
      stops: const [0.0, 0.1, 0.2, 0.25, 0.3, 0.4, 1.0],
      transform: GradientRotation(animationValue * 6.28), // Rotate full circle
    );

    final Paint paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Add a glow effect
    final Paint glowPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 // Thicker for glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    if (isDark) {
      canvas.drawRRect(rrect, glowPaint);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(NeonBorderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.borderColor != borderColor ||
           oldDelegate.isDark != isDark;
  }
}

class SunRayPainter extends CustomPainter {
  final Color color;
  final double intensity;

  SunRayPainter({required this.color, double? intensity}) : intensity = intensity ?? 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rayCount = 8;
    final rayWidth = 0.2; // Optimized for fewer rays

    for (int i = 0; i < rayCount; i++) {
        final startAngle = (i * 2 * 3.14159 / rayCount) - (rayWidth / 2);
        
        final path = Path();
        path.moveTo(center.dx, center.dy);
        path.arcTo(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          rayWidth,
          false,
        );
        path.lineTo(center.dx, center.dy);
        path.close();

        final paint = Paint()
          ..shader = RadialGradient(
            colors: [
              color.withOpacity(0.6 * intensity),
              color.withOpacity(0.1 * intensity),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius));

        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SunRayPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.intensity != intensity;
  }
}
