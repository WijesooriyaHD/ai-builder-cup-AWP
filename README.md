# AI Wellness Pal

A personal wellness companion built with Flutter and Firebase. AI Wellness Pal helps users build sustainable wellness habits through daily check-ins, personalized plans, guided reflections, and interactive wellness activities.

## Built during the hackathon

This repository starts from an existing app: the first commit, **"Existing app
foundation (pre-hackathon)"**, is the app as it stood before the hackathon
(check-ins, AI daily plans, Studio and Library, journaling, intentions, habit
builder, life-toolkit tools, themes, subscriptions and two home-screen widgets).
Everything after it was built during the hackathon, commit by commit:

- **Live voice pal (Gemini Live)** — real-time spoken conversations with the
  wellness pal: streaming audio, on-screen captions, "thinking" cue, graceful
  goodbyes, selectable AI voices, personalised greetings and conversation memory.
  Uses a native echo-cancelling audio pipeline on iOS and half-duplex mic gating
  with an Interrupt control on Android.
- **"Hey Pal" wake word** — hands-free activation while the app is open, with
  sound effects and an "Always listen for pal" setting.
- **The pal can act inside the app** — voice navigation, creating and scheduling
  habits by voice, adding and removing home cards, and context from the user's
  tools so answers are personal.
- **Home-screen widgets** (iOS WidgetKit + Android) — Today's Habits plus nine
  life-tool widgets (nutrition, meal planner, calorie budget, hydration, sleep,
  meditation, period, weight, travel) with live data, a per-widget light/dark
  toggle, and flip-to-details faces on iOS.
- **Customisable home** — tool cards on the home screen, pin to top, reorder,
  weight history card, and a toolkit customise sheet.
- **Wellness Reads narration** — narrated reading with offline support.
- **Habits and plans** — preferred wellness methods, AI explanations for plan
  actions, and reminders for Today's Plan that switch off once a task is done.
- **Reflections and achievements** — reflections saved to Firestore with a
  chat-style flow, and an expanded achievements system.
- **Push notifications** — OneSignal integration with notification categories,
  preferences and deep links.
- **Safety and access** — AI response safety filtering, a wellness chat guard,
  chat quotas, Premium access via RevenueCat, and in-app account deletion.
- **Release and hardening** — shipped to TestFlight (iOS) and Google Play,
  Firebase App Check on AI calls, Android-specific fixes, removal of the unused
  Mapbox dependency, and locked-down Cloud Functions.

The full list of hackathon commits is in the history after the foundation commit
(`git log`).

## Features

- **Daily Check-Ins** — Track energy, mood, and recovery each day. After 14+ check-ins, the app pre-fills values based on your patterns (Premium).
- **Personalized Daily Plans** — AI-generated wellness actions tailored to your check-in data and intentions.
- **Wellness Studio** — Short interactive challenges: breathing exercises, mindfulness sessions, wellness quizzes, pilates knowledge cards, and more.
- **Wellness Library** — Content across recovery, stress management, sleep, pilates, and women's wellness in short reads, audio sessions, and guided reflections.
- **AI Wellness Reflection (Journal)** — AI-guided journaling with personalized prompts and supportive responses.
- **Wellness Intentions** — Set and track long-term wellness goals with progress tracking.
- **Home Screen Widget** — Native widget showing today's focus and actions with deep-link check-in.
- **Themes** — 5 glassmorphism-inspired wellness themes (2 free, 3 Premium).
- **Push Notifications** — Gentle daily reminder if you haven't checked in.

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Cloud Functions, Storage)
- **AI**: Gemini via Firebase AI Logic (App Check enforced), Gemini Live for voice conversations, and a Cloud Function for journal insights
- **Payments**: RevenueCat for Premium subscription management

## Getting Started

### Prerequisites

- Flutter SDK (3.10.7+)
- Firebase project with Firestore, Auth, Storage, and Cloud Functions enabled
- RevenueCat account (for Premium features)

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/viraj-dhanushka/ai-wellness-pal.git
   cd ai-wellness-pal
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Firebase:
   - Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Deploy Cloud Functions:
     ```bash
     cd functions && npm run deploy
     ```

4. Run the app:
   ```bash
   flutter run
   ```

For local testing without the AI backend, the app uses fallback plans from `assets/data/fallback_plans.json` automatically when Cloud Functions are unavailable.

## Project Structure

```
lib/
├── data/           # Static data and templates
├── models/         # Data models (check-ins, plans, journals, etc.)
├── providers/      # State management (Provider)
├── screens/        # All app screens
├── services/       # Business logic and API services
├── theme/          # App themes and styling
├── utils/          # Utilities and helpers
└── widgets/        # Reusable UI components
```

## License

This project is private and not published to pub.dev.
