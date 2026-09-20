import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Frequently Asked Questions", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          FaqCard(
            question: "What is AI Magic? ✨",
            answer: "AI Magic uses advanced technology to help you improve your journaling. You can 'Refine' your text for better flow, 'Summarize' long notes into bullet points, or 'Reflect' to get thought-provoking follow-up questions about what you wrote.",
          ),
          FaqCard(
            question: "How do I use Dreams? 🚀",
            answer: "Dreams are your long-term goals. You can add a Dream from the Dreams tab, break it down into actionable steps, and track your progress as you complete them. AI Wellness Pal Premium users have unlimited dreams!",
          ),
          FaqCard(
            question: "What are Widgets on the Homepage? 🏠",
            answer: "Your Homepage is a dynamic command center. It features 'Widgets' for your Streak, Points, and Journal entries. You can customize these for a quick glance at your daily progress.",
          ),
          FaqCard(
            question: "How do I pin a Todo to Home? 📌",
            answer: "Long-press any journal entry in your Journal screen and select 'Add to Home'. This will pin the entry's checklist as a widget on your Homepage. You can then long-press that widget on Home to 'Pin to Top' for maximum visibility!",
          ),
          FaqCard(
            question: "What is the Travel feature? ✈️",
            answer: "The Travel tab lets you record and explore your global journeys. You can see a heat map of places you've visited, add travel memories, and collect digital stamps for your accomplishments.",
          ),
          FaqCard(
            question: "How do I earn Stamps and Passports? 🎫",
            answer: "Stamps are digital rewards for visiting new countries and reaching milestones. Your Passport is where your unique AI Wellness Pal ID and travel stats are stored, showcasing your progress as a global citizen.",
          ),
          FaqCard(
            question: "What are Achievements? 🏆",
            answer: "Achievements are earned by consistent use of the app—like maintaining a streak, finishing dreams, or journaling daily. Tap the Achievements card on Home to see your full collection of unlocked badges.",
          ),
          FaqCard(
            question: "What is Winter Mode? ❄️",
            answer: "Winter Mode is a beautiful seasonal effect that adds slow-falling snow to every screen of the app. You can toggle it on or off in the Appearance section of your Settings.",
          ),
          FaqCard(
            question: "Can I save AI insights? 💡",
            answer: "Yes! When you discuss a journal entry with the AI, you can tap the save icon on any AI response to store it directly in your 'Saved' insights tab for future reference.",
          ),
          FaqCard(
            question: "How does the Mood Filter work? 😊",
            answer: "Tap the search icon in your Journal to reveal the Mood Filter bar. Selecting an emoji will instantly show all entries where you tagged that specific mood, helping you find patterns in how you feel.",
          ),
          FaqCard(
            question: "Can I listen to Blog Posts? 🎧",
            answer: "Yes! Every blog post now features a 'Narrate' button. Tap it to hear a smooth, AI-generated reading of the content, perfect for when you're on the go.",
          ),
          FaqCard(
            question: "How do I share my progress? 📸",
            answer: "When you achieve a Dream or unlock an Achievement, look for the 'Share' button. AI Wellness Pal will generate a beautiful branded screenshot (complete with confetti and spotlights!) that you can share directly to your favorite social apps.",
          ),
          FaqCard(
            question: "What is Daily Motivation? 🧘",
            answer: "Every day, AI Wellness Pal features a new inspiring quote specifically curated for women's growth. You can find it on your home screen to start your morning with a positive mindset.",
          ),
          FaqCard(
            question: "Can I link my Instagram? 🤳",
            answer: "Absolutely. In your Profile settings, you can add your Instagram handle. This lets your fellow AI Wellness Pal community members connect with you on social media through your public profile.",
          ),
          FaqCard(
            question: "Why does the Journal look different? 🌸",
            answer: "We've updated the Journal with a 'Premium' aesthetic. It uses softer colors, subtle gradients, and refined typography to create a more gentle, focused environment for your personal reflections.",
          ),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}

class FaqCard extends StatefulWidget {
  final String question;
  final String answer;

  const FaqCard({
    super.key,
    required this.question,
    required this.answer,
  });

  @override
  State<FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<FaqCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isExpanded 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : (isDark ? Colors.white10 : Colors.grey.shade100),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _isExpanded ? Theme.of(context).colorScheme.primary : Colors.grey,
                    ),
                  ),
                ],
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 16),
                Text(
                  widget.answer,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
