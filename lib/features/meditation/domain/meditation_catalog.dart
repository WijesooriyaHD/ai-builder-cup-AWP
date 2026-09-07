import 'meditation_models.dart';

/// The static content catalog for the Meditation & Mindfulness tool. Kept out
/// of widgets so content can grow (or move to remote config) independently.
class MeditationCatalog {
  MeditationCatalog._();

  // ---------------------------------------------------------------------------
  // Guided meditations, grouped by category (in display order).
  // ---------------------------------------------------------------------------
  static const List<String> categories = [
    'Beginner Meditation',
    'Stress Relief',
    'Sleep Meditation',
    'Anxiety Reduction',
    'Focus & Productivity',
    'Morning Energy',
    'Evening Relaxation',
    'Gratitude',
    'Self-Compassion',
  ];

  static const List<GuidedMeditation> guided = [
    GuidedMeditation(
      id: 'g_first_breath',
      title: 'Your First Breath',
      description: 'A gentle introduction to meditation for complete beginners.',
      category: 'Beginner Meditation',
      durationMinutes: 5,
      difficulty: Difficulty.beginner,
      emoji: '🌱',
    ),
    GuidedMeditation(
      id: 'g_deep_relax',
      title: 'Deep Relaxation',
      description: 'Release tension and settle into a calm, easy stillness.',
      category: 'Beginner Meditation',
      durationMinutes: 10,
      difficulty: Difficulty.beginner,
      emoji: '🕊️',
    ),
    GuidedMeditation(
      id: 'g_stress_melt',
      title: 'Melt the Stress',
      description: 'Let go of the day\'s pressure with a soothing guided reset.',
      category: 'Stress Relief',
      durationMinutes: 8,
      difficulty: Difficulty.beginner,
      emoji: '😌',
    ),
    GuidedMeditation(
      id: 'g_sleep_drift',
      title: 'Drift Into Sleep',
      description: 'A slow, quieting practice to help you fall asleep.',
      category: 'Sleep Meditation',
      durationMinutes: 15,
      difficulty: Difficulty.beginner,
      emoji: '🌙',
    ),
    GuidedMeditation(
      id: 'g_anxiety_ease',
      title: 'Ease Anxious Thoughts',
      description: 'Steady your mind and soften anxious feelings.',
      category: 'Anxiety Reduction',
      durationMinutes: 10,
      difficulty: Difficulty.intermediate,
      emoji: '🫧',
    ),
    GuidedMeditation(
      id: 'g_focus_flow',
      title: 'Focus & Flow',
      description: 'Sharpen attention before deep work or study.',
      category: 'Focus & Productivity',
      durationMinutes: 7,
      difficulty: Difficulty.intermediate,
      emoji: '🎯',
    ),
    GuidedMeditation(
      id: 'g_morning_spark',
      title: 'Morning Spark',
      description: 'Wake up your body and set a calm, positive intention.',
      category: 'Morning Energy',
      durationMinutes: 6,
      difficulty: Difficulty.beginner,
      emoji: '☀️',
    ),
    GuidedMeditation(
      id: 'g_evening_unwind',
      title: 'Evening Unwind',
      description: 'Transition gently from the day into a restful evening.',
      category: 'Evening Relaxation',
      durationMinutes: 10,
      difficulty: Difficulty.beginner,
      emoji: '🌇',
    ),
    GuidedMeditation(
      id: 'g_gratitude',
      title: 'A Grateful Heart',
      description: 'Reflect on what\'s good and cultivate genuine gratitude.',
      category: 'Gratitude',
      durationMinutes: 8,
      difficulty: Difficulty.beginner,
      emoji: '🙏',
    ),
    GuidedMeditation(
      id: 'g_self_compassion',
      title: 'Be Kind to Yourself',
      description: 'A warm loving-kindness practice for self-compassion.',
      category: 'Self-Compassion',
      durationMinutes: 12,
      difficulty: Difficulty.intermediate,
      emoji: '💗',
    ),
  ];

  static List<GuidedMeditation> guidedFor(String category) =>
      guided.where((g) => g.category == category).toList();

  // ---------------------------------------------------------------------------
  // Breathing patterns.
  // ---------------------------------------------------------------------------
  static const List<BreathingPattern> breathing = [
    BreathingPattern(
      id: 'box',
      name: 'Box Breathing',
      description: 'Equal 4-4-4-4 rhythm to calm and center.',
      inhale: 4,
      hold1: 4,
      exhale: 4,
      hold2: 4,
    ),
    BreathingPattern(
      id: '478',
      name: '4-7-8 Breathing',
      description: 'A relaxing pattern that eases you toward rest.',
      inhale: 4,
      hold1: 7,
      exhale: 8,
    ),
    BreathingPattern(
      id: 'calm',
      name: 'Calm Breathing',
      description: 'Simple 5-in, 5-out to steady the nervous system.',
      inhale: 5,
      exhale: 5,
    ),
    BreathingPattern(
      id: 'stress',
      name: 'Stress Relief Breathing',
      description: 'Longer exhale (4-2-6) to release tension quickly.',
      inhale: 4,
      hold1: 2,
      exhale: 6,
    ),
  ];

  static const List<int> breathingDurations = [1, 3, 5, 10]; // minutes

  // ---------------------------------------------------------------------------
  // Body scan sessions + regions.
  // ---------------------------------------------------------------------------
  static const List<BodyScanSession> bodyScans = [
    BodyScanSession(
      id: 'bs_quick',
      title: 'Quick Body Scan',
      durationMinutes: 5,
      description: 'A brief head-to-toe check-in to release tension.',
    ),
    BodyScanSession(
      id: 'bs_full',
      title: 'Full Body Scan',
      durationMinutes: 15,
      description: 'A thorough, unhurried scan of the whole body.',
    ),
    BodyScanSession(
      id: 'bs_sleep',
      title: 'Sleep Body Scan',
      durationMinutes: 10,
      description: 'A soothing scan designed to help you drift off.',
    ),
    BodyScanSession(
      id: 'bs_stress',
      title: 'Stress Release Body Scan',
      durationMinutes: 8,
      description: 'Find and soften areas holding stress.',
    ),
  ];

  static const List<String> bodyRegions = [
    'Head',
    'Face',
    'Neck',
    'Shoulders',
    'Arms',
    'Chest',
    'Abdomen',
    'Legs',
    'Feet',
  ];

  // ---------------------------------------------------------------------------
  // Stress-relief exercises.
  // ---------------------------------------------------------------------------
  static const List<StressExercise> stressExercises = [
    StressExercise(
      id: 's_grounding',
      title: '5-4-3-2-1 Grounding',
      durationMinutes: 3,
      benefits: 'Anchors you in the present and interrupts spiraling thoughts.',
      emoji: '🌳',
      steps: [
        'Name 5 things you can see.',
        'Name 4 things you can feel.',
        'Name 3 things you can hear.',
        'Name 2 things you can smell.',
        'Name 1 thing you can taste.',
      ],
    ),
    StressExercise(
      id: 's_pmr',
      title: 'Progressive Muscle Relaxation',
      durationMinutes: 6,
      benefits: 'Releases physical tension held across the body.',
      emoji: '💪',
      steps: [
        'Tense your feet for 5 seconds, then release.',
        'Move up to your legs — tense, then release.',
        'Continue with your torso, arms, and shoulders.',
        'Finish with your face and jaw.',
        'Notice the wave of relaxation left behind.',
      ],
    ),
    StressExercise(
      id: 's_pause',
      title: 'Mindful Pause',
      durationMinutes: 2,
      benefits: 'A quick reset between tasks or stressful moments.',
      emoji: '⏸️',
      steps: [
        'Stop what you\'re doing.',
        'Take three slow, deep breaths.',
        'Notice how your body feels, without judging.',
        'Set one small, kind intention for the next moment.',
      ],
    ),
    StressExercise(
      id: 's_gratitude',
      title: 'Gratitude Reflection',
      durationMinutes: 3,
      benefits: 'Shifts focus toward the positive and calms the mind.',
      emoji: '🙏',
      steps: [
        'Think of one person you\'re grateful for.',
        'Recall one small thing that went well today.',
        'Notice one comfort you often take for granted.',
        'Rest in the warmth of that appreciation.',
      ],
    ),
    StressExercise(
      id: 's_visualize',
      title: 'Positive Visualization',
      durationMinutes: 4,
      benefits: 'Creates a calm mental refuge you can return to.',
      emoji: '🏞️',
      steps: [
        'Close your eyes and picture a peaceful place.',
        'Notice the colors, sounds, and warmth there.',
        'Let yourself fully arrive in that scene.',
        'Carry a little of its calm with you as you return.',
      ],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Sleep meditations.
  // ---------------------------------------------------------------------------
  static const List<SleepMeditation> sleep = [
    SleepMeditation(
      id: 'sl_fall',
      title: 'Falling Asleep',
      description: 'A gentle guide toward effortless sleep.',
      durationMinutes: 15,
      emoji: '😴',
    ),
    SleepMeditation(
      id: 'sl_quiet',
      title: 'Quieting the Mind',
      description: 'Settle a busy mind before bed.',
      durationMinutes: 12,
      emoji: '🌌',
    ),
    SleepMeditation(
      id: 'sl_deep',
      title: 'Deep Sleep',
      description: 'Sink into deep, restorative rest.',
      durationMinutes: 20,
      emoji: '🌙',
    ),
    SleepMeditation(
      id: 'sl_anxiety',
      title: 'Night Anxiety Relief',
      description: 'Soothe late-night worry and racing thoughts.',
      durationMinutes: 12,
      emoji: '🫧',
    ),
    SleepMeditation(
      id: 'sl_body',
      title: 'Body Relaxation',
      description: 'Relax the body fully, one part at a time.',
      durationMinutes: 10,
      emoji: '💆',
    ),
    SleepMeditation(
      id: 'sl_rain',
      title: 'Rain Sounds',
      description: 'Drift off to the soft rhythm of rainfall.',
      durationMinutes: 30,
      emoji: '🌧️',
    ),
    SleepMeditation(
      id: 'sl_ocean',
      title: 'Ocean Sounds',
      description: 'Let gentle waves carry you to sleep.',
      durationMinutes: 30,
      emoji: '🌊',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Achievements (with unlock rules evaluated in the repository/state).
  // ---------------------------------------------------------------------------
  static const List<MindfulnessAchievement> achievements = [
    MindfulnessAchievement(
      id: 'med_first_session',
      title: 'First Breath',
      description: 'Complete your very first meditation session.',
      emoji: '🌱',
    ),
    MindfulnessAchievement(
      id: 'med_streak_7',
      title: '7-Day Practice',
      description: 'Sit in stillness 7 days in a row.',
      emoji: '🕯️',
    ),
    MindfulnessAchievement(
      id: 'med_streak_30',
      title: 'Deep Roots',
      description: 'Sustain a daily meditation practice for 30 days.',
      emoji: '🌳',
    ),
    MindfulnessAchievement(
      id: 'med_minutes_100',
      title: '100 Mindful Minutes',
      description: 'Accumulate 100 minutes of meditation practice.',
      emoji: '⏳',
    ),
    MindfulnessAchievement(
      id: 'med_breathing_master',
      title: 'Breath Master',
      description: 'Complete 10 dedicated breathing sessions.',
      emoji: '🌬️',
    ),
    MindfulnessAchievement(
      id: 'med_explorer',
      title: 'Mindful Explorer',
      description: 'Experience 4 different types of meditation.',
      emoji: '🧭',
    ),
    MindfulnessAchievement(
      id: 'med_champion',
      title: 'Meditation Champion',
      description: 'Complete 50 meditation sessions.',
      emoji: '👑',
    ),
  ];
}
