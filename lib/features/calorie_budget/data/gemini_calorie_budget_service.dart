import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../services/ai_models.dart';
import '../../../services/content_safety_filter.dart';
import '../domain/calorie_budget_models.dart';
import '../domain/calorie_budget_service.dart';

/// [CalorieBudgetService] backed by Gemini Flash (Firebase Vertex AI) for
/// richer phrasing, with a deterministic heuristic that always produces a
/// sensible prediction/insights even offline or on AI failure.
class GeminiCalorieBudgetService implements CalorieBudgetService {
  static const String _modelId = kGeminiFlashModel;
  static const int _timeoutSeconds = 15;

  final FirebaseAI _ai;

  GeminiCalorieBudgetService({FirebaseAI? ai})
      : _ai = ai ??
            FirebaseAI.agentPlatform();

  // ---------------------------------------------------------------------------
  // Prediction — heuristic first, always reliable.
  // ---------------------------------------------------------------------------
  @override
  Future<CaloriePrediction> predictEndOfDay(
    CalorieSummary summary, {
    required int hourOfDay,
    List<int> recentIntakes = const [],
  }) async {
    return _heuristicPrediction(summary,
        hourOfDay: hourOfDay, recentIntakes: recentIntakes);
  }

  CaloriePrediction _heuristicPrediction(
    CalorieSummary s, {
    required int hourOfDay,
    List<int> recentIntakes = const [],
  }) {
    // Estimate remaining intake for the rest of the day.
    // Fraction of eating-day elapsed (assume eating window ~7:00–21:00).
    final elapsed = ((hourOfDay - 7) / 14).clamp(0.05, 1.0);

    int predicted;
    if (s.consumed <= 0) {
      // Nothing logged yet — assume they'll hit their budget.
      predicted = s.dailyBudget;
    } else {
      // Project current pace to end of day, but never below what's consumed.
      final paced = (s.consumed / elapsed).round();
      predicted = paced;
      // Blend with recent behavior average if available.
      if (recentIntakes.isNotEmpty) {
        final avg =
            recentIntakes.reduce((a, b) => a + b) / recentIntakes.length;
        predicted = ((paced + avg) / 2).round();
      }
      predicted = predicted < s.consumed ? s.consumed : predicted;
    }

    final goal = s.dailyBudget + s.burned; // burn increases allowance
    final over = predicted - goal;
    final RiskLevel risk;
    if (over <= 0) {
      risk = RiskLevel.low;
    } else if (over < goal * 0.1) {
      risk = RiskLevel.medium;
    } else {
      risk = RiskLevel.high;
    }

    final rec = _heuristicRecommendation(s, predicted, goal, risk);
    return CaloriePrediction(
      predictedIntake: predicted,
      dailyGoal: goal,
      risk: risk,
      recommendation: rec,
    );
  }

  String _heuristicRecommendation(
      CalorieSummary s, int predicted, int goal, RiskLevel risk) {
    final over = predicted - goal;
    switch (risk) {
      case RiskLevel.low:
        if (s.remaining > 400) {
          return 'You still have room for a satisfying, balanced meal today.';
        }
        return "You're on track to stay within your calorie goal.";
      case RiskLevel.medium:
        final walk = (over / 4).clamp(10, 60).round();
        return 'A $walk-minute walk would offset the projected excess.';
      case RiskLevel.high:
        return 'Choose a lighter dinner or add some activity to stay on track.';
    }
  }

  // ---------------------------------------------------------------------------
  // Insights — heuristic base, optionally enhanced by Gemini.
  // ---------------------------------------------------------------------------
  @override
  Future<List<String>> generateInsights(
    CalorieSummary summary,
    CaloriePrediction prediction, {
    required int hourOfDay,
  }) async {
    final base = _heuristicInsights(summary, prediction, hourOfDay);
    try {
      final ai = await _aiInsights(summary, prediction, hourOfDay)
          .timeout(const Duration(seconds: _timeoutSeconds));
      if (ai.isNotEmpty) return ai;
    } catch (e) {
      debugPrint('ℹ️ CalorieBudget AI insights fallback: $e');
    }
    return base;
  }

  List<String> _heuristicInsights(
      CalorieSummary s, CaloriePrediction p, int hour) {
    final out = <String>[];

    if (p.risk == RiskLevel.high) {
      final over = p.predictedIntake - p.dailyGoal;
      out.add('Your current pace suggests you may exceed today\'s target by '
          '~$over kcal.');
    } else if (p.risk == RiskLevel.low) {
      out.add('You are on track to stay within your calorie goal.');
    } else {
      out.add('You\'re slightly ahead of pace — a small adjustment keeps you '
          'on target.');
    }

    if (s.burned > 0) {
      out.add('Your activity added ${s.burned} kcal of allowance today.');
    }
    if (s.remaining > 300 && hour >= 16) {
      out.add('You still have enough calories remaining for a healthy dinner.');
    }
    if (hour >= 19 && s.remaining < 200 && s.remaining >= 0) {
      out.add('Evening snacking could push you above your goal — sip water '
          'first.');
    }
    if (s.consumed == 0) {
      out.add('Log your first meal to get a personalized prediction.');
    }
    return out.take(4).toList();
  }

  Future<List<String>> _aiInsights(
      CalorieSummary s, CaloriePrediction p, int hour) async {
    final model = _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 512,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(
        'You are a supportive calorie-budget wellness advisor. Be proactive, '
        'brief, and non-judgmental. No clinical language. Respond ONLY with '
        'valid JSON.',
      ),
    );

    final prompt = '''
Daily calorie status (hour $hour of 24):
- Budget: ${s.dailyBudget} kcal
- Consumed: ${s.consumed} kcal
- Burned (exercise): ${s.burned} kcal
- Remaining: ${s.remaining} kcal
- Goal: ${s.goalMode.label}
- Predicted end-of-day intake: ${p.predictedIntake} kcal (risk: ${p.risk.label})

Give 2-3 short, actionable insights/recommendations (each under 18 words).
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
