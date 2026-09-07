import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/sync_operation.dart';

void main() {
  group('SyncOperationType', () {
    test('toValue returns correct string for each type', () {
      expect(SyncOperationType.toggleAction.toValue(), 'toggle_action');
      expect(SyncOperationType.saveCheckin.toValue(), 'save_checkin');
      expect(SyncOperationType.savePlan.toValue(), 'save_plan');
      expect(SyncOperationType.saveIntention.toValue(), 'save_intention');
    });

    test('fromValue returns correct enum for each string', () {
      expect(SyncOperationType.fromValue('toggle_action'), SyncOperationType.toggleAction);
      expect(SyncOperationType.fromValue('save_checkin'), SyncOperationType.saveCheckin);
      expect(SyncOperationType.fromValue('save_plan'), SyncOperationType.savePlan);
      expect(SyncOperationType.fromValue('save_intention'), SyncOperationType.saveIntention);
    });

    test('fromValue throws on unknown value', () {
      expect(
        () => SyncOperationType.fromValue('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SyncOperation', () {
    test('constructor generates UUID when id is not provided', () {
      final op = SyncOperation(
        type: SyncOperationType.toggleAction,
        payload: {'actionId': 'abc123'},
      );
      expect(op.id, isNotEmpty);
      // UUID v4 format: 8-4-4-4-12 hex chars
      expect(op.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('constructor uses provided id', () {
      final op = SyncOperation(
        id: 'custom-id',
        type: SyncOperationType.savePlan,
        payload: {},
      );
      expect(op.id, 'custom-id');
    });

    test('constructor defaults retryCount to 0', () {
      final op = SyncOperation(
        type: SyncOperationType.saveCheckin,
        payload: {},
      );
      expect(op.retryCount, 0);
    });

    test('constructor defaults createdAt to now', () {
      final before = DateTime.now();
      final op = SyncOperation(
        type: SyncOperationType.saveCheckin,
        payload: {},
      );
      final after = DateTime.now();
      expect(op.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(op.createdAt.isBefore(after.add(const Duration(seconds: 1))), true);
    });

    test('toMap produces correct map', () {
      final createdAt = DateTime(2024, 6, 15, 10, 30, 0);
      final op = SyncOperation(
        id: 'test-id',
        type: SyncOperationType.toggleAction,
        payload: {'actionId': 'action1', 'completed': true},
        createdAt: createdAt,
        retryCount: 2,
      );

      final map = op.toMap();
      expect(map['id'], 'test-id');
      expect(map['type'], 'toggle_action');
      expect(map['payload'], {'actionId': 'action1', 'completed': true});
      expect(map['createdAt'], '2024-06-15T10:30:00.000');
      expect(map['retryCount'], 2);
    });

    test('fromMap reconstructs SyncOperation correctly', () {
      final map = {
        'id': 'test-id',
        'type': 'save_intention',
        'payload': {'intentionId': 'int1', 'isActive': false},
        'createdAt': '2024-06-15T10:30:00.000',
        'retryCount': 1,
      };

      final op = SyncOperation.fromMap(map);
      expect(op.id, 'test-id');
      expect(op.type, SyncOperationType.saveIntention);
      expect(op.payload, {'intentionId': 'int1', 'isActive': false});
      expect(op.createdAt, DateTime(2024, 6, 15, 10, 30, 0));
      expect(op.retryCount, 1);
    });

    test('fromMap defaults retryCount to 0 when missing', () {
      final map = {
        'id': 'test-id',
        'type': 'save_plan',
        'payload': {},
        'createdAt': '2024-06-15T10:30:00.000',
      };

      final op = SyncOperation.fromMap(map);
      expect(op.retryCount, 0);
    });

    test('fromMap defaults payload to empty map when null', () {
      final map = {
        'id': 'test-id',
        'type': 'save_checkin',
        'payload': null,
        'createdAt': '2024-06-15T10:30:00.000',
        'retryCount': 0,
      };

      final op = SyncOperation.fromMap(map);
      expect(op.payload, isEmpty);
    });

    test('toMap and fromMap are symmetric', () {
      final original = SyncOperation(
        id: 'round-trip-id',
        type: SyncOperationType.saveCheckin,
        payload: {'energyScore': 4, 'mood': 'calm'},
        createdAt: DateTime(2024, 3, 20, 8, 0, 0),
        retryCount: 1,
      );

      final reconstructed = SyncOperation.fromMap(original.toMap());
      expect(reconstructed.id, original.id);
      expect(reconstructed.type, original.type);
      expect(reconstructed.payload, original.payload);
      expect(reconstructed.createdAt, original.createdAt);
      expect(reconstructed.retryCount, original.retryCount);
    });

    test('copyWith updates retryCount', () {
      final op = SyncOperation(
        id: 'copy-id',
        type: SyncOperationType.toggleAction,
        payload: {'actionId': 'a1'},
        retryCount: 0,
      );

      final updated = op.copyWith(retryCount: 2);
      expect(updated.retryCount, 2);
      expect(updated.id, op.id);
      expect(updated.type, op.type);
      expect(updated.payload, op.payload);
      expect(updated.createdAt, op.createdAt);
    });

    test('copyWith without arguments returns equivalent object', () {
      final op = SyncOperation(
        id: 'copy-id',
        type: SyncOperationType.savePlan,
        payload: {'planId': 'p1'},
        retryCount: 1,
      );

      final copy = op.copyWith();
      expect(copy.id, op.id);
      expect(copy.type, op.type);
      expect(copy.payload, op.payload);
      expect(copy.createdAt, op.createdAt);
      expect(copy.retryCount, op.retryCount);
    });
  });
}
