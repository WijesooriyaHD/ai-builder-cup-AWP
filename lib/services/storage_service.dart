import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path/path.dart' as p;
import '../models/dream.dart';
import '../models/travel_memory.dart';
import '../models/journal_entry.dart';
import '../models/sync_operation.dart';
import '../models/period_data.dart';
import '../models/weight_data.dart';

class StorageService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // SharedPreferences keys (unchanged — local storage keys stay the same)
  static const String _dreamsKey = 'bloom_dreams';
  static const String _travelMemoriesKey = 'bloom_travel_memories';
  static const String _journalEntriesKey = 'bloom_journal_entries';
  static const String _gardenKey = 'bloom_garden_state';
  static const String _negotiationsCompletedKey = 'bloom_negotiations_completed';
  static const String _todoCompletionsKey = 'bloom_todo_completions';
  static const String _distinctGamesKey = 'bloom_distinct_she_stacks_games';
  static const String _totalCheckInsKey = 'bloom_total_check_ins';
  static const String _hasSeedDataKey = 'bloom_has_seed_data';
  static const String _pinnedJournalHomeKey = 'bloom_pinned_journal_home';
  static const String _widgetJournalEntryIdKey = 'bloom_widget_journal_entry_id';
  static const String _widgetIntentionIdKey = 'bloom_widget_intention_id';
  static const String _isWinterModeKey = 'bloom_is_winter_mode';
  static const String _showDailyMotivationKey = 'bloom_show_motivation';
  static const String _showGardenKey = 'bloom_show_garden';
  static const String _showAchievementsKey = 'bloom_show_achievements';
  static const String _showMapKey = 'bloom_show_map';
  static const String _themeModeKey = 'bloom_theme_mode';
  static const String _themeColorKey = 'bloom_theme_color';
  static const String _textScaleKey = 'bloom_text_scale';
  static const String _currentStreakKey = 'bloom_current_streak';
  static const String _lastActiveDateKey = 'bloom_last_active_date';
  static const String _pinnedCardsKey = 'bloom_pinned_cards';
  static const String _aiVoiceKey = 'bloom_ai_voice';
  static const String _periodDataKey = 'bloom_period_data';
  static const String _weightDataKey = 'bloom_weight_data';

  // Wellness keys
  static const String _wellnessDailyPlanKey = 'wellness_daily_plan';
  static const String _wellnessTodaysCheckInKey = 'wellness_todays_check_in';
  static const String _wellnessCheckInHistoryKey = 'wellness_check_in_history';
  static const String _wellnessBehaviorProfileKey = 'wellness_behavior_profile';
  static const String _wellnessOnboardingStepKey = 'wellness_onboarding_step';
  static const String _wellnessWidgetPlanKey = 'wellness_widget_plan';
  static const String _wellnessSyncQueueKey = 'wellness_sync_queue';
  static const String _wellnessPendingSyncKey = 'wellness_pending_sync';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> get _getPrefs async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  User? get _currentUser => _auth.currentUser;

  // --- PHOTO UPLOAD (Firebase Storage) ---

  Future<String?> _uploadPhoto(String localPath) async {
    final user = _currentUser;
    if (user == null) return null;

    final file = File(localPath);
    if (!await file.exists()) return null;

    final fileName = p.basename(localPath);
    final path = 'travel-photos/${user.uid}/$fileName';

    try {
      final ref = _storage.ref(path);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Photo Upload Error: $e');
      return null;
    }
  }

  // --- DREAMS (local only) ---

  Future<void> saveDreams(List<Dream> dreams) async {
    final prefs = await _getPrefs;
    await prefs.setString(_dreamsKey, jsonEncode(dreams.map((e) => e.toMap()).toList()));
  }

  Future<List<Dream>> loadDreams() async {
    final prefs = await _getPrefs;
    final data = prefs.getString(_dreamsKey);
    if (data == null) return [];
    try {
      return (jsonDecode(data) as List).map((e) => Dream.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // --- TRAVEL MEMORIES (local + Firestore) ---

  Future<void> saveTravelMemories(List<TravelMemory> memories) async {
    final prefs = await _getPrefs;

    final updatedMemories = <TravelMemory>[];
    for (final memory in memories) {
      final updatedPhotos = <String>[];
      bool modified = false;
      for (final photo in memory.photos) {
        if (photo.startsWith('http')) {
          updatedPhotos.add(photo);
        } else {
          final url = await _uploadPhoto(photo);
          if (url != null) {
            updatedPhotos.add(url);
            modified = true;
          } else {
            updatedPhotos.add(photo);
          }
        }
      }
      updatedMemories.add(modified
          ? TravelMemory(
              id: memory.id,
              place: memory.place,
              latitude: memory.latitude,
              longitude: memory.longitude,
              visitedDate: memory.visitedDate,
              memory: memory.memory,
              note: memory.note,
              photos: updatedPhotos,
              isPublic: memory.isPublic,
            )
          : memory);
    }

    await prefs.setString(
        _travelMemoriesKey, jsonEncode(updatedMemories.map((e) => e.toMap()).toList()));

    final user = _currentUser;
    if (user != null) {
      try {
        final batch = _db.batch();
        for (final m in updatedMemories) {
          final ref = _db
              .collection('users')
              .doc(user.uid)
              .collection('travel_memories')
              .doc(m.id);
          batch.set(ref, {
            'id': m.id,
            'place': m.place,
            'latitude': m.latitude,
            'longitude': m.longitude,
            'visited_date': m.visitedDate.toIso8601String(),
            'memory': m.memory,
            'note': m.note,
            'photos': m.photos,
            'public': m.isPublic,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Firestore Travel Sync Error: $e');
        rethrow;
      }
    }
  }

  Future<List<TravelMemory>> loadTravelMemories({bool syncCloud = false}) async {
    final prefs = await _getPrefs;

    if (syncCloud) {
      final user = _currentUser;
      if (user != null) {
        try {
          final snapshot = await _db
              .collection('users')
              .doc(user.uid)
              .collection('travel_memories')
              .orderBy('visited_date')
              .get();

          if (snapshot.docs.isNotEmpty) {
            final memories = snapshot.docs.map((doc) {
              final m = doc.data();
              return TravelMemory(
                id: m['id'],
                place: m['place'],
                latitude: (m['latitude'] as num).toDouble(),
                longitude: (m['longitude'] as num).toDouble(),
                visitedDate: DateTime.parse(m['visited_date']),
                memory: m['memory'] ?? '',
                note: m['note'],
                photos: List<String>.from(m['photos'] ?? []),
                isPublic: m['public'] ?? false,
              );
            }).toList();

            await prefs.setString(_travelMemoriesKey,
                jsonEncode(memories.map((e) => e.toMap()).toList()));
            return memories;
          }
        } catch (e) {
          debugPrint('Firestore Travel Load Error: $e');
        }
      }
    }

    final localData = prefs.getString(_travelMemoriesKey);
    if (localData == null) return [];
    try {
      return (jsonDecode(localData) as List).map((e) => TravelMemory.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<TravelMemory>> fetchPublicMemories() async {
    try {
      final snapshot = await _db
          .collectionGroup('travel_memories')
          .where('public', isEqualTo: true)
          .orderBy('visited_date', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) {
        final m = doc.data();
        return TravelMemory(
          id: m['id'],
          place: m['place'],
          latitude: (m['latitude'] as num).toDouble(),
          longitude: (m['longitude'] as num).toDouble(),
          visitedDate: DateTime.parse(m['visited_date']),
          memory: m['memory'] ?? '',
          note: m['note'],
          photos: List<String>.from(m['photos'] ?? []),
          isPublic: true,
          userId: m['user_id'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Firestore Public Fetch Error: $e');
      return [];
    }
  }

  // --- JOURNAL (local only) ---

  Future<void> saveJournalEntries(List<JournalEntry> entries) async {
    final prefs = await _getPrefs;
    await prefs.setString(_journalEntriesKey,
        jsonEncode(entries.map((e) => e.toMap()).toList()));
  }

  Future<List<JournalEntry>> loadJournalEntries() async {
    final prefs = await _getPrefs;
    final data = prefs.getString(_journalEntriesKey);
    if (data == null) return [];
    try {
      return (jsonDecode(data) as List).map((e) => JournalEntry.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // --- SETTINGS (local + Firestore profile) ---

  Future<void> saveSettings({
    required int themeModeIndex,
    required int themeColorValue,
    required double textScale,
    bool? isWinterMode,
    bool? showMotivation,
    bool? showGarden,
    bool? showAchievements,
    bool? showMap,
    String? instagram,
    String? aiVoice,
    bool syncToCloud = true,
  }) async {
    final prefs = await _getPrefs;
    await prefs.setInt(_themeModeKey, themeModeIndex);
    await prefs.setInt(_themeColorKey, themeColorValue);
    await prefs.setDouble(_textScaleKey, textScale);
    if (isWinterMode != null) await prefs.setBool(_isWinterModeKey, isWinterMode);
    if (showMotivation != null) await prefs.setBool(_showDailyMotivationKey, showMotivation);
    if (showGarden != null) await prefs.setBool(_showGardenKey, showGarden);
    if (showAchievements != null) await prefs.setBool(_showAchievementsKey, showAchievements);
    if (showMap != null) await prefs.setBool(_showMapKey, showMap);
    if (instagram != null) await prefs.setString('bloom_instagram', instagram);
    if (aiVoice != null) await prefs.setString(_aiVoiceKey, aiVoice);

    // Skip the cloud write until the app has loaded authoritative cloud
    // settings, to avoid a pre-sync default overwriting them.
    if (!syncToCloud) {
      debugPrint('☁️ saveSettings: SKIPPING cloud write (syncToCloud=false)');
      return;
    }

    final user = _currentUser;
    debugPrint('☁️ saveSettings: cloud write, user=${user?.uid ?? "NULL"}, '
        'aiVoice=$aiVoice');
    if (user != null) {
      try {
        // Persist ALL user settings to Firestore so they survive logout/login
        // and sync across devices. Only include nullable fields when provided
        // so a partial save never nulls out a stored value.
        final data = <String, dynamic>{
          'theme_mode': themeModeIndex,
          'theme_color': themeColorValue,
          'text_scale': textScale,
          'display_name': user.displayName,
          'avatar_url': user.photoURL,
          'instagram': instagram,
          'ai_voice': aiVoice,
          'updated_at': FieldValue.serverTimestamp(),
        };
        if (isWinterMode != null) data['is_winter_mode'] = isWinterMode;
        if (showMotivation != null) data['show_motivation'] = showMotivation;
        if (showGarden != null) data['show_garden'] = showGarden;
        if (showAchievements != null) data['show_achievements'] = showAchievements;
        if (showMap != null) data['show_map'] = showMap;

        await _db
            .collection('users')
            .doc(user.uid)
            .set(data, SetOptions(merge: true));
        debugPrint('✅ saveSettings: Firestore write SUCCEEDED (aiVoice=$aiVoice)');
      } catch (e) {
        debugPrint('❌ Firestore Profile Sync Error: $e');
      }
    }
  }

  Future<void> syncProfile() async {
    final user = _currentUser;
    if (user != null) {
      try {
        await _db.collection('users').doc(user.uid).set({
          'display_name': user.displayName,
          'avatar_url': user.photoURL,
          'email': user.email,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Firestore profile synced');
      } catch (e) {
        debugPrint('❌ Firestore profile sync error: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> fetchFullProfile() async {
    final user = _currentUser;
    if (user == null) return null;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Firestore Full Profile Fetch Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      debugPrint('Firestore User Profile Fetch Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> loadSettings({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await _getPrefs;
    final settings = <String, dynamic>{
      'themeMode': prefs.getInt(_themeModeKey) ?? 0,
      'themeColor': prefs.getInt(_themeColorKey) ?? 0xFFFF7F50,
      'textScale': prefs.getDouble(_textScaleKey) ?? 1.0,
      'isWinterMode': prefs.getBool(_isWinterModeKey) ?? false,
      'showMotivation': prefs.getBool(_showDailyMotivationKey) ?? true,
      'showGarden': prefs.getBool(_showGardenKey) ?? true,
      'showAchievements': prefs.getBool(_showAchievementsKey) ?? true,
      'showMap': prefs.getBool(_showMapKey) ?? true,
      'instagram': prefs.getString('bloom_instagram'),
      'aiVoice': prefs.getString(_aiVoiceKey) ?? 'default',
    };

    if (cloudProfile != null) {
      settings['themeMode'] = cloudProfile['theme_mode'] ?? settings['themeMode'];
      settings['themeColor'] = cloudProfile['theme_color'] ?? settings['themeColor'];
      settings['textScale'] =
          (cloudProfile['text_scale'] as num?)?.toDouble() ?? settings['textScale'];
      settings['instagram'] = cloudProfile['instagram'] ?? settings['instagram'];
      settings['aiVoice'] = cloudProfile['ai_voice'] ?? settings['aiVoice'];
      settings['isWinterMode'] =
          cloudProfile['is_winter_mode'] ?? settings['isWinterMode'];
      settings['showMotivation'] =
          cloudProfile['show_motivation'] ?? settings['showMotivation'];
      settings['showGarden'] =
          cloudProfile['show_garden'] ?? settings['showGarden'];
      settings['showAchievements'] =
          cloudProfile['show_achievements'] ?? settings['showAchievements'];
      settings['showMap'] = cloudProfile['show_map'] ?? settings['showMap'];

      if (cloudProfile['unlocked_achievements'] != null) {
        final List<String> cloudUnlocked =
            List<String>.from(cloudProfile['unlocked_achievements']);
        await prefs.setString('unlocked_achievements', jsonEncode(cloudUnlocked));
      }
    }
    return settings;
  }

  // --- PERIOD TRACKER (local + Firestore user doc) ---

  /// Persists period-tracking data locally and, for signed-in users, to the
  /// Firestore user document so it survives logout/login and syncs devices.
  Future<void> savePeriodData(PeriodData data, {bool syncToCloud = true}) async {
    final prefs = await _getPrefs;
    await prefs.setString(_periodDataKey, data.toJson());

    if (!syncToCloud) return;
    final user = _currentUser;
    if (user != null) {
      try {
        await _db.collection('users').doc(user.uid).set({
          'period_data': data.toMap(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ Period data cloud sync error: $e');
      }
    }
  }

  /// Loads period data. When [cloudProfile] is provided and contains
  /// `period_data`, the cloud copy takes precedence and is written back to the
  /// local cache. Returns an empty [PeriodData] when nothing is stored.
  Future<PeriodData> loadPeriodData({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await _getPrefs;

    if (cloudProfile != null && cloudProfile['period_data'] is Map) {
      try {
        final cloud = PeriodData.fromMap(
            Map<String, dynamic>.from(cloudProfile['period_data'] as Map));
        await prefs.setString(_periodDataKey, cloud.toJson());
        return cloud;
      } catch (e) {
        debugPrint('❌ Period data cloud parse error: $e');
      }
    }

    final raw = prefs.getString(_periodDataKey);
    if (raw != null) {
      try {
        return PeriodData.fromJson(raw);
      } catch (e) {
        debugPrint('❌ Period data local parse error: $e');
      }
    }
    return const PeriodData();
  }

  // --- BODY WEIGHT TRACKER (local + Firestore user doc) ---

  /// Persists body-weight data locally and, for signed-in users, to the
  /// Firestore user document.
  Future<void> saveWeightData(WeightData data, {bool syncToCloud = true}) async {
    final prefs = await _getPrefs;
    await prefs.setString(_weightDataKey, data.toJson());

    if (!syncToCloud) return;
    final user = _currentUser;
    if (user != null) {
      try {
        await _db.collection('users').doc(user.uid).set({
          'weight_data': data.toMap(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ Weight data cloud sync error: $e');
      }
    }
  }

  /// Loads body-weight data. When [cloudProfile] contains `weight_data`, the
  /// cloud copy wins and is written back to the local cache.
  Future<WeightData> loadWeightData({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await _getPrefs;

    if (cloudProfile != null && cloudProfile['weight_data'] is Map) {
      try {
        final cloud = WeightData.fromMap(
            Map<String, dynamic>.from(cloudProfile['weight_data'] as Map));
        await prefs.setString(_weightDataKey, cloud.toJson());
        return cloud;
      } catch (e) {
        debugPrint('❌ Weight data cloud parse error: $e');
      }
    }

    final raw = prefs.getString(_weightDataKey);
    if (raw != null) {
      try {
        return WeightData.fromJson(raw);
      } catch (e) {
        debugPrint('❌ Weight data local parse error: $e');
      }
    }
    return const WeightData();
  }

  // --- STATS ---

  Future<void> saveStreak(int streak, String lastActiveDate) async {
    final prefs = await _getPrefs;
    await prefs.setInt(_currentStreakKey, streak);
    await prefs.setString(_lastActiveDateKey, lastActiveDate);

    final user = _currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'current_streak': streak,
        'last_active_date': lastActiveDate,
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveActivityScore(int score) async {
    final user = _currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'activity_score': score,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveGarden(List<int> cells) async {
    final prefs = await _getPrefs;
    await prefs.setString(_gardenKey, jsonEncode(cells));

    final user = _currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'garden_state': cells,
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveUnlockedAchievementsToCloud(List<String> ids) async {
    final user = _currentUser;
    if (user != null) {
      try {
        final memories = await loadTravelMemories();
        final streakData = await loadStreakData();
        final score = (ids.length * 100) +
            (memories.length * 50) +
            ((streakData['streak'] as int? ?? 0) * 10);

        await _db.collection('users').doc(user.uid).set({
          'unlocked_achievements': ids,
          'activity_score': score,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore Achievement Sync Error: $e');
      }
    }
  }

  Future<void> syncAllLocalData() async {
    final user = _currentUser;
    if (user == null) return;

    final dreams = await loadDreams();
    if (dreams.isNotEmpty) await saveDreams(dreams);

    final memories = await loadTravelMemories();
    if (memories.isNotEmpty) await saveTravelMemories(memories);

    final entries = await loadJournalEntries();
    if (entries.isNotEmpty) await saveJournalEntries(entries);

    final streakData = await loadStreakData();
    if (streakData['streak'] != null) {
      await saveStreak(streakData['streak'], streakData['lastActiveDate'] ?? '');
    }

    final unlockedIds = (await _getPrefs).getString('unlocked_achievements');
    final List<String> loadedIds =
        unlockedIds != null ? List<String>.from(jsonDecode(unlockedIds)) : [];

    final score = (loadedIds.length * 100) +
        (memories.length * 50) +
        ((streakData['streak'] as int? ?? 0) * 10);
    await saveActivityScore(score);

    final garden = await loadGarden();
    await saveGarden(garden);

    if (loadedIds.isNotEmpty) {
      await saveUnlockedAchievementsToCloud(loadedIds);
    }
  }

  // --- STREAK ---

  Future<Map<String, dynamic>> loadStreakData({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await _getPrefs;
    final data = <String, dynamic>{
      'streak': prefs.getInt(_currentStreakKey) ?? 0,
      'lastActiveDate': prefs.getString(_lastActiveDateKey),
    };

    if (cloudProfile != null) {
      data['streak'] = cloudProfile['current_streak'] ?? data['streak'];
      data['lastActiveDate'] = cloudProfile['last_active_date'] ?? data['lastActiveDate'];
    }
    return data;
  }

  // --- GARDEN ---

  Future<List<int>> loadGarden({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await _getPrefs;
    final localJson = prefs.getString(_gardenKey);
    List<int> cells = localJson != null
        ? List<int>.from(jsonDecode(localJson))
        : List.filled(25, 0);

    if (cloudProfile != null && cloudProfile['garden_state'] != null) {
      cells = List<int>.from(cloudProfile['garden_state']);
    }
    return cells;
  }

  // --- PINNED CARDS ---

  Future<void> savePinnedCards(List<String> cardIds) async {
    final prefs = await _getPrefs;
    await prefs.setStringList(_pinnedCardsKey, cardIds);
  }

  Future<List<String>> loadPinnedCards() async {
    final prefs = await _getPrefs;
    return prefs.getStringList(_pinnedCardsKey) ?? [];
  }

  // --- MISC LOCAL ---

  Future<void> saveNegotiationsCompleted(int count) async =>
      (await _getPrefs).setInt(_negotiationsCompletedKey, count);
  Future<int> loadNegotiationsCompleted() async =>
      (await _getPrefs).getInt(_negotiationsCompletedKey) ?? 0;

  Future<void> saveTodoCompletions(int count) async =>
      (await _getPrefs).setInt(_todoCompletionsKey, count);
  Future<int> loadTodoCompletions() async =>
      (await _getPrefs).getInt(_todoCompletionsKey) ?? 0;

  Future<void> saveDistinctGames(List<String> games) async =>
      (await _getPrefs).setStringList(_distinctGamesKey, games);
  Future<List<String>> loadDistinctGames() async =>
      (await _getPrefs).getStringList(_distinctGamesKey) ?? [];

  Future<void> saveTotalCheckIns(int count) async =>
      (await _getPrefs).setInt(_totalCheckInsKey, count);
  Future<int> loadTotalCheckIns() async =>
      (await _getPrefs).getInt(_totalCheckInsKey) ?? 0;

  Future<void> savePinnedJournalHome(List<String> entryIds) async =>
      (await SharedPreferences.getInstance()).setStringList(_pinnedJournalHomeKey, entryIds);
  Future<List<String>> loadPinnedJournalHome() async =>
      (await SharedPreferences.getInstance()).getStringList(_pinnedJournalHomeKey) ?? [];

  Future<void> saveWidgetJournalEntryId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_widgetJournalEntryIdKey);
    } else {
      await prefs.setString(_widgetJournalEntryIdKey, id);
    }
  }

  Future<String?> loadWidgetJournalEntryId() async =>
      (await SharedPreferences.getInstance()).getString(_widgetJournalEntryIdKey);

  Future<void> saveWidgetIntentionId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_widgetIntentionIdKey);
    } else {
      await prefs.setString(_widgetIntentionIdKey, id);
    }
  }

  Future<String?> loadWidgetIntentionId() async =>
      (await SharedPreferences.getInstance()).getString(_widgetIntentionIdKey);


  Future<bool> hasSeedData() async =>
      (await _getPrefs).getBool(_hasSeedDataKey) ?? false;
  Future<void> setHasSeedData() async =>
      (await _getPrefs).setBool(_hasSeedDataKey, true);

  // --- DELETE TRAVEL MEMORY ---

  Future<void> deleteTravelMemory(String id, List<String> photos) async {
    final user = _currentUser;
    if (user != null) {
      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .collection('travel_memories')
            .doc(id)
            .delete();

        for (final url in photos) {
          if (url.contains('travel-photos') && url.contains(user.uid)) {
            try {
              final ref = _storage.refFromURL(url);
              await ref.delete();
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('Firestore Travel Delete Error: $e');
      }
    }
  }

  // --- SYNC QUEUE ---

  /// Drains the offline sync queue stored in SharedPreferences.
  ///
  /// Processes operations in FIFO order (oldest first). On success the
  /// operation is removed from the queue. On failure the `retryCount` is
  /// incremented; if `retryCount >= 3` the operation is discarded.
  ///
  /// Each operation is enforced with a 5-second timeout (Requirement 10.2).
  /// For `toggle_action` operations that fail or timeout, the checkbox visual
  /// state is reverted in SharedPreferences widget data and the native widget
  /// is refreshed.
  ///
  /// Each operation type maps to a specific Firestore write:
  /// - `toggle_action`: updates action completion in `daily_plans`
  /// - `save_checkin`: writes a check-in document to `check_ins`
  /// - `save_plan`: writes a daily plan document to `daily_plans`
  /// - `save_intention`: writes an intention document to `wellness_intentions`
  Future<void> drainSyncQueue(String userId) async {
    final prefs = await _getPrefs;
    final raw = prefs.getString(_wellnessSyncQueueKey);
    if (raw == null || raw.isEmpty) {
      // Clear the pending sync flag even if queue is empty
      await prefs.setBool(_wellnessPendingSyncKey, false);
      return;
    }

    List<SyncOperation> queue;
    try {
      queue = (jsonDecode(raw) as List)
          .map((e) => SyncOperation.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('drainSyncQueue: failed to parse queue: $e');
      // Clear corrupted queue data
      await prefs.remove(_wellnessSyncQueueKey);
      await prefs.setBool(_wellnessPendingSyncKey, false);
      return;
    }

    if (queue.isEmpty) {
      await prefs.setBool(_wellnessPendingSyncKey, false);
      return;
    }

    // Sort FIFO by createdAt (oldest first)
    queue.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final remaining = <SyncOperation>[];

    for (final op in queue) {
      try {
        // Enforce 5-second timeout per operation (Requirement 10.2)
        await _executeSyncOperation(userId, op)
            .timeout(const Duration(seconds: 5));
        // Success — operation is not added back to the queue
        debugPrint('✅ Sync operation completed: ${op.type.toValue()} (${op.id})');
      } catch (e) {
        debugPrint('❌ Sync operation failed: ${op.type.toValue()} (${op.id}): $e');

        // For toggle_action failures: revert checkbox and refresh widget
        if (op.type == SyncOperationType.toggleAction) {
          await _revertWidgetToggle(prefs, op);
        }

        final updatedOp = op.copyWith(retryCount: op.retryCount + 1);
        if (updatedOp.retryCount < 3) {
          remaining.add(updatedOp);
        } else {
          debugPrint('🗑️ Discarding sync operation after 3 retries: ${op.type.toValue()} (${op.id})');
          // Final discard of toggle_action: ensure widget stays reverted
          if (op.type == SyncOperationType.toggleAction) {
            await _revertWidgetToggle(prefs, op);
          }
        }
      }
    }

    // Persist the updated queue (or clear it if empty)
    if (remaining.isEmpty) {
      await prefs.remove(_wellnessSyncQueueKey);
    } else {
      await prefs.setString(
        _wellnessSyncQueueKey,
        jsonEncode(remaining.map((e) => e.toMap()).toList()),
      );
    }

    // Clear the pending sync flag
    await prefs.setBool(_wellnessPendingSyncKey, false);
  }

  /// Reverts a widget toggle action in SharedPreferences and refreshes the
  /// native widget. Called when a Firestore sync for a `toggle_action`
  /// operation fails or times out (Requirement 10.2).
  Future<void> _revertWidgetToggle(
      SharedPreferences prefs, SyncOperation op) async {
    try {
      final actionId = op.payload['actionId'] as String?;
      if (actionId == null) return;

      final planJson = prefs.getString(_wellnessDailyPlanKey);
      if (planJson == null) return;

      final Map<String, dynamic> planMap =
          Map<String, dynamic>.from(jsonDecode(planJson) as Map);
      final actions = planMap['actions'] as List<dynamic>? ?? [];
      bool reverted = false;

      for (final action in actions) {
        if (action['id'] == actionId) {
          // Revert: flip the completed state back
          action['isCompleted'] = !(action['isCompleted'] ?? false);
          reverted = true;
          debugPrint(
              '↩️ Reverted widget action: $actionId to ${action['isCompleted']}');
          break;
        }
      }

      if (reverted) {
        // Write reverted plan back to SharedPreferences
        await prefs.setString(_wellnessDailyPlanKey, jsonEncode(planMap));

        // Update the native widget visual state
        final actionsToUpdate = planMap['actions'] as List<dynamic>? ?? [];
        for (int i = 0; i < actionsToUpdate.length && i < 3; i++) {
          final a = actionsToUpdate[i] as Map<String, dynamic>;
          await HomeWidget.saveWidgetData<bool>(
              'wellness_action_${i + 1}_checked', a['isCompleted'] ?? false);
        }
        await HomeWidget.updateWidget(
            name: 'AIWellnessWidget', androidName: 'AIWellnessWidget');
        debugPrint('✅ Widget visual state reverted after sync failure');
      }
    } catch (e) {
      debugPrint('❌ _revertWidgetToggle error: $e');
    }
  }

  /// Executes a single [SyncOperation] against Firestore.
  Future<void> _executeSyncOperation(String userId, SyncOperation op) async {
    switch (op.type) {
      case SyncOperationType.toggleAction:
        final planId = op.payload['planId'] as String?;
        final actionId = op.payload['actionId'] as String?;
        final completed = op.payload['completed'] as bool?;
        if (planId == null || actionId == null || completed == null) return;

        final docRef = _db
            .collection('users')
            .doc(userId)
            .collection('daily_plans')
            .doc(planId);

        final snapshot = await docRef.get();
        if (!snapshot.exists || snapshot.data() == null) return;

        final data = snapshot.data()!;
        final actions = List<Map<String, dynamic>>.from(
          (data['actions'] as List<dynamic>)
              .map((a) => Map<String, dynamic>.from(a as Map)),
        );

        final updatedActions = actions.map((a) {
          if (a['id'] == actionId) {
            return {...a, 'isCompleted': completed};
          }
          return a;
        }).toList();

        await docRef.update({'actions': updatedActions});

      case SyncOperationType.saveCheckin:
        final checkInMap = op.payload['checkIn'] as Map<String, dynamic>?;
        if (checkInMap == null) return;
        final checkInId = checkInMap['id'] as String?;
        if (checkInId == null) return;

        await _db
            .collection('users')
            .doc(userId)
            .collection('check_ins')
            .doc(checkInId)
            .set(checkInMap);

      case SyncOperationType.savePlan:
        final planMap = op.payload['plan'] as Map<String, dynamic>?;
        if (planMap == null) return;
        final dateKey = op.payload['dateKey'] as String?;
        if (dateKey == null) return;

        await _db
            .collection('users')
            .doc(userId)
            .collection('daily_plans')
            .doc(dateKey)
            .set(planMap, SetOptions(merge: true));

      case SyncOperationType.saveIntention:
        final intentionMap = op.payload['intention'] as Map<String, dynamic>?;
        if (intentionMap == null) return;
        final intentionId = intentionMap['id'] as String?;
        if (intentionId == null) return;

        await _db
            .collection('users')
            .doc(userId)
            .collection('wellness_intentions')
            .doc(intentionId)
            .set(intentionMap, SetOptions(merge: true));
    }
  }
}
