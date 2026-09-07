import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'she_stacks_common.dart';

class FounderFinanceModal extends StatefulWidget {
  final Function(int) onComplete;
  const FounderFinanceModal({super.key, required this.onComplete});

  @override
  State<FounderFinanceModal> createState() => _FounderFinanceModalState();
}

class _FounderFinanceModalState extends State<FounderFinanceModal> {
  double _price = 50;
  double _cost = 15;
  double _units = 100;

  double get _profitPerUnit => _price - _cost;
  double get _totalProfit => _profitPerUnit * _units;
  double get _margin => _price > 0 ? (_profitPerUnit / _price) : 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.deepOrangeAccent;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15100F) : Colors.white,
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
                const Text("Founder Finance", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Unit Economics", "Profit isn't just Revenue - Expenses. It's about knowing if every single item you sell makes sense. If you lose \$1 on every unit, you can't make it up in volume!"),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SheStacksCommon.buildInsightBox(context, _getFounderInsight(), Icons.rocket_launch_rounded, primaryColor),
            const SizedBox(height: 32),
            
            // Stats Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat("Profit/Unit", "\$${_profitPerUnit.toInt()}", Colors.grey),
                _buildStat("Total Profit", "\$${_totalProfit.toInt()}", primaryColor),
                _buildStat("Margin", "${(_margin * 100).toInt()}%", Colors.cyan),
              ],
            ),
            
            const SizedBox(height: 32),
            // Burnout Meter
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Scaling Burnout Risk", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Text(_getBurnoutLabel(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _getBurnoutColor())),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_units / 1000).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                    color: _getBurnoutColor(),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                   _buildRow("Price per Unit", "\$${_price.toInt()}", _price, 1, 500, (v) => setState(() => _price = v)),
                   const SizedBox(height: 16),
                   _buildRow("Cost per Unit", "\$${_cost.toInt()}", _cost, 1, 300, (v) => setState(() => _cost = v)),
                   const SizedBox(height: 16),
                   _buildRow("Units Sold", "${_units.toInt()}", _units, 1, 1000, (v) => setState(() => _units = v)),
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
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () {
                  widget.onComplete(600);
                  Navigator.pop(context);
                },
                child: const Text("LAUNCH BLUEPRINT", style: TextStyle(fontWeight: FontWeight.w900)),
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
        Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRow(String label, String value, double current, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepOrangeAccent)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.deepOrangeAccent,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  String _getBurnoutLabel() {
    if (_units < 300) return "LOW";
    if (_units < 700) return "MODERATE";
    return "EXTREME";
  }

  Color _getBurnoutColor() {
    if (_units < 300) return Colors.green;
    if (_units < 700) return Colors.orange;
    return Colors.red;
  }

  String _getFounderInsight() {
    if (_profitPerUnit <= 0) return "Warning: You are losing money on every sale! Increase Price or Lower Costs immediately.";
    if (_margin < 0.2) return "Thin margins. One small mistake could wipe out your profits. Aim for 40%+ if possible.";
    if (_units > 800) return "Scaling fast! Ensure your systems can handle this many units without your constant manual work.";
    return "Solid foundations. Focus on increasing your 'Units Sold' while maintaining these margins.";
  }
}
