import 'package:flutter/material.dart';

/// Help centre for AI Wellness Pal.
///
/// Grouped by area rather than presented as one long list, so someone looking
/// for a specific answer can find it without reading everything. The Settings
/// and Home Screen Widget sections deliberately carry step-by-step
/// instructions — they are the questions people actually get stuck on, and the
/// widget setup in particular has no other home now that it has been taken out
/// of Settings.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Help & FAQ",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          // ── Getting started ────────────────────────────────────────────
          _FaqSection("Getting started"),
          FaqCard(
            question: "What does AI Wellness Pal actually do? 🌿",
            answer:
                "It answers one question each day: what should I do for my "
                "wellbeing right now?\n\nYou do a quick check-in, and the app "
                "builds Today's Plan — two to four small, doable actions "
                "shaped around your energy, mood, body recovery and how much "
                "time you actually have. Everything else in the app supports "
                "that: tools to track the day, a pal to talk it through, and "
                "progress you can see building up over time.",
          ),
          FaqCard(
            question: "What is the daily check-in? ✅",
            answer:
                "Three quick steps: your energy (1–5), your mood, and how your "
                "body feels plus the time you have today.\n\nYou can skip any "
                "step — the plan just uses what you gave it. Once you've "
                "checked in, Today's Plan is generated within a few seconds.\n\n"
                "Tapping the mic and asking your pal to \"start my check-in\" "
                "works too, if you'd rather talk than tap.",
          ),
          FaqCard(
            question: "What are the five tabs? 🧭",
            answer:
                "Home — Today's Plan, your check-in and your wellness cards.\n\n"
                "Intentions — the longer-term things you're working toward.\n\n"
                "Habit Builder — daily habits and multi-day Challenges.\n\n"
                "Reflection — your journal, AI reflections and saved "
                "conversations.\n\nSettings — everything you can tune.",
          ),
          FaqCard(
            question: "Is AI Wellness Pal medical advice? 🩺",
            answer:
                "No. AI Wellness Pal offers general wellness information and "
                "encouragement — it isn't a medical device and doesn't "
                "diagnose, treat or replace a doctor, therapist or other "
                "qualified professional. AI responses, calorie estimates and "
                "cycle predictions can be wrong, so talk to a healthcare "
                "provider about any health concern.\n\nIf you're in crisis "
                "or thinking about harming yourself, contact your local "
                "emergency number right away. In the US, call or text 988. "
                "In the UK, call 111 or Samaritans on 116 123. Elsewhere, "
                "find a helpline at findahelpline.com.",
          ),

          // ── Daily use ──────────────────────────────────────────────────
          _FaqSection("Your day"),
          FaqCard(
            question: "How does Today's Plan work? 📋",
            answer:
                "Each action has a checkbox. Tick them off as you go — when "
                "you finish them all you'll get a small celebration.\n\nIf "
                "your day changes, you don't have to live with the plan you "
                "got. Ask your pal to update it (\"I'm more tired than I "
                "thought\") and it'll rebuild around how you actually feel.",
          ),
          FaqCard(
            question: "What are Wellness Intentions? 🎯",
            answer:
                "Longer-term directions rather than daily tasks — \"sleep "
                "better\", \"move more\", \"feel calmer\".\n\nYour daily plans "
                "are shaped by them, and each one tracks its own progress. "
                "Premium members can have an intention broken into gentle "
                "daily steps automatically.",
          ),
          FaqCard(
            question: "Habits and Challenges — what's the difference? 🔥",
            answer:
                "A habit is something you're building into your routine, with "
                "its own schedule and optional reminder.\n\nA Challenge is a "
                "multi-day commitment with an end point — hydration, walking, "
                "meditation, cutting back on sugar, a sleep routine. You join one, log "
                "each day, and finishing it unlocks an achievement.",
          ),
          FaqCard(
            question: "What is the Wellness Studio? 🧘",
            answer:
                "Short guided activities for right now, usually 3–12 minutes, "
                "in six categories: Breathing Exercises, Recovery Challenges, "
                "Mindfulness Sessions, Wellness Quizzes, Pilates Knowledge "
                "Cards and Stress Recovery.\n\nThings like Box Breathing, the "
                "4-7-8 Calm Breath, a 5-Minute Stretch Reset or a Body Scan. "
                "Open it from the \"More\" tab. At least three activities per "
                "category are free.",
          ),
          FaqCard(
            question: "What are Wellness Reads? 📖",
            answer:
                "Short articles, roughly 3–5 minutes each, in the \"More\" "
                "tab. Filter by Mindfulness, Sleep, Movement, Nutrition, "
                "Mental Health, Stress Relief, Pilates or Yoga.\n\nMany have "
                "audio, so you can listen while you do something else — the "
                "player keeps going as you move around the app.",
          ),

          // ── Toolkit ────────────────────────────────────────────────────
          _FaqSection("The Life Toolkit"),
          FaqCard(
            question: "What's in the toolkit? 🧰",
            answer:
                "Nine tools, reached from the \"More\" tab:\n\n"
                "• Nutrition Coach — log meals by photo, description or "
                "barcode\n"
                "• Meal Planner — a week of meals built around your goals\n"
                "• Calorie Budget — intake and exercise together\n"
                "• Hydration Coach — water tracking with a daily target\n"
                "• Sleep Coach — reads Apple Health if you allow it\n"
                "• Meditation Pal — breathing and guided sessions\n"
                "• Period Tracker — cycle logging and predictions\n"
                "• Body Weight — weight and BMI over time\n"
                "• Mindful Travel — wellness while you're away",
          ),
          FaqCard(
            question: "Can I put tool summaries on my Home screen? 🏠",
            answer:
                "Yes — open any tool, long-press a card, and choose \"Add to "
                "Home Screen\".\n\nBack on Home, long-press that card again to "
                "pin it to the top, re-arrange, or remove it. Your layout "
                "syncs across your devices.\n\nYou can also just ask your pal: "
                "\"put my hydration streak on my home screen\".",
          ),
          FaqCard(
            question: "How does the Sleep Coach get my data? 😴",
            answer:
                "It reads sleep from Apple Health, so it needs permission the "
                "first time you open it.\n\nIf you skipped that prompt: iPhone "
                "Settings → Health → Data Access & Devices → AI Wellness Pal, "
                "and turn on Sleep.",
          ),

          // ── Your pal ───────────────────────────────────────────────────
          _FaqSection("Your Wellness Pal"),
          FaqCard(
            question: "How do I talk to my pal? 🎙️",
            answer:
                "Tap the glowing orb button — it opens your pal and starts "
                "listening.\n\nLong-press it instead to open the window "
                "without starting a conversation, which is how you get to your "
                "recent conversations.",
          ),
          FaqCard(
            question: "Can I type instead of talking? 💬",
            answer:
                "Yes. Open your pal and tap the smaller \"Chat\" orb beside "
                "the main one.\n\nFree members get three messages a day; "
                "Premium is unlimited. Your chats are saved alongside your "
                "spoken ones, and tapping a saved chat picks it back up where "
                "you left it.",
          ),
          FaqCard(
            question: "What can my pal actually do? ✨",
            answer:
                "More than talk. It can log water, meals, exercise, weight, a "
                "meditation session or a period start; create habits and set "
                "reminders; join challenges; run your check-in; rebuild "
                "Today's Plan; add or remove Home cards; change your theme or "
                "text size; and open any screen.\n\nJust ask in your own "
                "words.",
          ),
          FaqCard(
            question: "What is Live Chat Pal? 🎧",
            answer:
                "A real-time voice conversation — you talk naturally and your "
                "pal responds as you speak, rather than waiting for you to "
                "finish.\n\nTurn it on in Settings → AI Voice. It's a Premium "
                "feature. With it on, you can also enable \"Always listen for "
                "Pal\" and just say \"Hey Pal\" while the app is open.",
          ),
          FaqCard(
            question: "Where do my conversations go? 🗂️",
            answer:
                "Your three most recent conversations are kept as cards — "
                "long-press the orb button to see them.\n\nThey aren't saved "
                "as reflections automatically. If one was worth keeping, tap "
                "\"Generate Reflection\" to turn it into a reflection you can "
                "revisit.",
          ),

          // ── Reflection ─────────────────────────────────────────────────
          _FaqSection("Reflection & progress"),
          FaqCard(
            question: "How does AI journaling work? 📓",
            answer:
                "Start a reflection and you'll get prompts based on how your "
                "week has actually gone. Write your entry and your pal responds "
                "with something supportive and specific.\n\nOpen any reflection "
                "and tap \"Discuss\" (Premium) to talk it through properly — "
                "and save anything useful that comes out of it as an Insight.",
          ),
          FaqCard(
            question: "How do streaks work? 🔥",
            answer:
                "Your streak counts consecutive days you've checked in. "
                "Milestones at 1, 3, 7, 14, 30, 50 and 100 days each get a "
                "celebration.\n\nMissing a day costs you a day rather than "
                "wiping the streak out — so a gap sets you back, it doesn't "
                "undo everything.",
          ),
          FaqCard(
            question: "What are Achievements? 🏆",
            answer:
                "Badges across streaks, points, intentions, actions, "
                "reflections, studio sessions, meditation and challenges — "
                "from \"First Sunrise\" for your first check-in to \"Zen "
                "Master\" at 100 days.\n\nFind them on the Home screen or by "
                "asking your pal to open Achievements.",
          ),
          FaqCard(
            question: "What is the Wellness Journey Map? 🗺️",
            answer:
                "A visual timeline of how far you've come — milestones at 1, "
                "5, 10, 25 and 50 completed plans, your recent plan "
                "completion, and your energy trend over the last 30 days.",
          ),

          // ── Home screen widget ─────────────────────────────────────────
          _FaqSection("Home screen widget"),
          FaqCard(
            question: "How do I add the Today's Plan widget? 📲",
            answer:
                "It shows today's focus and your actions, with checkboxes you "
                "can tick without opening the app.\n\n"
                "1. Long-press an empty area of your iPhone home screen\n"
                "2. Tap the + in the top corner\n"
                "3. Search for \"AI Wellness Pal\"\n"
                "4. Choose the widget size you want and tap \"Add Widget\"\n"
                "5. Drag it where you'd like it and tap Done\n\n"
                "Tapping \"Check In\" on the widget opens the app straight to "
                "your check-in.",
          ),
          FaqCard(
            question: "My widget looks out of date 🔄",
            answer:
                "iOS decides how often widgets refresh, so it can lag a little "
                "behind.\n\nOpening the app syncs it immediately — including "
                "any boxes you ticked from the home screen.",
          ),

          // ── Settings ───────────────────────────────────────────────────
          _FaqSection("Settings"),
          FaqCard(
            question: "How do I get the best voice for readings? 🔊",
            answer:
                "By default iOS uses a standard voice (usually \"Samantha\"), "
                "which sounds noticeably robotic. A much better one is a free "
                "download:\n\n"
                "1. Open iPhone Settings (not this app)\n"
                "2. Accessibility → Spoken Content → Voices → English\n"
                "3. Pick a voice marked Enhanced or Premium — Ava, Zoe and "
                "Evan are good choices\n"
                "4. Tap the ⬇ icon to download it (around 100–200 MB, so use "
                "Wi-Fi)\n"
                "5. Come back here, open Settings → AI Voice, and turn on "
                "\"Higher-quality voice for readings\"\n\n"
                "If you reopen this screen after downloading, it will pick the "
                "better voice up automatically.",
          ),
          FaqCard(
            question: "Which notifications will I get? 🔔",
            answer:
                "Only what you ask for. Settings → Notifications → "
                "Notification Preferences gives you a switch per category: "
                "daily check-in, Today's Plan, meals, hydration, habits and "
                "challenges, meditation, achievements and streaks, and cycle "
                "reminders.\n\nThe master switch at the top mutes everything "
                "at once. Meals and hydration start off, because they're the "
                "chatty ones.\n\nCycle reminders only appear once you've "
                "logged period data.",
          ),
          FaqCard(
            question: "Notifications are blocked — how do I fix it? 🚫",
            answer:
                "If you declined the iOS prompt, the app can't ask again.\n\n"
                "iPhone Settings → Notifications → AI Wellness Pal → turn on "
                "Allow Notifications. Then come back and switch Push "
                "Notifications on here.",
          ),
          FaqCard(
            question: "Can I change how the app looks? 🎨",
            answer:
                "Settings → Appearance and Theme.\n\nMode switches between "
                "light and dark. Season adds a gentle winter effect. Theme "
                "changes the accent colour and background across the whole app "
                "— Clear Sky, Serenity, Lavender, Soft Sand, Morning Glow and "
                "Pilates Studio, all free.\n\nReadability below lets you scale "
                "the text size.",
          ),
          FaqCard(
            question: "Can I change my pal's voice? 🗣️",
            answer:
                "Settings → AI Voice. The standard pal has Default, Nova, "
                "Sage and Atlas.\n\nWith Live Chat Pal on you get a separate "
                "set of real-time voices, and \"Always speak English\" if you "
                "want replies in English whatever language you speak in.",
          ),

          // ── Premium & account ──────────────────────────────────────────
          _FaqSection("Premium & account"),
          FaqCard(
            question: "What do I get with Premium? ⭐",
            answer:
                "Unlimited chat with your pal, Live Chat Pal voice "
                "conversations, Discuss on your reflections, AI plans for your "
                "intentions, and the AI coaching inside the toolkit — "
                "nutrition analysis, meal plans, sleep, hydration and calorie "
                "insights.\n\nAlso the full Wellness Studio library and "
                "AI-picked activities refreshed daily.\n\nAll themes are free "
                "for everyone.",
          ),
          FaqCard(
            question: "How do I restore a purchase? 🔁",
            answer:
                "Settings → Manage Subscription → Restore Purchases.\n\nMake "
                "sure you're signed in with the same Apple ID you bought it "
                "with. Have a promo code? There's a \"Have a promo code?\" "
                "option on the same screen.",
          ),
          FaqCard(
            question: "Does my data sync across devices? ☁️",
            answer:
                "Yes. Sign in with the same account and your check-ins, plans, "
                "reflections, habits, intentions and settings follow you.\n\n"
                "Your data is stored in your own private area and isn't shared "
                "with other users.",
          ),

          SizedBox(height: 8),
          _FaqFooter(),
        ],
      ),
    );
  }
}

/// Section heading between groups of questions.
class _FaqSection extends StatelessWidget {
  const _FaqSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Closing note pointing at the pal, which can answer anything not covered.
class _FaqFooter extends StatelessWidget {
  const _FaqFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded,
              color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              "Still stuck? Tap the orb button and just ask your pal — it "
              "knows its way around every feature here.",
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? theme.cardColor : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _expanded
              ? theme.colorScheme.primary.withOpacity(0.35)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _expanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      widget.answer,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
