import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/check_in.dart';
import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../services/toolkit_context_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_wellness_loader.dart';
import '../widgets/frosted_container.dart';

/// A 3-step PageView modal for the daily wellness check-in.
///
/// Steps:
///   0 — Energy: 5-option visual scale (1–5)
///   1 — Mood: 6 emoji/illustrated cards
///   2 — Recovery + Time: radio group + time range selector
///
/// Each step has a "Skip" button that populates [skippedFields].
/// On final step advance: calls [CheckInState.submitCheckIn].
/// If the user exits without completing: calls [CheckInState.skipCheckIn]
/// which uses the last stored check-in (or empty) and shows a 4s banner.
///
/// Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.9, 2.10
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Selections (nullable means not yet selected or skipped)
  int? _energyScore;
  MoodState? _moodState;
  RecoveryStatus? _recoveryStatus;
  AvailableTimeRange? _availableTime;

  // Track which fields were skipped
  final List<String> _skippedFields = [];

  bool _isSubmitted = false;

  /// True from the instant Done is pressed until the screen closes.
  ///
  /// Separate from [_isSubmitted], which only guards against double
  /// submission. This one drives the UI: without it the button sat there
  /// looking pressable while the Firestore write ran, so the app read as
  /// frozen for the couple of seconds before anything appeared.
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill values if available (Premium + ≥14 check-ins)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final checkInState = context.read<CheckInState>();
      final prefill = checkInState.prefillValues;
      if (prefill != null) {
        setState(() {
          _energyScore = prefill.energyScore;
          _moodState = prefill.moodState;
          _recoveryStatus = prefill.recoveryStatus;
          _availableTime = prefill.availableTime;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    } else {
      _submitCheckIn();
    }
  }

  void _skipCurrentStep() {
    switch (_currentPage) {
      case 0:
        _skippedFields.add('energyScore');
        _energyScore = null;
        break;
      case 1:
        _skippedFields.add('moodState');
        _moodState = null;
        break;
      case 2:
        if (_recoveryStatus == null) _skippedFields.add('recoveryStatus');
        if (_availableTime == null) _skippedFields.add('availableTime');
        break;
    }
    _nextPage();
  }

  Future<void> _submitCheckIn() async {
    if (_isSubmitted) return;
    _isSubmitted = true;
    // Repaint BEFORE any await, so the loader is on screen while the Firestore
    // write happens rather than after it.
    setState(() => _isSubmitting = true);

    final checkIn = CheckIn(
      id: const Uuid().v4(),
      date: DateTime.now(),
      energyScore: _energyScore,
      moodState: _moodState,
      recoveryStatus: _recoveryStatus,
      availableTime: _availableTime,
      skippedFields: _skippedFields,
    );

    final checkInState = context.read<CheckInState>();
    final planState = context.read<WellnessPlanState>();
    final appState = context.read<AppState>();
    final intentions = appState.intentions;
    final preferredMethods = appState.preferredMethods;
    // Premium-only Life Toolkit context, assembled synchronously (BuildContext
    // must not cross the async gap). Returns null for Free users.
    final premiumToolkitContext = ToolkitContextBuilder.build(context);
    try {
      await checkInState.submitCheckIn(checkIn);
      // Trigger plan generation after successful check-in (Requirement 3.1)
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // Fire-and-forget — Home screen listens to WellnessPlanState changes
        // and also re-verifies a plan exists when the modal returns.
        planState.generatePlan(userId, checkIn,
            intentions: intentions,
            cycleContext: appState.cyclePhaseContext,
            travelContext: appState.travelContext,
            preferredMethods: preferredMethods,
            premiumToolkitContext: premiumToolkitContext);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _isSubmitted = false;
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to save check-in. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_isSubmitted) return true;
    // User is exiting without completing — call skipCheckIn
    final checkInState = context.read<CheckInState>();
    final planState = context.read<WellnessPlanState>();
    final preferredMethods = context.read<AppState>().preferredMethods;
    await checkInState.skipCheckIn();

    // A skipped check-in still needs a plan; generate one from the reused/
    // fallback check-in so the home screen doesn't get stuck on the empty
    // state. Fire-and-forget — the home screen reloads on return.
    final checkIn = checkInState.todaysCheckIn;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (checkIn != null && userId != null) {
      planState.generatePlan(userId, checkIn,
          preferredMethods: preferredMethods);
    }

    if (mounted) {
      _showSkippedBanner();
    }
    return true;
  }

  void _showSkippedBanner() {
    final checkInState = context.read<CheckInState>();
    final hasRecentCheckIn = checkInState.recentCheckIns.isNotEmpty;

    final message = hasRecentCheckIn
        ? "Today's plan is based on your previous check-in."
        : 'A default plan has been generated.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? theme.scaffoldBackgroundColor
            : AppTheme.backgroundColor,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  _buildProgressIndicator(theme),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildEnergyStep(theme, isDark),
                        _buildMoodStep(theme, isDark),
                        _buildRecoveryTimeStep(theme, isDark),
                      ],
                    ),
                  ),
                  _buildBottomButtons(theme),
                ],
              ),
            ),
            // Covers the form the moment Done is pressed, so the seconds spent
            // saving read as progress rather than a frozen screen. Absorbs
            // taps too, so nothing underneath can be pressed meanwhile.
            if (_isSubmitting) _buildSavingOverlay(theme, isDark),
          ],
        ),
      ),
    );
  }

  /// Full-screen "saving" state shown while the check-in is written and the
  /// plan starts generating.
  Widget _buildSavingOverlay(ThemeData theme, bool isDark) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: (isDark
                  ? theme.scaffoldBackgroundColor
                  : AppTheme.backgroundColor)
              .withOpacity(0.96),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AiWellnessLoader(color: theme.colorScheme.primary, size: 170),
              const SizedBox(height: 24),
              Text(
                'Saving your check-in',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Building today\'s plan around how you feel.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Daily Check-In',
            style: theme.textTheme.titleLarge,
          ),
          IconButton(
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop(false);
              }
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= _currentPage;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomButtons(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          TextButton(
            onPressed: _isSubmitting ? null : _skipCurrentStep,
            child: Text(
              'Skip',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: (_canAdvance() && !_isSubmitting) ? _nextPage : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_currentPage == 2 ? 'Done' : 'Next'),
          ),
        ],
      ),
    );
  }

  bool _canAdvance() {
    switch (_currentPage) {
      case 0:
        return _energyScore != null;
      case 1:
        return _moodState != null;
      case 2:
        // Recovery + Time: at least one selected to advance (or user can skip)
        return _recoveryStatus != null || _availableTime != null;
      default:
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Step 0 — Energy Score
  // ---------------------------------------------------------------------------

  Widget _buildEnergyStep(ThemeData theme, bool isDark) {
    const labels = {
      1: 'Completely Drained',
      2: 'Low Energy',
      3: 'Moderate Energy',
      4: 'Good Energy',
      5: 'Fully Energized',
    };

    const emojis = {
      1: '😴',
      2: '😮‍💨',
      3: '🙂',
      4: '😊',
      5: '⚡',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How is your energy today?',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Select the level that best describes how you feel right now.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 32),
          ...List.generate(5, (index) {
            final value = index + 1;
            final isSelected = _energyScore == value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                button: true,
                selected: isSelected,
                label: 'Energy level $value: ${labels[value]}',
                child: GestureDetector(
                  onTap: () => setState(() => _energyScore = value),
                  child: FrostedContainer(
                    opacity: isSelected ? 0.25 : 0.10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: isSelected
                          ? BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.borderRadius),
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              emojis[value]!,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labels[value]!,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                width: 2,
                              ),
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Mood
  // ---------------------------------------------------------------------------

  Widget _buildMoodStep(ThemeData theme, bool isDark) {
    const moodData = <MoodState, Map<String, String>>{
      MoodState.calm: {'emoji': '😌', 'label': 'Calm'},
      MoodState.anxious: {'emoji': '😰', 'label': 'Anxious'},
      MoodState.tired: {'emoji': '😩', 'label': 'Tired'},
      MoodState.energized: {'emoji': '🤩', 'label': 'Energized'},
      MoodState.stressed: {'emoji': '😣', 'label': 'Stressed'},
      MoodState.content: {'emoji': '☺️', 'label': 'Content'},
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How are you feeling?',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the mood that resonates most with you right now.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: moodData.entries.map((entry) {
              final isSelected = _moodState == entry.key;

              return Semantics(
                button: true,
                selected: isSelected,
                label: 'Mood: ${entry.value['label']}',
                child: GestureDetector(
                  onTap: () => setState(() => _moodState = entry.key),
                  child: FrostedContainer(
                    opacity: isSelected ? 0.25 : 0.10,
                    child: Container(
                      decoration: isSelected
                          ? BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.borderRadius),
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              entry.value['emoji']!,
                              style: const TextStyle(fontSize: 36),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.value['label']!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Recovery + Time
  // ---------------------------------------------------------------------------

  Widget _buildRecoveryTimeStep(ThemeData theme, bool isDark) {
    const recoveryData = <RecoveryStatus, Map<String, String>>{
      RecoveryStatus.wellRested: {'emoji': '💪', 'label': 'Well-Rested'},
      RecoveryStatus.sore: {'emoji': '🤕', 'label': 'Sore'},
      RecoveryStatus.fatigued: {'emoji': '😫', 'label': 'Fatigued'},
      RecoveryStatus.recovering: {'emoji': '🩹', 'label': 'Recovering'},
    };

    const timeData = <AvailableTimeRange, String>{
      AvailableTimeRange.under10: 'Under 10 min',
      AvailableTimeRange.range10_20: '10–20 min',
      AvailableTimeRange.range20_40: '20–40 min',
      AvailableTimeRange.range40_60: '40–60 min',
      AvailableTimeRange.over60: 'Over 60 min',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recovery & Time',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'How does your body feel, and how much time do you have today?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),

          // Recovery Status
          Text(
            'Body Recovery',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: recoveryData.entries.map((entry) {
              final isSelected = _recoveryStatus == entry.key;

              return Semantics(
                button: true,
                selected: isSelected,
                label: 'Recovery status: ${entry.value['label']}',
                child: GestureDetector(
                  onTap: () => setState(() => _recoveryStatus = entry.key),
                  child: FrostedContainer(
                    opacity: isSelected ? 0.25 : 0.10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: isSelected
                          ? BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.borderRadius),
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              entry.value['emoji']!,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.value['label']!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Available Time
          Text(
            'Available Time',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ...timeData.entries.map((entry) {
            final isSelected = _availableTime == entry.key;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => setState(() => _availableTime = entry.key),
                child: FrostedContainer(
                  opacity: isSelected ? 0.25 : 0.10,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: isSelected
                        ? BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTheme.borderRadius),
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          )
                        : null,
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          entry.value,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
