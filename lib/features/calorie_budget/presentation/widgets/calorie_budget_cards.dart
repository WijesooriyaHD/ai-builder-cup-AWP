import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../domain/calorie_budget_models.dart';

/// Accent color for the calorie budget module (energetic amber-orange).
const Color kCalorieAccent = Color(0xFFF5A623);

/// Large circular budget dashboard: ring + Budget/Consumed/Burned/Remaining.
class CalorieBudgetCard extends StatelessWidget {
  final CalorieSummary summary;

  /// Optional title header rendered inside the card (used on the Home screen so
  /// the card matches the other Home cards' icon + title formatting).
  final Widget? titleHeader;

  const CalorieBudgetCard({super.key, required this.summary, this.titleHeader});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = summary.isOverBudget;
    final ringColor = over ? const Color(0xFFE9506E) : kCalorieAccent;

    return NutritionCard(
      child: Column(
        children: [
          if (titleHeader != null) ...[
            Align(alignment: Alignment.centerLeft, child: titleHeader!),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: 210,
            height: 210,
            child: CustomPaint(
              painter: _BudgetRingPainter(
                fraction: summary.consumedFraction,
                color: ringColor,
                trackColor: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${summary.remaining.abs()}',
                      style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold, color: ringColor),
                    ),
                    Text(
                      over ? 'kcal over' : 'kcal remaining',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metric(context, 'Budget', summary.dailyBudget,
                  theme.colorScheme.onSurface),
              _metric(context, 'Consumed', summary.consumed,
                  const Color(0xFF4A90D9)),
              _metric(context, 'Burned', summary.burned,
                  const Color(0xFF34A853)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value, Color color) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$value',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _BudgetRingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color trackColor;

  _BudgetRingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 12;
    const stroke = 16.0;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (fraction > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final p = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: [color.withOpacity(0.5), color],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, p);
    }
  }

  @override
  bool shouldRepaint(_BudgetRingPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Shows the AI prediction + recommendation + risk level.
class AiInsightCard extends StatelessWidget {
  final CaloriePrediction? prediction;
  final List<String> insights;
  final bool isAnalyzing;

  const AiInsightCard({
    super.key,
    this.prediction,
    this.insights = const [],
    this.isAnalyzing = false,
  });

  Color _riskColor(RiskLevel r) {
    switch (r) {
      case RiskLevel.low:
        return const Color(0xFF34A853);
      case RiskLevel.medium:
        return const Color(0xFFF0A020);
      case RiskLevel.high:
        return const Color(0xFFE9506E);
    }
  }

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
            kCalorieAccent.withOpacity(0.16),
            kCalorieAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kCalorieAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  color: kCalorieAccent, size: 20),
              const SizedBox(width: 8),
              Text('AI prediction',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (isAnalyzing)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kCalorieAccent)),
            ],
          ),
          const SizedBox(height: 12),
          if (prediction != null) ...[
            Row(
              children: [
                _predStat(context, 'Predicted intake',
                    '${prediction!.predictedIntake}'),
                const SizedBox(width: 20),
                _predStat(context, 'Goal', '${prediction!.dailyGoal}'),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _riskColor(prediction!.risk).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${prediction!.risk.label} risk',
                      style: TextStyle(
                          color: _riskColor(prediction!.risk),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: prediction!.goalProbability / 100,
              minHeight: 6,
              backgroundColor: kCalorieAccent.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(_riskColor(prediction!.risk)),
            ),
            const SizedBox(height: 4),
            Text('${prediction!.goalProbability}% chance of staying on goal',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child:
                          Icon(Icons.circle, size: 6, color: kCalorieAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(i,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _predStat(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Shows food + exercise events through the day. Rows are tappable to edit.
class DailyTimelineCard extends StatelessWidget {
  final List<CalorieEvent> events;
  final ValueChanged<CalorieEvent>? onTapEvent;
  const DailyTimelineCard({super.key, required this.events, this.onTapEvent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today’s timeline',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (events.isNotEmpty && onTapEvent != null)
                Text('Tap to edit',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text('No events yet. Log meals or exercise to see your day.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            ...events.map((e) => _row(context, e)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, CalorieEvent e) {
    final theme = Theme.of(context);
    final isFood = e.kind == CalorieEventKind.food;
    final color = isFood ? const Color(0xFF4A90D9) : const Color(0xFF34A853);
    return InkWell(
      onTap: onTapEvent == null ? null : () => onTapEvent!(e),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(_time(e.time),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(
                  isFood
                      ? Icons.restaurant_rounded
                      : Icons.directions_run_rounded,
                  size: 16,
                  color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            Text('${e.calories > 0 ? '+' : ''}${e.calories} kcal',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            if (onTapEvent != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

/// A compact 7-day consumed-vs-budget bar chart.
class WeeklyProgressCard extends StatelessWidget {
  final List<CalorieTrendPoint> points; // oldest → newest, up to 7
  const WeeklyProgressCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 7 days',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (points.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text('Trends appear as you log more days.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points.map((p) => _bar(context, p)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, CalorieTrendPoint p) {
    final theme = Theme.of(context);
    final maxVal = points
        .map((e) => math.max(e.consumed, e.budget))
        .fold<int>(1, (a, b) => math.max(a, b));
    final h = (p.consumed / maxVal).clamp(0.05, 1.0) * 100;
    final met = p.metGoal;
    final color = met ? const Color(0xFF34A853) : const Color(0xFFE9506E);
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${p.consumed}',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: h,
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 4),
          Text(_dayLabel(p.date),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String _dayLabel(DateTime d) => _days[d.weekday - 1];
}

/// Shows current + best goal-achievement streak.
class GoalStreakCard extends StatelessWidget {
  final int currentStreak;
  final int bestStreak;
  const GoalStreakCard({
    super.key,
    required this.currentStreak,
    required this.bestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kCalorieAccent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🔥', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$currentStreak-day streak',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                    currentStreak == 0
                        ? 'Stay within budget today to start a streak.'
                        : 'Best: $bestStreak days. Keep it going!',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
