import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dream.dart';
import '../models/challenge_step.dart';
import '../models/travel_memory.dart';
import '../models/journal_entry.dart';
import '../models/journal_group.dart';
import '../models/wellness_intention.dart';
import '../models/daily_plan.dart';
import '../models/period_data.dart';
import '../models/weight_data.dart';
import '../services/storage_service.dart';
import '../services/achievement_service.dart';
import '../services/revenue_cat_service.dart';
import '../services/connectivity_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:async';
import '../models/blog_post.dart';
import '../services/blog_audio_handler.dart';
import '../theme/wellness_themes.dart';
import '../exceptions/premium_feature_exception.dart';
import '../data/ai_voices.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import '../services/dream_migration_service.dart';

@pragma('vm:entry-point')
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService _storage = StorageService();

  // ---------------------------------------------------------------------------
  // AI Wellness Widget Data Key Constants
  // ---------------------------------------------------------------------------
  static const String widgetFocusKey = 'wellness_focus';
  static const String widgetPlanIdKey = 'wellness_plan_id';
  static const String widgetEnergyScoreKey = 'wellness_energy_score';
  static const String widgetActionCountKey = 'wellness_action_count';
  // Per-action keys use pattern: wellness_action_{i}_id / _text / _checked (i=1–3)
  static const String widgetPlanDateKey = 'wellness_plan_date';
  static const String widgetPlaceholderKey = 'wellness_placeholder';
  static const String _widgetLastRefreshKey = 'wellness_widget_last_refresh';
  static const int _widgetRefreshCapMinutes = 30;
  
  // TTS / Audio Podcast State
  final FlutterTts _flutterTts = FlutterTts();
  BlogAudioHandler? _audioHandler;
  bool _isAudioHandlerReady = false;
  List<BlogPost> _allBlogs = [];
  BlogPost? _currentAudioBlog;
  bool _isAudioPlaying = false;
  double _audioProgress = 0.0;
  int _audioLastOffset = 0;
  String _audioFullText = "";
  static const int _charsPerSecond = 10;
  
  BlogPost? get currentAudioBlog => _currentAudioBlog;
  bool get isAudioPlaying => _isAudioPlaying;
  double get audioProgress => _audioProgress;
  int get audioLastOffset => _audioLastOffset;
  String get audioFullText => _audioFullText;
  int get audioTotalSeconds => _audioFullText.length ~/ _charsPerSecond;
  int get audioElapsedSeconds => (_audioProgress * audioTotalSeconds).toInt();

  List<Dream> _dreams = [];
  List<TravelMemory> _travelMemories = [];
  List<TravelMemory> _publicMemories = [];
  List<JournalEntry> _journalEntries = [];
  // List<JournalGroup> _journalGroups = [];
  List<String> _pinnedCardIds = [];
  final List<String> _pinnedDreamIds = [];
  List<String> _pinnedJournalToHomeIds = []; // Pin checklists to Home screen
  String? _widgetJournalEntryId; // The journal entry currently on the App Widget
  String? _widgetIntentionId; // The wellness intention currently on the home widget
  bool _isLoading = true;
  bool _isPro = false;

  /// True once the initial cloud settings restore has completed. Until then,
  /// settings saves are LOCAL ONLY — this prevents a pre-sync default value
  /// (e.g. after logout wipes local prefs) from clobbering the authoritative
  /// cloud settings via a merge write.
  bool _cloudSettingsLoaded = false;

  // Connectivity state
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isOnline = true;

  // Journal entries that failed Firestore write and need sync/retry (Req 8.5)
  final Set<String> _entriesNeedingSync = {};
  
  // Garden (formerly Bloom Garden)
  List<int> _gardenCells = List.filled(25, 0); // 5x5 grid
  double _waterRate = 0.0;
  int _lastMissedDays = 0; // Days missed since last activity
  int _negotiationsCompleted = 0;
  int _totalTodoCompletions = 0;
  Set<String> _distinctGamesPlayed = {};
  int _totalCheckIns = 0;
  String? _instagramUsername;
  String _aiVoice = 'default';
  
  List<Dream> get dreams => _dreams;
  /// Semantic alias for [_dreams] — maps each Dream to a [WellnessIntention]
  /// via `WellnessIntention.fromDream()`. Keeps `_dreams` as the internal
  /// storage while exposing typed wellness intentions to consumers.
  List<WellnessIntention> get intentions =>
      _dreams.map((d) => WellnessIntention.fromDream(d)).toList();
  List<TravelMemory> get travelMemories => _travelMemories;
  List<TravelMemory> get publicMemories => _publicMemories;
  List<JournalEntry> get journalEntries => _journalEntries;
  // List<JournalGroup> get journalGroups => _journalGroups;
  List<String> get pinnedCardIds => _pinnedCardIds;
  List<String> get pinnedDreamIds => _pinnedDreamIds;
  List<String> get pinnedJournalToHomeIds => _pinnedJournalToHomeIds;
  String? get widgetJournalEntryId => _widgetJournalEntryId;
  String? get widgetIntentionId => _widgetIntentionId;
  bool get isLoading => _isLoading;
  bool get isPro => _isPro;
  bool get isOnline => _isOnline;
  /// Set of journal entry IDs that failed Firestore sync and need retry.
  Set<String> get entriesNeedingSync => _entriesNeedingSync;
  List<int> get gardenCells => _gardenCells;
  double get waterRate => _waterRate;
  int get lastMissedDays => _lastMissedDays;
  int get negotiationsCompleted => _negotiationsCompleted;
  String? get instagramUsername => _instagramUsername;
  /// The selected AI assistant voice id (see kAiVoices).
  String get aiVoice => _aiVoice;
  int get activityPoints => (AchievementService().totalUnlocked * 100) + (_travelMemories.length * 50) + (_currentStreak * 10); // Updated formula to match storage service

  // Settings
  ThemeMode _themeMode = ThemeMode.light;
  Color _themeColor = const Color(0xFFFF7F50); // Coral Orange default
  double _textScaleFactor = 1.0;
  bool _isWinterMode = false;
  bool _showMotivation = true;
  bool _showGarden = true;
  bool _showAchievements = true;
  bool _showMap = true;

  // Period tracker data (persisted separately from settings via StorageService).
  PeriodData _periodData = const PeriodData();

  // Body weight tracker data (persisted separately via StorageService).
  WeightData _weightData = const WeightData();

  ThemeMode get themeMode => _themeMode;
  Color get themeColor => _themeColor;
  double get textScaleFactor => _textScaleFactor;
  bool get isWinnerMode => _isWinterMode; // Keep existing naming if any, but adding new ones
  bool get isWinterMode => _isWinterMode;
  bool get showMotivation => _showMotivation;
  bool get showGarden => _showGarden;
  bool get showAchievements => _showAchievements;
  bool get showMap => _showMap;

  // --- Period tracker ---
  PeriodData get periodData => _periodData;

  /// Non-clinical cycle context string for the AI planner, or null when the
  /// user has not logged any period data.
  String? get cyclePhaseContext => _periodData.aiCycleContext;

  /// Travel context string for the AI daily planner. Returns a brief
  /// summary of any active or upcoming trips (place, dates, user notes)
  /// so the plan can include travel-aware wellness actions.
  /// Returns null when no trips are active or upcoming within 7 days.
  String? get travelContext {
    if (_travelMemories.isEmpty) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final relevant = _travelMemories.where((m) {
      if (m.isActiveNow) return true;
      if (m.startDate != null) {
        final start = DateTime(
            m.startDate!.year, m.startDate!.month, m.startDate!.day);
        final diff = start.difference(today).inDays;
        return diff >= 0 && diff <= 7;
      }
      return false;
    }).toList();

    if (relevant.isEmpty) return null;

    final lines = relevant.take(3).map((m) {
      final status = m.isActiveNow ? 'Currently travelling' : 'Upcoming trip';
      final period = (m.startDate != null && m.endDate != null)
          ? ' (${_fmtDate(m.startDate!)} – ${_fmtDate(m.endDate!)})'
          : '';
      final note =
          (m.note != null && m.note!.trim().isNotEmpty) ? ' — "${m.note}"' : '';
      return '$status to ${m.place}$period$note';
    }).join('\n');

    return 'TRAVEL CONTEXT:\n$lines\n'
        'Where relevant, include travel-friendly wellness actions such as '
        'hydration, gentle movement, jet-lag recovery, or mindful exploration.';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_monthAbbr[d.month - 1]} ${d.year}';

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Future<void> _savePeriodData() async {
    await _storage.savePeriodData(_periodData, syncToCloud: _cloudSettingsLoaded);
  }

  /// Marks [date] as the first day of a period.
  Future<void> logPeriodStart(DateTime date) async {
    _periodData = _periodData.addPeriodStart(date);
    notifyListeners();
    await _savePeriodData();
  }

  /// Removes a previously logged period start [date].
  Future<void> removePeriodStart(DateTime date) async {
    _periodData = _periodData.removePeriodStart(date);
    notifyListeners();
    await _savePeriodData();
  }

  /// Updates the user's average cycle and/or period length.
  Future<void> updatePeriodSettings({int? cycleLength, int? periodLength}) async {
    _periodData = _periodData.copyWith(
      cycleLength: cycleLength,
      periodLength: periodLength,
    );
    notifyListeners();
    await _savePeriodData();
  }

  // --- Body weight tracker ---
  WeightData get weightData => _weightData;

  Future<void> _saveWeightData() async {
    await _storage.saveWeightData(_weightData, syncToCloud: _cloudSettingsLoaded);
  }

  /// Logs a weight measurement. [weightKg] must be in kilograms.
  Future<void> logWeight(double weightKg, {DateTime? date, String? note}) async {
    final when = date ?? DateTime.now();
    final entry = WeightEntry(
      id: 'w_${when.millisecondsSinceEpoch}',
      date: when,
      weightKg: weightKg,
      note: note,
    );
    _weightData = _weightData.addEntry(entry);
    notifyListeners();
    await _saveWeightData();
  }

  /// Removes a logged weight entry by id.
  Future<void> removeWeightEntry(String id) async {
    _weightData = _weightData.removeEntry(id);
    notifyListeners();
    await _saveWeightData();
  }

  /// Updates the display unit and/or height (cm, for BMI).
  Future<void> updateWeightSettings({WeightUnit? unit, double? heightCm}) async {
    _weightData = _weightData.copyWith(unit: unit, heightCm: heightCm);
    notifyListeners();
    await _saveWeightData();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }
  
  void setThemeColor(Color color) {
    _themeColor = color;
    _saveSettings();
    notifyListeners();
  }

  /// Applies a wellness theme. Throws [PremiumFeatureException] if the theme
  /// requires Premium and the user is not subscribed.
  void setWellnessTheme(WellnessThemeConfig theme) {
    if (theme.isPremium && !_isPro) {
      throw PremiumFeatureException('theme:${theme.id}');
    }
    _themeColor = theme.seedColor;
    _saveSettings();
    notifyListeners();
  }

  void setTextScaleFactor(double scale) {
    _textScaleFactor = scale.clamp(0.8, 1.3);
    _saveSettings();
    notifyListeners();
  }

  void setWinterMode(bool value) {
    _isWinterMode = value;
    _saveSettings();
    notifyListeners();
  }

  void setShowMotivation(bool value) {
    _showMotivation = value;
    _saveSettings();
    notifyListeners();
  }

  void setShowGarden(bool value) {
    _showGarden = value;
    _saveSettings();
    notifyListeners();
  }

  void setShowAchievements(bool value) {
    _showAchievements = value;
    _saveSettings();
    notifyListeners();
  }

  void setShowMap(bool value) {
    _showMap = value;
    _saveSettings();
    notifyListeners();
  }

  void setInstagramUsername(String? value) {
    _instagramUsername = value;
    _saveSettings();
    notifyListeners();
  }

  /// Selects the AI assistant voice. Throws [PremiumFeatureException] if the
  /// chosen voice requires Premium and the user is not subscribed.
  void setAiVoice(String voiceId) {
    final voice = aiVoiceById(voiceId);
    if (voice.isPremium && !_isPro) {
      throw PremiumFeatureException('aiVoice:$voiceId');
    }
    _aiVoice = voice.id;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    debugPrint('💾 _saveSettings: aiVoice=$_aiVoice, '
        'cloudSettingsLoaded=$_cloudSettingsLoaded');
    await _storage.saveSettings(
      themeModeIndex: _themeMode.index,
      themeColorValue: _themeColor.toARGB32(),
      textScale: _textScaleFactor,
      isWinterMode: _isWinterMode,
      showMotivation: _showMotivation,
      showGarden: _showGarden,
      showAchievements: _showAchievements,
      showMap: _showMap,
      instagram: _instagramUsername,
      aiVoice: _aiVoice,
      // Don't push settings to the cloud until the authoritative cloud values
      // have been loaded, so a transient pre-sync default can't overwrite them.
      syncToCloud: _cloudSettingsLoaded,
    );
  }

  AppState() {
    _loadSettings();
    _loadData();
    _initAudioService();
    _initTts();
    _initConnectivity();
    HomeWidget.registerInteractivityCallback(backgroundCallback);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _initAudioService() async {
    try {
      final session = await AudioSession.instance
          .timeout(const Duration(seconds: 5));
      await session.configure(const AudioSessionConfiguration.speech());
      
      _audioHandler = await AudioService.init(
        builder: () => BlogAudioHandler(
          onPlay: () {
            if (_currentAudioBlog != null) playBlog(_currentAudioBlog!);
          },
          onPause: () => pauseBlog(),
          onStop: () => stopBlog(),
          onSkipNext: () => skipNextBlog(),
          onSkipPrevious: () => skipPreviousBlog(),
          onSeek: (position) {
            if (audioTotalSeconds > 0) {
              seekAudio((position.inSeconds / audioTotalSeconds).clamp(0.0, 1.0));
            }
          },
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.aiwellnesspal.app.channel.audio',
          androidNotificationChannelName: 'AI Wellness Pal Narration',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'mipmap/launcher_icon',
        ),
      ).timeout(const Duration(seconds: 5));
      _isAudioHandlerReady = true;
      if (_currentAudioBlog != null) {
        _audioHandler?.updateMetadata(_currentAudioBlog!);
        _audioHandler?.updatePlaybackState(
          playing: _isAudioPlaying,
          position: Duration(seconds: audioElapsedSeconds),
        );
      }
    } catch (e) {
      debugPrint('Error initializing audio service: $e');
    }
  }
  
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);

    _flutterTts.setStartHandler(() {
      _isAudioPlaying = true;
      if (_isAudioHandlerReady) {
        _audioHandler?.updatePlaybackState(
          playing: true,
          position: Duration(seconds: audioElapsedSeconds),
        );
      }
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isAudioPlaying = false;
      _audioProgress = 1.0;
      _audioLastOffset = 0;
      if (_isAudioHandlerReady) {
        _audioHandler?.updatePlaybackState(
          playing: false,
          position: Duration(seconds: audioTotalSeconds),
        );
      }
      notifyListeners();
    });

    _flutterTts.setProgressHandler((text, start, end, word) {
      if (_audioFullText.isNotEmpty) {
        _audioProgress = (_audioLastOffset + start) / _audioFullText.length;
        if (_isAudioHandlerReady) {
          _audioHandler?.updatePlaybackState(
            playing: _isAudioPlaying,
            position: Duration(seconds: audioElapsedSeconds),
          );
        }
        notifyListeners();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      _isAudioPlaying = false;
      if (_isAudioHandlerReady) {
        _audioHandler?.updatePlaybackState(
          playing: false,
          position: Duration(seconds: audioElapsedSeconds),
        );
      }
      notifyListeners();
    });
  }

  String _cleanMarkdownForTts(String text) {
    // Remove headers (#, ##, etc.)
    var cleaned = text.replaceAll(RegExp(r'#+\s*'), '');
    // Remove bold/italic (**, *, __, _)
    cleaned = cleaned.replaceAll(RegExp(r'\*\*|__|\*|_'), '');
    // Remove links ([text](url)) - keep only text
    cleaned = cleaned.replaceAllMapped(RegExp(r'\[(.*?)\]\(.*?\)') , (match) => match.group(1) ?? '');
    // Remove images (![alt](url))
    cleaned = cleaned.replaceAll(RegExp(r'!\[.*?\]\(.*?\)') , '');
    // Remove extra whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  Future<void> playBlog(BlogPost blog, {List<BlogPost>? allBlogs}) async {
    if (allBlogs != null) {
      _allBlogs = allBlogs;
    }
    
    if (_currentAudioBlog?.id != blog.id) {
      await stopBlog();
      _currentAudioBlog = blog;
      _audioFullText = _cleanMarkdownForTts("${blog.title}. ${blog.excerpt}. ${blog.content}");
      _audioProgress = 0.0;
      _audioLastOffset = 0;
      if (_isAudioHandlerReady) {
        _audioHandler?.updateMetadata(blog);
      }
    }

    if (_audioProgress >= 0.99) {
      _audioLastOffset = 0;
      _audioProgress = 0.0;
    } else {
      _audioLastOffset = (_audioProgress * _audioFullText.length).toInt();
    }

    final textToSpeak = _audioFullText.substring(_audioLastOffset);
    if (textToSpeak.isNotEmpty) {
      _isAudioPlaying = true;
      if (_isAudioHandlerReady) {
        _audioHandler?.updatePlaybackState(
          playing: true,
          position: Duration(seconds: audioElapsedSeconds),
        );
      }
      notifyListeners();
      await _flutterTts.speak(textToSpeak);
    }
  }

  Future<void> skipNextBlog() async {
    if (_allBlogs.isEmpty || _currentAudioBlog == null) return;
    
    final currentIndex = _allBlogs.indexWhere((b) => b.id == _currentAudioBlog!.id);
    final nextIndex = (currentIndex + 1) % _allBlogs.length;
    final nextBlog = _allBlogs[nextIndex];
    
    await stopBlog();
    await playBlog(nextBlog);
  }

  Future<void> skipPreviousBlog() async {
    if (_allBlogs.isEmpty || _currentAudioBlog == null) return;
    
    final currentIndex = _allBlogs.indexWhere((b) => b.id == _currentAudioBlog!.id);
    final prevIndex = (currentIndex - 1 + _allBlogs.length) % _allBlogs.length;
    final prevBlog = _allBlogs[prevIndex];
    
    await stopBlog();
    await playBlog(prevBlog);
  }

  Future<void> pauseBlog() async {
    await _flutterTts.pause();
    _isAudioPlaying = false;
    if (_isAudioHandlerReady) {
      _audioHandler?.updatePlaybackState(
        playing: false,
        position: Duration(seconds: audioElapsedSeconds),
      );
    }
    notifyListeners();
  }

  Future<void> stopBlog() async {
    await _flutterTts.stop();
    _isAudioPlaying = false;
    _currentAudioBlog = null;
    _audioProgress = 0.0;
    _audioLastOffset = 0;
    _audioFullText = "";
    if (_isAudioHandlerReady) {
      _audioHandler?.updatePlaybackState(
        playing: false,
        position: Duration.zero,
      );
    }
    notifyListeners();
  }

  Future<void> seekAudio(double value) async {
    if (_currentAudioBlog == null) return;
    
    final wasPlaying = _isAudioPlaying;
    await _flutterTts.stop();
    
    _audioProgress = value;
    _audioLastOffset = (value * _audioFullText.length).toInt();
    notifyListeners();

    if (wasPlaying) {
      final textToSpeak = _audioFullText.substring(_audioLastOffset);
      if (textToSpeak.isNotEmpty) {
        await _flutterTts.speak(textToSpeak);
      }
    }
  }

  /// Subscribes to connectivity changes and drains the sync queue on
  /// transition to online. Updates [_isOnline] so the UI can show/hide
  /// the offline indicator banner.
  void _initConnectivity() {
    _connectivityService.isOnline.then((online) {
      _isOnline = online;
      notifyListeners();
    });

    _connectivitySubscription = _connectivityService.onlineStream.listen(
      (online) {
        final wasOffline = !_isOnline;
        _isOnline = online;
        notifyListeners();

        // On transition to online, drain the sync queue
        if (online && wasOffline) {
          _storage.drainSyncQueue(_currentUserId ?? '').catchError((e) {
            debugPrint('❌ AppState: drainSyncQueue error on reconnect: $e');
          });
        }
      },
    );
  }

  /// The current authenticated user's ID, set during cloud sync.
  String? _currentUserId;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Called when the app lifecycle state changes.
  ///
  /// On foreground resume (AppLifecycleState.resumed), checks the
  /// `wellness_pending_sync` flag from SharedPreferences. If true,
  /// drains the sync queue to sync widget toggle actions with Firestore.
  /// (Requirement 10.2 — widget Firestore sync on foreground open)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleForegroundResume();
    }
  }

  /// Checks for pending wellness widget syncs on foreground resume and
  /// triggers the drain with a 5-second timeout per operation.
  Future<void> _handleForegroundResume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pendingSync = prefs.getBool('wellness_pending_sync') ?? false;
      if (pendingSync && _currentUserId != null && _currentUserId!.isNotEmpty) {
        await _storage.drainSyncQueue(_currentUserId!);
      }

      // If an intention task was toggled from the home-screen widget (which
      // writes `bloom_dreams` from a background isolate), reload dreams so the
      // in-app Wellness Intentions screen reflects the change, then persist to
      // Firestore.
      final intentionPending =
          prefs.getBool('intention_pending_sync') ?? false;
      if (intentionPending) {
        _dreams = await _storage.loadDreams();
        notifyListeners();
        await prefs.setBool('intention_pending_sync', false);
        // Persist the reloaded dreams (writes through to Firestore).
        await _save();
      }
    } catch (e) {
      debugPrint('❌ AppState._handleForegroundResume error: $e');
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _storage.loadSettings();
    _applySettings(settings);
    notifyListeners();
  }
  @pragma('vm:entry-point')
  static Future<void> backgroundCallback(Uri? uri) async {
    debugPrint('--- Background Callback Triggered: $uri ---');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (uri?.host == 'habit_toggle') {
      // Toggle today's completion for a habit from the "Today's Habits" widget.
      final String? habitId = uri?.queryParameters['id'];
      debugPrint('Background Habit Toggle: habitId=$habitId');
      if (habitId != null && habitId.isNotEmpty) {
        final changed =
            await HabitBuilderState.toggleHabitInPrefs(prefs, habitId);
        if (changed) {
          // Flag for the UI to reload habits on next foreground resume.
          await prefs.setBool('habit_pending_sync', true);
          await HabitBuilderState.syncHabitWidgetFromPrefs(prefs);
        }
      }
    } else if (uri?.host == 'habit_refresh') {
      debugPrint('Background Habit Refresh Request');
      await HabitBuilderState.syncHabitWidgetFromPrefs(prefs);
    } else if (uri?.host == 'intention_toggle') {
      // Toggle a wellness intention task from the home-screen Intention widget.
      final String? intentionId = uri?.queryParameters['id'];
      final String? taskId = uri?.queryParameters['task'];
      debugPrint(
          'Background Intention Toggle: intentionId=$intentionId, taskId=$taskId');

      if (intentionId != null && taskId != null) {
        final String? localData = prefs.getString('bloom_dreams');
        if (localData != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(localData);
            bool found = false;

            for (var dreamMap in jsonList) {
              if (dreamMap['id'] == intentionId) {
                final steps = dreamMap['steps'] as List<dynamic>?;
                if (steps != null) {
                  for (var step in steps) {
                    if (step['id'] == taskId) {
                      final now = !(step['isCompleted'] ?? false);
                      step['isCompleted'] = now;
                      step['completedAt'] =
                          now ? DateTime.now().toIso8601String() : null;
                      found = true;
                      debugPrint('Toggled intention task: $taskId to $now');
                      break;
                    }
                  }
                }
                break;
              }
            }

            if (found) {
              await prefs.setString('bloom_dreams', jsonEncode(jsonList));
              // Flag for Firestore reconciliation on next foreground resume.
              await prefs.setBool('intention_pending_sync', true);
              // Show the task the user just tapped in its new (checked) state
              // for this render — it advances to the next step on the next
              // full push (app foreground/save).
              await _syncIntentionWidgetInIsolate(prefs, intentionId,
                  displayTaskId: taskId);
            }
          } catch (e) {
            debugPrint('Background Intention Toggle Error: $e');
          }
        }
      }
    } else if (uri?.host == 'intention_refresh') {
      debugPrint('Background Intention Refresh Request');
      final String? intentionId = prefs.getString('bloom_widget_intention_id');
      await _syncIntentionWidgetInIsolate(prefs, intentionId);
    } else if (uri?.host == 'wellness_toggle') {
      // Handle AI Wellness Widget action toggle
      final planId = uri?.queryParameters['plan_id'];
      final actionId = uri?.queryParameters['action_id'];
      debugPrint('Wellness Toggle Request: planId=$planId, actionId=$actionId');

      // Only [actionId] is strictly required — the action is matched by id
      // within the stored plan. [planId] is informational (may be empty for
      // older cached plans).
      if (actionId != null && actionId.isNotEmpty) {
        final String? planJson = prefs.getString('wellness_daily_plan');
        if (planJson != null) {
          try {
            final Map<String, dynamic> planMap =
                Map<String, dynamic>.from(jsonDecode(planJson) as Map);
            final actions = planMap['actions'] as List<dynamic>? ?? [];
            bool toggled = false;

            for (final action in actions) {
              if (action['id'] == actionId) {
                action['isCompleted'] = !(action['isCompleted'] ?? false);
                toggled = true;
                debugPrint(
                    'Toggled wellness action: $actionId to ${action['isCompleted']}');
                break;
              }
            }

            if (toggled) {
              await prefs.setString(
                  'wellness_daily_plan', jsonEncode(planMap));
              // Flag for foreground Firestore sync
              await prefs.setBool('wellness_pending_sync', true);
              // Show the tapped action checked for this render; advances on the
              // next full push.
              await _syncWellnessWidgetInIsolate(prefs, planMap,
                  displayTaskId: actionId);
            }
          } catch (e) {
            debugPrint('Wellness Toggle Error: $e');
          }
        }
      }
    } else if (uri?.host == 'wellness_refresh') {
      debugPrint('Wellness Widget Refresh Request');
      final String? planJson = prefs.getString('wellness_daily_plan');
      if (planJson != null) {
        try {
          final Map<String, dynamic> planMap =
              Map<String, dynamic>.from(jsonDecode(planJson) as Map);
          await _syncWellnessWidgetInIsolate(prefs, planMap);
        } catch (e) {
          debugPrint('Wellness Refresh Error: $e');
        }
      }
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _syncIntentionWidgetInIsolate(
      SharedPreferences prefs, String? intentionId,
      {String? displayTaskId}) async {
    debugPrint('Syncing Intention Widget Data in Background: id=$intentionId');

    if (intentionId == null || intentionId.isEmpty) {
      await _writeIntentionWidgetEmpty();
    } else {
      final String? localData = prefs.getString('bloom_dreams');
      if (localData != null) {
        try {
          final List<dynamic> jsonList = jsonDecode(localData);
          final dream = jsonList.firstWhere(
              (d) => d['id'] == intentionId,
              orElse: () => null);

          if (dream != null) {
            final title = (dream['title'] ?? '').toString();
            final List<dynamic> steps =
                dream['steps'] as List<dynamic>? ?? [];
            final total = steps.length;
            final completed =
                steps.where((s) => s['isCompleted'] == true).length;
            final allDone = total > 0 && completed == total;

            // Row 1: the just-tapped task (kept in its new checked state so the
            // user sees the checkmark before it advances) when [displayTaskId]
            // is provided; otherwise the first incomplete step.
            dynamic row1;
            if (displayTaskId != null) {
              row1 = steps.cast<dynamic>().firstWhere(
                    (s) => s['id'] == displayTaskId,
                    orElse: () => null,
                  );
            }
            row1 ??= steps.cast<dynamic>().firstWhere(
                  (s) => !(s['isCompleted'] == true),
                  orElse: () => null,
                );
            final row1Id = row1 != null ? row1['id'] : null;
            final row1Checked = row1 != null && (row1['isCompleted'] == true);

            // Row 2: the first incomplete step other than row 1.
            final row2 = steps.cast<dynamic>().firstWhere(
                  (s) => !(s['isCompleted'] == true) && s['id'] != row1Id,
                  orElse: () => null,
                );
            final row2Id = row2 != null ? row2['id'] : null;

            // Up next: the first incomplete step after rows 1 and 2.
            final next = steps.cast<dynamic>().firstWhere(
                  (s) =>
                      !(s['isCompleted'] == true) &&
                      s['id'] != row1Id &&
                      s['id'] != row2Id,
                  orElse: () => null,
                );

            await HomeWidget.saveWidgetData<bool>(
                'intention_has_intention', true);
            await HomeWidget.saveWidgetData<String>(
                'intention_id', intentionId);
            await HomeWidget.saveWidgetData<String>('intention_title',
                title.isEmpty ? 'Wellness Intention' : title);
            // Row 1
            await HomeWidget.saveWidgetData<String>('intention_task1_text',
                row1 != null ? (row1['title'] ?? '') : '');
            await HomeWidget.saveWidgetData<String>('intention_task1_id',
                row1 != null ? (row1['id'] ?? '') : '');
            await HomeWidget.saveWidgetData<bool>(
                'intention_task1_checked', row1Checked);
            // Row 2 (always shown unchecked)
            await HomeWidget.saveWidgetData<String>('intention_task2_text',
                row2 != null ? (row2['title'] ?? '') : '');
            await HomeWidget.saveWidgetData<String>('intention_task2_id',
                row2 != null ? (row2['id'] ?? '') : '');
            await HomeWidget.saveWidgetData<bool>(
                'intention_task2_checked', false);
            // Up next
            await HomeWidget.saveWidgetData<String>('intention_next_task',
                next != null ? (next['title'] ?? '') : '');
            // Only treat as "all done" celebration when everything is complete
            // and we're not pinning a specific just-tapped task.
            await HomeWidget.saveWidgetData<bool>('intention_all_done',
                allDone && displayTaskId == null);
            await HomeWidget.saveWidgetData<int>(
                'intention_completed', completed);
            await HomeWidget.saveWidgetData<int>('intention_total', total);
            await HomeWidget.saveWidgetData<int>('intention_progress',
                total == 0 ? 0 : ((completed / total) * 100).round());
            debugPrint('Successfully re-saved intention data for widget');
          }
        } catch (e) {
          debugPrint('Error syncing intention widget in background: $e');
        }
      }
    }

    await HomeWidget.updateWidget(
        name: 'IntentionWidget', androidName: 'IntentionWidget');
    debugPrint('Triggered Intention Widget Update from Background');
  }

  @pragma('vm:entry-point')
  static Future<void> _syncWellnessWidgetInIsolate(
      SharedPreferences prefs, Map<String, dynamic> planMap,
      {String? displayTaskId}) async {
    debugPrint('Syncing Wellness Widget Data in Background');

    final focus = planMap['todaysFocus'] as String? ?? '';
    final actions = planMap['actions'] as List<dynamic>? ?? [];
    final date = planMap['date'] as String? ?? '';

    final planId = planMap['id'] as String? ?? '';
    await HomeWidget.saveWidgetData<String>('wellness_focus', focus);
    await HomeWidget.saveWidgetData<String>('wellness_plan_id', planId);
    await HomeWidget.saveWidgetData<int>(
        'wellness_action_count', actions.length.clamp(0, 3));
    await HomeWidget.saveWidgetData<String>('wellness_plan_date', date);
    await HomeWidget.saveWidgetData<bool>('wellness_placeholder', false);

    for (int i = 0; i < actions.length && i < 3; i++) {
      final action = actions[i] as Map<String, dynamic>;
      await HomeWidget.saveWidgetData<String>(
          'wellness_action_${i + 1}_id', action['id'] ?? '');
      await HomeWidget.saveWidgetData<String>(
          'wellness_action_${i + 1}_text', action['title'] ?? '');
      await HomeWidget.saveWidgetData<bool>(
          'wellness_action_${i + 1}_checked',
          action['isCompleted'] ?? false);
    }

    // Formatted keys (two active rows + "up next" + progress).
    await _writeWellnessFormatted(
      actions
          .map((a) => {
                'id': a['id'] ?? '',
                'title': a['title'] ?? '',
                'isCompleted': a['isCompleted'] ?? false,
              })
          .toList(),
      displayTaskId: displayTaskId,
    );

    await HomeWidget.updateWidget(
        name: 'AIWellnessWidget', androidName: 'AIWellnessWidget');
    debugPrint('Wellness Widget Updated from Background');
  }

  /// Writes the "two active rows + up next + progress" formatted keys for the
  /// AI Wellness widget, mirroring the Intention widget layout.
  ///
  /// [actions] is a list of maps with `id`, `title`, `isCompleted`.
  /// When [displayTaskId] is set (a widget tap), row 1 pins to that task in its
  /// new (checked) state so the user sees the checkmark before it advances.
  static Future<void> _writeWellnessFormatted(
    List<Map<String, dynamic>> actions, {
    String? displayTaskId,
  }) async {
    final total = actions.length;
    final completed =
        actions.where((a) => a['isCompleted'] == true).length;
    final allDone = total > 0 && completed == total;

    // Row 1: the just-tapped task (kept in its new state) or first incomplete.
    Map<String, dynamic>? row1;
    if (displayTaskId != null) {
      for (final a in actions) {
        if (a['id'] == displayTaskId) {
          row1 = a;
          break;
        }
      }
    }
    row1 ??= actions.cast<Map<String, dynamic>?>().firstWhere(
          (a) => !(a!['isCompleted'] == true),
          orElse: () => null,
        );
    final row1Id = row1 != null ? row1['id'] : null;
    final row1Checked = row1 != null && (row1['isCompleted'] == true);

    // Row 2: first incomplete other than row 1.
    final row2 = actions.cast<Map<String, dynamic>?>().firstWhere(
          (a) => !(a!['isCompleted'] == true) && a['id'] != row1Id,
          orElse: () => null,
        );
    final row2Id = row2 != null ? row2['id'] : null;

    // Up next: first incomplete after rows 1 and 2.
    final next = actions.cast<Map<String, dynamic>?>().firstWhere(
          (a) =>
              !(a!['isCompleted'] == true) &&
              a['id'] != row1Id &&
              a['id'] != row2Id,
          orElse: () => null,
        );

    await HomeWidget.saveWidgetData<String>(
        'wellness_task1_text', row1 != null ? (row1['title'] ?? '') : '');
    await HomeWidget.saveWidgetData<String>(
        'wellness_task1_id', row1 != null ? (row1['id'] ?? '') : '');
    await HomeWidget.saveWidgetData<bool>('wellness_task1_checked', row1Checked);
    await HomeWidget.saveWidgetData<String>(
        'wellness_task2_text', row2 != null ? (row2['title'] ?? '') : '');
    await HomeWidget.saveWidgetData<String>(
        'wellness_task2_id', row2 != null ? (row2['id'] ?? '') : '');
    await HomeWidget.saveWidgetData<bool>('wellness_task2_checked', false);
    await HomeWidget.saveWidgetData<String>(
        'wellness_next_task', next != null ? (next['title'] ?? '') : '');
    await HomeWidget.saveWidgetData<bool>(
        'wellness_all_done', allDone && displayTaskId == null);
    await HomeWidget.saveWidgetData<int>('wellness_completed', completed);
    await HomeWidget.saveWidgetData<int>('wellness_total', total);
    await HomeWidget.saveWidgetData<int>('wellness_progress',
        total == 0 ? 0 : ((completed / total) * 100).round());
  }

  // ---------------------------------------------------------------------------
  // AI Wellness Widget — Public push method
  // ---------------------------------------------------------------------------

  /// Pushes [plan] data to the AI Wellness Widget.
  ///
  /// Implements a 30-minute refresh cap (Requirement 10.3): if the last
  /// successful push was less than 30 minutes ago AND the plan date has not
  /// changed, the push is skipped.
  ///
  /// On failure, the previous widget data is retained (Requirement 10.4).
  ///
  /// The [energyScore] is optional; when provided it is written to the
  /// widget so the native side can display an energy indicator.
  /// Set [force] to `true` to bypass the 30-minute refresh cap. This is used
  /// when an action is toggled in-app so the home-screen widget reflects the
  /// change instantly.
  static Future<bool> pushPlanToWidget(
    DailyPlan plan, {
    int? energyScore,
    bool force = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // --- 30-minute refresh cap ---
      final lastRefreshMs = prefs.getInt(_widgetLastRefreshKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedMinutes = (now - lastRefreshMs) / 60000;

      // Skip if within cap AND the plan date hasn't changed — unless [force]
      // is set (e.g. an in-app action toggle that must sync immediately).
      final existingPlanDate = prefs.getString(widgetPlanDateKey) ?? '';
      final newPlanDate = plan.date.toIso8601String().split('T').first;
      if (!force &&
          elapsedMinutes < _widgetRefreshCapMinutes &&
          existingPlanDate == newPlanDate) {
        debugPrint(
            '⏱ pushPlanToWidget: skipped (last refresh ${elapsedMinutes.toStringAsFixed(1)} min ago)');
        return true; // Not a failure — data is current
      }

      // Also mirror the plan JSON to SharedPreferences so the background
      // isolate (widget checkbox taps) reads the same current plan.
      await prefs.setString('wellness_daily_plan', jsonEncode(plan.toMap()));

      // --- Write widget data keys ---
      await HomeWidget.saveWidgetData<String>(
          widgetFocusKey, plan.todaysFocus);
      await HomeWidget.saveWidgetData<String>(
          widgetPlanIdKey, plan.id);
      await HomeWidget.saveWidgetData<int>(
          widgetEnergyScoreKey, energyScore ?? 0);

      final actionCount = plan.actions.length.clamp(0, 3);
      await HomeWidget.saveWidgetData<int>(widgetActionCountKey, actionCount);
      await HomeWidget.saveWidgetData<String>(widgetPlanDateKey, newPlanDate);
      await HomeWidget.saveWidgetData<bool>(widgetPlaceholderKey, false);

      for (int i = 0; i < actionCount; i++) {
        final action = plan.actions[i];
        await HomeWidget.saveWidgetData<String>(
            'wellness_action_${i + 1}_id', action.id);
        await HomeWidget.saveWidgetData<String>(
            'wellness_action_${i + 1}_text', action.title);
        await HomeWidget.saveWidgetData<bool>(
            'wellness_action_${i + 1}_checked', action.isCompleted);
      }

      // Clear any leftover action slots beyond current count
      for (int i = actionCount; i < 3; i++) {
        await HomeWidget.saveWidgetData<String>(
            'wellness_action_${i + 1}_id', '');
        await HomeWidget.saveWidgetData<String>(
            'wellness_action_${i + 1}_text', '');
        await HomeWidget.saveWidgetData<bool>(
            'wellness_action_${i + 1}_checked', false);
      }

      // --- Formatted keys (two active rows + "up next" + progress) ---
      await _writeWellnessFormatted(
        plan.actions
            .map((a) => {
                  'id': a.id,
                  'title': a.title,
                  'isCompleted': a.isCompleted,
                })
            .toList(),
      );

      // --- Update the native widget ---
      await HomeWidget.updateWidget(
          name: 'AIWellnessWidget', androidName: 'AIWellnessWidget');

      // Record the last refresh timestamp
      await prefs.setInt(_widgetLastRefreshKey, now);

      debugPrint('✅ pushPlanToWidget: widget updated successfully');
      return true;
    } catch (e) {
      // On failure, retain previous data (Requirement 10.4)
      debugPrint('❌ pushPlanToWidget failed: $e');
      return false;
    }
  }

  /// Pushes the placeholder state to the widget when no plan is available.
  static Future<void> pushWidgetPlaceholder() async {
    try {
      await HomeWidget.saveWidgetData<bool>(widgetPlaceholderKey, true);
      await HomeWidget.saveWidgetData<String>(widgetFocusKey, '');
      await HomeWidget.saveWidgetData<int>(widgetActionCountKey, 0);
      await HomeWidget.updateWidget(
          name: 'AIWellnessWidget', androidName: 'AIWellnessWidget');
    } catch (e) {
      debugPrint('❌ pushWidgetPlaceholder failed: $e');
    }
  }

  Future<void> _loadData() async {
    _isLoading = true;
    // Re-gate cloud settings writes until this load cycle's cloud sync
    // restores the authoritative values (important after a logout/login,
    // where local prefs were wiped and must not clobber the cloud).
    _cloudSettingsLoaded = false;
    notifyListeners();
    
    try {
      // PHASE 1: Parallel Local Reads
      final results = await Future.wait([
        _storage.loadSettings(),
        _storage.loadDreams(),
        _storage.loadTravelMemories(),
        _storage.loadJournalEntries(),
        _storage.loadPinnedCards(),
        _storage.loadGarden(),
        _storage.loadNegotiationsCompleted(),
        _storage.loadTodoCompletions(),
        _storage.loadDistinctGames(),
        _storage.loadTotalCheckIns(),
        _storage.loadStreakData(),
        _storage.hasSeedData(),
        _storage.loadPinnedJournalHome(),
        _storage.loadWidgetJournalEntryId(),
        _storage.loadPeriodData(),
        _storage.loadWeightData(),
        _storage.loadWidgetIntentionId(),
      ]);

      // Assign results
      final settings = results[0] as Map<String, dynamic>;
      _dreams = results[1] as List<Dream>;
      _travelMemories = results[2] as List<TravelMemory>;
      _journalEntries = results[3] as List<JournalEntry>;
      _pinnedCardIds = results[4] as List<String>;
      _gardenCells = results[5] as List<int>;
      _negotiationsCompleted = results[6] as int;
      _totalTodoCompletions = results[7] as int;
      _distinctGamesPlayed = (results[8] as List<String>).toSet();
      _totalCheckIns = results[9] as int;
      final streakData = results[10] as Map<String, dynamic>;
      _currentStreak = streakData['streak'] ?? 0;
      _pinnedJournalToHomeIds = results[12] as List<String>;
      _widgetJournalEntryId = results[13] as String?;
      _periodData = results[14] as PeriodData;
      _weightData = results[15] as WeightData;
      _widgetIntentionId = results[16] as String?;

      // Push the pinned intention to the home-screen widget on load so it
      // reflects the latest tasks (and their completion) without waiting for a
      // manual toggle. Runs after dreams are assigned above.
      _updateIntentionWidget();
      
      // Robust duplicate ID check
      bool hasDuplicateIds = false;
      for (var entry in _journalEntries) {
        if (entry.type == JournalEntryType.todo) {
          final ids = entry.todos.map((t) => t.id).toList();
          if (ids.length != ids.toSet().length && ids.isNotEmpty) {
            hasDuplicateIds = true;
            break;
          }
        }
      }

      if (_journalEntries.isEmpty || hasDuplicateIds) {
        debugPrint('Refreshing journal entries: isEmpty=${_journalEntries.isEmpty}, hasDuplicateIds=$hasDuplicateIds');
        await _addSampleData();
      }

      // Apply settings immediately
      _applySettings(settings);
      _updateWaterRate();

      // PHASE 2: Local activity tracking
      await trackActivity();

      // READY: Show UI with local data
      _isLoading = false;
      notifyListeners();

      // PHASE 3: Background Cloud Sync
      _syncWithCloudInBackground();

    } catch (e) {
      debugPrint('Error in _loadData: $e');
      _isLoading = false;
      notifyListeners();

      // Still run the cloud sync so settings restore and _cloudSettingsLoaded
      // gets set — otherwise a failure in the local phases would permanently
      // block settings from syncing to the cloud.
      _syncWithCloudInBackground();
    }
  }

  void _applySettings(Map<String, dynamic> settings) {
    final themeIndex = settings['themeMode'];
    if (themeIndex == ThemeMode.system.index) {
       _themeMode = ThemeMode.light;
    } else {
       _themeMode = ThemeMode.values[themeIndex];
    }
    final themeColorVal = settings['themeColor'];
    if (themeColorVal != null) {
      _themeColor = Color(themeColorVal);
    }
    _textScaleFactor = (settings['textScale'] as num?)?.toDouble().clamp(0.8, 1.3) ?? 1.0;
    _isWinterMode = settings['isWinterMode'] ?? false;
    _showMotivation = settings['showMotivation'] ?? true;
    _showGarden = settings['showGarden'] ?? true;
    _showAchievements = settings['showAchievements'] ?? true;
    _showMap = settings['showMap'] ?? true;
    _instagramUsername = settings['instagram'];
    _aiVoice = settings['aiVoice'] as String? ?? 'default';
  }

  Future<void> _syncWithCloudInBackground() async {
    // Set the current user ID for connectivity-based sync
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // 1. Fetch profile ONCE
    final cloudProfile = await _storage.fetchFullProfile();
    
    if (cloudProfile != null) {
      // 2. Update stats and settings from the same profile object
      final streakData = await _storage.loadStreakData(cloudProfile: cloudProfile);
      _currentStreak = streakData['streak'] ?? 0;

      _currentStreak = streakData['streak'] ?? 0;

      _gardenCells = await _storage.loadGarden(cloudProfile: cloudProfile);

      // Restore period tracker data from the cloud profile.
      _periodData = await _storage.loadPeriodData(cloudProfile: cloudProfile);

      // Restore body weight data from the cloud profile.
      _weightData = await _storage.loadWeightData(cloudProfile: cloudProfile);
      
      // Update memories from cloud in background
      _travelMemories = await _storage.loadTravelMemories(syncCloud: true);
      
      final settings = await _storage.loadSettings(cloudProfile: cloudProfile);
      _applySettings(settings);
      
      _updateWaterRate();
      notifyListeners();
    }

    // Cloud settings restore attempt is done — from here on it is safe for
    // settings saves to write to the cloud without clobbering the real values.
    _cloudSettingsLoaded = true;

    // 3. Other network tasks
    fetchPublicMemories();
    // Force a fresh RevenueCat fetch so isPro reflects the true subscription
    // state (a cached/early call can otherwise leave isPro=false even when the
    // user is subscribed, which the Settings screen's live check would show).
    updateProStatus(forceRefresh: true);
    
    // Register for real-time updates
    RevenueCatService().setUpdateListener((info) {
      updateProStatus(forceRefresh: true);
    });
    
    _checkAchievements();
  }

  void _updateWaterRate() {
    // Water rate based on streak (e.g., 7 days = 1.0)
    _waterRate = (_currentStreak / 7.0).clamp(0.0, 1.0);
  }

  Future<void> _updateGardenGrowth(bool isActiveToday, int dayDifference) async {
    if (dayDifference == 0 && isActiveToday) {
       // Just active today, maybe give a small growth boost if not already done today
       // (Real implementation would track "wateredToday" flag)
       _growRandomPlant();
    } else if (dayDifference > 1) {
       // Missed days! Wither some plants
       _witherPlants(dayDifference - 1);
    } else if (dayDifference == 1 && isActiveToday) {
       // Consecutive day! Grow plants
       _growRandomPlant();
    }
    
    await _storage.saveGarden(_gardenCells);
    notifyListeners();
  }

  void _growRandomPlant() {
    // Find cells that can grow (shuffled for randomness)
    final indices = List.generate(25, (i) => i)..shuffle();
    for (final i in indices) {
      if (_gardenCells[i] < 4) { // Max growth is 4 (Bloom)
        _gardenCells[i]++;
        break;
      }
    }
  }

  void _witherPlants(int missedDays) {
    // Wither plants based on missed days
    final indices = List.generate(25, (i) => i)..shuffle();
    int witheredCount = 0;
    for (final i in indices) {
      if (_gardenCells[i] > 0) {
        _gardenCells[i]--; // Back to previous stage or sand
        witheredCount++;
        if (witheredCount >= missedDays) break;
      }
    }
  }
  
  // Activity Streak
  int _currentStreak = 0;
  int get currentStreak => _currentStreak;

  int get totalPoints => activityPoints;
  int get currentLevel => 1 + (activityPoints / 200).floor();
  
  // Helper for UI
  int get pointsToNextLevel => currentLevel * 200;
  
  String get levelName {
    if (currentLevel >= 20) return "Wellness Legend";
    if (currentLevel >= 15) return "Master Botanist";
    if (currentLevel >= 10) return "Star Gardener";
    if (currentLevel >= 7) return "Green Thumb";
    if (currentLevel >= 4) return "Nature Guard";
    if (currentLevel >= 2) return "Sprout Guide";
    return "Seed Sower";
  }

  Future<List<Achievement>> trackActivity() async {
    // Load points data first - REMOVED

    final streakData = await _storage.loadStreakData();
    int loadedStreak = streakData['streak'] as int;
    String? lastActiveStr = streakData['lastActiveDate'] as String?;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Tolerate a malformed/legacy stored date instead of throwing (a
    // FormatException here would abort _loadData before the cloud settings
    // sync runs, permanently stranding _cloudSettingsLoaded=false).
    final lastActiveDate =
        lastActiveStr != null ? DateTime.tryParse(lastActiveStr) : null;
    if (lastActiveDate == null) {
      // First time, or an unparseable stored date — (re)start the streak.
      _currentStreak = 1;
      _totalCheckIns = 1;
      _lastMissedDays = 0;
      await _storage.saveTotalCheckIns(_totalCheckIns);
      await _storage.saveStreak(1, today.toIso8601String());
      await _updateGardenGrowth(true, 0);
    } else {
      final lastActiveDay = DateTime(lastActiveDate.year, lastActiveDate.month, lastActiveDate.day);
      
      final difference = today.difference(lastActiveDay).inDays;
      
      if (difference == 0) {
        // Already active today, maintain streak
        _currentStreak = loadedStreak;
        _lastMissedDays = 0;
        await _updateGardenGrowth(true, 0);
      } else if (difference == 1) {
        // Consecutive day
        _currentStreak = loadedStreak + 1;
        _totalCheckIns++;
        _lastMissedDays = 0;
        await _storage.saveTotalCheckIns(_totalCheckIns);
        await _storage.saveStreak(_currentStreak, today.toIso8601String());
        await _updateGardenGrowth(true, 1);
      } else {
        // Streak penalty logic: -1 for every missed day
        int missedDays = difference - 1;
        _currentStreak = (loadedStreak - missedDays).clamp(1, 1000).toInt();
        _lastMissedDays = difference;
        
        // Points are now dynamic, no need to deduct explicitly
        
        await _storage.saveStreak(_currentStreak, today.toIso8601String());
        _totalCheckIns++;
        await _storage.saveTotalCheckIns(_totalCheckIns);
        await _updateGardenGrowth(true, difference);
      }
    }
    _updateWaterRate();
    notifyListeners();
    
    // Check for streak achievements
    return await _checkAchievements();
  }

  Future<void> updateProStatus({bool forceRefresh = false}) async {
    try {
      final revenueCatService = RevenueCatService();
      final previousIsPro = _isPro;
      _isPro = await revenueCatService.hasProAccess(forceRefresh: forceRefresh);

      // --- Subscription lapse detection (Req 13.8) ---
      if (previousIsPro && !_isPro) {
        // User was Pro but is now free → lapse detected
        _lapseDetectedThisSession = true;
        debugPrint('⚠️ Subscription lapse detected: was Pro, now free tier');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to update pro status in AppState: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Subscription Lapse Banner (Req 13.8)
  // ---------------------------------------------------------------------------

  /// Key for persisting whether the lapse banner has already been shown.
  static const String _lapseBannerShownKey = 'lapse_banner_shown';

  /// True if a lapse was detected during this session (was Pro, now free).
  bool _lapseDetectedThisSession = false;
  bool get lapseDetectedThisSession => _lapseDetectedThisSession;

  /// Whether the lapse banner should be displayed.
  /// Returns true only if:
  /// - A lapse was detected this session
  /// - The banner has not been previously shown (persisted via SharedPreferences)
  Future<bool> shouldShowLapseBanner() async {
    if (!_lapseDetectedThisSession) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_lapseBannerShownKey) ?? false);
    } catch (e) {
      debugPrint('⚠️ Error checking lapse banner shown status: $e');
      return false;
    }
  }

  /// Marks the lapse banner as shown so it won't appear again.
  Future<void> dismissLapseBanner() async {
    _lapseDetectedThisSession = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lapseBannerShownKey, true);
    } catch (e) {
      debugPrint('⚠️ Error persisting lapse banner dismissal: $e');
    }
    notifyListeners();
  }

  /// Resets the lapse banner flag (e.g., if user re-subscribes).
  /// Called when user transitions back to Pro.
  Future<void> resetLapseBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lapseBannerShownKey);
      _lapseDetectedThisSession = false;
    } catch (e) {
      debugPrint('⚠️ Error resetting lapse banner: $e');
    }
  }

  Future<List<Achievement>> addDream(String title, {DateTime? deadline, int? themeColor, int? themeIcon, List<Map<String, dynamic>>? initialSteps}) async {
    // Determine steps source: provided AI steps OR generated mock steps
    final steps = (initialSteps != null && initialSteps.isNotEmpty)
        ? initialSteps.map((s) {
            // Ensure we handle String parsing for DateTime if needed, assuming edge function returns proper structure
            // Edge Function expected to return: {'title': '...', 'duration': 15}
            final dayOffset = initialSteps.indexOf(s); // 0-based index
            final scheduledDate = DateTime.now().add(Duration(days: dayOffset));
            
            return ChallengeStep(
              title: s['title'] ?? 'Action Step ${dayOffset + 1}',
              durationMinutes: s['duration'] is int ? s['duration'] : (int.tryParse(s['duration'].toString()) ?? 15),
              scheduledDate: scheduledDate, // Schedule sequentially
            );
          }).toList()
        : _generateStepsForDream(title);

    final newDream = Dream(
      title: title,
      deadline: deadline,
      themeColor: themeColor,
      themeIcon: themeIcon,
      steps: steps,
    );
    _dreams.add(newDream);
    await _save();
    notifyListeners();
    
    // Check for dream achievements
    return await _checkAchievements();
  }
  
  Future<void> addPoints(int amount) async {
    // Points are now calculated dynamically based on achievements/activity directly.
    // This function acts as a notifier for UI updates if needed, but storage is handled via derived score.
    notifyListeners();
  }

  Future<List<Achievement>> recordNegotiationCompletion() async {
    _negotiationsCompleted++;
    await _storage.saveNegotiationsCompleted(_negotiationsCompleted);
    // Also track as a generic She Stacks completion
    await trackGameCompletion("Negotiation Lab");
    
    // Add points for negotiation completion (+250 as seen in SheStacksScreen)
    await addPoints(250);
    notifyListeners();
    return await _checkAchievements();
  }

  Future<void> trackGameCompletion(String gameTitle) async {
    if (!_distinctGamesPlayed.contains(gameTitle)) {
      _distinctGamesPlayed.add(gameTitle);
      await _storage.saveDistinctGames(_distinctGamesPlayed.toList());
      notifyListeners();
      await _checkAchievements();
    }
  }
  
  Future<List<Achievement>> addTravelMemory(
    String place,
    double lat,
    double lng, {
    String? id,
    String memory = '',
    String? note,
    List<String> photos = const [],
    bool isPublic = false,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Prevent duplicate entries if retrying with the same ID
    if (id != null) {
      _travelMemories.removeWhere((m) => m.id == id);
    }

    final newMemory = TravelMemory(
      id: id,
      place: place,
      latitude: lat,
      longitude: lng,
      memory: memory,
      note: note,
      photos: photos,
      isPublic: isPublic,
      startDate: startDate,
      endDate: endDate,
    );
    _travelMemories.add(newMemory);
    await _save();

    // Add points for travel (+20)
    await addPoints(20);

    notifyListeners();

    // Check for travel achievements
    return await _checkAchievements();
  }

  Future<void> fetchPublicMemories() async {
    _publicMemories = await _storage.fetchPublicMemories();
    notifyListeners();
  }

  Future<void> deleteTravelMemory(String id) async {
    final index = _travelMemories.indexWhere((m) => m.id == id);
    if (index != -1) {
      final memory = _travelMemories[index];
      _travelMemories.removeAt(index);
      await _storage.deleteTravelMemory(id, memory.photos);
      await _save();
      notifyListeners();
      
      // Check for changes (potentially re-locking achievements)
      await _checkAchievements();
    }
  }

  Future<void> updateTravelMemory(TravelMemory updatedMemory) async {
    final index = _travelMemories.indexWhere((m) => m.id == updatedMemory.id);
    if (index != -1) {
      _travelMemories[index] = updatedMemory;
      await _save();
      notifyListeners();
    }
  }

  // Journal Methods
  Future<List<Achievement>> addJournalEntry(JournalEntry entry) async {
    _journalEntries.add(entry);
    await _save();
    notifyListeners();
    return await _checkAchievements();
  }

  Future<void> updateJournalEntry(JournalEntry updatedEntry) async {
    final index = _journalEntries.indexWhere((e) => e.id == updatedEntry.id);
    if (index != -1) {
      _journalEntries[index] = updatedEntry;
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteJournalEntry(String id) async {
    _journalEntries.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
    await _checkAchievements();
  }

  Future<List<Achievement>> toggleTodoItem(String entryId, String todoId) async {
    debugPrint('Toggling Todo: entryId=$entryId, todoId=$todoId');
    final entryIndex = _journalEntries.indexWhere((e) => e.id == entryId);
    if (entryIndex == -1) {
      debugPrint('Entry not found: $entryId');
      return [];
    }

    final entry = _journalEntries[entryIndex];
    final todoIndex = entry.todos.indexWhere((t) => t.id == todoId);
    if (todoIndex == -1) {
      debugPrint('Todo not found: $todoId among ${entry.todos.map((t) => t.id).toList()}');
      return [];
    }

    final updatedTodos = List<TodoItem>.from(entry.todos);
    updatedTodos[todoIndex] = updatedTodos[todoIndex].copyWith(
      isCompleted: !updatedTodos[todoIndex].isCompleted,
    );

    _journalEntries[entryIndex] = entry.copyWith(
      todos: updatedTodos,
      updatedAt: DateTime.now(),
    );

    debugPrint('Todo $todoId toggled to: ${updatedTodos[todoIndex].isCompleted}');

    // Track total todo completions
    if (updatedTodos[todoIndex].isCompleted) {
      _totalTodoCompletions++;
      await _storage.saveTodoCompletions(_totalTodoCompletions);
      await _checkAchievements();
    } else {
      _totalTodoCompletions = (_totalTodoCompletions - 1).clamp(0, 99999);
      await _storage.saveTodoCompletions(_totalTodoCompletions);
    }

    await _save();
    notifyListeners();
    return await _checkAchievements();
  }




  // Saved & AI Insight Methods

  /// Marks a journal entry as needing Firestore sync (write failed).
  /// This exposes a visual error state in the history list for retry.
  /// Requirement: 8.5
  void markEntryNeedsSync(String entryId) {
    _entriesNeedingSync.add(entryId);
    notifyListeners();
  }

  /// Clears the needs-sync flag for a journal entry after successful retry.
  void clearEntryNeedsSync(String entryId) {
    _entriesNeedingSync.remove(entryId);
    notifyListeners();
  }

  Future<void> toggleSavedEntry(String entryId, {bool? save, String? insight}) async {
    final index = _journalEntries.indexWhere((e) => e.id == entryId);
    if (index != -1) {
      final entry = _journalEntries[index];
      // If save is null, toggle. If insight is provided, auto-save=true.
      final newSavedState = save ?? !entry.isSaved; 
      
      _journalEntries[index] = entry.copyWith(
        isSaved: newSavedState,
        aiInsight: insight ?? entry.aiInsight, // Update insight if provided
      );
      await _save();
      notifyListeners();
    }
  }

  // Group methods removed...
  // Future<void> addJournalGroup...
  // Future<void> updateJournalGroup...
  // Future<void> deleteJournalGroup...
  // Future<void> assignEntryToGroup...

  // Journal group stubs — groups are stored on JournalEntry.groupId but not
  // persisted separately. These methods are retained for UI compatibility.
  void addJournalGroup(JournalGroup group) {}
  void updateJournalGroup(JournalGroup group) {}

  Future<bool> togglePinEntry(String entryId) async {
    final index = _journalEntries.indexWhere((e) => e.id == entryId);
    if (index == -1) return false;

    final entry = _journalEntries[index];
    
    // If trying to pin, check if we already have 3 pinned
    if (!entry.isPinned) {
      final pinnedCount = _journalEntries.where((e) => e.isPinned).length;
      if (pinnedCount >= 3) {
        return false; // Can't pin more than 3
      }
    }

    _journalEntries[index] = entry.copyWith(isPinned: !entry.isPinned);
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> deleteDream(String id) async {
    _dreams.removeWhere((d) => d.id == id);
    await _save();
    notifyListeners();
    
    // Check for changes (potentially re-locking achievements)
    await _checkAchievements();
  }

  Future<List<Achievement>> toggleStepCompletion(String dreamId, String stepId) async {
    final dreamIndex = _dreams.indexWhere((d) => d.id == dreamId);
    if (dreamIndex == -1) return [];

    final stepIndex = _dreams[dreamIndex].steps.indexWhere((s) => s.id == stepId);
    if (stepIndex == -1) return [];

    final step = _dreams[dreamIndex].steps[stepIndex];
    step.isCompleted = !step.isCompleted;
    step.completedAt = step.isCompleted ? DateTime.now() : null;

    // Re-save entire list for simplicity
    await _save();
    
    // Award points if completed (+30)
    if (step.isCompleted) {
      await addPoints(30);
    }
    
    notifyListeners();
    
    // Check for action completion achievements and return them
    return await _checkAchievements();
  }

  Future<void> _save() async {
    await _storage.saveDreams(_dreams);
    await _storage.saveTravelMemories(_travelMemories);
    await _storage.saveJournalEntries(_journalEntries);
    await _storage.savePinnedJournalHome(_pinnedJournalToHomeIds);
    await _storage.saveWidgetJournalEntryId(_widgetJournalEntryId);
    await _storage.saveWidgetIntentionId(_widgetIntentionId);
    // If an intention is pinned to the widget, refresh it so task edits and
    // completion changes made in-app show on the home screen immediately.
    if (_widgetIntentionId != null) {
      _updateIntentionWidget();
    }
    // await _storage.saveJournalGroups(_journalGroups);
  }

  // Mock AI breakdown
  List<ChallengeStep> _generateStepsForDream(String title) {
    // Start from midnight today to ensure consistent comparison
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return [
      ChallengeStep(title: 'Visualize exactly what "$title" looks like', durationMinutes: 5, scheduledDate: today),
      ChallengeStep(title: 'Research one person who has done this', durationMinutes: 10, scheduledDate: today.add(const Duration(days: 1))),
      ChallengeStep(title: 'Write down 3 main blockers', durationMinutes: 5, scheduledDate: today.add(const Duration(days: 2))),
      ChallengeStep(title: 'Brainstorm 5 tiny first steps', durationMinutes: 5, scheduledDate: today.add(const Duration(days: 3))),
      ChallengeStep(title: 'Pick one tiny step and do it now', durationMinutes: 15, scheduledDate: today.add(const Duration(days: 4))),
      ChallengeStep(title: 'Share your goal with one friend', durationMinutes: 5, scheduledDate: today.add(const Duration(days: 5))),
      ChallengeStep(title: 'Celebrate your first week of progress!', durationMinutes: 5, scheduledDate: today.add(const Duration(days: 6))),
    ]
;
  }
  
  Future<void> updateDream(Dream updatedDream) async {
    final index = _dreams.indexWhere((d) => d.id == updatedDream.id);
    if (index != -1) {
      _dreams[index] = updatedDream;
      await _save();
      notifyListeners();
    }
  }

  /// Check and unlock achievements based on current stats.
  ///
  /// IMPORTANT: we snapshot [activityPoints] and [currentLevel] *before*
  /// calling [AchievementService.checkAchievements] so that newly-unlocked
  /// badges don't immediately inflate the points total mid-check and cascade
  /// into unlocking further point/level achievements in the same pass.
  Future<List<Achievement>> _checkAchievements() async {
    final achievementService = AchievementService();

    // Snapshot points & level from the CURRENT totalUnlocked count, before
    // the check mutates it. activityPoints is a live getter that reads
    // AchievementService().totalUnlocked, so we freeze it here.
    final snapshotPoints = activityPoints;
    final snapshotLevel = 1 + (snapshotPoints / 200).floor();

    // Calculate stats
    final totalDreams = _dreams.length;
    final completedActions = _dreams
        .expand((dream) => dream.steps)
        .where((step) => step.isCompleted)
        .length;
    final completedDreams = _dreams.where((dream) => 
        dream.steps.every((step) => step.isCompleted)).length;
    
    final travelMemories = _travelMemories.length;
    final countriesVisited = _travelMemories.map((m) => m.place).toSet().length;
    final travelPhotos = _travelMemories
        .expand((m) => m.photos)
        .length;
    
    // Wellness Studio activity completions are stored by WellnessStudioScreen
    // in SharedPreferences as a JSON list of activity IDs.
    int studioActivitiesCompleted = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('wellness_studio_completions');
      if (raw != null) {
        studioActivitiesCompleted = (jsonDecode(raw) as List).length;
      }
    } catch (_) {
      studioActivitiesCompleted = 0;
    }

    // Filter out demo entries for achievements
    final userJournalEntries = _journalEntries.where((e) => e.id != 'welcome_note' && e.id != 'daily_rituals').length;
    final userTodoItems = _journalEntries
        .where((e) => e.id != 'welcome_note' && e.id != 'daily_rituals' && e.type == JournalEntryType.todo)
        .expand((e) => e.todos)
        .where((t) => t.isCompleted)
        .length;
    
    // Check achievements — use snapshotted points/level so newly-unlocked
    // badges don't inflate the score mid-check and cascade into further unlocks.
    final newAchievements = await achievementService.checkAchievements(
      currentStreak: _currentStreak,
      totalPoints: snapshotPoints,
      totalDreams: totalDreams,
      completedActions: completedActions,
      completedDreams: completedDreams,
      travelMemories: travelMemories,
      countriesVisited: countriesVisited,
      travelPhotos: travelPhotos,
      totalCheckIns: _totalCheckIns,
      currentLevel: snapshotLevel,
      studioActivitiesCompleted: studioActivitiesCompleted,
      isPro: _isPro,
      journalEntries: userJournalEntries,
      todoItems: userTodoItems,
    );
    
    if (newAchievements.isNotEmpty) {
      // +50 points for each new badge
      await addPoints(50 * newAchievements.length);
    }
    
    return newAchievements;
  }

  Future<void> toggleCardPin(String cardId) async {
    if (_pinnedCardIds.contains(cardId)) {
      _pinnedCardIds.remove(cardId);
    } else {
      _pinnedCardIds.add(cardId);
    }
    await _storage.savePinnedCards(_pinnedCardIds);
    notifyListeners();
  }

  Future<void> toggleDreamPin(String dreamId) async {
    if (_pinnedDreamIds.contains(dreamId)) {
      _pinnedDreamIds.remove(dreamId);
    } else {
      _pinnedDreamIds.add(dreamId);
    }
    // Storage persistence would be added to _storage.savePinnedDreams if desired
    // For now we rely on the main _save() which saves the dreams list
    // Actually, we should probably add a dedicated save for pinned dreams or
    // just ensure dreams are sorted by pinned status in the getter.
    notifyListeners();
  }

  void toggleJournalPinToHome(String entryId) {
    if (_pinnedJournalToHomeIds.contains(entryId)) {
      _pinnedJournalToHomeIds.remove(entryId);
    } else {
      _pinnedJournalToHomeIds.add(entryId);
    }
    _storage.savePinnedJournalHome(_pinnedJournalToHomeIds);
    notifyListeners();
  }

  /// Whether the given intention is currently pinned to the home-screen widget.
  bool isIntentionOnWidget(String intentionId) =>
      _widgetIntentionId == intentionId;

  /// Pins/unpins a wellness intention to the home-screen Intention widget.
  void togglePinIntentionToWidget(String intentionId) {
    if (_widgetIntentionId == intentionId) {
      _widgetIntentionId = null;
    } else {
      _widgetIntentionId = intentionId;
    }

    _updateIntentionWidget();
    _storage.saveWidgetIntentionId(_widgetIntentionId);
    notifyListeners();
  }

  /// Writes the pinned intention's summary to the home-screen Intention widget.
  ///
  /// The widget shows a single "current active task" (the first incomplete
  /// step) plus a progress indicator, mirroring the in-app intention card.
  ///
  /// Widget data keys (mirrors the native IntentionWidget provider):
  ///   intention_id (String), intention_title (String),
  ///   intention_active_task (String), intention_active_task_id (String),
  ///   intention_all_done (bool), intention_has_intention (bool),
  ///   intention_completed (int), intention_total (int),
  ///   intention_progress (int 0..100).
  Future<void> _updateIntentionWidget() async {
    if (_widgetIntentionId == null) {
      await _writeIntentionWidgetEmpty();
    } else {
      final dream = _dreams.firstWhere(
        (d) => d.id == _widgetIntentionId,
        orElse: () => Dream(title: '', steps: []),
      );
      final steps = dream.steps;
      final total = steps.length;
      final completed = steps.where((s) => s.isCompleted).length;
      final allDone = total > 0 && completed == total;
      // Show the first two incomplete steps as tappable rows; the third
      // incomplete step is shown dimmed as an "Up next" preview.
      final incomplete =
          steps.where((s) => !s.isCompleted).toList(growable: false);
      final task1 = incomplete.isNotEmpty ? incomplete[0] : null;
      final task2 = incomplete.length > 1 ? incomplete[1] : null;
      final next = incomplete.length > 2 ? incomplete[2] : null;

      await HomeWidget.saveWidgetData<bool>('intention_has_intention', true);
      await HomeWidget.saveWidgetData<String>('intention_id', _widgetIntentionId!);
      await HomeWidget.saveWidgetData<String>('intention_title',
          dream.title.isEmpty ? 'Wellness Intention' : dream.title);
      // Row 1
      await HomeWidget.saveWidgetData<String>(
          'intention_task1_text', task1?.title ?? '');
      await HomeWidget.saveWidgetData<String>(
          'intention_task1_id', task1?.id ?? '');
      await HomeWidget.saveWidgetData<bool>('intention_task1_checked', false);
      // Row 2
      await HomeWidget.saveWidgetData<String>(
          'intention_task2_text', task2?.title ?? '');
      await HomeWidget.saveWidgetData<String>(
          'intention_task2_id', task2?.id ?? '');
      await HomeWidget.saveWidgetData<bool>('intention_task2_checked', false);
      // Up next
      await HomeWidget.saveWidgetData<String>(
          'intention_next_task', next?.title ?? '');
      await HomeWidget.saveWidgetData<bool>('intention_all_done', allDone);
      await HomeWidget.saveWidgetData<int>('intention_completed', completed);
      await HomeWidget.saveWidgetData<int>('intention_total', total);
      await HomeWidget.saveWidgetData<int>('intention_progress',
          total == 0 ? 0 : ((completed / total) * 100).round());
    }

    await HomeWidget.updateWidget(
      name: 'IntentionWidget',
      androidName: 'IntentionWidget',
    );
  }

  static Future<void> _writeIntentionWidgetEmpty() async {
    await HomeWidget.saveWidgetData<bool>('intention_has_intention', false);
    await HomeWidget.saveWidgetData<String>('intention_id', '');
    await HomeWidget.saveWidgetData<String>(
        'intention_title', 'Wellness Intention');
    await HomeWidget.saveWidgetData<String>('intention_task1_text', '');
    await HomeWidget.saveWidgetData<String>('intention_task1_id', '');
    await HomeWidget.saveWidgetData<bool>('intention_task1_checked', false);
    await HomeWidget.saveWidgetData<String>('intention_task2_text', '');
    await HomeWidget.saveWidgetData<String>('intention_task2_id', '');
    await HomeWidget.saveWidgetData<bool>('intention_task2_checked', false);
    await HomeWidget.saveWidgetData<String>('intention_next_task', '');
    await HomeWidget.saveWidgetData<bool>('intention_all_done', false);
    await HomeWidget.saveWidgetData<int>('intention_completed', 0);
    await HomeWidget.saveWidgetData<int>('intention_total', 0);
    await HomeWidget.saveWidgetData<int>('intention_progress', 0);
  }

  Future<void> syncAllData() async {
    await _storage.syncAllLocalData();
    // Run Dream → WellnessIntention migration (idempotent, skips if already done)
    await DreamMigrationService().migrate();
    await _loadData(); // Re-load to get merged results or just to refresh everything
  }

  Future<void> _addSampleData() async {
    // Clear and add to ensure clean state
    _journalEntries.removeWhere((e) => e.id == 'welcome_note' || e.id == 'daily_rituals');
    
    final welcomeNote = JournalEntry(
      id: 'welcome_note',
      title: "Welcome to AI Wellness Pal! 🌸",
      content: "This is your personal space to reflect, dream, and grow. \n\n"
          "✨ **How to use AI Wellness Pal:**\n"
          "• Tap the + button to create a new note or list.\n"
          "• Use the 'Discuss' button on any entry to dive deeper with AI.\n"
          "• Track your mood to see how your garden grows.\n\n"
          "We're glad to have you on this journey!",
      type: JournalEntryType.note,
      color: Colors.purple.shade100.toARGB32(),
      tags: ["Welcome", "Guide"],
      mood: "😊",
      isPinned: true,
      isSaved: true,
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dailyRituals = JournalEntry(
      id: 'daily_rituals',
      title: "Daily Rituals 🌿",
      content: "",
      type: JournalEntryType.todo,
      color: Colors.green.shade100.toARGB32(),
      tags: ["Habits", "Routine"],
      todos: [
        TodoItem(id: 'ritual_1_$timestamp', text: "Morning Reflection", isCompleted: false),
        TodoItem(id: 'ritual_2_$timestamp', text: "Drink 2L Water", isCompleted: false),
        TodoItem(id: 'ritual_3_$timestamp', text: "30-min Movement", isCompleted: false),
        TodoItem(id: 'ritual_4_$timestamp', text: "Express Gratitude", isCompleted: false),
      ],
      mood: "✨",
      isSaved: true,
    );

    _journalEntries.addAll([welcomeNote, dailyRituals]);
    await _save();
    await _storage.setHasSeedData();
    notifyListeners();
  }
}
