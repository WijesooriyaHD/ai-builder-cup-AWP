# AI Wellness Pal

**Your personal AI wellness companion — talk it through, plan your day and build habits that last.**

[![Watch the demo](https://img.shields.io/badge/Demo-YouTube-red?logo=youtube)](https://www.youtube.com/watch?v=PYkPL-Q_1uw)
[![Website](https://img.shields.io/badge/Website-aiwelnesspal.com-2ea44f)](https://aiwelnesspal.com/)
[![Download on the App Store](https://img.shields.io/badge/App_Store-Download-0D96F6?logo=apple)](https://apps.apple.com/us/app/ai-wellness-pal/id6816496839)
[![Get it on Google Play](https://img.shields.io/badge/Google_Play-Download-34A853?logo=googleplay)](https://play.google.com/store/apps/details?id=com.aiwellnesspal.app)

| | |
|---|---|
| 🎬 **Demo video** | https://www.youtube.com/watch?v=PYkPL-Q_1uw |
| 🌐 **Website** | https://aiwelnesspal.com/ |
| 🍎 **App Store (iOS)** | https://apps.apple.com/us/app/ai-wellness-pal/id6816496839 |
| ▶️ **Google Play (Android)** | https://play.google.com/store/apps/details?id=com.aiwellnesspal.app |

---

## What it is

AI Wellness Pal is a mobile wellness companion for iOS and Android. At its heart
is **the Pal** — an AI companion you can chat with or simply talk to out loud. It
knows your goals, habits and recent check-ins, so its suggestions are personal
rather than generic, and it can act inside the app for you: plan your day, create
a habit, open a tool or log progress, just by asking.

Around the Pal sits a complete wellness toolkit — daily plans, habits, journaling,
guided activities and focused tools for nutrition, hydration, sleep and more — all
in one calm, private place, and reachable straight from your home screen.

## How it helps you

- **Start each day with a plan that fits you.** A quick check-in on energy, mood
  and recovery turns into a short, realistic plan — with the reasoning behind
  each suggestion.
- **Talk instead of tapping.** Have a natural spoken conversation with your Pal
  when you want to think something through, or just say "Hey Pal" to get help
  hands-free.
- **Build habits that stick.** Small daily habits with gentle reminders, streaks
  and achievements keep you consistent without pressure.
- **Understand yourself better.** AI-guided journaling and reflections help you
  notice patterns and process your day.
- **Keep everything in one place.** Nutrition, meals, calories, water, sleep,
  meditation, cycle, weight and mindful travel live together, so you don't need a
  separate app for each.
- **Stay on track at a glance.** Home-screen widgets show today's habits, plan
  and tool progress without opening the app.

## Features

### The Pal
- **Chat and live voice conversations** powered by Gemini, with on-screen
  captions and a choice of AI voices.
- **"Hey Pal" wake word** for hands-free help while the app is open.
- **Takes actions for you** — navigates the app, creates and schedules habits,
  manages your home cards and draws on your tools' data for personal answers.
- **Personal and safe** — greets you by name, remembers the conversation, and
  filters responses to stay supportive and non-clinical.

### Daily wellness
- **Daily check-ins** for energy, mood and recovery.
- **Today's Plan** — AI-generated wellness actions with explanations, and
  reminders that stop once you're done.
- **Habit Builder** — daily habits with reminders, progress and achievements.
- **Wellness Intentions** — longer-term goals broken into trackable steps.

### Reflect and learn
- **AI journal and reflections** with personalised prompts and supportive
  insights you can discuss further.
- **Wellness Studio** — short breathing, mindfulness and movement sessions.
- **Wellness Reads** — short articles across recovery, stress, sleep, pilates and
  women's wellness, with narration.

### Life toolkit
Nutrition Coach · AI Meal Planner · Calorie Budget · Hydration Coach · Sleep Coach
· Meditation · Period Tracker · Weight Tracker · Mindful Travel

### Made for everyday use
- **Customisable home** — pin and reorder the tools and cards you use most.
- **Home-screen widgets** on iOS and Android for habits, plans, intentions and
  every toolkit tool, each with its own light/dark switch.
- **Gentle notifications** you control by category.
- **Themes** and a calm, glass-style design.
- **Premium** subscription for unlimited Pal conversations and advanced features.
- **Privacy first** — your data is private to your account, and you can delete
  your account from inside the app at any time.

## Tech stack

- **App:** Flutter (Dart), with native iOS (WidgetKit, Swift) and Android
  (Kotlin) home-screen widgets
- **AI:** Gemini via Firebase AI Logic, Gemini Live for real-time voice
- **Backend:** Firebase — Authentication, Cloud Firestore, Cloud Functions,
  Storage and App Check
- **Subscriptions:** RevenueCat
- **Notifications:** OneSignal

## Getting started

### Prerequisites

- Flutter SDK with Dart 3.10.7+
- A Firebase project with Authentication, Firestore, Cloud Functions, Storage,
  App Check and Firebase AI Logic enabled
- A RevenueCat account (for subscriptions)

### Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Add your Firebase configuration files: `android/app/google-services.json`
   (Android) and `ios/Runner/GoogleService-Info.plist` (iOS).

3. Deploy the Cloud Functions:
   ```bash
   cd functions && npm install && npm run deploy
   ```

4. Run the app. Debug builds use the App Check debug provider, so register the
   debug token the app prints under Firebase Console → App Check:
   ```bash
   flutter run --dart-define=LIVE_CONVERSATION=true
   ```

For release builds, pass your RevenueCat public SDK keys with
`--dart-define=REVENUECAT_IOS_KEY=...` and `--dart-define=REVENUECAT_ANDROID_KEY=...`.

## Project structure

```
lib/
├── config/         # Feature flags
├── data/           # Static data and templates
├── features/       # Life-toolkit tools (nutrition, hydration, sleep, …)
├── models/         # Data models (check-ins, plans, journals, etc.)
├── providers/      # State management (Provider)
├── screens/        # App screens
├── services/       # AI, voice, notifications, subscriptions and more
├── theme/          # Themes and styling
├── utils/          # Utilities and helpers
└── widgets/        # Reusable UI components
functions/          # Firebase Cloud Functions (TypeScript)
android/, ios/      # Native code, including home-screen widgets
```

## Privacy and support

- Privacy policy: https://aiwelnesspal.com/privacy.html
- Terms of use: https://aiwelnesspal.com/terms.html
- Delete your account: https://aiwelnesspal.com/delete-account.html

AI Wellness Pal supports general wellbeing and is not a medical service. It does
not diagnose or treat any condition; please consult a healthcare professional for
medical advice.
