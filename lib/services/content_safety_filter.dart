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
    'treat',
    'treatment',
    'treating',
    'treated',
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

  /// Returns the original [text] if it passes the safety filter,
  /// or the static fallback message if banned content is detected.
  static String sanitize(String text) =>
      containsBannedContent(text) ? _fallbackMessage : text;
}
