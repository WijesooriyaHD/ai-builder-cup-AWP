import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../domain/meditation_models.dart';

/// Accent color for the Meditation module (soft indigo).
const Color kMeditationAccent = Color(0xFF6C63FF);
const Color kMeditationDeep = Color(0xFF3B2F80);

/// A large quick-action tile (Breathing, Guided, Body Scan, …).
class QuickActionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.85), color.withOpacity(0.55)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mindfulness streak / practice summary card.
class MindfulnessStreakCard extends StatelessWidget {
  final MindfulnessStats stats;
  const MindfulnessStreakCard({super.key, required this.stats});

  static String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Row(
        children: [
          Expanded(
            child: _stat(context, '🔥', '${stats.currentStreak}',
                'Day streak'),
          ),
          _divider(theme),
          Expanded(
            child: _stat(context, '🧘', '${stats.totalSessions}',
                'Sessions'),
          ),
          _divider(theme),
          Expanded(
            child: _stat(context, '⏱️', _fmt(stats.minutesThisWeek),
                'This week'),
          ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) => Container(
        width: 1,
        height: 44,
        color: theme.colorScheme.onSurface.withOpacity(0.08),
      );

  Widget _stat(BuildContext context, String emoji, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: kMeditationAccent)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// AI mindfulness recommendation banner.
class MindfulnessRecommendationCard extends StatelessWidget {
  final String recommendation;
  final bool loading;
  const MindfulnessRecommendationCard({
    super.key,
    required this.recommendation,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kMeditationAccent.withOpacity(0.18),
            kMeditationAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kMeditationAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: kMeditationAccent, size: 20),
              const SizedBox(width: 8),
              Text('AI Recommendation',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (loading)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kMeditationAccent)),
            ],
          ),
          const SizedBox(height: 10),
          Text(recommendation,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

/// A tappable card for a catalog item (guided meditation, sleep session, etc.).
class MeditationListCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String trailing; // e.g. "10 min · Beginner"
  final VoidCallback onTap;

  const MeditationListCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: NutritionCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kMeditationAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(trailing,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: kMeditationAccent,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded,
                color: kMeditationAccent.withOpacity(0.85), size: 30),
          ],
        ),
      ),
    );
  }
}

/// A premium achievement badge card.
class AchievementBadgeCard extends StatelessWidget {
  final MindfulnessAchievement achievement;
  final bool unlocked;
  const AchievementBadgeCard({
    super.key,
    required this.achievement,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: NutritionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: unlocked
                    ? const LinearGradient(
                        colors: [kMeditationAccent, kMeditationDeep])
                    : null,
                color: unlocked ? null : Colors.grey.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: unlocked
                    ? Text(achievement.emoji,
                        style: const TextStyle(fontSize: 26))
                    : const Icon(Icons.lock_rounded, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            Text(achievement.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(achievement.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

/// A weekly-minutes bar chart.
class WeeklyMinutesChart extends StatelessWidget {
  final List<int> minutes; // 7 values, oldest → newest
  const WeeklyMinutesChart({super.key, required this.minutes});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxV = minutes.fold<int>(1, (a, b) => math.max(a, b));
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(minutes.length, (i) {
          final h = (minutes[i] / maxV).clamp(0.04, 1.0) * 100;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${minutes[i]}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [kMeditationDeep, kMeditationAccent],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_days[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// The animated breathing circle. [t] is the phase progress (0→1) and [expand]
/// controls whether it grows (inhale/hold-full) or shrinks (exhale/hold-empty).
class BreathingCircle extends StatelessWidget {
  final double scale; // 0.55 (contracted) → 1.0 (expanded)
  final String instruction; // Inhale / Hold / Exhale
  final int countdown;
  final double progress; // overall session progress 0→1

  const BreathingCircle({
    super.key,
    required this.scale,
    required this.instruction,
    required this.countdown,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Progress ring.
          SizedBox(
            width: 260,
            height: 260,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: kMeditationAccent.withOpacity(0.12),
              valueColor:
                  const AlwaysStoppedAnimation(kMeditationAccent),
            ),
          ),
          // Breathing orb.
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 200 * scale,
            height: 200 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  kMeditationAccent.withOpacity(0.9),
                  kMeditationDeep.withOpacity(0.7),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: kMeditationAccent.withOpacity(0.4),
                  blurRadius: 40 * scale,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(instruction,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$countdown',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A simple sequential body illustration highlighting the active region.
class BodyRegionIndicator extends StatelessWidget {
  final List<String> regions;
  final int activeIndex;
  const BodyRegionIndicator({
    super.key,
    required this.regions,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Stylized figure = stacked rounded segments; active one glows.
        for (var i = 0; i < regions.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            width: _widthFor(i),
            decoration: BoxDecoration(
              color: i == activeIndex
                  ? kMeditationAccent
                  : kMeditationAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              boxShadow: i == activeIndex
                  ? [
                      BoxShadow(
                          color: kMeditationAccent.withOpacity(0.5),
                          blurRadius: 16)
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              regions[i],
              style: TextStyle(
                color: i == activeIndex
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                fontWeight:
                    i == activeIndex ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  // Vary widths so it reads a little like a body silhouette.
  double _widthFor(int i) {
    const widths = [120.0, 130.0, 90.0, 200.0, 220.0, 200.0, 170.0, 150.0, 120.0];
    return i < widths.length ? widths[i] : 160.0;
  }
}

/// Reusable calm empty state.
class MeditationEmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;
  const MeditationEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
