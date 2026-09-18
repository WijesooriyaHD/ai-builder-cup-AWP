import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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
import 'services/remote_config_service.dart';
import 'services/voice_command_service.dart';
import 'services/live_conversation_service.dart';
import 'services/record_pcm_audio_io.dart';
import 'services/app_navigation_service.dart';
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

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Activate Firebase App Check. Firebase AI Logic requires App Check to be
  // enforced, otherwise calls fail with "Firebase AI Logic has been
  // deactivated in this project".
  //
  // In debug builds we use the debug providers so development works on
  // simulators/emulators (register the printed debug token in the Firebase
  // console → App Check). Release builds use platform attestation:
  // Play Integrity on Android and App Attest / Device Check on Apple.
  try {
    // Enable automatic token refresh so the SDK keeps a valid App Check token
    // available for downstream services (including Firebase AI Logic).
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
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

  // Initialize Remote Config (defaults + background fetch). Fail-safe: never
  // blocks startup and falls back to code defaults if unavailable.
  try {
    await RemoteConfigService.instance.initialize();
  } catch (e) {
    debugPrint('Failed to initialize RemoteConfigService: $e');
  }

  runApp(const BloomApp());
}

class BloomApp extends StatelessWidget {
  const BloomApp({super.key});

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
            create: (_) =>
                LiveConversationService(audioIO: RecordPcmAudioIO())),
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
                child: SnowOverlay(
                  child: Stack(
                    children: [
                      child!,
                      const AudioFloatingPlayer(),
                    ],
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
