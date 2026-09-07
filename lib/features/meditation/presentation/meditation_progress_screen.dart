import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// Progress + analytics: weekly minutes, streaks, and a breakdown by session
/// type. Reads entirely from locally-stored history via [MeditationState].
class MeditationProgressScreen extends StatelessWidget {
  const MeditationProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<MeditationState>();
    final stats = state.stats;
    final byType = state.minutesByType;
    final hasData = stats.totalSessions > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: !hasData
          ? const MeditationEmptyState(
              emoji: '📈',
              title: 'No sessions yet',
              message:
                  'Complete a meditation and your progress will show up here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MindfulnessStreakCard(stats: stats),
                const SizedBox(height: 16),
                _buildStatsGrid(context, stats),
                const SizedBox(height: 24),
                Text('This week',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                NutritionCard(
                  child: WeeklyMinutesChart(minutes: state.weeklyMinutes),
                ),
                const SizedBox(height: 24),
                Text('By session type',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildByType(context, byType),
              ],
            ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, MindfulnessStats stats) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            emoji: '🏆',
            value: '${stats.longestStreak}',
            label: 'Longest streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricTile(
            emoji: '⏳',
            value: _fmtMinutes(stats.totalMinutes),
            label: 'Total practiced',
          ),
        ),
      ],
    );
  }

  Widget _buildByType(BuildContext context, Map<SessionType, int> byType) {
    final theme = Theme.of(context);
    final entries = byType.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxV = entries.first.value;

    return NutritionCard(
      child: Column(
        children: entries.map((e) {
          final frac = maxV == 0 ? 0.0 : e.value / maxV;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(e.key.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(e.key.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${e.value} min',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: kMeditationAccent,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    backgroundColor: kMeditationAccent.withOpacity(0.1),
                    valueColor:
                        const AlwaysStoppedAnimation(kMeditationAccent),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }
}

class _MetricTile extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _MetricTile({
    required this.emoji,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold, color: kMeditationAccent)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
