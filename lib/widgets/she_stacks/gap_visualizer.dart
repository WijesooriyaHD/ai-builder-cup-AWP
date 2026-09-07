import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'she_stacks_common.dart';

class GapVisualizerModal extends StatefulWidget {
  final Function(int) onComplete;
  const GapVisualizerModal({super.key, required this.onComplete});

  @override
  State<GapVisualizerModal> createState() => _GapVisualizerModalState();
}

class _GapVisualizerModalState extends State<GapVisualizerModal> {
  double _salary = 80000;
  double _gapMonths = 12;
  double _yearsToRetire = 25;
  final double _growthRate = 0.07;

  double get _directLoss => (_salary / 12) * _gapMonths;
  double get _opportunityCost {
    return _directLoss * math.pow(1 + _growthRate, _yearsToRetire);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.amber;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1812) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Gap Visualizer", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Opportunity Cost", "A career gap isn't just lost salary. It's the loss of compounding growth. Planning for this allows you to stay ahead of the wealth gap."),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("The true cost of a break", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SheStacksCommon.buildInsightBox(context, _getGapInsight(), Icons.warning_amber_rounded, primaryColor),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat("Direct Loss", "\$${(_directLoss / 1000).toInt()}k", Colors.grey),
                _buildStat("Future Impact", "\$${(_opportunityCost / 1000).toInt()}k", primaryColor),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  _buildSlider("Salary", "\$${(_salary/1000).toInt()}k", _salary, 30000, 250000, (v) => setState(() => _salary = v)),
                  const SizedBox(height: 16),
                  _buildSlider("Gap Months", "${_gapMonths.toInt()}", _gapMonths, 1, 60, (v) => setState(() => _gapMonths = v)),
                  const SizedBox(height: 16),
                  _buildSlider("Years to Retire", "${_yearsToRetire.toInt()}", _yearsToRetire, 5, 40, (v) => setState(() => _yearsToRetire = v)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () {
                  widget.onComplete(450);
                  Navigator.pop(context);
                },
                child: const Text("I'LL BRIDGE THE GAP", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String val, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSlider(String label, String value, double current, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.amber)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.amber,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  String _getGapInsight() {
    double multiplier = _opportunityCost / _directLoss;
    return "Your gap's future impact is ${multiplier.toStringAsFixed(1)}x greater than the lost salary alone due to missing compound growth.";
  }
}
