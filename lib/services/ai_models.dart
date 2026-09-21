/// Central configuration for the Gemini model ids used across the app.
///
/// Keeping these in one place means a model upgrade (or an emergency rollback)
/// is a single-line change rather than a hunt across every AI service.
///
/// ## Current models — verified available on this project's Agent Platform
/// (Vertex) endpoint via Firebase AI Logic
/// - Standard generation (chat, wellness planning, coaching, habit
///   recommendations, meal analysis, structured JSON): [kGeminiFlashModel]
///   = `gemini-3.5-flash` (Stable, released 2026-05-19, long-term availability
///   — shutdown no earlier than 2027-05-19; no billing required).
/// - Real-time voice / Live conversation: [kGeminiLiveModel]
///   = `gemini-live-2.5-flash` — the Live/BidiGenerateContent model this app
///   has shipped on and verified working end-to-end. (The `-native-audio`
///   variant is a different model that did not respond for this project, so we
///   stay on the proven `gemini-live-2.5-flash`.)
///
/// ## Model-selection decisions (documented)
/// - We deliberately do NOT use `gemini-3.8-flash` / `gemini-3.7-flash`:
///   although listed in the Firebase AI Logic docs, they are "short-term
///   availability" models and `gemini-3.8-flash` returned a "Publisher model
///   was not found or your project does not have access to it" error in the
///   `us-central1` region for this project. `gemini-3.5-flash` is the newest
///   LONG-TERM stable Flash model, so it's the safe production choice.
/// - There is NO Gemini 3.x Live model on the Agent Platform (Vertex) endpoint
///   this app uses (`FirebaseAI.agentPlatform()`): the docs state
///   "The Agent Platform Gemini API does not support any Gemini Live 3.x
///   models." So the Live model stays on the proven `gemini-live-2.5-flash`,
///   the model this app has shipped and tested on.
///
/// ## SDK compatibility
/// `firebase_ai: 4.0.0` treats the model id as a passthrough string
/// (`BaseModel._normalizeModelName` just wraps a bare name as `models/<name>`);
/// there is no client-side allow-list, so new model ids are accepted and
/// resolved server-side. Standard generation uses the default endpoint; Live
/// uses `FirebaseAI.agentPlatform()` (location `global`), where the
/// Live/BidiGenerateContent models are served.
///
/// ## Overrides & rollback
/// Both ids can be overridden at build time without a code change, e.g. to
/// try a newer/older model or fall back to the long-proven 2.5 line:
///   flutter run --dart-define=GEMINI_FLASH_MODEL=gemini-2.5-flash
///   flutter run --dart-define=LIVE_MODEL_ID=gemini-live-2.5-flash-preview
/// To roll back in code, change the two `defaultValue`s below (e.g. to
/// `gemini-2.5-flash`, which is still an active stable model).
///
/// All AI services degrade gracefully to deterministic offline heuristics on
/// any model/network failure, so an unavailable model id never crashes a
/// feature — it just falls back to the non-AI path.
library;

/// Standard-generation Gemini model (Flash). Overridable via
/// `--dart-define=GEMINI_FLASH_MODEL=<id>`.
const String kGeminiFlashModel = String.fromEnvironment(
  'GEMINI_FLASH_MODEL',
  defaultValue: 'gemini-3.5-flash',
);

/// Real-time Live (audio-to-audio) Gemini model. Overridable via
/// `--dart-define=LIVE_MODEL_ID=<id>` (kept as `LIVE_MODEL_ID` for backward
/// compatibility with existing launch configs).
const String kGeminiLiveModel = String.fromEnvironment(
  'LIVE_MODEL_ID',
  defaultValue: 'gemini-live-2.5-flash',
);
