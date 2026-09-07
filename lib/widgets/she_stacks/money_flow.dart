import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'she_stacks_common.dart';

class MoneyFlowModal extends StatefulWidget {
  final Function(int) onComplete;
  const MoneyFlowModal({super.key, required this.onComplete});

  @override
  State<MoneyFlowModal> createState() => _MoneyFlowModalState();
}

class _MoneyFlowModalState extends State<MoneyFlowModal> {
  double _income = 5000;
  double _needs = 0.5;
  double _wants = 0.3;
  double _future = 0.2;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.greenAccent;

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
                const Text("Money Flow", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: primaryColor),
                  onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Values-Based Budgeting", "It's not about restriction; it's about alignment. 50/30/20 is a rule of thumb to ensure your 'Needs' are covered while honoring your 'Future Self'."),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SheStacksCommon.buildInsightBox(context, _getMoneyFlowInsight(), Icons.auto_graph_rounded, primaryColor),
            const SizedBox(height: 32),
            
            // Allocation Bars
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildFlowBar("Needs", _income * _needs, Colors.blueAccent),
                _buildFlowBar("Wants", _income * _wants, Colors.orangeAccent),
                _buildFlowBar("Future", _income * _future, Colors.greenAccent),
              ],
            ),
            
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.green.shade50,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                   _buildRow("Monthly Income", "\$${_income.toInt()}", _income, 1000, 20000, (v) => setState(() => _income = v)),
                   const SizedBox(height: 16),
                   _buildAllocationSliders(),
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
                  widget.onComplete(300);
                  Navigator.pop(context);
                },
                child: const Text("LEVEL UP MY FLOW", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowBar(String label, double amount, Color color) {
    return Column(
      children: [
        Text("\$${amount.toInt()}", style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: (amount / _income) * 150 + 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
        ).animate(key: ValueKey(amount)).scaleY(alignment: Alignment.bottomCenter),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.greenAccent)),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          activeColor: Colors.greenAccent,
          onChanged: (v) {
            onChanged(v);
            HapticFeedback.selectionClick();
          },
        ),
      ],
    );
  }

  Widget _buildAllocationSliders() {
    return Column(
      children: [
        const Text("Adjust Percentages", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        _buildPercentSlider("Needs", _needs, (v) {
           setState(() {
             _needs = v;
             _balance(needs: true);
           });
        }),
        _buildPercentSlider("Wants", _wants, (v) {
           setState(() {
             _wants = v;
             _balance(wants: true);
           });
        }),
        _buildPercentSlider("Future Self", _future, (v) {
           setState(() {
             _future = v;
             _balance(future: true);
           });
        }),
      ],
    );
  }

  void _balance({bool needs = false, bool wants = false, bool future = false}) {
     // Simple normalization to keep sum at 1.0
     double total = _needs + _wants + _future;
     if (needs) {
       double remaining = 1.0 - _needs;
       double oldSubTotal = _wants + _future;
       if (oldSubTotal > 0) {
         _wants = (_wants / oldSubTotal) * remaining;
         _future = (_future / oldSubTotal) * remaining;
       } else {
         _wants = remaining / 2;
         _future = remaining / 2;
       }
     } else if (wants) {
       double remaining = 1.0 - _wants;
       double oldSubTotal = _needs + _future;
       if (oldSubTotal > 0) {
         _needs = (_needs / oldSubTotal) * remaining;
         _future = (_future / oldSubTotal) * remaining;
       } else {
         _needs = remaining / 2;
         _future = remaining / 2;
       }
     } else {
       double remaining = 1.0 - _future;
       double oldSubTotal = _needs + _wants;
       if (oldSubTotal > 0) {
         _needs = (_needs / oldSubTotal) * remaining;
         _wants = (_wants / oldSubTotal) * remaining;
       } else {
         _needs = remaining / 2;
         _wants = remaining / 2;
       }
     }
  }

  Widget _buildPercentSlider(String label, double val, Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: val,
            min: 0,
            max: 0.9,
            activeColor: Colors.greenAccent,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text("${(val * 100).toInt()}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
      ],
    );
  }

  String _getMoneyFlowInsight() {
    if (_needs > 0.6) return "Needs are heavy! Look for 'fixed-cost fixed-fees' like unused subscriptions to free up room.";
    if (_future < 0.15) return "Your Future Self is feeling a bit neglected. Try to nudge this toward 20% for long-term freedom.";
    if (_wants > 0.4) return "Life is for living! But ensure these 'Wants' aren't stealing from your 'Future' security.";
    return "Balanced Flow! You're covering today while respecting tomorrow.";
  }
}
