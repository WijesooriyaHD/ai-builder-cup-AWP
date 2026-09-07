import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../domain/sleep_models.dart';

/// Accent color for the Sleep Coach module (calm indigo/night).
const Color kSleepAccent = Color(0xFF6C63FF);

Color stageColor(SleepStageType t) {
  switch (t) {
    case SleepStageType.awake:
      return const Color(0xFFF0A020);
    case SleepStageType.rem:
      return const Color(0xFF7E9BFF);
    case SleepStageType.core:
      return const Color(0xFF6C63FF);
    case SleepStageType.deep:
      return const Color(0xFF3B3B98);
  }
}

/// Prominent sleep-score ring with duration + quality band.
class SleepScoreCard extends StatelessWidget {
  final String greeting;
  final SleepSession session;
  final SleepScore score;

  const SleepScoreCard({
    super.key,
    required this.greeting,
    required this.session,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        children: [
          Text(greeting,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('You slept',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(SleepSession.formatDuration(session.totalSleepMinutes),
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            width: 170,
            height: 170,
            child: CustomPaint(
              painter: _ScoreRingPainter(
                fraction: score.value / 100,
                color: kSleepAccent,
                trackColor: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${score.value}',
                        style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold, color: kSleepAccent)),
                    Text('Sleep Score',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: kSleepAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${score.emoji} ${score.band}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: kSleepAccent)),
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color trackColor;
  _ScoreRingPainter(
      {required this.fraction, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    const stroke = 14.0;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (fraction > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction.clamp(0.0, 1.0),
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: [color.withOpacity(0.5), color],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) => old.fraction != fraction;
}

/// Sleep-stage breakdown: segmented bar + per-stage rows.
class SleepStagesCard extends StatelessWidget {
  final SleepSession session;
  const SleepStagesCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const order = [
      SleepStageType.awake,
      SleepStageType.rem,
      SleepStageType.core,
      SleepStageType.deep,
    ];
    final inBed = session.timeInBedMinutes;
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sleep stages',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          // Segmented bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: order.map((t) {
                final flex = inBed <= 0 ? 1 : session.minutesFor(t);
                return Expanded(
                  flex: flex <= 0 ? 1 : flex,
                  child: Container(height: 12, color: stageColor(t)),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          ...order.map((t) {
            final mins = session.minutesFor(t);
            final pct = (session.fractionFor(t) * 100).round();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: stageColor(t), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.label)),
                  Text('$pct%',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: Text(SleepSession.formatDuration(mins),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Sleep factors: behavior → status with value + optimal range.
class SleepFactorsCard extends StatelessWidget {
  final List<SleepFactor> factors;
  const SleepFactorsCard({super.key, required this.factors});

  Color _statusColor(FactorStatus s) {
    switch (s) {
      case FactorStatus.excellent:
      case FactorStatus.good:
        return const Color(0xFF34A853);
      case FactorStatus.needsAttention:
      case FactorStatus.belowTarget:
      case FactorStatus.aboveTarget:
        return const Color(0xFFF0A020);
      case FactorStatus.noData:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sleep factors',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('How your day may relate to your sleep.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...factors.map((f) {
            final color = _statusColor(f.status);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (f.value != null || f.optimal != null)
                          Text(
                            [
                              if (f.value != null) f.value!,
                              if (f.optimal != null) 'Optimal: ${f.optimal!}',
                            ].join('  ·  '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(f.status.label,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// AI insight: what happened + why + view-why expansion.
class AISleepInsightCard extends StatelessWidget {
  final SleepInsight? insight;
  final bool isAnalyzing;
  final bool aiFailed;
  final VoidCallback? onRetry;

  const AISleepInsightCard({
    super.key,
    this.insight,
    this.isAnalyzing = false,
    this.aiFailed = false,
    this.onRetry,
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
            kSleepAccent.withOpacity(0.18),
            kSleepAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kSleepAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('AI Sleep Insight 🤖',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (isAnalyzing)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kSleepAccent)),
            ],
          ),
          const SizedBox(height: 12),
          if (isAnalyzing)
            Text('Analyzing your sleep patterns…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else if (aiFailed || insight == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("We couldn't generate your personalized insight right now.",
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, color: kSleepAccent),
                  label: const Text('Try again',
                      style: TextStyle(color: kSleepAccent)),
                ),
              ],
            )
          else ...[
            Text(insight!.summary,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 12),
            ...insight!.contributingFactors.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle,
                            size: 6, color: kSleepAccent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(f,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(height: 1.35))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// The prescriptive "Try this tonight" recommendation + add-to-routine CTA.
class AIRecommendationCard extends StatelessWidget {
  final SleepRecommendation recommendation;
  final VoidCallback? onAddToRoutine;
  final bool added;

  const AIRecommendationCard({
    super.key,
    required this.recommendation,
    this.onAddToRoutine,
    this.added = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Try this tonight',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(recommendation.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: kSleepAccent)),
          const SizedBox(height: 4),
          Text(recommendation.detail,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: added ? Colors.grey.shade400 : kSleepAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: added ? null : onAddToRoutine,
              icon: Icon(added
                  ? Icons.check_circle_rounded
                  : Icons.add_task_rounded),
              label: Text(added ? 'Added to your routine' : 'Add to my routine'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foods logged before sleep that may relate to rest.
class FoodSleepCard extends StatelessWidget {
  final String? dinnerName;
  final String? dinnerTime;
  final int? dinnerCalories;
  final int? protein;
  final int? carbs;
  final int? fat;
  final String? note; // e.g. "logged 48 min later than usual"

  const FoodSleepCard({
    super.key,
    this.dinnerName,
    this.dinnerTime,
    this.dinnerCalories,
    this.protein,
    this.carbs,
    this.fat,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Food & sleep',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (dinnerName == null)
            Text('Log your meals to discover how food may relate to your sleep.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else ...[
            Row(
              children: [
                const Text('🍽️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dinnerName!,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (dinnerTime != null)
                        Text('Dinner · $dinnerTime',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (dinnerCalories != null)
                  Text('$dinnerCalories kcal',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            if (protein != null || carbs != null || fat != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (carbs != null) 'Carbs ${carbs}g',
                  if (protein != null) 'Protein ${protein}g',
                  if (fat != null) 'Fat ${fat}g',
                ].join('   ·   '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kSleepAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_rounded,
                        size: 16, color: kSleepAccent),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(note!,
                            style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A compact last-7-days sleep-duration bar chart with scores.
class SleepHistoryChart extends StatelessWidget {
  final List<SleepHistoryPoint> points; // newest first
  const SleepHistoryChart({super.key, required this.points});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Oldest → newest for the chart.
    final ordered = points.reversed.toList();
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 7 days',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (ordered.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text('History appears as you track more nights.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: ordered.map((p) => _bar(context, p, ordered)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(
      BuildContext context, SleepHistoryPoint p, List<SleepHistoryPoint> all) {
    final theme = Theme.of(context);
    final maxMin = all
        .map((e) => e.totalSleepMinutes)
        .fold<int>(1, (a, b) => math.max(a, b));
    final h = (p.totalSleepMinutes / maxMin).clamp(0.1, 1.0) * 90;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${p.score}',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: h,
            decoration: BoxDecoration(
              color: kSleepAccent.withOpacity(0.85),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 4),
          Text(_days[p.date.weekday - 1],
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Skeleton loader shown while the dashboard loads.
class SleepSkeleton extends StatelessWidget {
  const SleepSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.06);
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(22),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [block(300), block(160), block(180), block(140)],
    );
  }
}
