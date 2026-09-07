import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/dream.dart';
import 'package:aiwellnesspal/models/challenge_step.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';

void main() {
  group('WellnessIntention', () {
    test('constructor sets category and isActive defaults to true', () {
      final intention = WellnessIntention(
        title: 'Improve Flexibility',
        category: WellnessCategory.flexibility,
      );

      expect(intention.title, 'Improve Flexibility');
      expect(intention.category, WellnessCategory.flexibility);
      expect(intention.isActive, true);
      expect(intention.description, '');
      expect(intention.steps, isEmpty);
    });

    test('constructor accepts isActive = false', () {
      final intention = WellnessIntention(
        title: 'Reduce Stress',
        category: WellnessCategory.stress,
        isActive: false,
      );

      expect(intention.isActive, false);
    });

    test('extends Dream and preserves all Dream fields', () {
      final deadline = DateTime(2025, 12, 31);
      final startDate = DateTime(2025, 1, 1);
      final steps = [
        ChallengeStep(title: 'Step 1'),
        ChallengeStep(title: 'Step 2'),
      ];

      final intention = WellnessIntention(
        id: 'test-id',
        title: 'Build Movement',
        description: 'Daily movement habit',
        startDate: startDate,
        deadline: deadline,
        themeColor: 0xFF6B9FD4,
        themeIcon: 0xE87D,
        backgroundImagePath: '/path/to/image.png',
        steps: steps,
        category: WellnessCategory.movement,
        isActive: true,
      );

      expect(intention, isA<Dream>());
      expect(intention.id, 'test-id');
      expect(intention.title, 'Build Movement');
      expect(intention.description, 'Daily movement habit');
      expect(intention.startDate, startDate);
      expect(intention.deadline, deadline);
      expect(intention.themeColor, 0xFF6B9FD4);
      expect(intention.themeIcon, 0xE87D);
      expect(intention.backgroundImagePath, '/path/to/image.png');
      expect(intention.steps.length, 2);
    });
  });

  group('WellnessIntention.toMap', () {
    test('includes all Dream fields plus category and isActive', () {
      final startDate = DateTime(2025, 1, 15);
      final intention = WellnessIntention(
        id: 'map-test-id',
        title: 'Improve Sleep',
        description: 'Better sleep hygiene',
        startDate: startDate,
        themeColor: 0xFF9B89C4,
        themeIcon: 0xE813,
        category: WellnessCategory.sleep,
        isActive: true,
      );

      final map = intention.toMap();

      expect(map['id'], 'map-test-id');
      expect(map['title'], 'Improve Sleep');
      expect(map['description'], 'Better sleep hygiene');
      expect(map['startDate'], startDate.toIso8601String());
      expect(map['deadline'], isNull);
      expect(map['themeColor'], 0xFF9B89C4);
      expect(map['themeIcon'], 0xE813);
      expect(map['backgroundImagePath'], isNull);
      expect(map['steps'], isEmpty);
      expect(map['category'], 'sleep');
      expect(map['isActive'], true);
    });

    test('toMap serializes isActive false correctly', () {
      final intention = WellnessIntention(
        title: 'Recovery',
        category: WellnessCategory.recovery,
        isActive: false,
      );

      final map = intention.toMap();
      expect(map['isActive'], false);
      expect(map['category'], 'recovery');
    });
  });

  group('WellnessIntention.fromMap', () {
    test('reconstructs from map with all fields', () {
      final map = {
        'id': 'from-map-id',
        'title': 'Increase Energy',
        'description': 'More energy throughout the day',
        'startDate': '2025-03-01T00:00:00.000',
        'deadline': '2025-06-01T00:00:00.000',
        'themeColor': 0xFFE8A84C,
        'themeIcon': 0xE8B5,
        'backgroundImagePath': '/bg.png',
        'steps': [
          {'id': 's1', 'title': 'Step A', 'durationMinutes': 10, 'isCompleted': false},
        ],
        'category': 'energy',
        'isActive': true,
      };

      final intention = WellnessIntention.fromMap(map);

      expect(intention.id, 'from-map-id');
      expect(intention.title, 'Increase Energy');
      expect(intention.description, 'More energy throughout the day');
      expect(intention.startDate, DateTime(2025, 3, 1));
      expect(intention.deadline, DateTime(2025, 6, 1));
      expect(intention.themeColor, 0xFFE8A84C);
      expect(intention.themeIcon, 0xE8B5);
      expect(intention.backgroundImagePath, '/bg.png');
      expect(intention.steps.length, 1);
      expect(intention.category, WellnessCategory.energy);
      expect(intention.isActive, true);
    });

    test('defaults category to general when missing', () {
      final map = {
        'id': 'no-cat',
        'title': 'General Wellness',
        'startDate': '2025-01-01T00:00:00.000',
        'steps': [],
      };

      final intention = WellnessIntention.fromMap(map);
      expect(intention.category, WellnessCategory.general);
    });

    test('defaults isActive to true when missing', () {
      final map = {
        'id': 'no-active',
        'title': 'Test',
        'startDate': '2025-01-01T00:00:00.000',
        'steps': [],
        'category': 'stress',
      };

      final intention = WellnessIntention.fromMap(map);
      expect(intention.isActive, true);
    });

    test('toMap and fromMap are symmetric', () {
      final original = WellnessIntention(
        id: 'round-trip',
        title: 'Mindfulness Practice',
        description: 'Daily mindfulness',
        startDate: DateTime(2025, 2, 14),
        deadline: DateTime(2025, 8, 14),
        themeColor: 0xFF7AAE8B,
        themeIcon: 0xE88A,
        backgroundImagePath: '/mindful.png',
        category: WellnessCategory.mindfulness,
        isActive: false,
      );

      final reconstructed = WellnessIntention.fromMap(original.toMap());

      expect(reconstructed.id, original.id);
      expect(reconstructed.title, original.title);
      expect(reconstructed.description, original.description);
      expect(reconstructed.startDate, original.startDate);
      expect(reconstructed.deadline, original.deadline);
      expect(reconstructed.themeColor, original.themeColor);
      expect(reconstructed.themeIcon, original.themeIcon);
      expect(reconstructed.backgroundImagePath, original.backgroundImagePath);
      expect(reconstructed.category, original.category);
      expect(reconstructed.isActive, original.isActive);
    });
  });

  group('WellnessIntention.fromDream', () {
    test('converts Dream to WellnessIntention preserving all fields', () {
      final dream = Dream(
        id: 'dream-id',
        title: 'My Dream',
        description: 'A big dream',
        startDate: DateTime(2025, 1, 1),
        deadline: DateTime(2025, 12, 31),
        themeColor: 0xFF6B9FD4,
        themeIcon: 0xE87D,
        backgroundImagePath: '/dream.png',
        steps: [ChallengeStep(title: 'Dream Step')],
      );

      final intention = WellnessIntention.fromDream(dream);

      expect(intention.id, 'dream-id');
      expect(intention.title, 'My Dream');
      expect(intention.description, 'A big dream');
      expect(intention.startDate, DateTime(2025, 1, 1));
      expect(intention.deadline, DateTime(2025, 12, 31));
      expect(intention.themeColor, 0xFF6B9FD4);
      expect(intention.themeIcon, 0xE87D);
      expect(intention.backgroundImagePath, '/dream.png');
      expect(intention.steps.length, 1);
      expect(intention.steps.first.title, 'Dream Step');
      expect(intention.category, WellnessCategory.general);
      expect(intention.isActive, true);
    });

    test('converts Dream with minimal fields', () {
      final dream = Dream(title: 'Simple Dream');

      final intention = WellnessIntention.fromDream(dream);

      expect(intention.title, 'Simple Dream');
      expect(intention.category, WellnessCategory.general);
      expect(intention.isActive, true);
      expect(intention.description, '');
      expect(intention.steps, isEmpty);
    });
  });

  group('WellnessIntention.progressPercent', () {
    test('returns 0.0 when completedMatchingPlans is 0', () {
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.flexibility,
      );
      expect(intention.progressPercent(0), 0.0);
    });

    test('returns proportional value for plans under 30', () {
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.flexibility,
      );
      expect(intention.progressPercent(15), closeTo(0.5, 0.001));
      expect(intention.progressPercent(10), closeTo(1 / 3, 0.001));
      expect(intention.progressPercent(1), closeTo(1 / 30, 0.001));
    });

    test('returns 1.0 when completedMatchingPlans is exactly 30', () {
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.stress,
      );
      expect(intention.progressPercent(30), 1.0);
    });

    test('caps at 1.0 when completedMatchingPlans exceeds 30', () {
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.sleep,
      );
      expect(intention.progressPercent(50), 1.0);
      expect(intention.progressPercent(100), 1.0);
    });
  });
}
