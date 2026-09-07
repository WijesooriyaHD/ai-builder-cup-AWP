import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SafetyShieldModal extends StatefulWidget {
  final Function(int) onComplete;
  const SafetyShieldModal({super.key, required this.onComplete});

  @override
  State<SafetyShieldModal> createState() => _SafetyShieldModalState();
}

class _SafetyShieldModalState extends State<SafetyShieldModal> {
  int _step = 0;
  final List<Map<String, dynamic>> _scenarios = [
    {
      "title": "The Joint Account Request",
      "scenario": "A new partner asks to join bank accounts after 3 months. What's your move?",
      "options": [
        {"text": "Sure, it shows trust!", "points": -20, "feedback": "Risk Alert! 3 months is too early for total commingling. Protect your baseline."},
        {"text": "Keep them separate for now.", "points": 20, "feedback": "Wise. Financial boundaries are healthy. Start with a joint 'bills-only' account much later."},
      ]
    },
    {
      "title": "The Family 'Loan'",
      "scenario": "A relative asks for \$2,000 for a 'sure thing' investment. You have it, but it's your emergency fund.",
      "options": [
        {"text": "Lend it, they're family.", "points": -30, "feedback": "Danger! Never lend money you can't afford to lose. Especially from your safety net."},
        {"text": "Offer non-financial help.", "points": 30, "feedback": "Perfect. 'I can't lend money right now, but I can help you budget' is a strong boundary."},
      ]
    },
    {
      "title": "The Credit Co-Sign",
      "scenario": "A friend needs a co-signer for a car. They promise to pay every month.",
      "options": [
        {"text": "Co-sign to be a good friend.", "points": -40, "feedback": "Critical Error! Co-signing makes YOU 100% liable. If they miss a payment, your credit is trashed."},
        {"text": "Politely decline.", "points": 40, "feedback": "Guard your score! Your credit score is your financial reputation. Don't risk it for others."},
      ]
    }
  ];

  int _totalScore = 100;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.blueGrey;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121415) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 32),
            const Text("Safety Shield", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Financial Boundaries Lab", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            
            // Shield Health
            Column(
              children: [
                const Text("Shield Integrity", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_totalScore / 100).clamp(0.0, 1.0),
                  minHeight: 12,
                  color: _totalScore > 50 ? Colors.blue : Colors.red,
                  backgroundColor: Colors.grey.withOpacity(0.1),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            if (_step < _scenarios.length) _buildScenarioCard(isDark, primaryColor)
            else _buildCompletionCard(primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioCard(bool isDark, Color primaryColor) {
    final s = _scenarios[_step];
    return Column(
      children: [
        Text(s['title'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(s['scenario'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
        ),
        const SizedBox(height: 32),
        ...s['options'].map<Widget>((opt) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                foregroundColor: isDark ? Colors.white : Colors.black,
                side: BorderSide(color: primaryColor.withOpacity(0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => _handleChoice(opt),
              child: Text(opt['text'], style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        )).toList(),
      ],
    );
  }

  void _handleChoice(Map<String, dynamic> opt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPositive = (opt['points'] as int) > 0;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Guardian Insight",
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C24) : Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: isPositive ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPositive ? Icons.shield_rounded : Icons.warning_amber_rounded,
                      color: isPositive ? Colors.green : Colors.red,
                      size: 40,
                    ),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  Text(
                    isPositive ? "SHIELD FORTIFIED" : "SHIELD WEAKENED",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    opt['feedback'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(20),
                        backgroundColor: isPositive ? Colors.green : Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _totalScore += (opt['points'] as int);
                          _step++;
                        });
                      },
                      child: const Text("GOT IT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().scale(begin: const Offset(0.8, 0.8)).fadeIn(),
        );
      },
    );
  }

  Widget _buildCompletionCard(Color primaryColor) {
    return Column(
      children: [
        const Icon(Icons.verified_user_rounded, size: 80, color: Colors.blue),
        const SizedBox(height: 24),
        const Text("Shield Fortified!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Text("Your final Shield Integrity is $_totalScore%. Remember, saying 'No' to others is saying 'Yes' to your future.", 
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
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
              widget.onComplete(400);
              Navigator.pop(context);
            },
            child: const Text("FINISH SESSION", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }
}
