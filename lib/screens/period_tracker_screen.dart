import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/period_data.dart';
import '../providers/app_state.dart';
import '../services/home_tool_cards_service.dart';
import '../widgets/add_to_home_wrapper.dart';

/// A full-featured period tracker: cycle ring, next-period prediction, a
/// markable month calendar, cycle/period-length settings, and phase insights.
///
/// All data is read from and written to [AppState.periodData], which persists
/// locally and syncs to Firestore. Logged data feeds the AI daily plan via
/// [AppState.cyclePhaseContext].
class PeriodTrackerScreen extends StatefulWidget {
  const PeriodTrackerScreen({super.key});

  @override
  State<PeriodTrackerScreen> createState() => _PeriodTrackerScreenState();
}

class _PeriodTrackerScreenState extends State<PeriodTrackerScreen> {
  late DateTime _visibleMonth;

  static const Color _periodColor = Color(0xFFE9506E);
  static const Color _fertileColor = Color(0xFF00BCD4);
  static const Color _ovulationColor = Color(0xFF7E57C2);
  static const Color _predictedColor = Color(0xFFF3A5B5);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final data = appState.periodData;
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFFDF4F6),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Period Tracker'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              AddToHomeWrapper(
                toolCardId: HomeToolCard.periodTracker,
                child: _buildCycleRing(context, data),
              ),
              const SizedBox(height: 24),
              _buildPredictionRow(context, data),
              const SizedBox(height: 16),
              _buildPhaseInsight(context, data),
              const SizedBox(height: 24),
              _buildLogButton(context, appState, data),
              const SizedBox(height: 28),
              _buildCalendar(context, appState, data),
              const SizedBox(height: 16),
              _buildLegend(context),
              const SizedBox(height: 28),
              _buildSettings(context, appState, data),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Cycle ring
  // ---------------------------------------------------------------------------
  Widget _buildCycleRing(BuildContext context, PeriodData data) {
    final theme = Theme.of(context);
    final phase = data.currentPhase;
    final day = data.currentCycleDay;
    final len = data.effectiveCycleLength;
    final progress = (day != null) ? (day / len).clamp(0.0, 1.0) : 0.0;

    final String centerTop;
    final String centerBottom;
    if (!data.hasData) {
      centerTop = '—';
      centerBottom = 'No data yet';
    } else {
      centerTop = 'Day $day';
      centerBottom = 'of $len';
    }

    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: CustomPaint(
          painter: _CycleRingPainter(
            progress: progress,
            phaseColor: _phaseColor(phase),
            trackColor: theme.colorScheme.onSurface.withOpacity(0.08),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_phaseIcon(phase),
                    size: 32, color: _phaseColor(phase)),
                const SizedBox(height: 6),
                Text(
                  centerTop,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  centerBottom,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _phaseColor(phase).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${phase.label} phase',
                    style: TextStyle(
                      color: _phaseColor(phase),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Prediction summary (next period + ovulation)
  // ---------------------------------------------------------------------------
  Widget _buildPredictionRow(BuildContext context, PeriodData data) {
    final next = data.nextPeriodDate;
    final until = data.daysUntilNextPeriod;
    final ov = data.ovulationDate;

    String nextValue;
    String nextSub;
    if (next == null) {
      nextValue = '—';
      nextSub = 'Log a period';
    } else if (until != null && until >= 0) {
      nextValue = until == 0 ? 'Today' : 'in $until d';
      nextSub = _formatShort(next);
    } else {
      nextValue = '${-(until ?? 0)}d late';
      nextSub = _formatShort(next);
    }

    return Row(
      children: [
        Expanded(
          child: _statCard(
            context,
            icon: Icons.water_drop_rounded,
            color: _periodColor,
            label: 'Next period',
            value: nextValue,
            sub: nextSub,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            icon: Icons.spa_rounded,
            color: _ovulationColor,
            label: 'Ovulation',
            value: ov == null ? '—' : _formatShort(ov),
            sub: ov == null ? 'Log a period' : 'Est. fertile window',
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(sub,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Phase insight (wellness tip)
  // ---------------------------------------------------------------------------
  Widget _buildPhaseInsight(BuildContext context, PeriodData data) {
    final theme = Theme.of(context);
    final phase = data.currentPhase;
    final color = _phaseColor(phase);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_phaseIcon(phase), size: 26, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.hasData
                      ? '${phase.label} phase tips'
                      : 'Start tracking',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  phase.wellnessTip,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                if (data.hasData) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your daily plan adapts to this phase.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Log button
  // ---------------------------------------------------------------------------
  Widget _buildLogButton(
      BuildContext context, AppState appState, PeriodData data) {
    final today = _dateOnly(DateTime.now());
    final loggedToday = data.isLoggedPeriodDay(today);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: loggedToday ? Colors.grey.shade400 : _periodColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        icon: Icon(loggedToday
            ? Icons.check_circle_rounded
            : Icons.water_drop_rounded),
        label: Text(
          loggedToday ? 'Period logged for today' : 'Log period today',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          if (loggedToday) {
            appState.removePeriodStart(today);
          } else {
            appState.logPeriodStart(today);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Month calendar
  // ---------------------------------------------------------------------------
  Widget _buildCalendar(
      BuildContext context, AppState appState, PeriodData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // Monday-first offset (weekday: Mon=1..Sun=7).
    final leadingBlanks = firstOfMonth.weekday - 1;
    final today = _dateOnly(DateTime.now());

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, d);
      cells.add(_dayCell(context, appState, data, date, today));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // Month header with nav.
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                }),
              ),
              Expanded(
                child: Text(
                  _formatMonth(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Weekday labels.
          Row(
            children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, AppState appState, PeriodData data,
      DateTime date, DateTime today) {
    final theme = Theme.of(context);
    final isToday = date == today;
    final isFuture = date.isAfter(today);

    final isLogged = data.isLoggedPeriodDay(date);
    final isPredicted = !isLogged && data.isPredictedPeriodDay(date);
    final isOvulation =
        data.ovulationDate != null && date == data.ovulationDate;
    final isFertile = !isOvulation && data.isFertileDay(date);

    Color? bg;
    Color fg = theme.colorScheme.onSurface;
    bool outlined = false;

    if (isLogged) {
      bg = _periodColor;
      fg = Colors.white;
    } else if (isPredicted) {
      bg = _predictedColor.withOpacity(0.35);
      outlined = true;
    } else if (isOvulation) {
      bg = _ovulationColor;
      fg = Colors.white;
    } else if (isFertile) {
      bg = _fertileColor.withOpacity(0.18);
    }

    return GestureDetector(
      // Only past/today can be logged as an actual period day.
      onTap: isFuture
          ? null
          : () {
              if (isLogged) {
                appState.removePeriodStart(date);
              } else {
                appState.logPeriodStart(date);
              }
            },
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: isToday
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : (isPredicted && outlined
                  ? Border.all(
                      color: _predictedColor,
                      width: 1.2,
                      style: BorderStyle.solid)
                  : null),
        ),
        child: Center(
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isFuture ? fg.withOpacity(0.35) : fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    Widget dot(Color c, String label, {bool outline = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: outline ? c.withOpacity(0.35) : c,
              shape: BoxShape.circle,
              border: outline ? Border.all(color: c, width: 1.2) : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        dot(_periodColor, 'Period'),
        dot(_predictedColor, 'Predicted', outline: true),
        dot(_fertileColor.withOpacity(0.6), 'Fertile'),
        dot(_ovulationColor, 'Ovulation'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Settings (cycle & period length)
  // ---------------------------------------------------------------------------
  Widget _buildSettings(
      BuildContext context, AppState appState, PeriodData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cycle settings',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Used to predict your next period and fertile window.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _stepperRow(
            context,
            label: 'Cycle length',
            value: data.cycleLength,
            unit: 'days',
            min: 20,
            max: 45,
            onChanged: (v) =>
                appState.updatePeriodSettings(cycleLength: v),
          ),
          const Divider(height: 24),
          _stepperRow(
            context,
            label: 'Period length',
            value: data.periodLength,
            unit: 'days',
            min: 2,
            max: 10,
            onChanged: (v) =>
                appState.updatePeriodSettings(periodLength: v),
          ),
          if (data.loggedPeriodStarts.length >= 2) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.insights_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'From your logs, your average cycle is about '
                      '${data.effectiveCycleLength} days.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepperRow(
    BuildContext context, {
    required String label,
    required int value,
    required String unit,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
        _roundIconButton(
          context,
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        _roundIconButton(
          context,
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Widget _roundIconButton(BuildContext context,
      {required IconData icon, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.colorScheme.onSurface.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 20,
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.3)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  /// Material icon per cycle phase. Uses a woman icon when the phase is
  /// unknown (no period logged yet).
  IconData _phaseIcon(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return Icons.water_drop_rounded;
      case CyclePhase.follicular:
        return Icons.eco_rounded;
      case CyclePhase.ovulation:
        return Icons.local_florist_rounded;
      case CyclePhase.luteal:
        return Icons.nightlight_round;
      case CyclePhase.unknown:
        return Icons.woman_rounded;
    }
  }

  Color _phaseColor(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return _periodColor;
      case CyclePhase.follicular:
        return const Color(0xFF66BB6A);
      case CyclePhase.ovulation:
        return _ovulationColor;
      case CyclePhase.luteal:
        return const Color(0xFF5C6BC0);
      case CyclePhase.unknown:
        return Colors.grey;
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatMonth(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

  String _formatShort(DateTime d) =>
      '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}';
}

/// Paints the circular cycle-progress ring behind the ring's center content.
class _CycleRingPainter extends CustomPainter {
  final double progress;
  final Color phaseColor;
  final Color trackColor;

  _CycleRingPainter({
    required this.progress,
    required this.phaseColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    const stroke = 14.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: [phaseColor.withOpacity(0.5), phaseColor],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CycleRingPainter old) =>
      old.progress != progress ||
      old.phaseColor != phaseColor ||
      old.trackColor != trackColor;
}
