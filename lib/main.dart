import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:home_widget/home_widget.dart';
import 'theme/app_theme.dart';
import 'providers/app_state.dart';
import 'providers/wellness_plan_state.dart';
import 'providers/check_in_state.dart';
import 'providers/personalization_state.dart';
import 'services/revenue_cat_service.dart';
import 'services/achievement_service.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';
import 'services/check_in_service.dart';
import 'services/personalization_service.dart';
import 'services/notification_service.dart';
import 'services/onesignal_service.dart';
import 'services/voice_command_service.dart';
import 'services/live_conversation_service.dart';
import 'services/native_aec_audio_io.dart';
import 'services/record_pcm_audio_io.dart';
import 'services/app_navigation_service.dart';
import 'services/conversation_store.dart';
import 'services/home_tool_cards_service.dart';
import 'services/prefs_brand_migration.dart';
import 'features/nutrition/presentation/nutrition_state.dart';
import 'features/meal_planner/presentation/meal_planner_state.dart';
import 'features/calorie_budget/presentation/calorie_budget_state.dart';
import 'features/hydration/presentation/hydration_state.dart';
import 'features/sleep/presentation/sleep_state.dart';
import 'features/sleep/data/health_sleep_data_provider.dart';
import 'features/meditation/presentation/meditation_state.dart';
import 'features/habit_builder/presentation/habit_builder_state.dart';
import 'features/habit_builder/presentation/challenge_state.dart';
import 'screens/auth_wrapper.dart';
import 'widgets/snow_overlay.dart';
import 'widgets/audio_floating_player.dart';
import 'widgets/pal_wake_word_coordinator.dart';
import 'widgets/onesignal_verification_gate.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

/// OneSignal App ID (public client identifier — safe to ship in the app).
const String kOneSignalAppId = 'b9e6a19e-8072-4118-bf06-0fd21868cb2e';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize OneSignal (push + in-app messaging). Must run before runApp so
  // the SDK is ready when the app mounts. Permission is NOT requested here —
  // it's requested from the push-subscription verification dialog's button.
  // All OneSignal SDK access goes through OneSignalService (the single wrapper).
  try {
    OneSignalService().initialize(kOneSignalAppId);
    // Tie the OneSignal user to the Firebase UID so sends can target this user
    // and their subscriptions stay merged across devices/reinstalls. Bind now
    // for the already-signed-in user, and keep it in sync as auth changes.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && currentUid.isNotEmpty) {
      OneSignalService().login(currentUid);
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && user.uid.isNotEmpty) {
        OneSignalService().login(user.uid);
      } else {
        OneSignalService().logout();
      }
    });
  } catch (e) {
    debugPrint('Failed to initialize OneSignal: $e');
  }

  // Activate Firebase App Check. Firebase AI Logic requires App Check to be
  // enforced, otherwise calls fail with "Firebase AI Logic has been
  // deactivated in this project".
  //
  // In debug builds we use the debug providers so development works on
  // simulators/emulators (register the printed debug token in the Firebase
  // console → App Check). Release builds use platform attestation:
  // Play Integrity on Android and App Attest / Device Check on Apple.
  // Dev-only override: force the App Check *debug* provider even in release
  // builds. This is needed on free/personal Apple teams, which cannot use
  // App Attest (a paid Apple Developer Program capability). Enable it by
  // building with `--dart-define=APPCHECK_DEBUG=true`, then register the
  // printed debug token in the Firebase console. It is OFF by default, so
  // production/App Store builds are unaffected and keep using App Attest.
  const bool forceAppCheckDebug =
      bool.fromEnvironment('APPCHECK_DEBUG', defaultValue: false);

  try {
    // Enable automatic token refresh so the SDK keeps a valid App Check token
    // available for downstream services (including Firebase AI Logic).
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    final bool useDebugProvider = kDebugMode || forceAppCheckDebug;

    await FirebaseAppCheck.instance.activate(
      androidProvider:
          useDebugProvider ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          useDebugProvider ? AppleProvider.debug : AppleProvider.appAttest,
    );

    // Prime an App Check token BEFORE any AI Logic call. Firebase AI Logic
    // requires enforced App Check; if the first calls fire before a token has
    // been fetched, the backend rejects them with "App Check token is
    // invalid". Forcing a fetch here (and awaiting it) guarantees a valid
    // token is cached before the app makes its first AI request.
    final acToken = await FirebaseAppCheck.instance.getToken(true);
    debugPrint(
        '🔐 App Check token primed: ${acToken != null && acToken.isNotEmpty ? "OK (len=${acToken.length})" : "NULL/EMPTY"}');
  } catch (e) {
    debugPrint('Failed to activate Firebase App Check: $e');
  }

  // Register the iOS App Group so home_widget can read/write shared data.
  // The native widget extension uses UserDefaults(suiteName:
  // "group.com.aiwellnesspal.app"), so the Dart side must match. Without this,
  // every HomeWidget call throws "AppGroupId not set. Call setAppGroupId first".
  try {
    await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');
  } catch (e) {
    debugPrint('Failed to set HomeWidget App Group ID: $e');
  }

  // Initialize RevenueCat
  try {
    await RevenueCatService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize RevenueCat: $e');
  }

  // Initialize AuthService (syncs current Firebase user with RevenueCat)
  try {
    await AuthService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize AuthService: $e');
  }

  //  so existing users keep their data after the brand rename.
  try {
    await PrefsBrandMigration.run();
  } catch (e) {
    debugPrint('Failed to run prefs brand migration: $e');
  }

  // Initialize StorageService (SharedPrefs Cache)
  try {
    await StorageService.init();
  } catch (e) {
    debugPrint('Failed to initialize StorageService: $e');
  }

  // Initialize Achievement Service
  try {
    await AchievementService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize AchievementService: $e');
  }

  // Initialize Notification Service
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize NotificationService: $e');
  }

  runApp(const AiWellnessPalApp());
}

class AiWellnessPalApp extends StatelessWidget {
  const AiWellnessPalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => AchievementService()),
        ChangeNotifierProvider(create: (_) => WellnessPlanState()),
        ChangeNotifierProvider(
          create: (_) => CheckInState(
            checkInService: CheckInService(),
            personalizationService: PersonalizationService(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => PersonalizationState()),
        ChangeNotifierProvider(create: (_) => VoiceCommandService()),
        // Premium "Conversation Mode" (Gemini Live). Idle until started; only
        // reachable through the feature-flag-gated UI, so registering it here
        // is inert in production.
        ChangeNotifierProvider(
            create: (_) => LiveConversationService(
                  // iOS uses the unified AVAudioEngine + Voice-Processing I/O
                  // pipeline (hardware AEC → no pal-voice echo in the mic).
                  // Other platforms keep the record + flutter_pcm_sound path.
                  // To roll back iOS to the old pipeline, replace
                  // NativeAecAudioIO() with RecordPcmAudioIO().
                  audioIO: defaultTargetPlatform == TargetPlatform.iOS
                      ? NativeAecAudioIO()
                      : RecordPcmAudioIO(),
                )),
        ChangeNotifierProvider(create: (_) => AppNavigationService()),
        ChangeNotifierProvider(create: (_) => NutritionState()),
        ChangeNotifierProvider(create: (_) => MealPlannerState()),
        ChangeNotifierProvider(create: (_) => CalorieBudgetState()),
        ChangeNotifierProvider(create: (_) => HydrationState()),
        ChangeNotifierProvider(
            create: (_) => SleepState(healthProvider: HealthSleepDataProvider())),
        ChangeNotifierProvider(create: (_) => MeditationState()),
        ChangeNotifierProvider(create: (_) => HabitBuilderState()),
        ChangeNotifierProvider(create: (_) => ChallengeState()),
        // Recent Gemini Live "Talk" conversations (max 3), shown as cards on
        // the Wellness Assistant page and persisted to Firestore.
        ChangeNotifierProvider(create: (_) => ConversationStore()..load()),
        // Which wellness-tool summary cards the user has added to Home. Loaded
        // up front so the Home screen can render them immediately.
        ChangeNotifierProvider(create: (_) => HomeToolCardsService()..load()),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'AI Wellness Pal',
            navigatorKey: globalNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.getLightTheme(appState.themeColor),
            darkTheme: AppTheme.getDarkTheme(appState.themeColor),
            themeMode: appState.themeMode,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(appState.textScaleFactor),
                ),
                child: OneSignalVerificationGate(
                  child: SnowOverlay(
                    child: PalWakeWordCoordinator(
                      child: Stack(
                        children: [
                          child!,
                          const AudioFloatingPlayer(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}
