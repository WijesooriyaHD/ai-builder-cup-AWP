import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'sleep_coach_screen.dart';
import 'sleep_state.dart';
import 'widgets/sleep_cards.dart';

/// A short educational onboarding shown the first time the user opens Sleep
/// Coach. Explains why sleep matters and how it connects with other habits
/// before revealing the dashboard. No permissions are requested here.
class SleepOnboardingScreen extends StatefulWidget {
  const SleepOnboardingScreen({super.key});

  @override
  State<SleepOnboardingScreen> createState() => _SleepOnboardingScreenState();
}

class _SleepOnboardingScreenState extends State<SleepOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      emoji: '🌙',
      title: 'How does your daily routine affect your sleep?',
      body:
          'AI Wellness Pal connects your sleep with hydration, nutrition, '
          'exercise and daily habits to help you understand what affects your '
          'recovery.',
    ),
    _OnboardPage(
      emoji: '🔎',
      title: 'What happened, and why?',
      body:
          'Instead of just numbers, your coach explains what changed in your '
          'sleep and which of your habits may have contributed.',
    ),
    _OnboardPage(
      emoji: '✅',
      title: 'A clear action for tonight',
      body:
          'You\'ll get one specific, realistic suggestion you can add to your '
          'routine — and build better sleep, one night at a time.\n\n'
          'Your sleep data helps personalize your recommendations and is never '
          'shared with identifying details.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final state = context.read<SleepState>();
    await state.completeOnboarding();
    // Offer to connect real health data now (permission prompt shown here,
    // after we've explained why). Denial simply falls back to sample data.
    await state.connectHealth();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SleepCoachScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F3FB),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            // Page indicators.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? kSleepAccent
                        : kSleepAccent.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSleepAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    if (isLast) {
                      _finish();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(isLast ? 'See My Sleep Data' : 'Continue',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  const _OnboardPage(
      {required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: kSleepAccent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 56))),
          ),
          const SizedBox(height: 32),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }
}
