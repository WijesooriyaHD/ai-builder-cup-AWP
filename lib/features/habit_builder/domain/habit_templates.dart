import 'habit_models.dart';

/// A suggestion shown in the "Add from suggestions" sheet.
class HabitTemplate {
  final String title;
  final String description;
  final HabitTool tool;
  final HabitFrequency frequency;
  final double? targetValue;
  final String? targetUnit;

  const HabitTemplate({
    required this.title,
    required this.description,
    required this.tool,
    this.frequency = HabitFrequency.daily,
    this.targetValue,
    this.targetUnit,
  });
}

/// Static catalog — one section per wellness tool.
class HabitTemplateCatalog {
  HabitTemplateCatalog._();

  static const List<HabitTemplate> all = [
    // ── Hydration ─────────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Drink 8 glasses of water',
      description: 'Stay consistently hydrated throughout the day.',
      tool: HabitTool.hydration,
      targetValue: 8,
      targetUnit: 'glasses',
    ),
    HabitTemplate(
      title: 'Drink 2 L of water',
      description: 'Hit your daily hydration goal.',
      tool: HabitTool.hydration,
      targetValue: 2,
      targetUnit: 'litres',
    ),
    HabitTemplate(
      title: 'Morning glass of water',
      description: 'Start every morning with a full glass of water before anything else.',
      tool: HabitTool.hydration,
    ),

    // ── Sleep ─────────────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Sleep before 11 PM',
      description: 'Consistent sleep timing improves quality and recovery.',
      tool: HabitTool.sleep,
    ),
    HabitTemplate(
      title: 'Get 7–8 hours of sleep',
      description: 'Hit your nightly sleep target.',
      tool: HabitTool.sleep,
      targetValue: 7.5,
      targetUnit: 'hours',
    ),
    HabitTemplate(
      title: 'No screens 30 mins before bed',
      description: 'Blue light blocks melatonin and delays sleep onset.',
      tool: HabitTool.sleep,
    ),

    // ── Meditation ────────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Meditate for 5 minutes',
      description: 'A short daily session builds a lasting mindfulness habit.',
      tool: HabitTool.meditation,
      targetValue: 5,
      targetUnit: 'mins',
    ),
    HabitTemplate(
      title: 'Morning breathing exercise',
      description: 'Start the day with box breathing or 4-7-8 to set a calm tone.',
      tool: HabitTool.meditation,
    ),
    HabitTemplate(
      title: 'Evening wind-down meditation',
      description: 'A short body scan or sleep meditation to ease into rest.',
      tool: HabitTool.meditation,
    ),

    // ── Nutrition ─────────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Log every meal',
      description: 'Awareness is the first step — track what you eat each day.',
      tool: HabitTool.nutrition,
    ),
    HabitTemplate(
      title: 'Eat 5 portions of fruit & veg',
      description: 'Hit your daily plant-food target.',
      tool: HabitTool.nutrition,
      targetValue: 5,
      targetUnit: 'portions',
    ),
    HabitTemplate(
      title: 'No processed food today',
      description: 'Choose whole, minimally processed foods for the full day.',
      tool: HabitTool.nutrition,
    ),

    // ── Calorie Budget ────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Stay within calorie budget',
      description: 'Keep daily intake within your personalised calorie target.',
      tool: HabitTool.calorieBudget,
    ),
    HabitTemplate(
      title: 'Hit protein goal',
      description: 'Meet your daily protein target to support muscle and satiety.',
      tool: HabitTool.calorieBudget,
    ),

    // ── Meal Planner ──────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Follow today\'s meal plan',
      description: 'Eat all three planned meals from your weekly plan.',
      tool: HabitTool.mealPlanner,
    ),
    HabitTemplate(
      title: 'Prep tomorrow\'s meals tonight',
      description: 'A 15-minute prep session prevents unhealthy impulsive choices.',
      tool: HabitTool.mealPlanner,
    ),

    // ── Weight Tracker ────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Log my weight',
      description: 'Consistent morning weigh-ins provide accurate trend data.',
      tool: HabitTool.weightTracker,
      frequency: HabitFrequency.daily,
    ),
    HabitTemplate(
      title: 'Walk 8,000 steps',
      description: 'Daily movement supports weight management and heart health.',
      tool: HabitTool.weightTracker,
      targetValue: 8000,
      targetUnit: 'steps',
    ),

    // ── Period Tracker ────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Log period symptoms',
      description: 'Track daily symptoms to identify patterns over time.',
      tool: HabitTool.periodTracker,
    ),
    HabitTemplate(
      title: 'Take iron-rich food during period',
      description: 'Support energy levels with iron-rich foods during menstruation.',
      tool: HabitTool.periodTracker,
    ),

    // ── Mindful Travel ────────────────────────────────────────────────────────
    HabitTemplate(
      title: 'Mindful moment while travelling',
      description: 'Take 5 minutes each day on a trip to be fully present without a screen.',
      tool: HabitTool.mindfulTravel,
    ),
    HabitTemplate(
      title: 'Stay hydrated on travel days',
      description: 'Drink extra water on flights and transit to counter dehydration.',
      tool: HabitTool.mindfulTravel,
    ),
  ];

  /// All templates grouped by tool.
  static Map<HabitTool, List<HabitTemplate>> get byTool {
    final map = <HabitTool, List<HabitTemplate>>{};
    for (final t in all) {
      map.putIfAbsent(t.tool, () => []).add(t);
    }
    return map;
  }

  static List<HabitTemplate> forTool(HabitTool tool) =>
      all.where((t) => t.tool == tool).toList();
}
