import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/weight_data.dart';
import '../providers/app_state.dart';
import '../services/home_tool_cards_service.dart';
import '../widgets/add_to_home_wrapper.dart';

/// Body weight tracker: log measurements, view the trend over time on a chart,
/// see net change and BMI, switch units, and manage history.
///
/// Backed by [AppState.weightData] (persisted locally + Firestore).
class WeightTrackerScreen extends StatelessWidget {
  const WeightTrackerScreen({super.key});

  static const Color _accent = Color(0xFF5C9EAD);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final data = appState.weightData;
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFF3F8F9),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Body Weight'),
            centerTitle: true,
            actions: [
              // Unit toggle (kg / lb).
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _UnitToggle(
                  unit: data.unit,
                  onChanged: (u) =>
                      appState.updateWeightSettings(unit: u),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            onPressed: () => _showLogDialog(context, appState, data),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log weight'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              AddToHomeWrapper(
                toolCardId: HomeToolCard.bodyWeight,
                child: _buildSummary(context, data),
              ),
              const SizedBox(height: 20),
              _buildChartCard(context, data),
              const SizedBox(height: 20),
              _buildBmiCard(context, appState, data),
              const SizedBox(height: 20),
              _buildHistory(context, appState, data),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Summary: current weight + net change
  // ---------------------------------------------------------------------------
  Widget _buildSummary(BuildContext context, WeightData data) {
    final theme = Theme.of(context);
    final unit = data.unit;
    final current = data.currentInUnit;
    final change = data.totalChangeKg;

    String changeText;
    Color changeColor;
    IconData changeIcon;
    if (change == null) {
      changeText = 'Add a second entry to see your trend';
      changeColor = theme.colorScheme.onSurfaceVariant;
      changeIcon = Icons.trending_flat_rounded;
    } else {
      final inUnit = unit.fromKg(change.abs());
      final rounded = inUnit.toStringAsFixed(1);
      if (change > 0.05) {
        changeText = 'Up $rounded ${unit.label} overall';
        changeColor = const Color(0xFFEF7C4B);
        changeIcon = Icons.trending_up_rounded;
      } else if (change < -0.05) {
        changeText = 'Down $rounded ${unit.label} overall';
        changeColor = const Color(0xFF34A853);
        changeIcon = Icons.trending_down_rounded;
      } else {
        changeText = 'Holding steady';
        changeColor = theme.colorScheme.onSurfaceVariant;
        changeIcon = Icons.trending_flat_rounded;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent.withOpacity(0.18), _accent.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT WEIGHT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                current == null ? '—' : current.toStringAsFixed(1),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(changeIcon, size: 18, color: changeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  changeText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (data.hasData) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _miniStat(context, 'Lowest',
                    data.minKg == null ? '—' : unit.fromKg(data.minKg!).toStringAsFixed(1), unit.label),
                const SizedBox(width: 24),
                _miniStat(context, 'Highest',
                    data.maxKg == null ? '—' : unit.fromKg(data.maxKg!).toStringAsFixed(1), unit.label),
                const SizedBox(width: 24),
                _miniStat(context, 'Entries', '${data.entries.length}', ''),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, String unit) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text('$value${unit.isEmpty ? '' : ' $unit'}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Trend chart
  // ---------------------------------------------------------------------------
  Widget _buildChartCard(BuildContext context, WeightData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final entries = data.sortedEntries;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trend over time',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (entries.length < 2)
            SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant
                            .withOpacity(0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Log at least two entries to see your chart',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: CustomPaint(
                size: Size.infinite,
                painter: _WeightChartPainter(
                  entries: entries,
                  unit: data.unit,
                  lineColor: _accent,
                  gridColor: theme.colorScheme.onSurface.withOpacity(0.08),
                  labelColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BMI card
  // ---------------------------------------------------------------------------
  Widget _buildBmiCard(BuildContext context, AppState appState, WeightData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bmi = data.bmi;
    final category = data.bmiCategory;
    final color = _bmiColor(category);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                bmi == null ? '—' : bmi.toStringAsFixed(1),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Body Mass Index',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  category.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: bmi == null
                        ? theme.colorScheme.onSurfaceVariant
                        : color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showHeightDialog(context, appState, data),
            child: Text(data.heightCm == null ? 'Add height' : 'Edit'),
          ),
        ],
      ),
    );
  }

  Color _bmiColor(BmiCategory c) {
    switch (c) {
      case BmiCategory.underweight:
        return const Color(0xFF4A90D9);
      case BmiCategory.healthy:
        return const Color(0xFF34A853);
      case BmiCategory.overweight:
        return const Color(0xFFF0A020);
      case BmiCategory.obese:
        return const Color(0xFFE9506E);
      case BmiCategory.unknown:
        return Colors.grey;
    }
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------
  Widget _buildHistory(BuildContext context, AppState appState, WeightData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final entries = data.sortedEntries.reversed.toList(); // newest first
    final unit = data.unit;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No entries yet. Tap "Log weight" to add your first.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...List.generate(entries.length, (i) {
              final e = entries[i];
              // Difference vs the previous (older) entry.
              final older = i < entries.length - 1 ? entries[i + 1] : null;
              final diffKg = older == null ? null : e.weightKg - older.weightKg;
              return _historyRow(context, appState, e, diffKg, unit);
            }),
        ],
      ),
    );
  }

  Widget _historyRow(BuildContext context, AppState appState, WeightEntry e,
      double? diffKg, WeightUnit unit) {
    final theme = Theme.of(context);
    String? diffText;
    Color diffColor = theme.colorScheme.onSurfaceVariant;
    if (diffKg != null && diffKg.abs() > 0.05) {
      final v = unit.fromKg(diffKg.abs()).toStringAsFixed(1);
      diffText = diffKg > 0 ? '+$v' : '-$v';
      diffColor =
          diffKg > 0 ? const Color(0xFFEF7C4B) : const Color(0xFF34A853);
    }

    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE9506E).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: Color(0xFFE9506E)),
      ),
      onDismissed: (_) => appState.removeWeightEntry(e.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.monitor_weight_rounded,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatDate(e.date),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (e.note != null && e.note!.isNotEmpty)
                    Text(e.note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (diffText != null) ...[
              Text(diffText,
                  style: TextStyle(
                      color: diffColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(width: 10),
            ],
            Text(
              '${unit.fromKg(e.weightKg).toStringAsFixed(1)} ${unit.label}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------
  void _showLogDialog(BuildContext context, AppState appState, WeightData data) {
    final controller = TextEditingController(
      text: data.currentInUnit?.toStringAsFixed(1) ?? '',
    );
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Log weight'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixText: data.unit.label,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 365 * 5)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setLocalState(() => selectedDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(_formatDate(selectedDate)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final entered = double.tryParse(controller.text.trim());
                  if (entered == null || entered <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Enter a valid weight')),
                    );
                    return;
                  }
                  final kg = data.unit.toKg(entered);
                  appState.logWeight(kg, date: selectedDate);
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showHeightDialog(
      BuildContext context, AppState appState, WeightData data) {
    final controller = TextEditingController(
      text: data.heightCm?.toStringAsFixed(0) ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Your height'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Height',
              suffixText: 'cm',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final h = double.tryParse(controller.text.trim());
                if (h != null && h > 50 && h < 260) {
                  appState.updateWeightSettings(heightCm: h);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Segmented kg / lb toggle used in the app bar.
class _UnitToggle extends StatelessWidget {
  final WeightUnit unit;
  final ValueChanged<WeightUnit> onChanged;

  const _UnitToggle({required this.unit, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget seg(WeightUnit u) {
      final selected = unit == u;
      return GestureDetector(
        onTap: () => onChanged(u),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? WeightTrackerScreen._accent
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            u.label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: selected
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(WeightUnit.kg), seg(WeightUnit.lb)],
      ),
    );
  }
}

/// Paints a simple line chart of weight entries over time.
class _WeightChartPainter extends CustomPainter {
  final List<WeightEntry> entries; // sorted oldest → newest
  final WeightUnit unit;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _WeightChartPainter({
    required this.entries,
    required this.unit,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;

    const leftPad = 36.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    final values = entries.map((e) => unit.fromKg(e.weightKg)).toList();
    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if ((maxV - minV).abs() < 0.5) {
      minV -= 1;
      maxV += 1;
    } else {
      final pad = (maxV - minV) * 0.15;
      minV -= pad;
      maxV += pad;
    }
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    double xFor(int i) =>
        leftPad + (entries.length == 1 ? 0 : (chartW * i / (entries.length - 1)));
    double yFor(double v) => topPad + chartH * (1 - (v - minV) / range);

    // Horizontal gridlines + y labels (min, mid, max).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 2; i++) {
      final v = minV + range * (i / 2);
      final y = yFor(v);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      tp.text = TextSpan(
        text: v.toStringAsFixed(0),
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // Fill under the line.
    final fillPath = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < values.length; i++) {
      fillPath.lineTo(xFor(i), yFor(values[i]));
    }
    fillPath.lineTo(xFor(values.length - 1), topPad + chartH);
    fillPath.lineTo(xFor(0), topPad + chartH);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()..color = lineColor.withOpacity(0.12),
    );

    // The line.
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xFor(i), yFor(values[i]));
    }
    canvas.drawPath(path, linePaint);

    // Data points.
    final dotPaint = Paint()..color = lineColor;
    final dotInner = Paint()..color = Colors.white;
    for (var i = 0; i < values.length; i++) {
      final o = Offset(xFor(i), yFor(values[i]));
      canvas.drawCircle(o, 4, dotPaint);
      canvas.drawCircle(o, 2, dotInner);
    }

    // X labels: first and last date.
    void drawXLabel(int i, TextAlign align) {
      final d = entries[i].date;
      tp.text = TextSpan(
        text: '${d.month}/${d.day}',
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      tp.layout();
      var x = xFor(i);
      if (align == TextAlign.right) x -= tp.width;
      if (align == TextAlign.center) x -= tp.width / 2;
      x = x.clamp(leftPad, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }

    drawXLabel(0, TextAlign.left);
    drawXLabel(entries.length - 1, TextAlign.right);
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.entries != entries || old.unit != unit;
}
