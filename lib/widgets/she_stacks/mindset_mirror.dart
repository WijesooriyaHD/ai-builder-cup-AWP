import 'package:flutter/material.dart';

class MindsetMirrorModal extends StatefulWidget {
  final Function(int) onComplete;
  const MindsetMirrorModal({super.key, required this.onComplete});

  @override
  State<MindsetMirrorModal> createState() => _MindsetMirrorModalState();
}

class _MindsetMirrorModalState extends State<MindsetMirrorModal> {
  final List<Map<String, dynamic>> _prompts = [
    {
      "trigger": "Shopping online late at night when bored.",
      "mindset": "Scarcity of Time / Dopamine seeking.",
      "shift": "Abundance of Purpose. Replace the scroll with a 5-min ritual."
    },
    {
      "trigger": "Checking your bank balance makes you anxious.",
      "mindset": "Scarcity of Safety.",
      "shift": "Abundance of Awareness. Numbers are just data, not your worth."
    },
    {
      "trigger": "Feeling guilty after a 'treat yourself' purchase.",
      "mindset": "Scarcity of Permission.",
      "shift": "Abundance of Joy. If it's in the 'Wants' flow, it's 100% guilt-free."
    },
    {
      "trigger": "Thinking 'I'll start saving once I make more money.'",
      "mindset": "Scarcity of Present Power.",
      "shift": "Abundance of Consistency. Time is more powerful than the amount. Start with \$5."
    },
    {
      "trigger": "Comparing your lifestyle to a friend's social media.",
      "mindset": "Scarcity of Worth.",
      "shift": "Abundance of Path. Your financial journey is personal, not a performance."
    },
    {
      "trigger": "Hoarding money and refusing to spend on basic health/rest.",
      "mindset": "Scarcity of Safety (Fear of Loss).",
      "shift": "Abundance of Maintenance. You are your most valuable asset. Investing in you is a win."
    },
    {
      "trigger": "Buying something 'on sale' that you didn't plan to buy.",
      "mindset": "Scarcity of Opportunity.",
      "shift": "Abundance of Choice. You save 100% by not buying it at all."
    }
  ];

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.indigoAccent;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121215) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 32),
            const Text("Mindset Mirror", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Reflecting on Money Psychology", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            
            _buildReflectionCard(isDark, primaryColor),
            
            const SizedBox(height: 32),
            if (_currentIndex < _prompts.length - 1)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () => setState(() => _currentIndex++),
                  child: const Text("NEXT REFLECTION", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () {
                    widget.onComplete(500);
                    Navigator.pop(context);
                  },
                  child: const Text("COMPLETE REFLECTION", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReflectionCard(bool isDark, Color primaryColor) {
    final p = _prompts[_currentIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("THE TRIGGER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Text(p['trigger'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        const Text("CURRENT PATTERN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.redAccent, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
          ),
          child: Text(p['mindset'], style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 32),
        const Text("MINDSET SHIFT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.greenAccent, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
          ),
          child: Text(p['shift'], style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
