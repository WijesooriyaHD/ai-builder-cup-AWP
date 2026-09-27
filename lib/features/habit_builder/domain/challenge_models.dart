import 'package:cloud_firestore/cloud_firestore.dart';

/// The wellness domain a challenge belongs to.
enum ChallengeCategory {
  hydration,
  movement,
  meditation,
  nutrition,
  sleep,
  detox,
  general,
}

extension ChallengeCategoryInfo on ChallengeCategory {
  String get label {
    switch (this) {
      case ChallengeCategory.hydration:
        return 'Hydration';
      case ChallengeCategory.movement:
        return 'Movement';
      case ChallengeCategory.meditation:
        return 'Meditation';
      case ChallengeCategory.nutrition:
        return 'Nutrition';
      case ChallengeCategory.sleep:
        return 'Sleep';
      case ChallengeCategory.detox:
        return 'Sugar reset';
      case ChallengeCategory.general:
        return 'Wellness';
    }
  }
}

/// Lifecycle state for a challenge the user has joined.
enum ChallengeStatus { upcoming, active, completed, abandoned }

/// A badge tag shown on the challenge card.
enum ChallengeBadge { beginner, popular, trending, recommended, new_ }

extension ChallengeBadgeInfo on ChallengeBadge {
  String get label {
    switch (this) {
      case ChallengeBadge.beginner:
        return 'Beginner';
      case ChallengeBadge.popular:
        return 'Popular';
      case ChallengeBadge.trending:
        return 'Trending';
      case ChallengeBadge.recommended:
        return 'Recommended';
      case ChallengeBadge.new_:
        return 'New';
    }
  }
}

/// Static definition of a challenge template (shown in the browse carousel).
class ChallengeTemplate {
  final String id;
  final String title;
  final String description;
  final String goalDescription;
  final int durationDays;
  final ChallengeCategory category;
  final ChallengeBadge badge;
  final int xpReward;
  final int wellnessPointsReward;
  final String trophyEmoji;
  final String trophyTitle;

  /// Progressive per-day steps, one entry per challenge day (index 0 = day 1).
  /// Each day is achievable and gradually harder, keeping the streak meaningful.
  /// If empty or shorter than [durationDays], callers fall back to
  /// [goalDescription] for out-of-range days.
  final List<String> dailySteps;

  const ChallengeTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.goalDescription,
    required this.durationDays,
    required this.category,
    required this.badge,
    required this.xpReward,
    required this.wellnessPointsReward,
    required this.trophyEmoji,
    required this.trophyTitle,
    this.dailySteps = const [],
  });

  /// The step instruction for a given 1-based [dayNumber]. Falls back to the
  /// overall [goalDescription] when there's no specific step for that day.
  String stepForDay(int dayNumber) {
    final idx = dayNumber - 1;
    if (idx >= 0 && idx < dailySteps.length) return dailySteps[idx];
    return goalDescription;
  }
}

/// A user's active/completed/upcoming instance of a challenge.
class UserChallenge {
  final String id;
  final String templateId;
  final String title;
  final String description;
  final String goalDescription;
  final int durationDays;
  final ChallengeCategory category;
  final ChallengeBadge badge;
  final int xpReward;
  final int wellnessPointsReward;
  final String trophyEmoji;
  final String trophyTitle;

  final DateTime startDate;
  final DateTime endDate;

  /// Number of days the user has logged progress.
  final int daysCompleted;

  /// The date (day granularity) the user last logged progress, or null if the
  /// user hasn't logged any day yet. Used to enforce one log per calendar day.
  final DateTime? lastLoggedDate;

  final ChallengeStatus status;
  final bool rewardsClaimed;

  const UserChallenge({
    required this.id,
    required this.templateId,
    required this.title,
    required this.description,
    required this.goalDescription,
    required this.durationDays,
    required this.category,
    required this.badge,
    required this.xpReward,
    required this.wellnessPointsReward,
    required this.trophyEmoji,
    required this.trophyTitle,
    required this.startDate,
    required this.endDate,
    this.daysCompleted = 0,
    this.lastLoggedDate,
    this.status = ChallengeStatus.active,
    this.rewardsClaimed = false,
  });

  // ---------------------------------------------------------------------------
  // Computed helpers
  // ---------------------------------------------------------------------------

  int get daysRemaining {
    final remaining = endDate.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  double get progressFraction =>
      durationDays == 0 ? 0 : (daysCompleted / durationDays).clamp(0.0, 1.0);

  int get progressPercent => (progressFraction * 100).round();

  bool get isCompleted => status == ChallengeStatus.completed;

  /// The 1-based day number the user is currently working on. If today is
  /// already logged, this is the day just completed; otherwise it's the next
  /// day to complete. Clamped to [durationDays].
  int get currentDayNumber {
    final day = loggedToday ? daysCompleted : daysCompleted + 1;
    return day.clamp(1, durationDays == 0 ? 1 : durationDays);
  }

  /// True if the user has already logged today's step for this challenge, so
  /// they cannot log again until the next calendar day.
  bool get loggedToday {
    final d = lastLoggedDate;
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toFirestore() => {
        'templateId': templateId,
        'title': title,
        'description': description,
        'goalDescription': goalDescription,
        'durationDays': durationDays,
        'category': category.name,
        'badge': badge.name,
        'xpReward': xpReward,
        'wellnessPointsReward': wellnessPointsReward,
        'trophyEmoji': trophyEmoji,
        'trophyTitle': trophyTitle,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'daysCompleted': daysCompleted,
        'lastLoggedDate':
            lastLoggedDate == null ? null : Timestamp.fromDate(lastLoggedDate!),
        'status': status.name,
        'rewardsClaimed': rewardsClaimed,
      };

  factory UserChallenge.fromFirestore(String id, Map<String, dynamic> m) {
    DateTime _ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.now();

    return UserChallenge(
      id: id,
      templateId: m['templateId'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      goalDescription: m['goalDescription'] as String? ?? '',
      durationDays: (m['durationDays'] as num?)?.toInt() ?? 7,
      category: ChallengeCategory.values.firstWhere(
        (c) => c.name == m['category'],
        orElse: () => ChallengeCategory.general,
      ),
      badge: ChallengeBadge.values.firstWhere(
        (b) => b.name == m['badge'],
        orElse: () => ChallengeBadge.popular,
      ),
      xpReward: (m['xpReward'] as num?)?.toInt() ?? 50,
      wellnessPointsReward:
          (m['wellnessPointsReward'] as num?)?.toInt() ?? 100,
      trophyEmoji: m['trophyEmoji'] as String? ?? '🏆',
      trophyTitle: m['trophyTitle'] as String? ?? 'Champion',
      startDate: _ts(m['startDate']),
      endDate: _ts(m['endDate']),
      daysCompleted: (m['daysCompleted'] as num?)?.toInt() ?? 0,
      lastLoggedDate:
          m['lastLoggedDate'] is Timestamp ? (m['lastLoggedDate'] as Timestamp).toDate() : null,
      status: ChallengeStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => ChallengeStatus.active,
      ),
      rewardsClaimed: m['rewardsClaimed'] as bool? ?? false,
    );
  }

  UserChallenge copyWith({
    int? daysCompleted,
    DateTime? lastLoggedDate,
    ChallengeStatus? status,
    bool? rewardsClaimed,
  }) =>
      UserChallenge(
        id: id,
        templateId: templateId,
        title: title,
        description: description,
        goalDescription: goalDescription,
        durationDays: durationDays,
        category: category,
        badge: badge,
        xpReward: xpReward,
        wellnessPointsReward: wellnessPointsReward,
        trophyEmoji: trophyEmoji,
        trophyTitle: trophyTitle,
        startDate: startDate,
        endDate: endDate,
        daysCompleted: daysCompleted ?? this.daysCompleted,
        lastLoggedDate: lastLoggedDate ?? this.lastLoggedDate,
        status: status ?? this.status,
        rewardsClaimed: rewardsClaimed ?? this.rewardsClaimed,
      );
}

/// Static catalog of challenge templates shown to all users.
class ChallengeCatalog {
  ChallengeCatalog._();

  static final List<ChallengeTemplate> all = [
    ChallengeTemplate(
      id: 'hydration_7',
      title: '7-Day Hydration Challenge',
      description: 'Build a powerful daily hydration habit, one glass at a time.',
      goalDescription: 'Drink your daily water target for 7 consecutive days.',
      durationDays: 7,
      category: ChallengeCategory.hydration,
      badge: ChallengeBadge.popular,
      xpReward: 50,
      wellnessPointsReward: 100,
      trophyEmoji: '💧',
      trophyTitle: 'Hydration Hero',
      dailySteps: const [
        'Day 1: Drink 4 glasses of water (start a glass with each meal).',
        'Day 2: Drink 5 glasses — add one first thing after waking.',
        'Day 3: Drink 6 glasses — keep a bottle at your desk.',
        'Day 4: Drink 6 glasses and swap one sugary drink for water.',
        'Day 5: Drink 7 glasses — sip between meals, not just with them.',
        'Day 6: Drink 8 glasses — your full daily target.',
        'Day 7: Hit 8 glasses and plan how you\'ll keep it going. 💧',
      ],
    ),
    ChallengeTemplate(
      id: 'walking_30',
      title: '30-Day Walking Challenge',
      description: 'Walk your way to better health, ramping up gently.',
      goalDescription:
          'Reach your daily step target for 30 consecutive days.',
      durationDays: 30,
      category: ChallengeCategory.movement,
      badge: ChallengeBadge.trending,
      xpReward: 200,
      wellnessPointsReward: 400,
      trophyEmoji: '🚶',
      trophyTitle: 'Stride Champion',
      dailySteps: _walkingSteps(),
    ),
    ChallengeTemplate(
      id: 'meditation_14',
      title: '14-Day Meditation Challenge',
      description: 'Discover the calm that comes from daily stillness.',
      goalDescription: 'Meditate at least 5 minutes every day for 2 weeks.',
      durationDays: 14,
      category: ChallengeCategory.meditation,
      badge: ChallengeBadge.recommended,
      xpReward: 100,
      wellnessPointsReward: 200,
      trophyEmoji: '🧘',
      trophyTitle: 'Mindful Soul',
      dailySteps: const [
        'Day 1: Sit quietly and breathe for 3 minutes.',
        'Day 2: 3 minutes of focused breathing — count each exhale.',
        'Day 3: 5 minutes of breath awareness.',
        'Day 4: 5 minutes — notice thoughts, gently return to the breath.',
        'Day 5: 6 minutes of stillness.',
        'Day 6: 7 minutes — try a short body scan.',
        'Day 7: 8 minutes of meditation.',
        'Day 8: 8 minutes — focus on relaxing each muscle group.',
        'Day 9: 9 minutes of quiet sitting.',
        'Day 10: 10 minutes — a full body scan.',
        'Day 11: 10 minutes of breath + gratitude.',
        'Day 12: 11 minutes of meditation.',
        'Day 13: 12 minutes — sit with whatever arises.',
        'Day 14: 12 minutes and reflect on your 2-week journey. 🧘',
      ],
    ),
    ChallengeTemplate(
      id: 'sugar_detox_7',
      title: 'Cut Back on Sugar Challenge',
      description:
          'Reset your relationship with sugar — cutting back a little each day.',
      goalDescription:
          'Reduce added sugar gradually until you reach under 25 g per day.',
      durationDays: 7,
      category: ChallengeCategory.detox,
      badge: ChallengeBadge.new_,
      xpReward: 75,
      wellnessPointsReward: 150,
      trophyEmoji: '🌿',
      trophyTitle: 'Clean Eater',
      dailySteps: const [
        'Day 1: Keep added sugar under 60 g — just cut sugary drinks.',
        'Day 2: Under 50 g — swap dessert for fruit once today.',
        'Day 3: Under 45 g — check labels and avoid one hidden-sugar snack.',
        'Day 4: Under 40 g — no sweetened drinks all day.',
        'Day 5: Under 35 g — replace a sweet snack with nuts or yogurt.',
        'Day 6: Under 30 g — dessert-free day.',
        'Day 7: Under 25 g — you\'ve reset your sugar baseline! 🌿',
      ],
    ),
    ChallengeTemplate(
      id: 'sleep_14',
      title: '14-Day Sleep Routine',
      description: 'Ease into an earlier, more consistent bedtime.',
      goalDescription: 'Be in bed before 11 PM for 14 consecutive nights.',
      durationDays: 14,
      category: ChallengeCategory.sleep,
      badge: ChallengeBadge.beginner,
      xpReward: 100,
      wellnessPointsReward: 200,
      trophyEmoji: '🌙',
      trophyTitle: 'Sleep Warrior',
      dailySteps: const [
        'Day 1: Set a target bedtime and dim lights 30 min before.',
        'Day 2: In bed by 11:45 PM — no screens for the last 15 min.',
        'Day 3: In bed by 11:45 PM — try a short wind-down routine.',
        'Day 4: In bed by 11:30 PM.',
        'Day 5: In bed by 11:30 PM — no caffeine after 4 PM.',
        'Day 6: In bed by 11:20 PM.',
        'Day 7: In bed by 11:15 PM — read instead of scrolling.',
        'Day 8: In bed by 11:15 PM.',
        'Day 9: In bed by 11:10 PM — keep the room cool and dark.',
        'Day 10: In bed by 11:05 PM.',
        'Day 11: In bed by 11:00 PM.',
        'Day 12: In bed by 11:00 PM — no screens 30 min before.',
        'Day 13: In bed by 11:00 PM — repeat your wind-down routine.',
        'Day 14: In bed by 11:00 PM and celebrate 2 weeks of better sleep! 🌙',
      ],
    ),
  ];

  /// Generates the 30-day walking step plan, ramping from ~3,000 to 10,000
  /// steps in gentle weekly increments.
  static List<String> _walkingSteps() {
    const targets = <int>[
      // Week 1
      3000, 3500, 4000, 4000, 4500, 5000, 5000,
      // Week 2
      5500, 6000, 6000, 6500, 7000, 7000, 7500,
      // Week 3
      7500, 8000, 8000, 8500, 8500, 9000, 9000,
      // Week 4+
      9000, 9500, 9500, 10000, 10000, 10000, 10000, 10000, 10000,
    ];
    return List<String>.generate(targets.length, (i) {
      final day = i + 1;
      final steps = targets[i];
      final suffix = day == 30 ? ' — final day, you did it! 🚶' : '';
      return 'Day $day: Walk ${_fmt(steps)} steps.$suffix';
    });
  }

  static String _fmt(int n) => n >= 1000
      ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k'
      : '$n';

  static ChallengeTemplate? findById(String id) {
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}
