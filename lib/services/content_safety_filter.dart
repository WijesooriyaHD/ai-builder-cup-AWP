/// Content safety filter for AI-generated wellness content.
///
/// Ensures no clinical or therapeutic language is rendered to the user.
/// Used both client-side (before rendering) and referenced by server-side
/// Cloud Functions before returning responses.
class ContentSafetyFilter {
  ContentSafetyFilter._();

  /// All banned words including inflected forms.
  /// These terms are prohibited in AI-generated content per Requirements 8.3, 8.6.
  static const List<String> _bannedWords = [
    'diagnose',
    'diagnoses',
    'diagnosing',
    // "treat" / "treated" are deliberately absent: they are overwhelmingly
    // used as "treat yourself", and blocking them wiped out harmless replies.
    'treatment',
    'treating',
    'therapy',
    'therapeutic',
    'therapist',
    'therapists',
    'disorder',
    'disorders',
    'symptom',
    'symptoms',
    'condition',
    'conditions',
    'clinical',
    'clinically',
  ];

  /// Fallback message displayed when banned content is detected.
  static const String _fallbackMessage =
      "We're here to support your wellness journey. "
      'How are you feeling right now?';

  /// Exposed getter for the fallback message (useful for tests and other services).
  static String get fallbackMessage => _fallbackMessage;

  /// Checks whether [text] contains any banned word using word-boundary
  /// regex matching (case-insensitive).
  ///
  /// Returns `true` if banned content is found, `false` otherwise.
  static bool containsBannedContent(String text) {
    final lower = text.toLowerCase();
    return _bannedWords.any(
      (word) => RegExp(r'\b' + word + r'\b', caseSensitive: false).hasMatch(lower),
    );
  }

  /// Encouraging someone to get professional or crisis help is exactly what
  /// the AI should do, so replies that refer the user onward are never
  /// replaced — even though they naturally mention "therapist" or "therapy".
  static final RegExp _referral = RegExp(
    r'\b(talk|talking|speak|speaking|reach(ing)? out|consider|see|seeing|'
    r'contact|call|visit|find|ask)\b[^.?!]{0,60}\b(therapist|therapists|'
    r'therapy|counsel+or|counsel+ing|doctor|gp|professional|helpline|'
    r'hotline|crisis line|support line|988|samaritans)\b',
    caseSensitive: false,
  );

  /// True when [text] points the user towards professional or crisis help.
  static bool isReferral(String text) => _referral.hasMatch(text);

  /// Returns the original [text] if it passes the safety filter,
  /// or the static fallback message if banned content is detected.
  /// Replies that refer the user to professional help always pass.
  static String sanitize(String text) =>
      containsBannedContent(text) && !isReferral(text) ? _fallbackMessage : text;
}
