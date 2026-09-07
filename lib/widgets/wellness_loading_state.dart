import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ai_wellness_loader.dart';

/// A calm, full-screen loading state widget displayed while the AI engine
/// generates a Daily Wellness Plan after Check-In submission.
///
/// Shows rotating supportive text phrases that cycle every 3 seconds with
/// a gentle crossfade animation. No spinner or progress bar — just calm,
/// supportive messaging.
///
/// **Validates: Requirements 2.8**
class WellnessLoadingState extends StatefulWidget {
  const WellnessLoadingState({super.key});

  /// The supportive phrases that rotate during loading.
  static const List<String> phrases = [
    'Taking a moment to craft your plan...',
    'Listening to how you\'re feeling today...',
    'Preparing something just for you...',
    'Finding the right balance for today...',
    'Tuning in to your energy and needs...',
  ];

  /// Duration between phrase rotations.
  static const Duration cycleDuration = Duration(seconds: 3);

  @override
  State<WellnessLoadingState> createState() => _WellnessLoadingStateState();
}

class _WellnessLoadingStateState extends State<WellnessLoadingState> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(WellnessLoadingState.cycleDuration, (_) {
      setState(() {
        _currentIndex =
            (_currentIndex + 1) % WellnessLoadingState.phrases.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface,
            colorScheme.surface.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI + wellness themed animation, tinted with the app's primary.
              AiWellnessLoader(color: colorScheme.primary, size: 180),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: Text(
                  WellnessLoadingState.phrases[_currentIndex],
                  key: ValueKey<int>(_currentIndex),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
