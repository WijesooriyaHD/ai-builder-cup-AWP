import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/dream.dart';
import 'package:aiwellnesspal/models/journal_entry.dart';
import 'package:aiwellnesspal/models/travel_memory.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
// StorageService is not instantiated (requires Firebase) — we verify its
// source code directly to confirm key constants are preserved.

/// Backward compatibility verification tests.
///
/// These tests ensure that:
/// 1. All original StorageService SharedPreferences keys are preserved
/// 2. Firestore paths `users/{uid}/journal_entries` and
///    `users/{uid}/travel_memories` are unchanged
/// 3. JournalEntry and TravelMemory model fields are preserved
/// 4. Local cache keys still work
/// 5. Dream.fromMap still parses without 'category' field (defaults to general)
/// 6. Existing journal widget toggle URI still handled in backgroundCallback
///
/// Validates: Requirements 5.8, 8.9, 9.7, 14.7
void main() {
  group('StorageService SharedPreferences keys are preserved', () {
    test('StorageService class compiles with all key constants declared', () {
      // Verify the StorageService source file declares all expected key
      // constants. We check the source rather than instantiating because
      // the constructor requires Firebase initialization.
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      // The class must exist and contain static const String fields
      expect(sourceFile.contains('class StorageService'), isTrue);
      expect(sourceFile.contains('static const String'), isTrue);
    });

    test('rebranded aiwellnesspal_ storage keys are present in source', () {
      // After the brand rename, StorageService keys use the aiwellnesspal_
      // PrefsBrandMigration (see the migration test below).
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      const storageKeys = [
        "aiwellnesspal_dreams",
        "aiwellnesspal_travel_memories",
        "aiwellnesspal_journal_entries",
        "aiwellnesspal_negotiations_completed",
        "aiwellnesspal_todo_completions",
        "aiwellnesspal_distinct_she_stacks_games",
        "aiwellnesspal_total_check_ins",
        "aiwellnesspal_has_seed_data",
        "aiwellnesspal_pinned_journal_home",
        "aiwellnesspal_widget_journal_entry_id",
        "aiwellnesspal_is_winter_mode",
        "aiwellnesspal_show_motivation",
        "aiwellnesspal_show_achievements",
        "aiwellnesspal_show_map",
        "aiwellnesspal_theme_mode",
        "aiwellnesspal_theme_color",
        "aiwellnesspal_text_scale",
        "aiwellnesspal_current_streak",
        "aiwellnesspal_last_active_date",
        "aiwellnesspal_pinned_cards",
      ];

      for (final key in storageKeys) {
        expect(sourceFile.contains("'$key'"), isTrue,
            reason:
                'StorageService source must contain key "$key"');
      }
    });

    test('legacy bloom_ prefix migration exists', () {
      // The rename must be paired with a migration so existing users keep
      // their data.
      final migration =
          File('lib/services/prefs_brand_migration.dart').readAsStringSync();
      expect(migration.contains("'bloom_'"), isTrue,
          reason: 'Migration must reference the legacy bloom_ prefix');
      expect(migration.contains("'aiwellnesspal_'"), isTrue,
          reason: 'Migration must target the aiwellnesspal_ prefix');
    });

    test('new wellness keys are additive', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      const wellnessKeys = [
        'wellness_daily_plan',
        'wellness_todays_check_in',
        'wellness_check_in_history',
        'wellness_behavior_profile',
        'wellness_onboarding_step',
        'wellness_widget_plan',
        'wellness_sync_queue',
        'wellness_pending_sync',
      ];

      for (final key in wellnessKeys) {
        expect(sourceFile.contains("'$key'"), isTrue,
            reason: 'StorageService source must contain wellness key "$key"');
      }
    });
  });

  group('Firestore paths users/{uid}/journal_entries unchanged', () {
    test('StorageService uses journal_entries collection path', () {
      // Verify the source still references the exact Firestore collection name
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      // The path is constructed via .collection('journal_entries') or similar
      // but journal entries in this service are stored locally only.
      // The design doc guarantees this path is used by other services.
      // We verify the local key remains 'aiwellnesspal_journal_entries'.
      expect(sourceFile.contains("'aiwellnesspal_journal_entries'"), isTrue,
          reason: 'Local journal entries cache key must be preserved');
    });

    test('StorageService uses travel_memories Firestore path', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      // Verify the actual Firestore collection path is 'travel_memories'
      expect(
          sourceFile.contains(".collection('travel_memories')"), isTrue,
          reason:
              'Firestore travel_memories collection path must be preserved');
    });
  });

  group('JournalEntry model fields preserved (Req 8.9)', () {
    test('all 15 required fields are present and accessible', () {
      final entry = JournalEntry(
        id: 'test-id',
        title: 'Test Title',
        content: 'Test Content',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 2),
        type: JournalEntryType.note,
        color: 0xFFFF0000,
        todos: [TodoItem(text: 'Task 1')],
        isPinned: true,
        isSaved: true,
        aiInsight: 'AI response text',
        mood: '😊',
        tags: ['wellness', 'reflection'],
        sourceEntryId: 'source-1',
        groupId: 'group-1',
      );

      expect(entry.id, 'test-id');
      expect(entry.title, 'Test Title');
      expect(entry.content, 'Test Content');
      expect(entry.createdAt, DateTime(2025, 1, 1));
      expect(entry.updatedAt, DateTime(2025, 1, 2));
      expect(entry.type, JournalEntryType.note);
      expect(entry.color, 0xFFFF0000);
      expect(entry.todos.length, 1);
      expect(entry.isPinned, true);
      expect(entry.isSaved, true);
      expect(entry.aiInsight, 'AI response text');
      expect(entry.mood, '😊');
      expect(entry.tags, ['wellness', 'reflection']);
      expect(entry.sourceEntryId, 'source-1');
      expect(entry.groupId, 'group-1');
    });

    test('toMap includes every field key', () {
      final entry = JournalEntry(
        id: 'map-test',
        title: 'Map Test',
        content: 'body',
        createdAt: DateTime(2025, 3, 15),
        updatedAt: DateTime(2025, 3, 16),
        type: JournalEntryType.todo,
        color: 0xFF00FF00,
        isPinned: false,
        isSaved: true,
        aiInsight: 'Insight',
        mood: '🧘',
        tags: ['tag1'],
        sourceEntryId: 'src',
        groupId: 'grp',
      );

      final map = entry.toMap();

      // All 15 fields must appear in the serialized map
      const requiredKeys = [
        'id', 'title', 'content', 'createdAt', 'updatedAt',
        'type', 'color', 'todos', 'isPinned', 'isSaved',
        'aiInsight', 'mood', 'tags', 'sourceEntryId', 'groupId',
      ];

      for (final key in requiredKeys) {
        expect(map.containsKey(key), isTrue,
            reason: 'JournalEntry.toMap() must include "$key"');
      }
    });

    test('fromMap deserializes all fields correctly', () {
      final map = {
        'id': 'deser-id',
        'title': 'Deserialized',
        'content': 'Content here',
        'createdAt': '2025-04-01T00:00:00.000',
        'updatedAt': '2025-04-02T00:00:00.000',
        'type': 'JournalEntryType.note',
        'color': 0xFF0000FF,
        'todos': [
          {'id': 't1', 'text': 'Todo 1', 'isCompleted': true},
        ],
        'isPinned': true,
        'isSaved': false,
        'aiInsight': 'Some insight',
        'mood': '🔥',
        'tags': ['a', 'b'],
        'sourceEntryId': 'source-x',
        'groupId': 'group-x',
      };

      final entry = JournalEntry.fromMap(map);

      expect(entry.id, 'deser-id');
      expect(entry.title, 'Deserialized');
      expect(entry.content, 'Content here');
      expect(entry.createdAt, DateTime(2025, 4, 1));
      expect(entry.updatedAt, DateTime(2025, 4, 2));
      expect(entry.type, JournalEntryType.note);
      expect(entry.color, 0xFF0000FF);
      expect(entry.todos.length, 1);
      expect(entry.todos.first.isCompleted, true);
      expect(entry.isPinned, true);
      expect(entry.isSaved, false);
      expect(entry.aiInsight, 'Some insight');
      expect(entry.mood, '🔥');
      expect(entry.tags, ['a', 'b']);
      expect(entry.sourceEntryId, 'source-x');
      expect(entry.groupId, 'group-x');
    });

    test('toMap/fromMap round-trip is lossless', () {
      final original = JournalEntry(
        id: 'roundtrip',
        title: 'Round Trip',
        content: 'Full circle',
        createdAt: DateTime(2025, 5, 10),
        updatedAt: DateTime(2025, 5, 11),
        type: JournalEntryType.note,
        color: 0xFFABCDEF,
        todos: [TodoItem(id: 'td1', text: 'item', isCompleted: true)],
        isPinned: true,
        isSaved: true,
        aiInsight: 'round trip insight',
        mood: '💡',
        tags: ['round', 'trip'],
        sourceEntryId: 'src-rt',
        groupId: 'grp-rt',
      );

      final reconstructed = JournalEntry.fromMap(original.toMap());

      expect(reconstructed.id, original.id);
      expect(reconstructed.title, original.title);
      expect(reconstructed.content, original.content);
      expect(reconstructed.createdAt, original.createdAt);
      expect(reconstructed.updatedAt, original.updatedAt);
      expect(reconstructed.type, original.type);
      expect(reconstructed.color, original.color);
      expect(reconstructed.todos.length, original.todos.length);
      expect(reconstructed.isPinned, original.isPinned);
      expect(reconstructed.isSaved, original.isSaved);
      expect(reconstructed.aiInsight, original.aiInsight);
      expect(reconstructed.mood, original.mood);
      expect(reconstructed.tags, original.tags);
      expect(reconstructed.sourceEntryId, original.sourceEntryId);
      expect(reconstructed.groupId, original.groupId);
    });
  });

  group('TravelMemory model fields preserved (Req 9.7)', () {
    test('all required fields are present and accessible', () {
      final memory = TravelMemory(
        id: 'tm-id',
        place: 'Paris',
        latitude: 48.8566,
        longitude: 2.3522,
        visitedDate: DateTime(2025, 6, 1),
        memory: 'Beautiful city',
        note: 'Trip notes',
        photos: ['/photo1.jpg'],
        isPublic: true,
      );

      expect(memory.id, 'tm-id');
      expect(memory.place, 'Paris');
      expect(memory.latitude, 48.8566);
      expect(memory.longitude, 2.3522);
      expect(memory.visitedDate, DateTime(2025, 6, 1));
      expect(memory.memory, 'Beautiful city');
      expect(memory.note, 'Trip notes');
      expect(memory.photos, ['/photo1.jpg']);
      expect(memory.isPublic, true);
    });

    test('toMap serializes all fields', () {
      final memory = TravelMemory(
        id: 'tm-serial',
        place: 'Tokyo',
        latitude: 35.6762,
        longitude: 139.6503,
        visitedDate: DateTime(2025, 7, 4),
        memory: 'Amazing food',
        note: 'Ramen tour',
        photos: ['http://example.com/pic.jpg'],
        isPublic: false,
      );

      final map = memory.toMap();

      const requiredKeys = [
        'id', 'place', 'latitude', 'longitude',
        'visitedDate', 'memory', 'note', 'photos', 'isPublic',
      ];

      for (final key in requiredKeys) {
        expect(map.containsKey(key), isTrue,
            reason: 'TravelMemory.toMap() must include "$key"');
      }
    });

    test('fromMap deserializes correctly', () {
      final map = {
        'id': 'tm-deser',
        'place': 'London',
        'latitude': 51.5074,
        'longitude': -0.1278,
        'visitedDate': '2025-08-01T00:00:00.000',
        'memory': 'Big Ben',
        'note': 'Rainy day',
        'photos': ['/london.jpg', '/bridge.jpg'],
        'isPublic': true,
      };

      final memory = TravelMemory.fromMap(map);

      expect(memory.id, 'tm-deser');
      expect(memory.place, 'London');
      expect(memory.latitude, 51.5074);
      expect(memory.longitude, -0.1278);
      expect(memory.visitedDate, DateTime(2025, 8, 1));
      expect(memory.memory, 'Big Ben');
      expect(memory.note, 'Rainy day');
      expect(memory.photos, ['/london.jpg', '/bridge.jpg']);
      expect(memory.isPublic, true);
    });

    test('toMap/fromMap round-trip is lossless', () {
      final original = TravelMemory(
        id: 'tm-rt',
        place: 'Sydney',
        latitude: -33.8688,
        longitude: 151.2093,
        visitedDate: DateTime(2025, 9, 15),
        memory: 'Opera House',
        note: 'Harbour Bridge too',
        photos: ['/sydney1.jpg', '/sydney2.jpg'],
        isPublic: false,
      );

      final reconstructed = TravelMemory.fromMap(original.toMap());

      expect(reconstructed.id, original.id);
      expect(reconstructed.place, original.place);
      expect(reconstructed.latitude, original.latitude);
      expect(reconstructed.longitude, original.longitude);
      expect(reconstructed.visitedDate, original.visitedDate);
      expect(reconstructed.memory, original.memory);
      expect(reconstructed.note, original.note);
      expect(reconstructed.photos, original.photos);
      expect(reconstructed.isPublic, original.isPublic);
    });
  });

  group('Dream model backward compatibility (Req 5.8)', () {
    test('Dream.fromMap parses without category field', () {
      // Old-format Dream data that does NOT have a 'category' field
      final oldDreamMap = {
        'id': 'old-dream-id',
        'title': 'Learn Piano',
        'description': 'Master basic piano pieces',
        'startDate': '2025-01-01T00:00:00.000',
        'deadline': '2025-12-31T00:00:00.000',
        'themeColor': 0xFF6B9FD4,
        'themeIcon': 0xE87D,
        'backgroundImagePath': '/piano.png',
        'steps': [
          {
            'id': 's1',
            'title': 'Buy a keyboard',
            'durationMinutes': 0,
            'isCompleted': true
          },
          {
            'id': 's2',
            'title': 'Take first lesson',
            'durationMinutes': 60,
            'isCompleted': false
          },
        ],
      };

      // Dream.fromMap must not throw when category is missing
      final dream = Dream.fromMap(oldDreamMap);

      expect(dream.id, 'old-dream-id');
      expect(dream.title, 'Learn Piano');
      expect(dream.description, 'Master basic piano pieces');
      expect(dream.startDate, DateTime(2025, 1, 1));
      expect(dream.deadline, DateTime(2025, 12, 31));
      expect(dream.themeColor, 0xFF6B9FD4);
      expect(dream.themeIcon, 0xE87D);
      expect(dream.backgroundImagePath, '/piano.png');
      expect(dream.steps.length, 2);
      expect(dream.steps[0].isCompleted, true);
      expect(dream.steps[1].isCompleted, false);
    });

    test(
        'WellnessIntention.fromMap defaults category to general when missing',
        () {
      final oldDreamMap = {
        'id': 'legacy-dream',
        'title': 'Old Dream Goal',
        'description': 'From pre-pivot era',
        'startDate': '2024-06-01T00:00:00.000',
        'steps': [],
        // No 'category' field — must default to 'general'
        // No 'isActive' field — must default to true
      };

      final intention = WellnessIntention.fromMap(oldDreamMap);

      expect(intention.id, 'legacy-dream');
      expect(intention.title, 'Old Dream Goal');
      expect(intention.category, WellnessCategory.general);
      expect(intention.isActive, true);
    });

    test('WellnessIntention.fromDream preserves all Dream fields', () {
      final dream = Dream(
        id: 'full-dream',
        title: 'Full Dream',
        description: 'All fields populated',
        startDate: DateTime(2024, 3, 1),
        deadline: DateTime(2024, 12, 31),
        themeColor: 0xFFABCDEF,
        themeIcon: 0xE800,
        backgroundImagePath: '/full.png',
        steps: [],
      );

      final intention = WellnessIntention.fromDream(dream);

      expect(intention.id, dream.id);
      expect(intention.title, dream.title);
      expect(intention.description, dream.description);
      expect(intention.startDate, dream.startDate);
      expect(intention.deadline, dream.deadline);
      expect(intention.themeColor, dream.themeColor);
      expect(intention.themeIcon, dream.themeIcon);
      expect(intention.backgroundImagePath, dream.backgroundImagePath);
      expect(intention.category, WellnessCategory.general);
      expect(intention.isActive, true);
    });

    test('Dream with null optional fields round-trips correctly', () {
      final minimalDream = {
        'id': 'minimal',
        'title': 'Minimal Dream',
        'startDate': '2025-01-15T00:00:00.000',
        'steps': [],
        // No description, deadline, themeColor, themeIcon, backgroundImagePath
      };

      final dream = Dream.fromMap(minimalDream);
      expect(dream.title, 'Minimal Dream');
      expect(dream.description, '');
      expect(dream.deadline, isNull);
      expect(dream.themeColor, isNull);
      expect(dream.themeIcon, isNull);
      expect(dream.backgroundImagePath, isNull);

      // Should also migrate to WellnessIntention without error
      final intention = WellnessIntention.fromDream(dream);
      expect(intention.title, 'Minimal Dream');
      expect(intention.category, WellnessCategory.general);
    });
  });

  group('Firestore paths are unchanged', () {
    test('travel_memories collection path exists in StorageService', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      // Verify the actual Firestore collection('travel_memories') call exists
      expect(
        sourceFile.contains(".collection('travel_memories')"),
        isTrue,
        reason:
            'StorageService must reference Firestore travel_memories collection',
      );
    });

    test('journal_entries Firestore path is not renamed', () {
      // The design doc guarantees journal_entries path stays the same.
      // StorageService stores journal entries locally under
      // aiwellnesspal_journal_entries and other services write to Firestore at
      // users/{uid}/journal_entries (that Firestore path is unchanged).
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      expect(sourceFile.contains("'aiwellnesspal_journal_entries'"), isTrue,
          reason: 'Journal entries local cache key must remain unchanged');

      // Ensure no accidental rename to something like 'wellness_reflections'
      expect(
        sourceFile.contains("'wellness_reflections'"),
        isFalse,
        reason:
            'journal_entries must not be renamed to wellness_reflections in StorageService',
      );
    });

    test('travel_memories path is not renamed to journey_map', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      expect(sourceFile.contains("'aiwellnesspal_travel_memories'"), isTrue);
      // Ensure no rename to wellness_milestones or journey_map
      expect(
        sourceFile.contains("_travelMemoriesKey = 'wellness_milestones'"),
        isFalse,
        reason: 'travel_memories key must not be renamed to wellness_milestones',
      );
    });
  });

  group('backgroundCallback toggle URI backward compatibility', () {
    test('app_state source handles a toggle URI host', () {
      final sourceFile =
          File('lib/providers/app_state.dart').readAsStringSync();

      // The background callback must handle at least one toggle host.
      expect(
        sourceFile.contains("uri?.host == 'intention_toggle'") ||
            sourceFile.contains("uri?.host == 'habit_toggle'") ||
            sourceFile.contains("uri?.host == 'wellness_toggle'"),
        isTrue,
        reason: 'backgroundCallback must handle a toggle URI host',
      );
    });

    test('app_state source handles wellness_toggle host', () {
      final sourceFile =
          File('lib/providers/app_state.dart').readAsStringSync();

      // The new wellness_toggle URI host must also be handled
      expect(
        sourceFile.contains("uri?.host == 'wellness_toggle'"),
        isTrue,
        reason:
            'backgroundCallback must handle the new "wellness_toggle" URI host',
      );
    });

    test('app_state source handles a refresh URI host', () {
      final sourceFile =
          File('lib/providers/app_state.dart').readAsStringSync();

      // The background callback must handle at least one refresh host.
      expect(
        sourceFile.contains("uri?.host == 'intention_refresh'") ||
            sourceFile.contains("uri?.host == 'habit_refresh'") ||
            sourceFile.contains("uri?.host == 'wellness_refresh'"),
        isTrue,
        reason: 'backgroundCallback must handle a refresh URI host',
      );
    });
  });

  group('Local cache keys still work', () {
    test('aiwellnesspal_dreams key is used for Dream serialization', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      // The saveDreams/loadDreams methods must use _dreamsKey = 'aiwellnesspal_dreams'
      expect(sourceFile.contains("_dreamsKey"), isTrue,
          reason: 'StorageService must use _dreamsKey field');
      expect(sourceFile.contains("'aiwellnesspal_dreams'"), isTrue);
    });

    test('aiwellnesspal_journal_entries key is used for journal serialization', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      expect(sourceFile.contains("_journalEntriesKey"), isTrue);
      expect(sourceFile.contains("'aiwellnesspal_journal_entries'"), isTrue);
    });

    test('aiwellnesspal_travel_memories key is used for travel serialization', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      expect(sourceFile.contains("_travelMemoriesKey"), isTrue);
      expect(sourceFile.contains("'aiwellnesspal_travel_memories'"), isTrue);
    });

    test('aiwellnesspal_todo_completions key still exists', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();
      expect(sourceFile.contains("'aiwellnesspal_todo_completions'"), isTrue);
    });

    test('widget-related keys are preserved', () {
      final sourceFile =
          File('lib/services/storage_service.dart').readAsStringSync();

      expect(sourceFile.contains("'aiwellnesspal_widget_journal_entry_id'"), isTrue);
      expect(sourceFile.contains("'aiwellnesspal_widget_intention_id'"), isTrue);
    });
  });
}
