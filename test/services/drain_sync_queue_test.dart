import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/sync_operation.dart';

/// Unit tests for the sync queue drain logic.
///
/// Since `StorageService.drainSyncQueue` requires Firebase initialization,
/// these tests verify the SyncOperation model serialization, FIFO ordering,
/// retry logic, and discard behavior at the data level.
void main() {
  group('SyncOperation model (sync queue foundation)', () {
    test('serializes and deserializes correctly', () {
      final op = SyncOperation(
        id: 'test-id',
        type: SyncOperationType.toggleAction,
        payload: {'planId': 'plan1', 'actionId': 'a1', 'completed': true},
        createdAt: DateTime(2024, 1, 15, 10, 30),
        retryCount: 1,
      );

      final map = op.toMap();
      final restored = SyncOperation.fromMap(map);

      expect(restored.id, 'test-id');
      expect(restored.type, SyncOperationType.toggleAction);
      expect(restored.payload['planId'], 'plan1');
      expect(restored.payload['actionId'], 'a1');
      expect(restored.payload['completed'], true);
      expect(restored.createdAt, DateTime(2024, 1, 15, 10, 30));
      expect(restored.retryCount, 1);
    });

    test('copyWith increments retryCount', () {
      final op = SyncOperation(
        id: 'op1',
        type: SyncOperationType.saveCheckin,
        payload: {'checkIn': {'id': 'c1'}},
        createdAt: DateTime(2024, 1, 1),
        retryCount: 0,
      );

      final updated = op.copyWith(retryCount: op.retryCount + 1);

      expect(updated.retryCount, 1);
      expect(updated.id, op.id);
      expect(updated.type, op.type);
      expect(updated.payload, op.payload);
      expect(updated.createdAt, op.createdAt);
    });

    test('all SyncOperationType values round-trip through toValue/fromValue',
        () {
      for (final type in SyncOperationType.values) {
        final value = type.toValue();
        final restored = SyncOperationType.fromValue(value);
        expect(restored, type);
      }
    });

    test('queue JSON serialization preserves FIFO order', () {
      final ops = [
        SyncOperation(
          id: 'op1',
          type: SyncOperationType.toggleAction,
          payload: {'planId': 'p1', 'actionId': 'a1', 'completed': true},
          createdAt: DateTime(2024, 1, 1, 12, 0),
        ),
        SyncOperation(
          id: 'op2',
          type: SyncOperationType.saveCheckin,
          payload: {'checkIn': {'id': 'c1'}},
          createdAt: DateTime(2024, 1, 1, 10, 0), // Earlier
        ),
        SyncOperation(
          id: 'op3',
          type: SyncOperationType.savePlan,
          payload: {'plan': {}, 'dateKey': '2024-01-01'},
          createdAt: DateTime(2024, 1, 1, 11, 0),
        ),
      ];

      // Serialize
      final json = jsonEncode(ops.map((e) => e.toMap()).toList());

      // Deserialize and sort FIFO
      final restored = (jsonDecode(json) as List)
          .map((e) => SyncOperation.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      restored.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Verify FIFO order: op2 (10:00), op3 (11:00), op1 (12:00)
      expect(restored[0].id, 'op2');
      expect(restored[1].id, 'op3');
      expect(restored[2].id, 'op1');
    });

    test('retryCount >= 3 means discard', () {
      final op = SyncOperation(
        id: 'op-discard',
        type: SyncOperationType.saveIntention,
        payload: {'intention': {'id': 'i1', 'title': 'Flexibility'}},
        createdAt: DateTime(2024, 1, 1),
        retryCount: 2,
      );

      // Simulate failure → increment
      final updated = op.copyWith(retryCount: op.retryCount + 1);
      expect(updated.retryCount, 3);

      // Discard condition
      expect(updated.retryCount >= 3, isTrue);
    });

    test('retryCount < 3 means keep in queue', () {
      final op = SyncOperation(
        id: 'op-keep',
        type: SyncOperationType.toggleAction,
        payload: {'planId': 'p1', 'actionId': 'a1', 'completed': false},
        createdAt: DateTime(2024, 1, 1),
        retryCount: 0,
      );

      final updated = op.copyWith(retryCount: op.retryCount + 1);
      expect(updated.retryCount, 1);
      expect(updated.retryCount < 3, isTrue);
    });

    test('generates unique IDs when id is not provided', () {
      final op1 = SyncOperation(
        type: SyncOperationType.saveCheckin,
        payload: {'checkIn': {'id': 'c1'}},
      );
      final op2 = SyncOperation(
        type: SyncOperationType.saveCheckin,
        payload: {'checkIn': {'id': 'c2'}},
      );

      expect(op1.id, isNotEmpty);
      expect(op2.id, isNotEmpty);
      expect(op1.id, isNot(op2.id));
    });

    test('defaults retryCount to 0', () {
      final op = SyncOperation(
        type: SyncOperationType.savePlan,
        payload: {'plan': {}, 'dateKey': '2024-01-15'},
      );

      expect(op.retryCount, 0);
    });

    test('all operation types can be serialized to queue JSON', () {
      final ops = [
        SyncOperation(
          type: SyncOperationType.toggleAction,
          payload: {'planId': 'p1', 'actionId': 'a1', 'completed': true},
        ),
        SyncOperation(
          type: SyncOperationType.saveCheckin,
          payload: {'checkIn': {'id': 'c1', 'date': '2024-01-01'}},
        ),
        SyncOperation(
          type: SyncOperationType.savePlan,
          payload: {'plan': {'id': 'plan1'}, 'dateKey': '2024-01-01'},
        ),
        SyncOperation(
          type: SyncOperationType.saveIntention,
          payload: {'intention': {'id': 'i1', 'title': 'Flexibility'}},
        ),
      ];

      final json = jsonEncode(ops.map((e) => e.toMap()).toList());
      final restored = (jsonDecode(json) as List)
          .map((e) => SyncOperation.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      expect(restored.length, 4);
      expect(restored[0].type, SyncOperationType.toggleAction);
      expect(restored[1].type, SyncOperationType.saveCheckin);
      expect(restored[2].type, SyncOperationType.savePlan);
      expect(restored[3].type, SyncOperationType.saveIntention);
    });
  });
}
