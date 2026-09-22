import 'package:flutter_test/flutter_test.dart';

import 'package:aiwellnesspal/features/meal_planner/domain/meal_planner_models.dart';
import 'package:aiwellnesspal/features/nutrition/domain/nutrition_models.dart';

/// Validates that generated meal plans are correctly stored and retrieved.
///
/// The repository dual-writes each plan as:
///   - Firestore document via `MealPlan.toMap()` (read back with `fromMap`)
///   - Local SharedPreferences string via `MealPlan.toJson()` (read back with
///     `fromJson`)
///
/// These tests exercise both round-trips for daily, weekly, and monthly plans,
/// with special attention to the monthly plan retaining all 30 days (the data
/// behind the Monthly overview).
void main() {
  PlannedMeal meal(String name, MealType type, int cal) => PlannedMeal(
        id: 'id-$name',
        type: type,
        name: name,
        calories: cal,
        macros: MacroNutrients(
          protein: cal / 40,
          carbs: cal / 20,
          fat: cal / 60,
          fiber: 3,
          sugar: 5,
        ),
        reason: 'because $name',
      );

  DayPlan day(int index) => DayPlan(
        dayIndex: index,
        breakfast: meal('Oats $index', MealType.breakfast, 350),
        lunch: meal('Rice bowl $index', MealType.lunch, 600),
        dinner: meal('Grilled fish $index', MealType.dinner, 550),
        snacks: [meal('Fruit $index', MealType.snack, 120)],
      );

  MealPlan buildPlan(PlanType type) {
    final dayCount = type.days; // 1 / 7 / 30
    return MealPlan(
      id: 'plan-${type.name}',
      planType: type,
      goal: WellnessGoal.weightLoss,
      dietMode: DietMode.vegetarian,
      dailyCalories: 1800,
      days: List.generate(dayCount, day),
      aiInsights: const ['Hydrate well', 'Front-load protein'],
      createdAt: DateTime.parse('2026-01-02T03:04:05.000'),
    );
  }

  void expectPlansEqual(MealPlan a, MealPlan b) {
    expect(b.id, a.id);
    expect(b.planType, a.planType);
    expect(b.goal, a.goal);
    expect(b.dietMode, a.dietMode);
    expect(b.dailyCalories, a.dailyCalories);
    expect(b.days.length, a.days.length);
    expect(b.aiInsights, a.aiInsights);
    expect(b.createdAt.toIso8601String(), a.createdAt.toIso8601String());
    for (var i = 0; i < a.days.length; i++) {
      final da = a.days[i];
      final db = b.days[i];
      expect(db.dayIndex, da.dayIndex, reason: 'day $i index');
      expect(db.breakfast.name, da.breakfast.name, reason: 'day $i breakfast');
      expect(db.lunch.name, da.lunch.name, reason: 'day $i lunch');
      expect(db.dinner.name, da.dinner.name, reason: 'day $i dinner');
      expect(db.snacks.length, da.snacks.length, reason: 'day $i snacks');
      expect(db.totalCalories, da.totalCalories, reason: 'day $i calories');
    }
  }

  group('Firestore round-trip (toMap/fromMap)', () {
    for (final type in PlanType.values) {
      test('${type.name} plan survives toMap → fromMap', () {
        final plan = buildPlan(type);
        final restored = MealPlan.fromMap(plan.id, plan.toMap());
        expectPlansEqual(plan, restored);
      });
    }

    test('monthly plan retains all 30 days through Firestore serialization',
        () {
      final plan = buildPlan(PlanType.monthly);
      expect(plan.days.length, 30);
      final restored = MealPlan.fromMap(plan.id, plan.toMap());
      expect(restored.days.length, 30,
          reason: 'Monthly overview needs every day to be persisted');
      // Day indices must remain contiguous 0..29 so week grouping is correct.
      for (var i = 0; i < 30; i++) {
        expect(restored.days[i].dayIndex, i);
      }
    });
  });

  group('Local cache round-trip (toJson/fromJson)', () {
    for (final type in PlanType.values) {
      test('${type.name} plan survives toJson → fromJson', () {
        final plan = buildPlan(type);
        final restored = MealPlan.fromJson(plan.toJson());
        expectPlansEqual(plan, restored);
      });
    }

    test('monthly plan retains all 30 days through local cache serialization',
        () {
      final plan = buildPlan(PlanType.monthly);
      final restored = MealPlan.fromJson(plan.toJson());
      expect(restored.days.length, 30);
    });
  });

  group('Firestore document shape', () {
    test('monthly toMap exposes both full days array and day-1 convenience keys',
        () {
      final plan = buildPlan(PlanType.monthly);
      final map = plan.toMap();
      // Full multi-day structure used by the Monthly overview.
      expect((map['days'] as List).length, 30);
      // Spec-aligned convenience top-level meals (day 1) for quick reads.
      expect(map['breakfast'], isA<Map<String, dynamic>>());
      expect(map['planType'], 'monthly');
      expect(map['dailyCalories'], 1800);
    });
  });
}
