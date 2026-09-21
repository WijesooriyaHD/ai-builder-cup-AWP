import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../services/ai_models.dart';
import '../../../services/content_safety_filter.dart';
import '../domain/hydration_coach_service.dart';
import '../domain/hydration_models.dart';

/// [HydrationCoachService] backed by Gemini 2.5 Flash (Firebase Vertex AI) for
/// richer phrasing, with deterministic heuristics that always work offline.
class GeminiHydrationCoachService implements HydrationCoachService {
  static const String _modelId = kGeminiFlashModel;
  static const int _timeoutSeconds = 15;

  FirebaseAI? _aiOverride;
  FirebaseAI? _lazyAi;

  GeminiHydrationCoachService({FirebaseAI? ai}) : _aiOverride = ai;

  /// Lazily created so the pure-heuristic paths (e.g. calculateGoal) work
  /// without Firebase being initialized (also keeps unit tests light).
  FirebaseAI get _ai => _aiOverride ??= (_lazyAi ??= FirebaseAI.agentPlatform());

  // ---------------------------------------------------------------------------
  // Goal calculation (pure heuristic — reliable, instant).
  // ---------------------------------------------------------------------------
  @override
  Future<HydrationGoal> calculateGoal(
    HydrationProfile profile, {
    WeatherAdjustment weather = const WeatherAdjustment(),
  }) async {
    // Base: ~35 ml per kg body weight, defaulting to a sensible 2500 ml.
    int base;
    if (profile.weightKg != null && profile.weightKg! > 0) {
      base = (profile.weightKg! * 35).round();
    } else {
      base = 2500;
    }

    // Gender nudge (men typically need a bit more).
    if ((profile.gender ?? '').toLowerCase() == 'male') {
      base += 300;
    }

    // Activity-level baseline nudge.
    switch (profile.activityLevel) {
      case 'active':
        base += 300;
        break;
      case 'very_active':
        base += 500;
        break;
      case 'light':
        base += 100;
        break;
    }

    // Older adults: keep goal grounded (avoid overhydration guidance).
    base = base.clamp(1800, 4500);

    // Exercise adjustment: ~350 ml per 30 min of exercise today.
    final exercise = ((profile.exerciseMinutesToday / 30) * 350).round();

    return HydrationGoal(
      baseMl: base,
      exerciseAdjustmentMl: exercise,
      weatherAdjustmentMl: weather.extraMl,
    );
  }

  // ---------------------------------------------------------------------------
  // Prediction (heuristic).
  // ---------------------------------------------------------------------------
  @override
  Future<HydrationPrediction> predictCompletion({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
  }) async {
    // Waking hydration window ~7:00–22:00.
    final elapsed = ((hourOfDay - 7) / 15).clamp(0.05, 1.0);
    int predicted;
    if (consumedMl <= 0) {
      predicted = (goalMl * 0.6).round(); // pessimistic if nothing yet
    } else {
      predicted = (consumedMl / elapsed).round();
      predicted = predicted < consumedMl ? consumedMl : predicted;
    }

    final HydrationRisk risk;
    if (consumedMl >= goalMl) {
      risk = HydrationRisk.ahead;
    } else if (predicted >= goalMl * 0.95) {
      risk = HydrationRisk.onTrack;
    } else {
      risk = HydrationRisk.behind;
    }

    final remaining = (goalMl - consumedMl).clamp(0, 999999);
    final String rec;
    switch (risk) {
      case HydrationRisk.ahead:
        rec = "You're ahead of your hydration goal — nicely done.";
        break;
      case HydrationRisk.onTrack:
        rec = 'You are on track. About ${_l(remaining)} to go.';
        break;
      case HydrationRisk.behind:
        final perHour = hourOfDay < 22
            ? (remaining / (22 - hourOfDay)).clamp(0, 9999).round()
            : remaining;
        rec = 'Sip ~${_l(perHour)} per hour to reach your goal by tonight.';
        break;
    }

    return HydrationPrediction(
      predictedMl: predicted,
      goalMl: goalMl,
      risk: risk,
      recommendation: rec,
    );
  }

  // ---------------------------------------------------------------------------
  // Insights (heuristic base, optional AI enhancement).
  // ---------------------------------------------------------------------------
  @override
  Future<List<String>> generateInsights({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
    required List<HydrationEntry> entries,
    List<HydrationTrendPoint> recent = const [],
    Map<String, dynamic>? weatherContext,
  }) async {
    final base =
        _heuristicInsights(goalMl, consumedMl, hourOfDay, entries, recent);
    try {
      final ai = await _aiInsights(
              goalMl, consumedMl, hourOfDay, recent, weatherContext)
          .timeout(const Duration(seconds: _timeoutSeconds));
      if (ai.isNotEmpty) return ai;
    } catch (e) {
      debugPrint('ℹ️ Hydration AI insights fallback: $e');
    }
    return base;
  }

  List<String> _heuristicInsights(int goal, int consumed, int hour,
      List<HydrationEntry> entries, List<HydrationTrendPoint> recent) {
    final out = <String>[];
    final pct = goal <= 0 ? 0 : (consumed / goal * 100).round();

    if (consumed >= goal) {
      out.add('Hydration levels are excellent today.');
    } else if (pct >= 70) {
      out.add('You are close to your hydration goal — keep sipping.');
    } else if (hour >= 14 && pct < 50) {
      out.add('You may fall short today. Have a glass of water now.');
    }

    // Morning hydration check.
    final morningMl = entries
        .where((e) => e.timestamp.hour < 11)
        .fold<int>(0, (s, e) => s + e.amountMl);
    if (hour >= 11 && morningMl < goal * 0.25) {
      out.add('Morning hydration was light — front-load a bit tomorrow.');
    }

    // Afternoon gap detection (2–5 PM).
    final afternoon = entries
        .where((e) => e.timestamp.hour >= 14 && e.timestamp.hour < 17)
        .fold<int>(0, (s, e) => s + e.amountMl);
    if (hour >= 17 && afternoon == 0) {
      out.add('Most missed hydration happens 2–5 PM. Set a mid-afternoon sip.');
    }

    // Weekly consistency.
    if (recent.length >= 4) {
      final met = recent.where((r) => r.metGoal).length;
      out.add('You met your goal ${met}/${recent.length} of recent days.');
    }

    if (out.isEmpty) {
      out.add('Log your first glass to get personalized hydration coaching.');
    }
    return out.take(4).toList();
  }

  Future<List<String>> _aiInsights(int goal, int consumed, int hour,
      List<HydrationTrendPoint> recent,
      [Map<String, dynamic>? weatherContext]) async {
    final model = _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 512,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(
        'You are a supportive hydration coach. Be brief, encouraging, and '
        'non-clinical. Never make medical claims like "you are dehydrated"; '
        'prefer "your intake is below your target". Weather facts are provided '
        'to you — do not invent them. Respond ONLY with valid JSON.',
      ),
    );
    final recentLine = recent.isEmpty
        ? 'no history'
        : recent
            .map((r) => '${r.completion >= 1 ? "met" : "missed"}')
            .join(',');
    final weatherLine = weatherContext == null
        ? ''
        : '\n- Weather (factual): ${jsonEncode(weatherContext)}';
    final prompt = '''
Hydration status (hour $hour of 24):
- Goal: $goal ml
- Consumed: $consumed ml
- Recent days: $recentLine$weatherLine
Give 2-3 short insights/recommendations (each under 16 words). If weather is
provided and warm/humid, include a weather-aware tip.
Respond ONLY as JSON: {"insights":["",""]}''';

    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) return [];
    final map = _decode(text);
    final raw = (map?['insights'] as List<dynamic>?) ?? const [];
    return raw
        .map((e) => ContentSafetyFilter.sanitize(e.toString()))
        .where((s) => s.trim().isNotEmpty)
        .take(4)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Reminders (heuristic, behavior-based).
  // ---------------------------------------------------------------------------
  @override
  Future<List<Reminder>> generateReminders({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
    required List<HydrationEntry> entries,
  }) async {
    final out = <Reminder>[];
    final remaining = (goalMl - consumedMl).clamp(0, 999999);

    // Time since last log.
    if (entries.isNotEmpty) {
      final last = entries
          .map((e) => e.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final gap = DateTime.now().difference(last).inHours;
      if (gap >= 3) {
        out.add(Reminder(
            message: "You haven't logged water for $gap hours.",
            tone: 'nudge'));
      }
    } else if (hourOfDay >= 9) {
      out.add(const Reminder(
          message: 'Morning hydration is still pending.', tone: 'nudge'));
    }

    if (remaining > 0 && remaining <= 600) {
      out.add(Reminder(
          message: 'Only ${_l(remaining)} remaining to reach today\'s goal.',
          tone: 'gentle'));
    }
    if (consumedMl >= goalMl) {
      out.add(const Reminder(
          message: 'Great progress today. Keep it up!', tone: 'celebratory'));
    }
    if (hourOfDay >= 11 && hourOfDay <= 13 && remaining > 0) {
      out.add(const Reminder(
          message: 'Drink water before your next meal.', tone: 'gentle'));
    }
    return out.take(3).toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _l(int ml) =>
      ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1)}L' : '${ml}ml';

  Map<String, dynamic>? _decode(String raw) {
    try {
      var t = raw.replaceAll(RegExp(r'```json', caseSensitive: false), '');
      t = t.replaceAll('```', '').trim();
      final d = jsonDecode(t);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {
      try {
        final a = raw.indexOf('{');
        final b = raw.lastIndexOf('}');
        if (a != -1 && b > a) {
          final d = jsonDecode(raw.substring(a, b + 1));
          if (d is Map<String, dynamic>) return d;
        }
      } catch (_) {}
    }
    return null;
  }
}
