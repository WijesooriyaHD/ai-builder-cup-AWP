# AI Wellness Pal

A personal wellness companion built with Flutter and Firebase. AI Wellness Pal helps users build sustainable wellness habits through daily check-ins, personalized plans, guided reflections, and interactive wellness activities.

## Features

- **Daily Check-Ins** — Track energy, mood, and recovery each day. After 14+ check-ins, the app pre-fills values based on your patterns (Premium).
- **Personalized Daily Plans** — AI-generated wellness actions tailored to your check-in data and intentions.
- **Wellness Studio** — Short interactive challenges: breathing exercises, mindfulness sessions, wellness quizzes, pilates knowledge cards, and more.
- **Wellness Library** — Content across recovery, stress management, sleep, pilates, and women's wellness in short reads, audio sessions, and guided reflections.
- **AI Wellness Reflection (Journal)** — AI-guided journaling with personalized prompts and supportive responses.
- **Wellness Journey Map** — Visual timeline of milestones, trends, and achievements rendered with Mapbox (Flutter CustomPainter fallback).
- **Wellness Intentions** — Set and track long-term wellness goals with progress tracking.
- **Home Screen Widget** — Native widget showing today's focus and actions with deep-link check-in.
- **Themes** — 5 glassmorphism-inspired wellness themes (2 free, 3 Premium).
- **Push Notifications** — Gentle daily reminder if you haven't checked in.

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Cloud Functions, Storage)
- **AI**: Cloud Functions with AI-powered plan generation and journal responses
- **Payments**: RevenueCat for Premium subscription management
- **Maps**: Mapbox Maps Flutter SDK

## Getting Started

### Prerequisites

- Flutter SDK (3.10.7+)
- Firebase project with Firestore, Auth, Storage, and Cloud Functions enabled
- RevenueCat account (for Premium features)
- Mapbox access token (optional — falls back to Flutter painter)

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
