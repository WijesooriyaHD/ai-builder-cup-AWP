# AI Wellness Pal — Usage Guide

## Getting Started

### 1. Launch & Sign In

Run the app with `flutter run`. You'll land on the auth screen — sign in with Firebase Auth (email/password or Google).

### 2. Onboarding (first time only)

After sign-in, you'll go through a 5-step flow:
- Welcome screen
- Enter your first name and preferred name
- Select your age range (18–24, 25–34, 35–44, 45–54, 55+)
- Choose 1–5 Wellness Intentions (e.g., Improve Flexibility, Reduce Stress, Improve Sleep)
- Completion — this triggers your first Daily Plan generation

If you close the app mid-onboarding, it resumes where you left off.

---

## Daily Usage

### 3. Daily Check-In

Each day when you open the app, you'll be prompted with a 3-step check-in:
- **Energy Score** (1–5 scale)
- **Mood** (Calm, Anxious, Tired, Energized, Stressed, Content)
- **Recovery + Available Time** (how your body feels + how much time you have)

You can skip any step. After 14+ check-ins, values pre-fill based on your patterns (Premium).

### 4. Home Screen (Wellness Command Center)

After check-in, the home screen shows:
- Personalized greeting using your preferred name
- Today's Focus label
- Energy & Recovery summaries
- Your Daily Plan — 2–4 wellness actions with checkboxes
- Recommended Wellness Studio session
- AI Wellness Insight card (Premium, if AI is available)

Tap checkboxes to mark actions complete. When all are done, you get a calm Lottie completion animation.

---

## Feature Screens (Bottom Navigation)

### 5. Wellness Intentions

Manage your long-term wellness goals. View progress (% toward 30 completed related plans), add/deactivate intentions, and see AI encouragement on each detail page.

### 6. Wellness Studio

Short interactive challenges across 6 categories:
- Breathing Exercises (animated inhale/hold/exhale, minimum 3 min)
- Recovery Challenges
- Mindfulness Sessions
- Wellness Quizzes (score + explanations after)
- Pilates Knowledge Cards
- Stress Recovery Activities

Activities matching your Daily Plan's focus get a "Recommended for Today" badge. Free tier has 3+ activities per category; Premium unlocks all.

### 7. Wellness Library

Content across 5 topics: Recovery Education, Stress Management, Sleep Improvement, Pilates Guidance, Women's Wellness. Three formats:
- Short Reads
- Audio Sessions (floating player persists across screens)
- Guided Reflections (interactive prompts)

A "Recommended" section surfaces items matching your intentions/check-ins. Bookmark items for later.

### 8. AI Wellness Reflection (Journal)

AI-guided journaling:
- Open a new session → 3 personalized reflection prompts
- Write your entry → receive a supportive AI response (50–150 words)
- History shows past reflections with AI insights inline
- Premium users with 3+ entries/week get a Weekly Reflection summary

### 9. Wellness Journey Map

Visual timeline showing:
- Milestones at 1, 5, 10, 25, 50 completed plans (tap for details)
- 7-day plan completion trend
- Energy trend line (last 30 days)
- Recovery achievements

Uses Mapbox rendering with a Flutter CustomPainter fallback.

---

## Settings & Extras

### 10. Themes

5 wellness themes — 2 free (Serenity, Soft Sand), 3 Premium (Lavender, Morning Glow, Pilates Studio). Change in Settings; applies instantly with glassmorphism.

### 11. AI Insights (Settings)

See what the AI has learned about you — typical energy range, common mood, preferred time ranges, deprioritized categories. Toggle AI insights on/off.

### 12. Home Screen Widget

Add the AI Wellness Widget to your phone's home screen:
- Shows Today's Focus + up to 3 actions with checkboxes
- "Check In" button deep-links to the check-in flow
- Syncs toggles to Firestore when the app opens

### 13. Push Notifications

A gentle 6pm reminder if you haven't checked in that day.

---

## Prerequisites for Full Functionality

- **Firebase project** configured with Firestore, Auth, and Cloud Functions deployed (the `functions/` folder)
- **RevenueCat** configured for Premium subscription gating
- **Mapbox** access token for the Journey Map (falls back to Flutter painter without it)
- Deploy Cloud Functions: `cd functions && npm run deploy`

For local testing without the AI backend, the app uses fallback plans from `assets/data/fallback_plans.json` automatically when Cloud Functions time out.
