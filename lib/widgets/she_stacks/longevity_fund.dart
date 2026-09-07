import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'she_stacks_common.dart';

class LongevityFundModal extends StatefulWidget {
  final Function(int) onComplete;
  const LongevityFundModal({super.key, required this.onComplete});

  @override
  State<LongevityFundModal> createState() => _LongevityFundModalState();
}

class _LongevityFundModalState extends State<LongevityFundModal> {
  double _currentAge = 30;
  double _retireAge = 65;
  double _spendMonthly = 5000;
  double _lifeExpectancy = 100;

  double get _yearsInRetirement => _lifeExpectancy - _retireAge;
  double get _totalRequired => _spendMonthly * 12 * _yearsInRetirement;
  double get _totalRequiredStandard => _spendMonthly * 12 * (85 - _retireAge);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.pinkAccent;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1215) : Colors.white,
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
                const Text("Longevity Fund", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Life Expectancy", "On average, women live longer than men. Planning for age 85 might leave you short if you live to 100. This is the 'Longevity Risk'."),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("Planning for the 100-year life", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            SheStacksCommon.buildInsightBox(
              context,
              _getLongevityInsight(),
              Icons.auto_awesome_rounded,
              primaryColor,
            ),

            const SizedBox(height: 32),
            Column(
              children: [
                Text(
                  "\$${(_totalRequired / 1000000).toStringAsFixed(1)}M",
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: primaryColor),
                ).animate(key: ValueKey(_totalRequired)).scale(),
                const Text("Total Retirement Fund Needed", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
            
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildBar("Age 85", _totalRequiredStandard, _totalRequired, Colors.grey),
                const SizedBox(width: 48),
                _buildBar("Age 100", _totalRequired, _totalRequired, primaryColor),
              ],
            ),

            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.pink.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  _buildRow("Current Age", "${_currentAge.toInt()}", _currentAge, 18, 60, (v) => setState(() => _currentAge = v)),
                  const SizedBox(height: 16),
                  _buildRow("Retire At", "${_retireAge.toInt()}", _retireAge, 50, 75, (v) => setState(() => _retireAge = v)),
                  const SizedBox(height: 16),
                  _buildRow("Monthly Spend", "\$${_spendMonthly.toInt()}", _spendMonthly, 2000, 20000, (v) => setState(() => _spendMonthly = v)),
                  const SizedBox(height: 16),
                  _buildRow("Plan Until Age", "${_lifeExpectancy.toInt()}", _lifeExpectancy, 85, 105, (v) => setState(() => _lifeExpectancy = v)),
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
                child: const Text("I'LL PLAN AHEAD", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String label, double val, double max, Color color) {
    double height = (val / max) * 120;
    return Column(
      children: [
        Container(
          width: 60,
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

  Widget _buildRow(String label, String value, double current, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.pinkAccent)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.pinkAccent,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  String _getLongevityInsight() {
    double diff = _totalRequired - _totalRequiredStandard;
    if (_lifeExpectancy > 95) {
      return "Planning for 100 requires \$${(diff/1000).toInt()}k MORE than a standard retirement. Start early to let compound interest cover the gap!";
    }
    if (_retireAge < 60) {
      return "Early retirement means you need to fund ${_yearsInRetirement.toInt()} years. Your 'STASH' needs to be significantly larger.";
    }
    return "Most retirement calculators stop at 85. By planning for 100, you're ensuring your money never runs out.";
  }
}
