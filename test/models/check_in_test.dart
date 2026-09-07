import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';

void main() {
  group('CheckIn', () {
    test('constructor with all fields', () {
      final date = DateTime(2024, 6, 15, 9, 0);
      final checkIn = CheckIn(
        id: 'ci-001',
        date: date,
        energyScore: 4,
        moodState: MoodState.calm,
        recoveryStatus: RecoveryStatus.wellRested,
        availableTime: AvailableTimeRange.range20_40,
        skippedFields: [],
      );

      expect(checkIn.id, 'ci-001');
      expect(checkIn.date, date);
      expect(checkIn.energyScore, 4);
      expect(checkIn.moodState, MoodState.calm);
      expect(checkIn.recoveryStatus, RecoveryStatus.wellRested);
      expect(checkIn.availableTime, AvailableTimeRange.range20_40);
      expect(checkIn.skippedFields, isEmpty);
    });

    test('constructor with nullable fields as null', () {
      final checkIn = CheckIn(
        id: 'ci-002',
        date: DateTime(2024, 6, 15),
        skippedFields: ['energyScore', 'moodState', 'recoveryStatus', 'availableTime'],
      );

      expect(checkIn.energyScore, isNull);
      expect(checkIn.moodState, isNull);
      expect(checkIn.recoveryStatus, isNull);
      expect(checkIn.availableTime, isNull);
      expect(checkIn.skippedFields, hasLength(4));
    });

    test('skippedFields defaults to empty list', () {
      final checkIn = CheckIn(
        id: 'ci-003',
        date: DateTime(2024, 6, 15),
      );

      expect(checkIn.skippedFields, isEmpty);
    });
  });

  group('CheckIn.energyTier', () {
    test('returns 2 when energyScore is null', () {
      final checkIn = CheckIn(id: 'ci-t1', date: DateTime(2024, 1, 1));
      expect(checkIn.energyTier, 2);
    });

    test('returns 1 when energyScore is 1', () {
      final checkIn = CheckIn(id: 'ci-t2', date: DateTime(2024, 1, 1), energyScore: 1);
      expect(checkIn.energyTier, 1);
    });

    test('returns 1 when energyScore is 2', () {
      final checkIn = CheckIn(id: 'ci-t3', date: DateTime(2024, 1, 1), energyScore: 2);
      expect(checkIn.energyTier, 1);
    });

    test('returns 2 when energyScore is 3', () {
      final checkIn = CheckIn(id: 'ci-t4', date: DateTime(2024, 1, 1), energyScore: 3);
      expect(checkIn.energyTier, 2);
    });

    test('returns 3 when energyScore is 4', () {
      final checkIn = CheckIn(id: 'ci-t5', date: DateTime(2024, 1, 1), energyScore: 4);
      expect(checkIn.energyTier, 3);
    });

    test('returns 3 when energyScore is 5', () {
      final checkIn = CheckIn(id: 'ci-t6', date: DateTime(2024, 1, 1), energyScore: 5);
      expect(checkIn.energyTier, 3);
    });
  });

  group('CheckIn.toMap', () {
    test('serializes all fields correctly', () {
      final date = DateTime(2024, 6, 15, 10, 30, 0);
      final checkIn = CheckIn(
        id: 'ci-map-1',
        date: date,
        energyScore: 3,
        moodState: MoodState.energized,
        recoveryStatus: RecoveryStatus.sore,
        availableTime: AvailableTimeRange.range40_60,
        skippedFields: [],
      );

      final map = checkIn.toMap();
      expect(map['id'], 'ci-map-1');
      expect(map['date'], '2024-06-15T10:30:00.000');
      expect(map['energyScore'], 3);
      expect(map['moodState'], 'energized');
      expect(map['recoveryStatus'], 'sore');
      expect(map['availableTime'], 'range40_60');
      expect(map['skippedFields'], <String>[]);
    });

    test('serializes null fields as null', () {
      final checkIn = CheckIn(
        id: 'ci-map-2',
        date: DateTime(2024, 6, 15),
        skippedFields: ['energyScore', 'moodState'],
      );

      final map = checkIn.toMap();
      expect(map['energyScore'], isNull);
      expect(map['moodState'], isNull);
      expect(map['recoveryStatus'], isNull);
      expect(map['availableTime'], isNull);
      expect(map['skippedFields'], ['energyScore', 'moodState']);
    });
  });

  group('CheckIn.fromMap', () {
    test('deserializes all fields correctly', () {
      final map = {
        'id': 'ci-from-1',
        'date': '2024-06-15T10:30:00.000',
        'energyScore': 4,
        'moodState': 'calm',
        'recoveryStatus': 'wellRested',
        'availableTime': 'range10_20',
        'skippedFields': <String>[],
      };

      final checkIn = CheckIn.fromMap(map);
      expect(checkIn.id, 'ci-from-1');
      expect(checkIn.date, DateTime(2024, 6, 15, 10, 30, 0));
      expect(checkIn.energyScore, 4);
      expect(checkIn.moodState, MoodState.calm);
      expect(checkIn.recoveryStatus, RecoveryStatus.wellRested);
      expect(checkIn.availableTime, AvailableTimeRange.range10_20);
      expect(checkIn.skippedFields, isEmpty);
    });

    test('deserializes null fields correctly', () {
      final map = {
        'id': 'ci-from-2',
        'date': '2024-06-15T10:30:00.000',
        'energyScore': null,
        'moodState': null,
        'recoveryStatus': null,
        'availableTime': null,
        'skippedFields': ['energyScore', 'recoveryStatus'],
      };

      final checkIn = CheckIn.fromMap(map);
      expect(checkIn.energyScore, isNull);
      expect(checkIn.moodState, isNull);
      expect(checkIn.recoveryStatus, isNull);
      expect(checkIn.availableTime, isNull);
      expect(checkIn.skippedFields, ['energyScore', 'recoveryStatus']);
    });

    test('defaults skippedFields to empty list when missing', () {
      final map = {
        'id': 'ci-from-3',
        'date': '2024-06-15T10:30:00.000',
        'energyScore': 2,
        'moodState': 'tired',
        'recoveryStatus': 'fatigued',
        'availableTime': 'under10',
      };

      final checkIn = CheckIn.fromMap(map);
      expect(checkIn.skippedFields, isEmpty);
    });
  });

  group('CheckIn toMap/fromMap round-trip', () {
    test('symmetric serialization with all fields populated', () {
      final original = CheckIn(
        id: 'ci-rt-1',
        date: DateTime(2024, 3, 20, 8, 0, 0),
        energyScore: 5,
        moodState: MoodState.content,
        recoveryStatus: RecoveryStatus.recovering,
        availableTime: AvailableTimeRange.over60,
        skippedFields: [],
      );

      final reconstructed = CheckIn.fromMap(original.toMap());
      expect(reconstructed.id, original.id);
      expect(reconstructed.date, original.date);
      expect(reconstructed.energyScore, original.energyScore);
      expect(reconstructed.moodState, original.moodState);
      expect(reconstructed.recoveryStatus, original.recoveryStatus);
      expect(reconstructed.availableTime, original.availableTime);
      expect(reconstructed.skippedFields, original.skippedFields);
    });

    test('symmetric serialization with all nullable fields null', () {
      final original = CheckIn(
        id: 'ci-rt-2',
        date: DateTime(2024, 3, 20, 8, 0, 0),
        skippedFields: ['energyScore', 'moodState', 'recoveryStatus', 'availableTime'],
      );

      final reconstructed = CheckIn.fromMap(original.toMap());
      expect(reconstructed.id, original.id);
      expect(reconstructed.date, original.date);
      expect(reconstructed.energyScore, isNull);
      expect(reconstructed.moodState, isNull);
      expect(reconstructed.recoveryStatus, isNull);
      expect(reconstructed.availableTime, isNull);
      expect(reconstructed.skippedFields, original.skippedFields);
    });
  });
}
