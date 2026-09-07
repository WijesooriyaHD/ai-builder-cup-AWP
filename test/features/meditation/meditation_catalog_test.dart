import 'package:aiwellnesspal/features/meditation/domain/meditation_catalog.dart';
import 'package:aiwellnesspal/features/meditation/domain/meditation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalog integrity', () {
    test('has content in every collection', () {
      expect(MeditationCatalog.categories, isNotEmpty);
      expect(MeditationCatalog.guided, isNotEmpty);
      expect(MeditationCatalog.breathing, isNotEmpty);
      expect(MeditationCatalog.bodyScans, isNotEmpty);
      expect(MeditationCatalog.bodyRegions, isNotEmpty);
      expect(MeditationCatalog.stressExercises, isNotEmpty);
      expect(MeditationCatalog.sleep, isNotEmpty);
      expect(MeditationCatalog.achievements, isNotEmpty);
    });

    test('every guided meditation belongs to a known category', () {
      for (final g in MeditationCatalog.guided) {
        expect(MeditationCatalog.categories, contains(g.category),
            reason: '${g.id} has an unknown category');
      }
    });

    test('guidedFor filters by category', () {
      final beginner = MeditationCatalog.guidedFor('Beginner Meditation');
      expect(beginner, isNotEmpty);
      expect(beginner.every((g) => g.category == 'Beginner Meditation'), isTrue);
    });

    test('ids are unique across guided meditations', () {
      final ids = MeditationCatalog.guided.map((g) => g.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('achievement ids are unique', () {
      final ids = MeditationCatalog.achievements.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('durations are positive', () {
      expect(MeditationCatalog.guided.every((g) => g.durationMinutes > 0), isTrue);
      expect(MeditationCatalog.sleep.every((s) => s.durationMinutes > 0), isTrue);
      expect(
          MeditationCatalog.bodyScans.every((b) => b.durationMinutes > 0), isTrue);
    });

    test('stress exercises have steps', () {
      expect(
          MeditationCatalog.stressExercises.every((e) => e.steps.isNotEmpty),
          isTrue);
    });

    test('breathing durations are the expected set', () {
      expect(MeditationCatalog.breathingDurations, [1, 3, 5, 10]);
    });
  });

  group('BreathingPattern.cycleSeconds', () {
    test('sums all four phases', () {
      const p = BreathingPattern(
        id: 'x',
        name: 'X',
        description: '',
        inhale: 4,
        hold1: 4,
        exhale: 4,
        hold2: 4,
      );
      expect(p.cycleSeconds, 16);
    });

    test('skipped phases (0) do not add time', () {
      const p = BreathingPattern(
        id: 'calm',
        name: 'Calm',
        description: '',
        inhale: 5,
        exhale: 5,
      );
      expect(p.cycleSeconds, 10);
    });

    test('every catalog pattern has a positive cycle', () {
      expect(
          MeditationCatalog.breathing.every((p) => p.cycleSeconds > 0), isTrue);
    });
  });

  group('SessionType', () {
    test('label + emoji defined for all values', () {
      for (final t in SessionType.values) {
        expect(t.label, isNotEmpty);
        expect(t.emoji, isNotEmpty);
      }
    });

    test('fromName round-trips and falls back to guided', () {
      expect(SessionTypeInfo.fromName('breathing'), SessionType.breathing);
      expect(SessionTypeInfo.fromName('nonsense'), SessionType.guided);
      expect(SessionTypeInfo.fromName(null), SessionType.guided);
    });
  });
}
