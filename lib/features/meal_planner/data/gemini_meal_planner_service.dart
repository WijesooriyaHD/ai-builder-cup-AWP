import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../services/content_safety_filter.dart';
import '../../nutrition/domain/nutrition_models.dart';
import '../domain/meal_planner_models.dart';
import '../domain/meal_planner_service.dart';

/// [MealPlannerService] backed by Gemini 2.5 Flash via Firebase Vertex AI.
///
/// Uses the same App Check + Auth setup as the rest of the app. All AI text is
/// sanitized via [ContentSafetyFilter].
class GeminiMealPlannerService implements MealPlannerService {
  static const String _modelId = 'gemini-2.5-flash';
  static const int _dailyTimeout = 30;
  static const int _weeklyTimeout = 55;
  static const int _shortTimeout = 25;

  final FirebaseAI _ai;
  final _uuid = const Uuid();

  GeminiMealPlannerService({FirebaseAI? ai})
      : _ai = ai ??
            FirebaseAI.vertexAI(
              appCheck: FirebaseAppCheck.instance,
              auth: FirebaseAuth.instance,
            );

  GenerativeModel _model({int maxTokens = 2048}) => _ai.generativeModel(
        model: _modelId,
        generationConfig: GenerationConfig(
          temperature: 0.6,
          maxOutputTokens: maxTokens,
          responseMimeType: 'application/json',
        ),
        systemInstruction: Content.system(
          'You are an experienced, practical nutritionist who designs '
          'realistic, culturally-aware meal plans tailored to the user\'s '
          'home country and food culture. Estimate nutrition realistically. '
          'Keep meals achievable and affordable. Respond ONLY with valid JSON, '
          'no markdown or code fences. Use a warm, encouraging, non-clinical '
          'tone.',
        ),
      );

  // ---------------------------------------------------------------------------
  // Daily / multi-day plans
  // ---------------------------------------------------------------------------
  @override
  Future<MealPlan> generateDailyPlan(
    UserProfile profile, {
    DietMode dietMode = DietMode.standard,
    List<String> include = const [],
    List<String> exclude = const [],
  }) =>
      generatePlan(profile,
          planType: PlanType.daily,
          dietMode: dietMode,
          include: include,
          exclude: exclude);

  @override
  Future<MealPlan> generatePlan(
    UserProfile profile, {
    PlanType planType = PlanType.daily,
    DietMode dietMode = DietMode.standard,
    List<String> include = const [],
    List<String> exclude = const [],
  }) async {
    // Cap AI-generated days; monthly plans reuse a weekly template client-side.
    final aiDays = planType == PlanType.daily ? 1 : 7;
    try {
      final prompt = _planPrompt(profile, planType, dietMode, aiDays,
          include: include, exclude: exclude);
      final model = _model(maxTokens: aiDays == 1 ? 3072 : 8192);
      final response = await model
          .generateContent([Content.text(prompt)]).timeout(
              Duration(seconds: aiDays == 1 ? _dailyTimeout : _weeklyTimeout));

      final text = response.text;
      // Log the finish reason + a preview so failures are diagnosable.
      final finish = response.candidates.isNotEmpty
          ? response.candidates.first.finishReason
          : null;
      debugPrint('🍽️ MealPlanner Gemini (finish=$finish, '
          'len=${text?.length ?? 0}): ${text ?? "<null>"}');

      if (text == null || text.trim().isEmpty) {
        // Surface the real reason (e.g. MAX_TOKENS, SAFETY) to the UI.
        throw MealPlannerException(
            'The AI returned an empty response (reason: ${finish ?? "unknown"}).'
            ' Please try again.');
      }

      final map = _decodeObject(text);
      if (map == null) {
        throw const MealPlannerException(
            'The AI response could not be read. Please try again.');
      }
      return _planFromMap(map, profile, planType, dietMode);
    } on MealPlannerException {
      rethrow;
    } on TimeoutException {
      throw const MealPlannerException(
          'Plan generation timed out. Please try again.');
    } catch (e) {
      debugPrint('❌ GeminiMealPlannerService.generatePlan: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('app check') || msg.contains('appcheck')) {
        throw const MealPlannerException(
            'Could not verify the app with the AI service (App Check). '
            'Please try again in a moment.');
      }
      if (msg.contains('unauthenticated') ||
          msg.contains('permission') ||
          msg.contains('403')) {
        throw const MealPlannerException(
            'The AI service rejected the request. Please sign in again and '
            'retry.');
      }
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('connection')) {
        throw const MealPlannerException(
            'Network issue reaching the AI service. Check your connection.');
      }
      throw MealPlannerException('Could not generate your plan ($e).');
    }
  }

  String _planPrompt(UserProfile profile, PlanType planType, DietMode diet,
      int aiDays,
      {List<String> include = const [], List<String> exclude = const []}) {
    final b = StringBuffer();
    b.writeln('Create a $aiDays-day meal plan.');
    b.writeln('USER:');
    if (profile.age != null) b.writeln('- Age: ${profile.age}');
    if (profile.gender != null) b.writeln('- Gender: ${profile.gender}');
    if (profile.heightCm != null) {
      b.writeln('- Height: ${profile.heightCm!.round()} cm');
    }
    if (profile.weightKg != null) {
      b.writeln('- Weight: ${profile.weightKg!.round()} kg');
    }
    if (profile.goalWeightKg != null) {
      b.writeln('- Goal weight: ${profile.goalWeightKg!.round()} kg');
    }
    b.writeln('- Activity level: ${profile.activityLevel}');
    b.writeln('- Wellness goal: ${profile.goal.label}');
    b.writeln('- Daily calorie target: ~${profile.dailyCalories} kcal');
    b.writeln('- Home country / food culture: ${profile.nationality}');
    b.writeln('DIET STYLE: ${diet.promptGuidance}.');
    b.writeln('Favor foods, dishes, and ingredients that are common, familiar, '
        'and easy to buy in ${profile.nationality}.');
    if (include.isNotEmpty) {
      b.writeln('MUST INCLUDE where sensible: ${include.join(", ")}.');
    }
    if (exclude.isNotEmpty) {
      b.writeln('MUST AVOID: ${exclude.join(", ")}.');
    }
    b.writeln('''
For EACH day provide breakfast (b), lunch (l), dinner (d), and 1 snack (s).
Keys per meal: n=name, cal=calories, p=protein g, c=carbs g, f=fat g,
r=one short reason it fits the goal (max 12 words). Keep each day near the
calorie target. Provide 2-3 short overall notes in "notes".
Be concise. Output ONLY compact JSON, no whitespace, in EXACTLY this shape:
{"days":[{"b":{"n":"","cal":0,"p":0,"c":0,"f":0,"r":""},"l":{"n":"","cal":0,"p":0,"c":0,"f":0,"r":""},"d":{"n":"","cal":0,"p":0,"c":0,"f":0,"r":""},"s":{"n":"","cal":0,"p":0,"c":0,"f":0,"r":""}}],"notes":["",""]}''');
    return b.toString();
  }

  MealPlan _planFromMap(Map<String, dynamic> m, UserProfile profile,
      PlanType planType, DietMode diet) {
    final rawDays = (m['days'] as List<dynamic>?) ?? const [];
    final aiDays = <DayPlan>[];
    for (var i = 0; i < rawDays.length; i++) {
      final dm = Map<String, dynamic>.from(rawDays[i] as Map);
      aiDays.add(_dayFromMap(dm, i));
    }
    if (aiDays.isEmpty) {
      throw const MealPlannerException('The plan came back empty.');
    }

    // For monthly plans, tile the weekly template out to 30 days.
    List<DayPlan> days = aiDays;
    if (planType == PlanType.monthly) {
      days = List.generate(30, (i) {
        final src = aiDays[i % aiDays.length];
        return DayPlan(
          dayIndex: i,
          breakfast: _reid(src.breakfast),
          lunch: _reid(src.lunch),
          dinner: _reid(src.dinner),
          snacks: src.snacks.map(_reid).toList(),
        );
      });
    } else if (planType == PlanType.daily) {
      days = [aiDays.first];
    }

    final rawNotes =
        (m['notes'] ?? m['aiInsights']) as List<dynamic>? ?? const [];
    final insights = rawNotes
        .map((e) => ContentSafetyFilter.sanitize(e.toString()))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return MealPlan(
      id: _uuid.v4(),
      planType: planType,
      goal: profile.goal,
      dietMode: diet,
      dailyCalories: profile.dailyCalories,
      days: days,
      aiInsights: insights,
      createdAt: DateTime.now(),
    );
  }

  DayPlan _dayFromMap(Map<String, dynamic> dm, int index) {
    // Accept both compact keys (b/l/d/s) and full keys (breakfast/...).
    PlannedMeal meal(List<String> keys, MealType type) {
      dynamic raw;
      for (final k in keys) {
        if (dm[k] != null) {
          raw = dm[k];
          break;
        }
      }
      final map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return _sanitize(PlannedMeal.fromAi(map, type, _uuid.v4()));
    }

    // Snack can be a single object ("s") or a list ("snacks").
    final snacks = <PlannedMeal>[];
    final snackRaw = dm['s'] ?? dm['snack'] ?? dm['snacks'];
    if (snackRaw is List) {
      for (final s in snackRaw) {
        if (s is Map) {
          snacks.add(_sanitize(PlannedMeal.fromAi(
              Map<String, dynamic>.from(s), MealType.snack, _uuid.v4())));
        }
      }
    } else if (snackRaw is Map) {
      snacks.add(_sanitize(PlannedMeal.fromAi(
          Map<String, dynamic>.from(snackRaw), MealType.snack, _uuid.v4())));
    }

    return DayPlan(
      dayIndex: index,
      breakfast: meal(['b', 'breakfast'], MealType.breakfast),
      lunch: meal(['l', 'lunch'], MealType.lunch),
      dinner: meal(['d', 'dinner'], MealType.dinner),
      snacks: snacks,
    );
  }

  PlannedMeal _sanitize(PlannedMeal m) => PlannedMeal(
        id: m.id,
        type: m.type,
        name: ContentSafetyFilter.sanitize(m.name),
        calories: m.calories,
        macros: m.macros,
        reason: m.reason == null
            ? null
            : ContentSafetyFilter.sanitize(m.reason!),
      );

  PlannedMeal _reid(PlannedMeal m) => PlannedMeal(
        id: _uuid.v4(),
        type: m.type,
        name: m.name,
        calories: m.calories,
        macros: m.macros,
        reason: m.reason,
      );

  // ---------------------------------------------------------------------------
  // Meal swap
  // ---------------------------------------------------------------------------
  @override
  Future<MealSuggestion> replaceMeal(
    PlannedMeal current, {
    required UserProfile profile,
    required DietMode dietMode,
  }) async {
    try {
      final prompt = '''
Suggest 3 alternative ${current.type.label.toLowerCase()} options to replace
"${current.name}" (${current.calories} kcal, ${current.macros.protein.round()}g
protein, ${current.macros.carbs.round()}g carbs, ${current.macros.fat.round()}g fat).
Diet style: ${dietMode.promptGuidance}. Wellness goal: ${profile.goal.label}.
Each alternative MUST stay close to the same calories and macros so the plan's
targets are preserved.

Keys: n=name, cal=calories, p=protein g, c=carbs g, f=fat g, r=short reason.
Output ONLY compact JSON, no whitespace:
{"options":[{"n":"","cal":0,"p":0,"c":0,"f":0,"r":""}]}''';

      final model = _model(maxTokens: 3072);
      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: _shortTimeout));

      final text = response.text;
      final finish = response.candidates.isNotEmpty
          ? response.candidates.first.finishReason
          : null;
      debugPrint('🔁 MealPlanner swap (finish=$finish, '
          'len=${text?.length ?? 0}): ${text ?? "<null>"}');

      final map = _decodeObject(text);
      final rawOptions = (map?['options'] as List<dynamic>?) ?? const [];
      final options = rawOptions
          .whereType<Map>()
          .map((o) => _sanitize(PlannedMeal.fromAi(
              Map<String, dynamic>.from(o), current.type, _uuid.v4())))
          // Keep only options that actually have a name.
          .where((m) => m.name.trim().isNotEmpty && m.name != 'Meal')
          .take(3)
          .toList();
      if (options.isEmpty) {
        throw const MealPlannerException('No alternatives were returned.');
      }
      return MealSuggestion(type: current.type, options: options);
    } on MealPlannerException {
      rethrow;
    } on TimeoutException {
      throw const MealPlannerException('Timed out finding alternatives.');
    } catch (e) {
      debugPrint('❌ GeminiMealPlannerService.replaceMeal: $e');
      throw const MealPlannerException('Could not find alternatives.');
    }
  }

  // ---------------------------------------------------------------------------
  // Grocery list
  // ---------------------------------------------------------------------------
  @override
  Future<GroceryList> generateShoppingList(MealPlan plan) async {
    try {
      final mealNames = plan.days
          .expand((d) => d.allMeals)
          .map((m) => m.name)
          .toSet()
          .join('; ');
      final prompt = '''
Create a consolidated grocery shopping list for these meals: $mealNames.
Combine duplicate ingredients and give a realistic total quantity for the whole
plan (${plan.days.length} day(s)). Categorize each item as one of: vegetables,
fruits, proteins, dairy, grains, pantry.

Respond ONLY with valid JSON:
{ "items": [ {"name":"Eggs","quantity":"x12","category":"proteins"} ] }''';

      final model = _model(maxTokens: 3072);
      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: _shortTimeout));

      final map = _decodeObject(response.text);
      final rawItems = (map?['items'] as List<dynamic>?) ?? const [];
      final items = rawItems.map((i) {
        final im = Map<String, dynamic>.from(i as Map);
        return GroceryItem(
          name: ContentSafetyFilter.sanitize((im['name'] ?? '').toString()),
          quantity: (im['quantity'] as String?)?.trim(),
          category: GroceryCategoryInfo.fromName(im['category'] as String?),
        );
      }).where((g) => g.name.isNotEmpty).toList();

      return GroceryList(items: items);
    } on TimeoutException {
      throw const MealPlannerException('Timed out building the grocery list.');
    } catch (e) {
      debugPrint('❌ GeminiMealPlannerService.generateShoppingList: $e');
      throw const MealPlannerException('Could not build the grocery list.');
    }
  }

  // ---------------------------------------------------------------------------
  // JSON helpers
  // ---------------------------------------------------------------------------
  Map<String, dynamic>? _decodeObject(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var t = raw.replaceAll(RegExp(r'```json', caseSensitive: false), '');
    t = t.replaceAll('```', '').trim();

    // 1) Try as-is.
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    // 2) Try the first {...} block.
    try {
      final start = t.indexOf('{');
      final end = t.lastIndexOf('}');
      if (start != -1 && end > start) {
        final decoded = jsonDecode(t.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    // 3) Best-effort repair of a truncated response: strip a dangling partial
    //    key/value, then close any open strings/brackets/braces.
    try {
      final repaired = _repairTruncatedJson(t);
      if (repaired != null) {
        final decoded = jsonDecode(repaired);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    return null;
  }

  /// Attempts to close an incomplete JSON object so a truncated (but mostly
  /// complete) response can still be used.
  String? _repairTruncatedJson(String input) {
    var s = input;
    final start = s.indexOf('{');
    if (start == -1) return null;
    s = s.substring(start);

    // Trim to the last "complete-looking" boundary (end of a value or brace).
    var cut = s.length;
    for (var i = s.length - 1; i >= 0; i--) {
      final c = s[i];
      if (c == '}' || c == ']' || c == '"' ||
          RegExp(r'[0-9]').hasMatch(c)) {
        cut = i + 1;
        break;
      }
    }
    s = s.substring(0, cut);

    // Drop a trailing partial `"key":` or `"key": <partial>` with no value.
    s = s.replaceAll(RegExp(r',\s*"[^"]*"\s*:\s*$'), '');
    s = s.replaceAll(RegExp(r',\s*"[^"]*$'), '');
    s = s.replaceAll(RegExp(r',\s*$'), '');

    // Balance brackets/braces by scanning (ignoring those inside strings).
    var inString = false;
    var escape = false;
    final stack = <String>[];
    for (final ch in s.split('')) {
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') stack.add('}');
      if (ch == '[') stack.add(']');
      if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty) stack.removeLast();
      }
    }
    if (inString) s += '"';
    while (stack.isNotEmpty) {
      s += stack.removeLast();
    }
    return s;
  }
}
