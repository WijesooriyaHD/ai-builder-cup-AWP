import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'she_stacks_common.dart';

class InflationTripModal extends StatefulWidget {
  final Function(int) onComplete;
  const InflationTripModal({super.key, required this.onComplete});

  @override
  State<InflationTripModal> createState() => _InflationTripModalState();
}

class _InflationTripModalState extends State<InflationTripModal> {
  double _years = 10;
  double _inflationRate = 0.03;
  final double _initialValue = 1000;

  double get _futureValue {
    return _initialValue / math.pow(1 + _inflationRate, _years);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.redAccent;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1212) : Colors.white,
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
                const Text("Inflation Machine", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Inflation Power", "Inflation is the 'invisible tax'. It means your \$1 stays the same number, but buys FEWER things every year."),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("See your money's value disappear", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "\$${_futureValue.toInt()}",
                  style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: primaryColor),
                ).animate(key: ValueKey(_futureValue)).shake(),
                Text("is what \$1,000 today buys in ${_years.toInt()} years", 
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 32),
                SheStacksCommon.buildInsightBox(
                  context,
                  _getInflationInsight(),
                  Icons.trending_down_rounded,
                  primaryColor,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildSubBar("Today", 1000, 1000, Colors.grey),
                    const SizedBox(width: 48),
                    _buildSubBar("Future", _futureValue, 1000, primaryColor),
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
                  _buildSliderRow("Time Travel", "${_years.toInt()} Years", _years, 1, 50, (v) => setState(() => _years = v)),
                  const SizedBox(height: 16),
                  _buildSliderRow("Inflation Rate", "${(_inflationRate * 100).toStringAsFixed(1)}%", _inflationRate, 0.01, 0.15, (v) => setState(() => _inflationRate = v)),
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
                  widget.onComplete(300);
                  Navigator.pop(context);
                },
                child: const Text("I UNDERSTAND THE RISK", style: TextStyle(fontWeight: FontWeight.w900)),
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.redAccent)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.redAccent,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  Widget _buildSubBar(String label, double val, double max, Color color) {
    double height = (val / max) * 120;
    return Column(
      children: [
        Container(
          width: 50,
          height: height.clamp(10, 120),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
        ).animate(key: ValueKey(height)).scaleY(alignment: Alignment.bottomCenter),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getInflationInsight() {
    if (_inflationRate > 0.08) return "Hyper-inflation! In this scenario, basic goods like a loaf of bread could double in price every few years.";
    if (_years > 30) return "Over long periods, even 2% inflation halves your purchasing power. This is why investing in assets is vital.";
    if (_futureValue < 500) return "Your money lost half its value. To fight this, your investments must GROW faster than inflation!";
    return "Inflation is the 'invisible tax' on cash. It eats your savings while you sleep.";
  }
}
