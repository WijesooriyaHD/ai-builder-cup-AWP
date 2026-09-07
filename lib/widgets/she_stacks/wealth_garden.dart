import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'she_stacks_common.dart';

class WealthGardenModal extends StatefulWidget {
  final Function(int) onComplete;
  const WealthGardenModal({super.key, required this.onComplete});

  @override
  State<WealthGardenModal> createState() => _WealthGardenModalState();
}

class _WealthGardenModalState extends State<WealthGardenModal> {
  double _monthly = 500;
  double _years = 10;
  final double _rate = 0.08; // 8% average return

  double get _totalReturn {
    double n = 12; // monthly
    double r = _rate;
    double t = _years;
    double pmt = _monthly;
    
    if (r == 0) return pmt * n * t;
    return pmt * ((math.pow(1 + r/n, n * t) - 1) / (r/n));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.cyan;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1512) : Colors.white,
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
                const Text("Wealth Garden", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Compound Interest", "Compound interest is the 8th wonder of the world. Your money makes money, and then THAT money makes money!"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("Visualize the power of time", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "\$${_totalReturn.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}",
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: primaryColor),
                ).animate(key: ValueKey(_totalReturn)).scale(),
                const Text("Estimated Wealth", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 32),
                SheStacksCommon.buildInsightBox(
                  context,
                  _getWealthInsight(),
                  Icons.lightbulb_outline_rounded,
                  primaryColor,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildGardenBar("Principal", (_monthly * 12 * _years), _totalReturn, Colors.grey),
                    const SizedBox(width: 24),
                    _buildGardenBar("Wealth", _totalReturn, _totalReturn, primaryColor),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  _buildSliderRow("Monthly Invest", "\$${_monthly.toInt()}", _monthly, 100, 5000, (v) => setState(() => _monthly = v)),
                  const SizedBox(height: 24),
                  _buildSliderRow("Time Horizon", "${_years.toInt()} Years", _years, 1, 40, (v) => setState(() => _years = v)),
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
                  widget.onComplete(500);
                  Navigator.pop(context);
                },
                child: const Text("HARVEST KNOWLEDGE", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, String value, double current, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.cyan)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.cyan,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  Widget _buildGardenBar(String label, double val, double max, Color color) {
    double height = (val / max) * 150;
    return Column(
      children: [
        Container(
          width: 60,
          height: height.clamp(20, 150),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10)],
          ),
        ).animate(key: ValueKey(height)).scaleY(alignment: Alignment.bottomCenter),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getWealthInsight() {
    if (_years < 10) return "Time is your biggest ally. See what happens if you double your years—compounding explodes!";
    if (_monthly < 500) return "Even an extra \$50/month could add tens of thousands to your harvest over time.";
    if (_totalReturn > 1000000) return "Millionaire status! This is the power of consistency and time.";
    return "The first person to name a number usually sets the range. Aim high, but back it up with data.";
  }
}
