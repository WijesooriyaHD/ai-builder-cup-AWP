import 'dart:convert';

/// Which part of the day a meal belongs to.
enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeInfo on MealType {
  String get label {
    switch (this) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
      case MealType.snack:
        return 'Snacks';
    }
  }

  String get emoji {
    switch (this) {
      case MealType.breakfast:
        return '🌅';
      case MealType.lunch:
        return '🍽️';
      case MealType.dinner:
        return '🌙';
      case MealType.snack:
        return '🍎';
    }
  }

  static MealType fromName(String? name) {
    return MealType.values.firstWhere(
      (m) => m.name == name,
      orElse: () => MealType.snack,
    );
  }

  /// A sensible default meal type based on the current time of day.
  static MealType forNow([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 11) return MealType.breakfast;
    if (h < 15) return MealType.lunch;
    if (h < 21) return MealType.dinner;
    return MealType.snack;
  }
}

/// Macro + micro nutrient breakdown for a meal (all amounts in grams except
/// [sodiumMg] which is milligrams).
class MacroNutrients {
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodiumMg;

  const MacroNutrients({
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.sodiumMg = 0,
  });

  MacroNutrients operator +(MacroNutrients o) => MacroNutrients(
        protein: protein + o.protein,
        carbs: carbs + o.carbs,
        fat: fat + o.fat,
        fiber: fiber + o.fiber,
        sugar: sugar + o.sugar,
        sodiumMg: sodiumMg + o.sodiumMg,
      );

  Map<String, dynamic> toMap() => {
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'sugar': sugar,
        'sodium': sodiumMg,
      };

  factory MacroNutrients.fromMap(Map<String, dynamic> m) => MacroNutrients(
        protein: _d(m['protein']),
        carbs: _d(m['carbs']),
        fat: _d(m['fat']),
        fiber: _d(m['fiber']),
        sugar: _d(m['sugar']),
        sodiumMg: _d(m['sodium']),
      );

  static double _d(dynamic v) => (v is num) ? v.toDouble() : 0.0;
}

/// The raw result of analyzing a food input (photo/text/barcode). This is the
/// provider-agnostic output of [NutritionAnalysisService]; it becomes a [Meal]
/// once the user assigns it a meal type and saves it.
class NutritionResult {
  final String mealName;
  final int calories;
  final MacroNutrients macros;

  /// Food Quality Score, 0–100.
  final int foodQualityScore;

  /// Short, supportive, non-clinical wellness insights.
  final List<String> aiInsights;

  /// Detected food items (for photo/text analysis).
  final List<String> detectedItems;

  /// Estimated serving/portion description, e.g. "1 plate (~350g)".
  final String? servingInfo;

  /// Where the analysis came from (photo / text / barcode).
  final String source;

  const NutritionResult({
    required this.mealName,
    required this.calories,
    required this.macros,
    required this.foodQualityScore,
    this.aiInsights = const [],
    this.detectedItems = const [],
    this.servingInfo,
    this.source = 'text',
  });

  NutritionResult copyWith({
    String? mealName,
    int? calories,
    MacroNutrients? macros,
    int? foodQualityScore,
    List<String>? aiInsights,
    List<String>? detectedItems,
    String? servingInfo,
    String? source,
  }) {
    return NutritionResult(
      mealName: mealName ?? this.mealName,
      calories: calories ?? this.calories,
      macros: macros ?? this.macros,
      foodQualityScore: foodQualityScore ?? this.foodQualityScore,
      aiInsights: aiInsights ?? this.aiInsights,
      detectedItems: detectedItems ?? this.detectedItems,
      servingInfo: servingInfo ?? this.servingInfo,
      source: source ?? this.source,
    );
  }
}

/// A logged meal in the user's diary. Persisted to Firestore under
/// users/{userId}/meals/{mealId}.
class Meal {
  final String id;
  final String mealName;
  final MealType mealType;
  final String? imageUrl;
  final int calories;
  final MacroNutrients macros;
  final int foodQualityScore;
  final List<String> aiInsights;
  final DateTime createdAt;

  const Meal({
    required this.id,
    required this.mealName,
    required this.mealType,
    this.imageUrl,
    required this.calories,
    required this.macros,
    required this.foodQualityScore,
    this.aiInsights = const [],
    required this.createdAt,
  });

  double get protein => macros.protein;
  double get carbs => macros.carbs;
  double get fat => macros.fat;

  factory Meal.fromResult(
    NutritionResult r, {
    required String id,
    required MealType mealType,
    String? imageUrl,
    DateTime? createdAt,
  }) {
    return Meal(
      id: id,
      mealName: r.mealName,
      mealType: mealType,
      imageUrl: imageUrl,
      calories: r.calories,
      macros: r.macros,
      foodQualityScore: r.foodQualityScore,
      aiInsights: r.aiInsights,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// Firestore/JSON shape matching the requested Meal Object schema.
  Map<String, dynamic> toMap() => {
        'mealName': mealName,
        'mealType': mealType.name,
        'imageUrl': imageUrl,
        'calories': calories,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'fiber': macros.fiber,
        'sugar': macros.sugar,
        'sodium': macros.sodiumMg,
        'foodQualityScore': foodQualityScore,
        'aiInsights': aiInsights,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Meal.fromMap(String id, Map<String, dynamic> m) => Meal(
        id: id,
        mealName: (m['mealName'] as String?) ?? 'Meal',
        mealType: MealTypeInfo.fromName(m['mealType'] as String?),
        imageUrl: m['imageUrl'] as String?,
        calories: (m['calories'] as num?)?.round() ?? 0,
        macros: MacroNutrients.fromMap(m),
        foodQualityScore: (m['foodQualityScore'] as num?)?.round() ?? 0,
        aiInsights: (m['aiInsights'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        createdAt:
            DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  String toJson() => jsonEncode(toMap()..['id'] = id);

  factory Meal.fromJson(String source) {
    final m = jsonDecode(source) as Map<String, dynamic>;
    return Meal.fromMap(m['id'] as String? ?? 'm', m);
  }
}

/// User-configurable daily nutrition goals used for progress tracking.
class NutritionGoals {
  final int calories;
  final int protein; // grams
  final int carbs; // grams
  final int fat; // grams
  final int sugar; // grams (allowance)

  const NutritionGoals({
    this.calories = 2000,
    this.protein = 90,
    this.carbs = 250,
    this.fat = 65,
    this.sugar = 50,
  });

  Map<String, dynamic> toMap() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'sugar': sugar,
      };

  factory NutritionGoals.fromMap(Map<String, dynamic> m) => NutritionGoals(
        calories: (m['calories'] as num?)?.round() ?? 2000,
        protein: (m['protein'] as num?)?.round() ?? 90,
        carbs: (m['carbs'] as num?)?.round() ?? 250,
        fat: (m['fat'] as num?)?.round() ?? 65,
        sugar: (m['sugar'] as num?)?.round() ?? 50,
      );

  NutritionGoals copyWith({
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    int? sugar,
  }) =>
      NutritionGoals(
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        sugar: sugar ?? this.sugar,
      );
}

/// Aggregated totals for a set of meals (e.g. today's diary).
class DailyTotals {
  final int calories;
  final MacroNutrients macros;
  final int mealCount;

  const DailyTotals({
    this.calories = 0,
    this.macros = const MacroNutrients(),
    this.mealCount = 0,
  });

  factory DailyTotals.fromMeals(List<Meal> meals) {
    var cals = 0;
    var macros = const MacroNutrients();
    for (final m in meals) {
      cals += m.calories;
      macros = macros + m.macros;
    }
    return DailyTotals(
      calories: cals,
      macros: macros,
      mealCount: meals.length,
    );
  }
}
