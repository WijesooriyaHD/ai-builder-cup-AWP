import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../domain/hydration_models.dart';

/// Accent color for the hydration module (refreshing water blue).
const Color kHydrationAccent = Color(0xFF3FA9F5);

String formatMl(int ml) =>
    ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1)}L' : '${ml}ml';

/// Water-fill progress ring: Goal / Consumed / Remaining / Progress %.
class HydrationProgressCard extends StatefulWidget {
  final int goalMl;
  final int consumedMl;

  /// Whether the goal is a user-set value (shows an "Edit" hint).
  final bool isManualGoal;

  /// Tapped to edit the daily target. When null, the goal is not editable.
  final VoidCallback? onEditGoal;

  /// Optional title header rendered inside the card (used on the Home screen so
  /// the card matches the other Home cards' icon + title formatting).
  final Widget? titleHeader;

  const HydrationProgressCard({
    super.key,
    required this.goalMl,
    required this.consumedMl,
    this.isManualGoal = false,
    this.onEditGoal,
    this.titleHeader,
  });

  @override
  State<HydrationProgressCard> createState() => _HydrationProgressCardState();
}

class _HydrationProgressCardState extends State<HydrationProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        widget.goalMl <= 0 ? 0.0 : (widget.consumedMl / widget.goalMl).clamp(0.0, 1.0);
    final pct = (progress * 100).round();
    final remaining = (widget.goalMl - widget.consumedMl).clamp(0, 999999);

    return NutritionCard(
      child: Column(
        children: [
          if (widget.titleHeader != null) ...[
            Align(
                alignment: Alignment.centerLeft, child: widget.titleHeader!),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: 200,
            height: 200,
            child: AnimatedBuilder(
              animation: _wave,
              builder: (context, _) {
                return CustomPaint(
                  painter: _WaterRingPainter(
                    fraction: progress,
                    phase: _wave.value * 2 * math.pi,
                    color: kHydrationAccent,
                    trackColor: theme.colorScheme.onSurface.withOpacity(0.06),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$pct%',
                            style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: kHydrationAccent)),
                        Text('complete',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _goalMetric(context),
              _metric(context, 'Consumed', formatMl(widget.consumedMl),
                  kHydrationAccent),
              _metric(context, 'Remaining', formatMl(remaining),
                  const Color(0xFF34A853)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, Color c) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: c)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// The "Goal" metric, tappable to edit the daily target when [onEditGoal] is
  /// provided. Shows an edit icon and a "Custom"/"Edit" hint.
  Widget _goalMetric(BuildContext context) {
    final theme = Theme.of(context);
    final column = Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatMl(widget.goalMl),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface)),
            if (widget.onEditGoal != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 14, color: kHydrationAccent),
            ],
          ],
        ),
        Text(widget.onEditGoal == null
            ? 'Goal'
            : (widget.isManualGoal ? 'Goal · Custom' : 'Goal · Tap to edit'),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
    if (widget.onEditGoal == null) return column;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onEditGoal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: column,
      ),
    );
  }
}

/// Ring with an animated water-fill inside the circle.
class _WaterRingPainter extends CustomPainter {
  final double fraction;
  final double phase;
  final Color color;
  final Color trackColor;

  _WaterRingPainter({
    required this.fraction,
    required this.phase,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const stroke = 12.0;
    final innerRadius = radius - stroke;

    // Clip a circle for the water fill.
    canvas.save();
    final clip = Path()
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.clipPath(clip);

    // Water level: bottom (empty) → top (full).
    final waterTop = center.dy + innerRadius - (2 * innerRadius * fraction);
    final wavePath = Path();
    const waveHeight = 6.0;
    final left = center.dx - innerRadius;
    final right = center.dx + innerRadius;
    wavePath.moveTo(left, size.height);
    wavePath.lineTo(left, waterTop);
    for (double x = left; x <= right; x += 4) {
      final y = waterTop +
          math.sin((x / innerRadius * 2 * math.pi) + phase) * waveHeight;
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(right, size.height);
    wavePath.close();
    canvas.drawPath(
        wavePath, Paint()..color = color.withOpacity(0.35));

    // Second, offset wave for depth.
    final wave2 = Path();
    wave2.moveTo(left, size.height);
    wave2.lineTo(left, waterTop);
    for (double x = left; x <= right; x += 4) {
      final y = waterTop +
          math.sin((x / innerRadius * 2 * math.pi) + phase + math.pi) *
              waveHeight;
      wave2.lineTo(x, y);
    }
    wave2.lineTo(right, size.height);
    wave2.close();
    canvas.drawPath(wave2, Paint()..color = color.withOpacity(0.22));
    canvas.restore();

    // Track ring.
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);

    // Progress arc.
    if (fraction > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_WaterRingPainter old) =>
      old.fraction != fraction || old.phase != phase;
}

/// 0–100 hydration score + AI explanation.
class HydrationScoreCard extends StatelessWidget {
  final HydrationScore score;
  const HydrationScoreCard({super.key, required this.score});

  Color get _color {
    if (score.score >= 85) return const Color(0xFF34A853);
    if (score.score >= 60) return kHydrationAccent;
    if (score.score >= 35) return const Color(0xFFF0A020);
    return const Color(0xFFE9506E);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: score.score / 100,
                    strokeWidth: 6,
                    backgroundColor: _color.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(_color),
                  ),
                ),
                Text('${score.score}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: _color)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hydration score',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(score.explanation,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(height: 1.35, color: _color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AI insights, prediction, and behavior-based reminders.
class SmartInsightsCard extends StatelessWidget {
  final HydrationPrediction? prediction;
  final List<String> insights;
  final List<Reminder> reminders;
  final bool isAnalyzing;

  const SmartInsightsCard({
    super.key,
    this.prediction,
    this.insights = const [],
    this.reminders = const [],
    this.isAnalyzing = false,
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
            kHydrationAccent.withOpacity(0.16),
            kHydrationAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kHydrationAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_rounded,
                  color: kHydrationAccent, size: 20),
              const SizedBox(width: 8),
              Text('Smart insights',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (isAnalyzing)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kHydrationAccent)),
            ],
          ),
          if (prediction != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: kHydrationAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(prediction!.recommendation,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...insights.map((i) => _bullet(context, i)),
          ...reminders.map((r) => _bullet(context, r.message, reminder: true)),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text, {bool reminder = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
                reminder
                    ? Icons.notifications_active_rounded
                    : Icons.circle,
                size: reminder ? 14 : 6,
                color: kHydrationAccent),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
        ],
      ),
    );
  }
}

/// Today's water-intake timeline (rows tappable to delete).
class HydrationTimelineCard extends StatelessWidget {
  final List<HydrationEntry> entries;
  final ValueChanged<HydrationEntry>? onTapEntry;

  const HydrationTimelineCard({
    super.key,
    required this.entries,
    this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today’s timeline",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text('No water logged yet. Tap a quick-add below to start.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            ...entries.map((e) => _row(context, e)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, HydrationEntry e) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTapEntry == null ? null : () => onTapEntry!(e),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(_time(e.timestamp),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: kHydrationAccent.withOpacity(0.12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.water_drop_rounded,
                  size: 16, color: kHydrationAccent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(formatMl(e.amountMl),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Text('+${e.amountMl} ml',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: kHydrationAccent)),
            if (onTapEntry != null) ...[
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

/// 7-day intake-vs-goal bars + consistency summary.
class WeeklyAnalyticsCard extends StatelessWidget {
  final List<HydrationTrendPoint> points; // oldest → newest, up to 7
  const WeeklyAnalyticsCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final met = points.where((p) => p.metGoal).length;
    final avg = points.isEmpty
        ? 0
        : (points.map((p) => p.consumedMl).reduce((a, b) => a + b) /
                points.length)
            .round();

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Last 7 days',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (points.isNotEmpty)
                Text('Avg ${formatMl(avg)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
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
          else ...[
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points.map((p) => _bar(context, p)).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Consistency: met goal $met/${points.length} days',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, HydrationTrendPoint p) {
    final theme = Theme.of(context);
    final maxVal = points
        .map((e) => math.max(e.consumedMl, e.goalMl))
        .fold<int>(1, (a, b) => math.max(a, b));
    final h = (p.consumedMl / maxVal).clamp(0.05, 1.0) * 90;
    final color = p.metGoal ? kHydrationAccent : const Color(0xFF9CC7E8);
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: h,
            decoration: BoxDecoration(
              color: color,
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

/// Current + best hydration streak.
class HydrationStreakCard extends StatelessWidget {
  final int currentStreak;
  final int bestStreak;
  const HydrationStreakCard({
    super.key,
    required this.currentStreak,
    required this.bestStreak,
  });

  String get _milestone {
    if (currentStreak >= 30) return 'Hydration Champion · 30-day streak!';
    if (currentStreak >= 7) return 'Hydration Hero · 7-day streak!';
    if (currentStreak >= 3) return 'Nice — $currentStreak days in a row!';
    return 'Meet your goal today to start a streak.';
  }

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
              color: kHydrationAccent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('💧', style: TextStyle(fontSize: 26))),
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
                    bestStreak > 0
                        ? '$_milestone  ·  Best: $bestStreak'
                        : _milestone,
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
