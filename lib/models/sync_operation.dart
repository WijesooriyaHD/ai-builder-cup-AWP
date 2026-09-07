import 'package:uuid/uuid.dart';

/// The type of sync operation queued for offline-first processing.
enum SyncOperationType {
  toggleAction,
  saveCheckin,
  savePlan,
  saveIntention;

  String toValue() {
    switch (this) {
      case SyncOperationType.toggleAction:
        return 'toggle_action';
      case SyncOperationType.saveCheckin:
        return 'save_checkin';
      case SyncOperationType.savePlan:
        return 'save_plan';
      case SyncOperationType.saveIntention:
        return 'save_intention';
    }
  }

  static SyncOperationType fromValue(String value) {
    switch (value) {
      case 'toggle_action':
        return SyncOperationType.toggleAction;
      case 'save_checkin':
        return SyncOperationType.saveCheckin;
      case 'save_plan':
        return SyncOperationType.savePlan;
      case 'save_intention':
        return SyncOperationType.saveIntention;
      default:
        throw ArgumentError('Unknown SyncOperationType value: $value');
    }
  }
}

/// Represents a queued sync operation for offline-first behavior.
///
/// When the device is offline, operations are stored locally and
/// processed in FIFO order when connectivity is restored.
class SyncOperation {
  final String id;
  final SyncOperationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;

  SyncOperation({
    String? id,
    required this.type,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.toValue(),
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      id: map['id'],
      type: SyncOperationType.fromValue(map['type']),
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
      createdAt: DateTime.parse(map['createdAt']),
      retryCount: map['retryCount'] ?? 0,
    );
  }

  SyncOperation copyWith({
    int? retryCount,
  }) {
    return SyncOperation(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
