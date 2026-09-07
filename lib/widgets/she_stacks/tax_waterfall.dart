import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'she_stacks_common.dart';

class TaxWaterfallModal extends StatefulWidget {
  final Function(int) onComplete;
  const TaxWaterfallModal({super.key, required this.onComplete});

  @override
  State<TaxWaterfallModal> createState() => _TaxWaterfallModalState();
}

class _TaxWaterfallModalState extends State<TaxWaterfallModal> {
  double _income = 75000;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.orange;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1512) : Colors.white,
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
                const Text("Tax Waterfall", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Tax Brackets", "Tax brackets are NOT all-or-nothing. Only the money in that specific bracket is taxed at that rate. Your income overflows into the next bucket!"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text("Visualize how your income is taxed", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SheStacksCommon.buildInsightBox(
              context,
              _getTaxInsight(),
              Icons.water_rounded,
              primaryColor,
            ),
            const SizedBox(height: 32),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTaxBucket("10%", _income > 11000 ? 11000 : _income, 11000, Colors.green),
                const SizedBox(height: 8),
                _buildTaxBucket("12%", _income > 44725 ? 33725 : (_income > 11000 ? _income - 11000 : 0), 33725, Colors.blue),
                const SizedBox(height: 8),
                _buildTaxBucket("22%", _income > 95375 ? 50650 : (_income > 44725 ? _income - 44725 : 0), 50650, Colors.orange),
                const SizedBox(height: 8),
                _buildTaxBucket("24%+", _income > 95375 ? _income - 95375 : 0, 100000, Colors.red),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Your Annual Income", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("\$${_income.toInt()}", style: TextStyle(fontWeight: FontWeight.w900, color: primaryColor)),
                    ],
                  ),
                  Slider(
                    value: _income,
                    min: 10000,
                    max: 200000,
                    activeColor: primaryColor,
                    onChanged: (v) => setState(() => _income = v),
                  ),
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
                  widget.onComplete(450);
                  Navigator.pop(context);
                },
                child: const Text("I MASTERED TAXES", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxBucket(String rate, double filled, double capacity, Color color) {
    double percent = (filled / capacity).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(width: 40, child: Text(rate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text("\$${filled.toInt()}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    ).animate().fadeIn().slideX();
  }

  String _getTaxInsight() {
    if (_income < 44725) return "You're in the 'Sweet Spot'. Most of your income is taxed at just 10-12%.";
    if (_income > 95375) return "Overflow alert! You've hit the 24% bracket. Every extra dollar is now taxed more heavily.";
    return "Only the money 'inside' the bucket is taxed at that rate. Your first \$11k is ALWAYS taxed at 10%, no matter what!";
  }
}
