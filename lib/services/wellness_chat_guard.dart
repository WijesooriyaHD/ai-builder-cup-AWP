/// Keeps the Wellness Pal chat on its purpose: the user's wellbeing.
///
/// This is the *first* of two layers. The model's system instruction in
/// [AIService.chatWithPal] does the real work — it handles nuance, tone, and
/// anything phrased indirectly. This guard only catches the blatant, unambiguous
/// cases ("write me a python script") so they get an instant, consistent
/// redirect without spending a model call.
///
/// Deliberately conservative. A false positive here silently refuses a real
/// wellness message, which is far worse than letting a borderline one through
/// to the model — which is better at judging it anyway. So a message is only
/// blocked when it BOTH matches an explicit task-request pattern AND contains
/// no wellbeing signal at all.
class WellnessChatGuard {
  WellnessChatGuard._();

  /// Explicit "do this task for me" requests that have nothing to do with
  /// wellbeing. Each requires a request verb next to a task noun, so ordinary
  /// sentences that merely mention the word don't trip it.
  static final List<RegExp> _offTopicTaskPatterns = [
    // Code: "write me a python script", "generate sql", "debug this function"
    RegExp(
      r'\b(write|generate|create|build|make|give me|show me|debug|fix|refactor|optimi[sz]e)\b'
      r'[^.?!]{0,40}\b(code|script|program|programme|function|regex|query|algorithm|'
      r'python|javascript|typescript|java|kotlin|swift|dart|c\+\+|c#|php|ruby|rust|go|'
      r'sql|html|css|json|xml|yaml|bash|shell|api|app|website|snippet)\b',
      caseSensitive: false,
    ),
    // Written assignments: "write an essay about", "draft my cover letter"
    RegExp(
      r'\b(write|draft|compose|generate|create)\b[^.?!]{0,30}\b'
      r'(essay|homework|assignment|thesis|dissertation|blog post|article|'
      r'press release|cover letter|resume|cv|report|speech|poem|song lyrics|story)\b',
      caseSensitive: false,
    ),
    // Homework-style maths: "solve this equation", "calculate the derivative"
    RegExp(
      r'\b(solve|calculate|compute|evaluate)\b[^.?!]{0,30}\b'
      r'(equation|integral|derivative|matrix|polynomial|for x|this sum|this problem)\b',
      caseSensitive: false,
    ),
    // Financial / legal advice, which we must not give.
    RegExp(
      r'\b(invest|investing|stocks?|shares?|crypto|bitcoin|portfolio|tax(es)?|'
      r'lawsuit|sue|legal advice|contract)\b[^.?!]{0,30}\b(advice|should i|recommend|tips?)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(should i (invest|buy|sell)|is .{0,20} a good (investment|stock|buy))\b',
      caseSensitive: false,
    ),
  ];

  /// Any hint that the message is really about the user's wellbeing. When one
  /// of these is present we hand the message to the model regardless — it can
  /// tell that "coding all night is wrecking my sleep" is a wellness message.
  static final RegExp _wellbeingSignal = RegExp(
    r'\b(sleep|sleeping|slept|insomnia|tired|exhaust\w*|fatigue|rest|nap|'
    r'stress\w*|anxious|anxiety|worried|worry|overwhelm\w*|burn ?out|burnt out|'
    r'mood|sad|down|low|lonely|angry|frustrated|upset|cry\w*|'
    r'energy|motivat\w*|focus|calm|relax\w*|breathe|breathing|mindful\w*|meditat\w*|'
    r'eat\w*|diet|food|meal|nutrition|hydrat\w*|water|drink\w*|'
    r'exercise|workout|walk\w*|run\w*|yoga|pilates|stretch\w*|movement|'
    r'habit|routine|balance|wellbeing|well-being|wellness|health\w*|self ?care|'
    r'feel\w*|felt|mental|emotion\w*|mind|body|'
    // Physical discomfort, including the desk-work aches this app's users
    // most often describe ("my back hurts", "stiff neck", "eye strain").
    r'pain\w*|ache|aches|aching|sore|soreness|hurt\w*|stiff\w*|tension|strain|'
    r'posture|back|neck|shoulder\w*|wrist\w*|headache|migraine|'
    r'work.{0,10}(stress|life|balance)|relationship|partner|family|friend)\b',
    caseSensitive: false,
  );

  /// A warm, non-lecturing redirect. Kept short so it reads like the Pal
  /// talking, not a policy notice.
  static const String redirectMessage =
      "That's a bit outside what I can help with — I'm here for your wellbeing. "
      "How are you doing today?";

  /// Clear signs that the user may be at risk of harming themselves.
  ///
  /// When one matches, the app answers with [crisisMessage] instead of calling
  /// the model, so the user always gets real emergency resources — never a
  /// model reply that could miss the moment or be filtered away (App Store
  /// Review Guideline 1.4.1).
  static final List<RegExp> _crisisPatterns = [
    RegExp(
      r'\b(kill(ing)?|hurt(ing)?|harm(ing)?|cut(ting)?|end(ing)?) (myself|my life|it all)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bsuicid\w*', caseSensitive: false),
    RegExp(r'\bself[- ]?harm\w*', caseSensitive: false),
    RegExp(
      r"\b(want|wanna|going|plan(ning)?|ready) to (die|end it)\b",
      caseSensitive: false,
    ),
    RegExp(
      r"\b(don'?t|do not) want to (live|be alive|be here|wake up)( anymore)?\b",
      caseSensitive: false,
    ),
    RegExp(r'\b(no reason|not worth) (to )?(go on )?(living|live|going on)\b',
        caseSensitive: false),
    RegExp(r"\b(is ?n'?t|is not|not) worth living\b", caseSensitive: false),
    RegExp(r'\bbetter off (dead|without me)\b', caseSensitive: false),
    RegExp(r'\boverdos\w*', caseSensitive: false),
  ];

  /// Shown instead of a model reply when [isCrisis] matches.
  static const String crisisMessage =
      "I'm really glad you told me, and I'm sorry you're going through this. "
      "You deserve support from a real person right now.\n\n"
      "If you're in immediate danger, please call your local emergency number "
      "(911 in the US, 999 in the UK, 112 in the EU).\n\n"
      "You can talk to someone any time, for free:\n"
      "• US: call or text 988 (Suicide & Crisis Lifeline)\n"
      "• UK & Ireland: call Samaritans on 116 123\n"
      "• Elsewhere: find a helpline at findahelpline.com\n\n"
      "I'm an AI and can't provide crisis support, but reaching out to one of "
      "these services or someone you trust can really help.";

  /// Spoken form of [crisisMessage] for voice replies (no bullet points).
  static const String crisisSpokenMessage =
      "I'm really glad you told me, and I'm sorry you're going through this. "
      "Please reach out to a real person right now. If you're in immediate "
      "danger, call your local emergency number. In the US you can call or "
      "text 988, and in the UK and Ireland you can call Samaritans on "
      "116 123. Anywhere else, findahelpline.com lists free helplines. "
      "I'm an AI and can't provide crisis support, but they can help.";

  /// True when [message] contains clear signs of crisis or self-harm.
  static bool isCrisis(String message) {
    final text = message.trim();
    if (text.isEmpty) return false;
    return _crisisPatterns.any((p) => p.hasMatch(text));
  }

  /// True when [message] is a clear off-topic task request with no wellbeing
  /// angle, and should be redirected without calling the model.
  static bool isOffTopic(String message) {
    final text = message.trim();
    if (text.isEmpty) return false;

    // A wellbeing signal always wins — let the model handle the nuance.
    if (_wellbeingSignal.hasMatch(text)) return false;

    return _offTopicTaskPatterns.any((p) => p.hasMatch(text));
  }
}
