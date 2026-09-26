import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/wellness_chat_guard.dart';

void main() {
  group('WellnessChatGuard.isOffTopic', () {
    test('blocks blatant off-topic task requests', () {
      const offTopic = [
        'write me a python script to scrape a website',
        'generate code for a login form',
        'Can you debug this function for me?',
        'write an essay about climate change',
        'draft my cover letter',
        'solve this equation for x',
        'should i invest in bitcoin',
        'give me a sql query',
      ];
      for (final m in offTopic) {
        expect(WellnessChatGuard.isOffTopic(m), isTrue, reason: 'should block: $m');
      }
    });

    test('allows genuine wellness messages', () {
      const wellness = [
        "I'm feeling stressed",
        "I can't sleep well",
        'I have no energy today',
        'Help me build a habit',
        'my back aches after sitting all day',
        'I feel overwhelmed by work',
        'what should I eat before a workout?',
        'I keep waking up at 3am',
        'feeling really low lately',
        'how do I start meditating',
      ];
      for (final m in wellness) {
        expect(WellnessChatGuard.isOffTopic(m), isFalse, reason: 'should allow: $m');
      }
    });

    test('allows wellness framed around an off-topic activity', () {
      const mixed = [
        'coding all night is wrecking my sleep',
        'I write code for 10 hours and my back hurts',
        'stress from a deadline to build an app is burning me out',
        'I am exhausted from writing a thesis',
      ];
      for (final m in mixed) {
        expect(WellnessChatGuard.isOffTopic(m), isFalse, reason: 'should allow: $m');
      }
    });

    test('ignores empty input', () {
      expect(WellnessChatGuard.isOffTopic(''), isFalse);
      expect(WellnessChatGuard.isOffTopic('   '), isFalse);
    });
  });
}
