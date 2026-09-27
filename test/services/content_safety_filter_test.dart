import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/content_safety_filter.dart';

void main() {
  group('ContentSafetyFilter.containsBannedContent', () {
    group('detects base banned words', () {
      final baseWords = [
        'diagnose',
        'therapy',
        'therapist',
        'disorder',
        'symptom',
        'condition',
        'clinical',
      ];

      for (final word in baseWords) {
        test('detects "$word"', () {
          expect(
            ContentSafetyFilter.containsBannedContent('You should $word this issue.'),
            isTrue,
          );
        });
      }
    });

    group('detects inflected forms', () {
      final inflectedWords = [
        'diagnoses',
        'diagnosing',
        'treatment',
        'treating',
        'therapeutic',
        'therapists',
        'disorders',
        'symptoms',
        'conditions',
        'clinically',
      ];

      for (final word in inflectedWords) {
        test('detects "$word"', () {
          expect(
            ContentSafetyFilter.containsBannedContent('This involves $word approaches.'),
            isTrue,
          );
        });
      }
    });

    test('is case-insensitive', () {
      expect(ContentSafetyFilter.containsBannedContent('THERAPY is important'), isTrue);
      expect(ContentSafetyFilter.containsBannedContent('Clinical Review'), isTrue);
      expect(ContentSafetyFilter.containsBannedContent('Diagnose early'), isTrue);
      expect(ContentSafetyFilter.containsBannedContent('DISORDER found'), isTrue);
    });

    test('allows "treat yourself" phrasing', () {
      expect(ContentSafetyFilter.containsBannedContent('Treat yourself to a walk'), isFalse);
      expect(ContentSafetyFilter.containsBannedContent('You treated yourself well'), isFalse);
    });

    test('uses word boundaries — does not match partial words', () {
      // "condition" should not match inside "unconditional"
      expect(ContentSafetyFilter.containsBannedContent('unconditional love'), isFalse);
      // "treat" should not match inside "retreat"
      expect(ContentSafetyFilter.containsBannedContent('Go on a retreat'), isFalse);
      // "clinical" should not match inside "preclinical" — wait, "preclinical" contains "clinical" at a word boundary end
      // Actually \bclinical\b won't match in "preclinical" because 'p' before 'c' means no word boundary
      expect(ContentSafetyFilter.containsBannedContent('preclinical studies'), isFalse);
    });

    test('returns false for safe wellness content', () {
      expect(
        ContentSafetyFilter.containsBannedContent(
          'How are you feeling today? Where is your body asking for extra care?',
        ),
        isFalse,
      );
      expect(
        ContentSafetyFilter.containsBannedContent(
          'Take a moment to reflect on your energy levels.',
        ),
        isFalse,
      );
    });

    test('returns false for empty string', () {
      expect(ContentSafetyFilter.containsBannedContent(''), isFalse);
    });

    test('detects banned word at start of text', () {
      expect(ContentSafetyFilter.containsBannedContent('Therapy can help'), isTrue);
    });

    test('detects banned word at end of text', () {
      expect(ContentSafetyFilter.containsBannedContent('You need therapy'), isTrue);
    });

    test('detects banned word surrounded by punctuation', () {
      expect(ContentSafetyFilter.containsBannedContent('(therapy)'), isTrue);
      expect(ContentSafetyFilter.containsBannedContent('"disorder"'), isTrue);
      expect(ContentSafetyFilter.containsBannedContent('symptom.'), isTrue);
    });
  });

  group('ContentSafetyFilter.sanitize', () {
    test('returns original text when no banned content is found', () {
      const safeText = 'How are you feeling today?';
      expect(ContentSafetyFilter.sanitize(safeText), safeText);
    });

    test('returns fallback message when banned content is found', () {
      const unsafeText = 'I recommend therapy for your condition.';
      expect(
        ContentSafetyFilter.sanitize(unsafeText),
        ContentSafetyFilter.fallbackMessage,
      );
    });

    test('fallback message is the expected static string', () {
      expect(
        ContentSafetyFilter.fallbackMessage,
        "We're here to support your wellness journey. How are you feeling right now?",
      );
    });

    test('returns original text unchanged (not trimmed or modified)', () {
      const text = '  Hello, how are you?  ';
      expect(ContentSafetyFilter.sanitize(text), text);
    });
  });

  group('ContentSafetyFilter.fallbackMessage', () {
    test('is non-empty', () {
      expect(ContentSafetyFilter.fallbackMessage, isNotEmpty);
    });

    test('does not itself contain banned content', () {
      expect(
        ContentSafetyFilter.containsBannedContent(ContentSafetyFilter.fallbackMessage),
        isFalse,
      );
    });
  });

  group('ContentSafetyFilter.sanitize referrals', () {
    test('keeps replies that refer the user to professional help', () {
      const reply = "It might help to talk to a therapist about how you're feeling.";
      expect(ContentSafetyFilter.sanitize(reply), reply);
      const crisis = 'Please call 988 or reach out to a crisis line right now.';
      expect(ContentSafetyFilter.sanitize(crisis), crisis);
    });

    test('still replaces replies that give clinical advice', () {
      expect(
        ContentSafetyFilter.sanitize('This sounds like an anxiety disorder that needs treatment.'),
        ContentSafetyFilter.fallbackMessage,
      );
    });
  });
}
