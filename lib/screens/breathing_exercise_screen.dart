import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Breathing Exercise screen with animated inhale/hold/exhale visual cues.
///
/// The exercise guides the user through a repeating cycle:
///   - Inhale (4 seconds) — circle expands
///   - Hold (4 seconds) — circle stays at max size
///   - Exhale (4 seconds) — circle contracts
///
/// The "Complete" button is disabled until 3 minutes (180 seconds) have elapsed.
/// On completion, pops with result `true` so calling code can record completion.
///
/// Requirements: 6.5
class BreathingExerciseScreen extends StatefulWidget {
  const BreathingExerciseScreen({super.key});

  /// Minimum session duration in seconds before the exercise can be completed.
  static const int minimumDurationSeconds = 180;

  /// Duration of each breathing phase in seconds.
  static const int phaseDurationSeconds = 4;

  @override
  State<BreathingExerciseScreen> createState() =>
      _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  /// Total cycle duration: inhale + hold + exhale = 12 seconds.
  static const int _cycleDurationMs = 12000;

  /// The three phases of the breathing cycle.
  static const List<_BreathPhase> _phases = [
    _BreathPhase(label: 'Inhale...', startFraction: 0.0, endFraction: 1 / 3),
    _BreathPhase(label: 'Hold...', startFraction: 1 / 3, endFraction: 2 / 3),
    _BreathPhase(label: 'Exhale...', startFraction: 2 / 3, endFraction: 1.0),
  ];

  @override
  void initState() {
    super.initState();

    // Animation controller repeats every 12 seconds (one full breath cycle).
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleDurationMs),
    );

    // Scale: expand during inhale (0→1/3), hold at max during hold (1/3→2/3),
    // contract during exhale (2/3→1).
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.5)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_animationController);

    // Opacity pulses gently for a calming effect.
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.4, end: 0.8)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.8),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 0.4)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_animationController);

    _animationController.repeat();
    _startTimer();
  }

  void _startTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  bool get _canComplete =>
      _elapsedSeconds >= BreathingExerciseScreen.minimumDurationSeconds;

  String get _currentPhaseLabel {
    final progress = _animationController.value;
    for (final phase in _phases) {
      if (progress >= phase.startFraction && progress < phase.endFraction) {
        return phase.label;
      }
    }
    return _phases.last.label;
  }

  String get _formattedElapsedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _formattedMinimumTime {
    final remaining =
        BreathingExerciseScreen.minimumDurationSeconds - _elapsedSeconds;
    if (remaining <= 0) return '';
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
  }

  void _onComplete() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          'Breathing Exercise',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 24),

                    // Phase label
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Text(
                          _currentPhaseLabel,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: primaryColor.withOpacity(0.9),
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Animated breathing circle
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        final scale = _scaleAnimation.value;
                        final opacity = _opacityAnimation.value;
                        final size = 180.0 * scale;

                        return Semantics(
                          label: 'Breathing animation, $_currentPhaseLabel',
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(
                              child: Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      primaryColor.withOpacity(opacity),
                                      primaryColor.withOpacity(opacity * 0.3),
                                    ],
                                    stops: const [0.4, 1.0],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryColor.withOpacity(opacity * 0.4),
                                      blurRadius: 30 * scale,
                                      spreadRadius: 5 * scale,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Outer ring indicator showing cycle progress
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return SizedBox(
                          width: 50,
                          height: 50,
                          child: CustomPaint(
                            painter: _CycleProgressPainter(
                              progress: _animationController.value,
                              color: primaryColor,
                              isDark: isDark,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Elapsed time display
                    Text(
                      _formattedElapsedTime,
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                        letterSpacing: 2.0,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Remaining time until "Complete" is enabled
                    AnimatedOpacity(
                      opacity: _canComplete ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        _formattedMinimumTime,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Complete button — disabled until 3 minutes elapsed
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: Semantics(
                          button: true,
                          enabled: _canComplete,
                          label: _canComplete
                              ? 'Complete breathing exercise'
                              : 'Complete button disabled, $_formattedMinimumTime',
                          child: AnimatedOpacity(
                          opacity: _canComplete ? 1.0 : 0.5,
                          duration: const Duration(milliseconds: 400),
                          child: ElevatedButton(
                            onPressed: _canComplete ? _onComplete : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[300],
                              disabledForegroundColor: isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[500],
                              elevation: _canComplete ? 4 : 0,
                              shadowColor: primaryColor.withOpacity(0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              _canComplete ? 'Complete' : 'Complete (3 min required)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Represents a single phase of the breathing cycle.
class _BreathPhase {
  final String label;
  final double startFraction;
  final double endFraction;

  const _BreathPhase({
    required this.label,
    required this.startFraction,
    required this.endFraction,
  });
}

/// Paints a circular progress indicator showing position within the current
/// breathing cycle.
class _CycleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDark;

  _CycleProgressPainter({
    required this.progress,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background circle
    final bgPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CycleProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
