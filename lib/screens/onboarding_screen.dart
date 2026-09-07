import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:country_picker/country_picker.dart';

import '../models/wellness_enums.dart';
import '../features/meal_planner/domain/meal_planner_models.dart';
import '../models/wellness_intention.dart';
import '../models/check_in.dart';
import '../providers/wellness_plan_state.dart';
import '../widgets/frosted_container.dart';
import '../theme/app_theme.dart';

/// The onboarding flow screen for new users.
///
/// Presents a 5-step PageView:
///   0 – Welcome
///   1 – Display name (1–50 chars; pre-filled from Google if available)
///   2 – Age range selector (18–24, 25–34, 35–44, 45–54, 55+)
///   3 – Intention selection (1–5 max; disable selection at 5)
///   4 – Completion
///
/// Persists current step index to `wellness_onboarding_step` SharedPreferences
/// on each step advance, and resumes from persisted step on re-launch before
/// completion.
///
/// Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 1.7, 1.8, 1.9, 1.10
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const String _onboardingStepKey = 'wellness_onboarding_step';

  late final PageController _pageController;
  int _currentStep = 0;

  // Step 1: Name + nationality
  final _displayNameController = TextEditingController();
  final _displayNameFocusNode = FocusNode();
  // Nationality captured via the country picker (defaults to United States).
  String _nationality = 'United States';
  String _nationalityFlag = '🇺🇸';
  // Gender (defaults to Female).
  String _gender = 'female';
  static const List<String> _genderOptions = ['female', 'male', 'other'];

  // Step 2: Age range
  String? _selectedAgeRange;
  static const List<String> _ageRanges = [
    '18–24',
    '25–34',
    '35–44',
    '45–54',
    '55+',
  ];

  // Step 3: Intentions
  final Set<_IntentionOption> _selectedIntentions = {};

  // Loading state for completion
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPersistedStep();
    _prefillDisplayName();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    _displayNameFocusNode.dispose();
    super.dispose();
  }

  /// Pre-fill the display name from the Firebase Auth user profile
  /// (e.g. from Google Sign-In).
  void _prefillDisplayName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName != null && user.displayName!.trim().isNotEmpty) {
      _displayNameController.text = user.displayName!.trim();
    }
  }

  Future<void> _loadPersistedStep() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStep = prefs.getInt(_onboardingStepKey) ?? 0;
    if (savedStep > 0 && savedStep < 5) {
      setState(() {
        _currentStep = savedStep;
      });
      // Jump to the saved step after the PageView is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(savedStep);
        }
      });
    }
  }

  Future<void> _persistStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_onboardingStepKey, step);
  }

  void _goToNextStep() {
    if (_currentStep < 4) {
      final nextStep = _currentStep + 1;
      _pageController.animateToPage(
        nextStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep = nextStep;
      });
      _persistStep(nextStep);
    }
  }

  void _goToPreviousStep() {
    if (_currentStep > 0) {
      final prevStep = _currentStep - 1;
      _pageController.animateToPage(
        prevStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep = prevStep;
      });
      _persistStep(prevStep);
    }
  }

  bool get _canProceedFromStep1 {
    final displayName = _displayNameController.text.trim();
    return displayName.isNotEmpty && displayName.length <= 50;
  }

  bool get _canProceedFromStep2 {
    return _selectedAgeRange != null;
  }

  bool get _canProceedFromStep3 {
    return _selectedIntentions.isNotEmpty;
  }

  bool get _canComplete {
    return _selectedIntentions.isNotEmpty && !_isCompleting;
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;

    setState(() {
      _isCompleting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final uid = user.uid;
      final displayName = _displayNameController.text.trim();

      // Seed the meal-planner profile with the chosen nationality and gender so
      // the AI Meal Planner tailors cuisine and plans from day one.
      final mealPlannerProfile =
          UserProfile(nationality: _nationality, gender: _gender).toMap();

      // Write user profile data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'display_name': displayName,
        'age_range': _selectedAgeRange,
        'nationality': _nationality,
        'gender': _gender,
        'meal_planner_profile': mealPlannerProfile,
        'onboarding_completed': true,
        'onboarding_completed_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Cache the meal-planner profile locally (matches MealPlanRepository key)
      // so the planner has the nationality immediately, offline too.
      final profilePrefs = await SharedPreferences.getInstance();
      await profilePrefs.setString(
          'meal_planner_profile', jsonEncode(mealPlannerProfile));

      // Also update Firebase Auth display name
      await user.updateDisplayName(displayName);

      // Write wellness intentions to Firestore subcollection
      final batch = FirebaseFirestore.instance.batch();
      final intentionsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wellness_intentions');

      final createdIntentions = <WellnessIntention>[];
      for (final option in _selectedIntentions) {
        final intention = WellnessIntention(
          id: const Uuid().v4(),
          title: option.title,
          category: option.category,
          isActive: true,
        );
        createdIntentions.add(intention);
        batch.set(intentionsRef.doc(intention.id), intention.toMap());
      }
      await batch.commit();

      // Clear the persisted onboarding step
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_onboardingStepKey);

      // Trigger plan generation (10s path with fallback per Req 1.8/1.9)
      if (mounted) {
        final planState = context.read<WellnessPlanState>();
        // Generate an initial plan with empty check-in (first time)
        final emptyCheckIn = CheckIn(
          id: const Uuid().v4(),
          date: DateTime.now(),
        );
        await planState.generatePlan(
          uid,
          emptyCheckIn,
          intentions: createdIntentions,
        );
      }

      // Navigate away - the AuthWrapper will handle routing to HomeScreen
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint('❌ OnboardingScreen._completeOnboarding error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(5, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: index <= _currentStep
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // PageView
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(theme),
                  _buildNameStep(theme),
                  _buildAgeRangeStep(theme),
                  _buildIntentionsStep(theme),
                  _buildCompletionStep(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 0: Welcome ────────────────────────────────────────────────

  Widget _buildWelcomeStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          FrostedContainer(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.spa_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to\nAI Wellness Pal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your personal wellness companion.\n'
                    'Let\'s set up your profile so we can\n'
                    'create your first personalized plan.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _goToNextStep,
              child: const Text('Get Started'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Step 1: Name ───────────────────────────────────────────────────

  /// Opens the searchable country picker and stores the selection.
  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      favorite: const ['US', 'GB', 'CA', 'AU', 'IN', 'LK'],
      onSelect: (country) {
        setState(() {
          _nationality = country.name;
          _nationalityFlag = country.flagEmoji;
        });
      },
    );
  }

  Widget _buildNameStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              'What should we call you?',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'We\'ll use this to personalize your experience.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Display Name',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _displayNameController,
                      focusNode: _displayNameFocusNode,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.borderRadius / 2),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Country',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickCountry,
                      borderRadius:
                          BorderRadius.circular(AppTheme.borderRadius / 2),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppTheme.borderRadius / 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                        ),
                        child: Row(
                          children: [
                            Text(_nationalityFlag,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _nationality,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down_rounded,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Helps us tailor meals and wellness tips to your region.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Gender',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _genderOptions.map((g) {
                        final selected = _gender == g;
                        return ChoiceChip(
                          label: Text(g[0].toUpperCase() + g.substring(1)),
                          selected: selected,
                          onSelected: (_) => setState(() => _gender = g),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                TextButton(
                  onPressed: _goToPreviousStep,
                  child: const Text('Back'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _canProceedFromStep1 ? _goToNextStep : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Age Range ──────────────────────────────────────────────

  Widget _buildAgeRangeStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            'Your age range',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us tailor wellness recommendations\nto your life stage.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _ageRanges.map((range) {
                    final isSelected = _selectedAgeRange == range;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _selectedAgeRange = range;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline.withOpacity(0.3),
                              width: isSelected ? 2 : 1,
                            ),
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary.withOpacity(0.08)
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppTheme.borderRadius / 2),
                            ),
                          ),
                          child: Text(
                            range,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _canProceedFromStep2 ? _goToNextStep : null,
                child: const Text('Continue'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Step 3: Intentions ─────────────────────────────────────────────

  Widget _buildIntentionsStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            'Your wellness intentions',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose 1–5 areas you\'d like to focus on.\nWe\'ll personalize your plans around these.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedIntentions.length}/5 selected',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView.builder(
                  itemCount: _IntentionOption.all.length,
                  itemBuilder: (context, index) {
                    final option = _IntentionOption.all[index];
                    final isSelected = _selectedIntentions.contains(option);
                    final isMaxReached = _selectedIntentions.length >= 5;
                    final isDisabled = !isSelected && isMaxReached;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Semantics(
                        button: true,
                        selected: isSelected,
                        enabled: !isDisabled,
                        label: 'Wellness intention: ${option.title}${isSelected ? ", selected" : ""}${isDisabled ? ", maximum reached" : ""}',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isDisabled
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedIntentions.remove(option);
                                      } else {
                                        _selectedIntentions.add(option);
                                      }
                                    });
                                  },
                            borderRadius:
                                BorderRadius.circular(AppTheme.borderRadius / 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  AppTheme.borderRadius / 2),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : isDisabled
                                        ? theme.colorScheme.outline
                                            .withOpacity(0.15)
                                        : theme.colorScheme.outline
                                            .withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              color: isSelected
                                  ? theme.colorScheme.primary.withOpacity(0.08)
                                  : isDisabled
                                      ? theme.colorScheme.surface
                                          .withOpacity(0.3)
                                      : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  option.icon,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : isDisabled
                                          ? theme.colorScheme.onSurface
                                              .withOpacity(0.3)
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.7),
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    option.title,
                                    style:
                                        theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isDisabled
                                          ? theme.colorScheme.onSurface
                                              .withOpacity(0.3)
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
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
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _canProceedFromStep3 ? _goToNextStep : null,
                child: const Text('Continue'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Step 4: Completion ─────────────────────────────────────────────

  Widget _buildCompletionStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          FrostedContainer(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.celebration_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'You\'re all set!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We\'ll create your first personalized\n'
                    'wellness plan based on your intentions.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (_selectedIntentions.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _selectedIntentions.map((option) {
                        return Chip(
                          avatar: Icon(option.icon, size: 16),
                          label: Text(
                            option.title,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor:
                              theme.colorScheme.primary.withOpacity(0.1),
                          side: BorderSide.none,
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 2),
          Row(
            children: [
              TextButton(
                onPressed: _isCompleting ? null : _goToPreviousStep,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _canComplete ? _completeOnboarding : null,
                child: _isCompleting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Complete'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Intention Options Data ─────────────────────────────────────────────────

/// Represents an intention option presented during onboarding.
///
/// Maps each user-facing intention to a [WellnessCategory] enum value.
class _IntentionOption {
  final String title;
  final WellnessCategory category;
  final IconData icon;

  const _IntentionOption({
    required this.title,
    required this.category,
    required this.icon,
  });

  /// All available intention options from Requirement 1.2.
  static const List<_IntentionOption> all = [
    _IntentionOption(
      title: 'Improve Flexibility',
      category: WellnessCategory.flexibility,
      icon: Icons.self_improvement,
    ),
    _IntentionOption(
      title: 'Reduce Stress',
      category: WellnessCategory.stress,
      icon: Icons.spa_outlined,
    ),
    _IntentionOption(
      title: 'Improve Sleep',
      category: WellnessCategory.sleep,
      icon: Icons.nightlight_round,
    ),
    _IntentionOption(
      title: 'Build Consistent Movement Habits',
      category: WellnessCategory.movement,
      icon: Icons.directions_walk,
    ),
    _IntentionOption(
      title: 'Improve Recovery',
      category: WellnessCategory.recovery,
      icon: Icons.favorite_outline,
    ),
    _IntentionOption(
      title: 'Increase Energy',
      category: WellnessCategory.energy,
      icon: Icons.bolt_outlined,
    ),
    _IntentionOption(
      title: 'Support Mental Clarity',
      category: WellnessCategory.mentalClarity,
      icon: Icons.psychology_outlined,
    ),
    _IntentionOption(
      title: 'Build Mindfulness Practice',
      category: WellnessCategory.mindfulness,
      icon: Icons.air,
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _IntentionOption &&
          runtimeType == other.runtimeType &&
          title == other.title;

  @override
  int get hashCode => title.hashCode;
}
