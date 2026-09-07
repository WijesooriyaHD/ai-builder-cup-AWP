import 'dart:convert';

import '../../nutrition/domain/nutrition_models.dart';

/// The wellness objective a meal plan is optimized for.
enum WellnessGoal {
  weightLoss,
  weightGain,
  muscleBuilding,
  healthyLiving,
  betterEnergy,
  betterSleep,
  stressManagement,
  generalWellness,
}

extension WellnessGoalInfo on WellnessGoal {
  String get label {
    switch (this) {
      case WellnessGoal.weightLoss:
        return 'Weight Loss';
      case WellnessGoal.weightGain:
        return 'Weight Gain';
      case WellnessGoal.muscleBuilding:
        return 'Muscle Building';
      case WellnessGoal.healthyLiving:
        return 'Healthy Living';
      case WellnessGoal.betterEnergy:
        return 'Better Energy';
      case WellnessGoal.betterSleep:
        return 'Better Sleep';
      case WellnessGoal.stressManagement:
        return 'Stress Management';
      case WellnessGoal.generalWellness:
        return 'General Wellness';
    }
  }

  String get emoji {
    switch (this) {
      case WellnessGoal.weightLoss:
        return '🔥';
      case WellnessGoal.weightGain:
        return '📈';
      case WellnessGoal.muscleBuilding:
        return '💪';
      case WellnessGoal.healthyLiving:
        return '🌿';
      case WellnessGoal.betterEnergy:
        return '⚡';
      case WellnessGoal.betterSleep:
        return '🌙';
      case WellnessGoal.stressManagement:
        return '🧘';
      case WellnessGoal.generalWellness:
        return '✨';
    }
  }

  static WellnessGoal fromName(String? n) => WellnessGoal.values.firstWhere(
        (g) => g.name == n,
        orElse: () => WellnessGoal.generalWellness,
      );
}

/// Dietary style / constraints applied to a plan.
enum DietMode {
  standard,
  vegetarian,
  vegan,
  localCuisine,
  budgetFriendly,
  highProtein,
  lowCarb,
  custom,
}

extension DietModeInfo on DietMode {
  String get label {
    switch (this) {
      case DietMode.standard:
        return 'Standard';
      case DietMode.vegetarian:
        return 'Vegetarian';
      case DietMode.vegan:
        return 'Vegan';
      case DietMode.localCuisine:
        return 'Local Cuisine';
      case DietMode.budgetFriendly:
        return 'Budget-Friendly';
      case DietMode.highProtein:
        return 'High Protein';
      case DietMode.lowCarb:
        return 'Low Carb';
      case DietMode.custom:
        return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case DietMode.standard:
        return '🍽️';
      case DietMode.vegetarian:
        return '🥗';
      case DietMode.vegan:
        return '🌱';
      case DietMode.localCuisine:
        return '🍲';
      case DietMode.budgetFriendly:
        return '💰';
      case DietMode.highProtein:
        return '🥩';
      case DietMode.lowCarb:
        return '🥑';
      case DietMode.custom:
        return '⚙️';
    }
  }

  /// A concise instruction fragment injected into the AI prompt.
  String get promptGuidance {
    switch (this) {
      case DietMode.standard:
        return 'a balanced standard diet';
      case DietMode.vegetarian:
        return 'strictly vegetarian (no meat or fish; eggs and dairy allowed)';
      case DietMode.vegan:
        return 'strictly vegan (no animal-derived products at all)';
      case DietMode.localCuisine:
        return 'traditional dishes and everyday eating habits from the '
            'user\'s home country/culture';
      case DietMode.budgetFriendly:
        return 'affordable, budget-friendly, easily available ingredients';
      case DietMode.highProtein:
        return 'high protein, optimized for muscle building';
      case DietMode.lowCarb:
        return 'low carbohydrate, optimized for weight loss';
      case DietMode.custom:
        return 'the user\'s custom include/exclude preferences';
    }
  }

  static DietMode fromName(String? n) => DietMode.values.firstWhere(
        (d) => d.name == n,
        orElse: () => DietMode.standard,
      );
}

/// The time span a plan covers.
enum PlanType { daily, weekly, monthly }

extension PlanTypeInfo on PlanType {
  String get label {
    switch (this) {
      case PlanType.daily:
        return 'Daily';
      case PlanType.weekly:
        return 'Weekly';
      case PlanType.monthly:
        return 'Monthly';
    }
  }

  int get days {
    switch (this) {
      case PlanType.daily:
        return 1;
      case PlanType.weekly:
        return 7;
      case PlanType.monthly:
        return 30;
    }
  }

  static PlanType fromName(String? n) => PlanType.values.firstWhere(
        (p) => p.name == n,
        orElse: () => PlanType.daily,
      );
}

/// The user's profile used to tailor plans. Height in cm, weights in kg.
class UserProfile {
  final int? age;
  final String? gender; // free-form: 'female' / 'male' / 'other'
  final double? heightCm;
  final double? weightKg;
  final double? goalWeightKg;
  final String activityLevel; // sedentary/light/moderate/active/very_active
  final WellnessGoal goal;
  final int dailyCalories;

  /// The user's country/culture, used to steer culturally-appropriate meals
  /// (e.g. "United States", "Sri Lanka", "India"). Defaults to United States.
  final String nationality;

  const UserProfile({
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.goalWeightKg,
    this.activityLevel = 'moderate',
    this.goal = WellnessGoal.generalWellness,
    this.dailyCalories = 2000,
    this.nationality = 'United States',
  });

  /// Whether the selected [goal] requires current + goal weight to be set.
  /// Only weight-change goals need weights; others treat them as optional.
  bool get goalRequiresWeight =>
      goal == WellnessGoal.weightLoss || goal == WellnessGoal.weightGain;

  /// True when we have enough to generate a reasonable plan. A daily calorie
  /// target is always needed; weights are only required for weight-change goals.
  bool get isComplete {
    if (dailyCalories <= 0) return false;
    if (goalRequiresWeight) {
      return weightKg != null && goalWeightKg != null;
    }
    return true;
  }

  UserProfile copyWith({
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    double? goalWeightKg,
    String? activityLevel,
    WellnessGoal? goal,
    int? dailyCalories,
    String? nationality,
  }) {
    return UserProfile(
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      goalWeightKg: goalWeightKg ?? this.goalWeightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      dailyCalories: dailyCalories ?? this.dailyCalories,
      nationality: nationality ?? this.nationality,
    );
  }

  Map<String, dynamic> toMap() => {
        'age': age,
        'gender': gender,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'goalWeightKg': goalWeightKg,
        'activityLevel': activityLevel,
        'goal': goal.name,
        'dailyCalories': dailyCalories,
        'nationality': nationality,
      };

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        age: (m['age'] as num?)?.toInt(),
        gender: m['gender'] as String?,
        heightCm: (m['heightCm'] as num?)?.toDouble(),
        weightKg: (m['weightKg'] as num?)?.toDouble(),
        goalWeightKg: (m['goalWeightKg'] as num?)?.toDouble(),
        activityLevel: m['activityLevel'] as String? ?? 'moderate',
        goal: WellnessGoalInfo.fromName(m['goal'] as String?),
        dailyCalories: (m['dailyCalories'] as num?)?.toInt() ?? 2000,
        nationality: m['nationality'] as String? ?? 'United States',
      );

  String toJson() => jsonEncode(toMap());
  factory UserProfile.fromJson(String s) =>
      UserProfile.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A single planned meal (breakfast/lunch/dinner/snack) with macros + a reason.
class PlannedMeal {
  final String id;
  final MealType type;
  final String name;
  final int calories;
  final MacroNutrients macros;

  /// AI explanation for why this meal fits the plan.
  final String? reason;

  const PlannedMeal({
    required this.id,
    required this.type,
    required this.name,
    required this.calories,
    required this.macros,
    this.reason,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'name': name,
        'calories': calories,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'fiber': macros.fiber,
        'sugar': macros.sugar,
        'sodium': macros.sodiumMg,
        'reason': reason,
      };

  factory PlannedMeal.fromMap(Map<String, dynamic> m) => PlannedMeal(
        id: m['id'] as String? ?? 'pm',
        type: MealTypeInfo.fromName(m['type'] as String?),
        name: m['name'] as String? ?? 'Meal',
        calories: (m['calories'] as num?)?.round() ?? 0,
        macros: MacroNutrients.fromMap(m),
        reason: m['reason'] as String?,
      );

  /// Build from a loosely-typed AI map for a given [type].
  ///
  /// Accepts both compact keys (n/cal/p/c/f/r) and full keys
  /// (name/calories/protein/carbs/fat/reason) so the prompt schema can be
  /// token-efficient while staying backward-compatible.
  factory PlannedMeal.fromAi(Map<String, dynamic> m, MealType type, String id) {
    num? pick(List<String> keys) {
      for (final k in keys) {
        if (m[k] is num) return m[k] as num;
      }
      return null;
    }

    double d(List<String> keys) => pick(keys)?.toDouble() ?? 0.0;

    return PlannedMeal(
      id: id,
      type: type,
      name: (m['n'] ?? m['name'] ?? m['mealName'] ?? 'Meal').toString(),
      calories: pick(['cal', 'calories'])?.round() ?? 0,
      macros: MacroNutrients(
        protein: d(['p', 'protein']),
        carbs: d(['c', 'carbs']),
        fat: d(['f', 'fat']),
        fiber: d(['fiber']),
        sugar: d(['sugar']),
      ),
      reason: (m['r'] ?? m['reason'] ?? m['why'])?.toString(),
    );
  }
}

/// A full day's meals within a plan.
class DayPlan {
  final int dayIndex; // 0-based day within the plan
  final PlannedMeal breakfast;
  final PlannedMeal lunch;
  final PlannedMeal dinner;
  final List<PlannedMeal> snacks;

  const DayPlan({
    required this.dayIndex,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    this.snacks = const [],
  });

  List<PlannedMeal> get allMeals => [breakfast, lunch, dinner, ...snacks];

  int get totalCalories =>
      allMeals.fold(0, (s, m) => s + m.calories);

  MacroNutrients get totalMacros =>
      allMeals.fold(const MacroNutrients(), (s, m) => s + m.macros);

  DayPlan replace(PlannedMeal meal) {
    switch (meal.type) {
      case MealType.breakfast:
        return DayPlan(
            dayIndex: dayIndex,
            breakfast: meal,
            lunch: lunch,
            dinner: dinner,
            snacks: snacks);
      case MealType.lunch:
        return DayPlan(
            dayIndex: dayIndex,
            breakfast: breakfast,
            lunch: meal,
            dinner: dinner,
            snacks: snacks);
      case MealType.dinner:
        return DayPlan(
            dayIndex: dayIndex,
            breakfast: breakfast,
            lunch: lunch,
            dinner: meal,
            snacks: snacks);
      case MealType.snack:
        return DayPlan(
          dayIndex: dayIndex,
          breakfast: breakfast,
          lunch: lunch,
          dinner: dinner,
          snacks: [
            for (final s in snacks) if (s.id == meal.id) meal else s,
          ],
        );
    }
  }

  Map<String, dynamic> toMap() => {
        'dayIndex': dayIndex,
        'breakfast': breakfast.toMap(),
        'lunch': lunch.toMap(),
        'dinner': dinner.toMap(),
        'snacks': snacks.map((s) => s.toMap()).toList(),
      };

  factory DayPlan.fromMap(Map<String, dynamic> m) => DayPlan(
        dayIndex: (m['dayIndex'] as num?)?.toInt() ?? 0,
        breakfast:
            PlannedMeal.fromMap(Map<String, dynamic>.from(m['breakfast'] as Map)),
        lunch: PlannedMeal.fromMap(Map<String, dynamic>.from(m['lunch'] as Map)),
        dinner:
            PlannedMeal.fromMap(Map<String, dynamic>.from(m['dinner'] as Map)),
        snacks: (m['snacks'] as List<dynamic>? ?? [])
            .map((s) => PlannedMeal.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
}

/// A generated meal plan (daily/weekly/monthly) with grocery list + insights.
class MealPlan {
  final String id;
  final PlanType planType;
  final WellnessGoal goal;
  final DietMode dietMode;
  final int dailyCalories;
  final List<DayPlan> days;
  final GroceryList groceryList;
  final List<String> aiInsights;
  final DateTime createdAt;

  const MealPlan({
    required this.id,
    required this.planType,
    required this.goal,
    required this.dietMode,
    required this.dailyCalories,
    required this.days,
    this.groceryList = const GroceryList(),
    this.aiInsights = const [],
    required this.createdAt,
  });

  DayPlan get today => days.isNotEmpty ? days.first : days.first;

  MealPlan copyWith({
    List<DayPlan>? days,
    GroceryList? groceryList,
    List<String>? aiInsights,
  }) {
    return MealPlan(
      id: id,
      planType: planType,
      goal: goal,
      dietMode: dietMode,
      dailyCalories: dailyCalories,
      days: days ?? this.days,
      groceryList: groceryList ?? this.groceryList,
      aiInsights: aiInsights ?? this.aiInsights,
      createdAt: createdAt,
    );
  }

  /// Firestore document shape matching the requested schema.
  Map<String, dynamic> toMap() {
    final firstDay = days.isNotEmpty ? days.first : null;
    return {
      'planType': planType.name,
      'goal': goal.name,
      'dietMode': dietMode.name,
      'dailyCalories': dailyCalories,
      // Convenience top-level day-1 meals (spec-aligned).
      'breakfast': firstDay?.breakfast.toMap() ?? {},
      'lunch': firstDay?.lunch.toMap() ?? {},
      'dinner': firstDay?.dinner.toMap() ?? {},
      'snacks': firstDay?.snacks.map((s) => s.toMap()).toList() ?? [],
      // Full multi-day structure.
      'days': days.map((d) => d.toMap()).toList(),
      'groceryList': groceryList.toMapList(),
      'aiInsights': aiInsights,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MealPlan.fromMap(String id, Map<String, dynamic> m) {
    final rawDays = (m['days'] as List<dynamic>?) ?? const [];
    final days = rawDays
        .map((d) => DayPlan.fromMap(Map<String, dynamic>.from(d as Map)))
        .toList();
    return MealPlan(
      id: id,
      planType: PlanTypeInfo.fromName(m['planType'] as String?),
      goal: WellnessGoalInfo.fromName(m['goal'] as String?),
      dietMode: DietModeInfo.fromName(m['dietMode'] as String?),
      dailyCalories: (m['dailyCalories'] as num?)?.toInt() ?? 2000,
      days: days,
      groceryList: GroceryList.fromMapList(
          (m['groceryList'] as List<dynamic>?) ?? const []),
      aiInsights: (m['aiInsights'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap()..['id'] = id);
  factory MealPlan.fromJson(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return MealPlan.fromMap(m['id'] as String? ?? 'plan', m);
  }
}

/// Grocery categories for grouping the shopping list.
enum GroceryCategory { vegetables, fruits, proteins, dairy, grains, pantry }

extension GroceryCategoryInfo on GroceryCategory {
  String get label {
    switch (this) {
      case GroceryCategory.vegetables:
        return 'Vegetables';
      case GroceryCategory.fruits:
        return 'Fruits';
      case GroceryCategory.proteins:
        return 'Proteins';
      case GroceryCategory.dairy:
        return 'Dairy';
      case GroceryCategory.grains:
        return 'Grains';
      case GroceryCategory.pantry:
        return 'Pantry Items';
    }
  }

  String get emoji {
    switch (this) {
      case GroceryCategory.vegetables:
        return '🥬';
      case GroceryCategory.fruits:
        return '🍎';
      case GroceryCategory.proteins:
        return '🍗';
      case GroceryCategory.dairy:
        return '🥛';
      case GroceryCategory.grains:
        return '🌾';
      case GroceryCategory.pantry:
        return '🧂';
    }
  }

  static GroceryCategory fromName(String? n) {
    final norm = (n ?? '').toLowerCase();
    for (final c in GroceryCategory.values) {
      if (c.name == norm || c.label.toLowerCase() == norm) return c;
    }
    if (norm.contains('veg')) return GroceryCategory.vegetables;
    if (norm.contains('fruit')) return GroceryCategory.fruits;
    if (norm.contains('protein') || norm.contains('meat')) {
      return GroceryCategory.proteins;
    }
    if (norm.contains('dairy') || norm.contains('milk')) {
      return GroceryCategory.dairy;
    }
    if (norm.contains('grain') || norm.contains('rice')) {
      return GroceryCategory.grains;
    }
    return GroceryCategory.pantry;
  }
}

class GroceryItem {
  final String name;
  final String? quantity; // e.g. "1 kg", "×12", "6"
  final GroceryCategory category;
  final bool checked;

  const GroceryItem({
    required this.name,
    this.quantity,
    this.category = GroceryCategory.pantry,
    this.checked = false,
  });

  GroceryItem copyWith({bool? checked}) => GroceryItem(
        name: name,
        quantity: quantity,
        category: category,
        checked: checked ?? this.checked,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'category': category.name,
        'checked': checked,
      };

  factory GroceryItem.fromMap(Map<String, dynamic> m) => GroceryItem(
        name: m['name'] as String? ?? '',
        quantity: m['quantity'] as String?,
        category: GroceryCategoryInfo.fromName(m['category'] as String?),
        checked: m['checked'] as bool? ?? false,
      );
}

/// A categorized shopping list generated from a plan.
class GroceryList {
  final List<GroceryItem> items;
  const GroceryList({this.items = const []});

  bool get isEmpty => items.isEmpty;
  int get checkedCount => items.where((i) => i.checked).length;

  Map<GroceryCategory, List<GroceryItem>> get grouped {
    final map = <GroceryCategory, List<GroceryItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  GroceryList toggle(String name) => GroceryList(
        items: items
            .map((i) => i.name == name ? i.copyWith(checked: !i.checked) : i)
            .toList(),
      );

  List<Map<String, dynamic>> toMapList() =>
      items.map((i) => i.toMap()).toList();

  factory GroceryList.fromMapList(List<dynamic> list) => GroceryList(
        items: list
            .map((e) => GroceryItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Alternative meal options returned by a meal-swap request.
class MealSuggestion {
  final MealType type;
  final List<PlannedMeal> options;
  const MealSuggestion({required this.type, required this.options});
}
