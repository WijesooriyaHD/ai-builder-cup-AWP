# Conversation Mode — Test Checklist (Gemini Live, Premium)

Feature flag: `LIVE_CONVERSATION` (off by default). Entry: Voice Assistant → **Talk**.

## Preconditions
- [ ] Run on a **real device** (iOS/Android). The iOS Simulator has no mic and won't stream Live audio.
- [ ] Launch with the flag on: `flutter run --dart-define=LIVE_CONVERSATION=true`
- [ ] Test account is **Premium** (`AppState.isPro == true`). Have a **Free** account ready too.
- [ ] Firebase: App Check is registered for this build; Vertex AI + Firebase AI Logic enabled on the project.
- [ ] Notifications permission is grantable (for reminder tool calls).
- [ ] Sound on, not silent/DND; grant mic permission when prompted.

## Gating
- [ ] Flag OFF (normal build): no **Talk** button in the assistant; nothing about Conversation Mode is visible.
- [ ] Flag ON + **Free** user: tapping **Talk** shows the "Talk with your Pal" upsell (no session starts, no mic prompt).
- [ ] Flag ON + **Premium**: tapping **Talk** opens the sheet and starts connecting.

## Permissions
- [ ] First run: mic permission is requested; granting proceeds to "Connecting…" → "Listening…".
- [ ] Deny mic: shows the "Microphone permission is needed" message, no crash; re-granting + retry works.

## Session lifecycle
- [ ] Orb shows: connecting spinner → active (graphic_eq) → idle on End.
- [ ] "Connecting…" resolves to "Listening…" within a few seconds (note the latency).
- [ ] Connection failure path: shows error text + **Try again**; retry reconnects.

## Audio round-trip (the core)
- [ ] Speak a greeting → hear a spoken reply in a natural voice (not the old flat TTS).
- [ ] Reply audio is clear at the right pitch/speed (confirms 24 kHz PCM playback is correct — wrong rate = chipmunk/slow).
- [ ] Mic captures speech reliably (confirms 16 kHz PCM16 capture); no constant echo/feedback loop.

## Multi-turn conversation (continuous receive loop)
- [ ] Have a 4–5 turn back-and-forth; it keeps listening after each reply **without** re-tapping.
- [ ] Follow-ups resolve in context ("how about tomorrow?" refers to the prior turn).

## Barge-in / interrupt
- [ ] While the pal is speaking, tap **Interrupt** → playback stops promptly.
- [ ] After interrupt, you can speak and get a new reply (session still healthy).
- [ ] Note: SDK-driven VAD/auto-interrupt is "coming soon"; only the manual button is expected to work now.

## Tool calling (create habit / set reminder mid-chat)
- [ ] Say: "Create a daily habit of swimming and remind me at 7 pm."
  - [ ] Pal confirms verbally; habit appears in **Habit Builder** with a **7:00 PM** reminder.
- [ ] Follow up: "Actually change it to 7:30."
  - [ ] `update_habit_reminder` fires; the same habit's reminder becomes **7:30 PM** (resolves "it" via last-habit memory).
- [ ] Weekdays/weekends: "Create a weekdays habit of stretching" → correct frequency + active days.
- [ ] Reminder actually fires at the set time (leave one scheduled a couple minutes out).
- [ ] Tool failure is graceful: revoke notifications, create a habit with a reminder → pal says reminder saved but notifications are off; no crash.

## Remote Config model name
- [ ] With no remote value set: session uses the code default model — works.
- [ ] Set `live_conversation_model_id` in Firebase console to a valid Live model → new session uses it (debug fetches immediately; release within ~1h).
- [ ] Set it to an invalid/garbage model → session errors cleanly with **Try again** (no hard crash); reverting fixes it.

## Robustness / edge cases
- [ ] End session mid-reply → audio stops, sheet closes, no lingering mic indicator.
- [ ] Background the app during a session → returns without a stuck/hot mic; End still works.
- [ ] Toggle airplane mode mid-session → error state, not a crash; recovers on reconnect.
- [ ] Open → End → reopen several times: no leaked recorder/player, no audio artifacts building up.
- [ ] Free command-and-control assistant (mic → parse → TTS) still works unchanged with the flag both on and off.

## Sign-off
- [ ] No `flutter analyze lib` errors (baseline: 0).
- [ ] Latency, voice quality, and interrupt feel acceptable for a Premium experience.
- [ ] Cost sanity-checked (Live is billed by audio time) before wider rollout.
