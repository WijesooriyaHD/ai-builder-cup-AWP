import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'frosted_container.dart';

/// Displays the AI Wellness Insight text from a [DailyPlan.aiInsight].
///
/// This card is only shown when:
/// 1. The user has a Premium subscription (`isPro == true`)
/// 2. AI insights have not been disabled in Settings
/// 3. The `aiInsight` text is non-null and non-empty
///
/// If any of these conditions are not met, the widget renders [SizedBox.shrink]
/// — no error state is shown. (Requirement 4.5)
class AIWellnessInsightCard extends StatelessWidget {
  const AIWellnessInsightCard({
    super.key,
    required this.aiInsight,
    required this.isPro,
    required this.insightsEnabled,
  });

  /// The AI-generated insight text (30–80 words) explaining today's plan.
  final String? aiInsight;

  /// Whether the user has a Premium subscription.
  final bool isPro;

  /// Whether AI insights are enabled in Settings (not disabled by user).
  final bool insightsEnabled;

  @override
  Widget build(BuildContext context) {
    // Hide entirely if not Premium, insights disabled, or no insight text
    if (!isPro || !insightsEnabled || aiInsight == null || aiInsight!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Wellness Insight',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              aiInsight!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 450.ms, duration: 400.ms);
  }
}
