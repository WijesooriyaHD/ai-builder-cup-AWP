import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../services/content_safety_filter.dart';

/// Privacy-safe context for a mindfulness recommendation (no identifiers).
class MindfulnessContext {
  final int currentStreak;
  final int minutesThisWeek;
  final int? lastSleepMinutes; // from Sleep Coach, if available
  final int? hydrationPercent; // % of goal, if available
  final int? exerciseMinutesToday; // if available
  final int hourOfDay;

  const MindfulnessContext({
    this.currentStreak = 0,
    this.minutesThisWeek = 0,
    this.lastSleepMinutes,
    this.hydrationPercent,
    this.exerciseMinutesToday,
    required this.hourOfDay,
  });

  Map<String, dynamic> toJsonContext() => {
        'currentStreak': currentStreak,
        'minutesThisWeek': minutesThisWeek,
        if (lastSleepMinutes != null) 'lastSleepMinutes': lastSleepMinutes,
        if (hydrationPercent != null) 'hydrationPercent': hydrationPercent,
        if (exerciseMinutesToday != null)
          'exerciseMinutesToday': exerciseMinutesToday,
        'hourOfDay': hourOfDay,
      };
}

/// Generates a short mindfulness recommendation. Heuristic-first (works
/// offline / for free users), optionally enriched by Gemini.
class GeminiMindfulnessCoach {
  static const String _modelId = 'gemini-2.5-flash';
  static const int _timeoutSeconds = 12;

  FirebaseAI? _override;
  FirebaseAI? _lazy;

  GeminiMindfulnessCoach({FirebaseAI? ai}) : _override = ai;

  FirebaseAI get _ai => _override ??= (_lazy ??= FirebaseAI.vertexAI());

  Future<String> recommend(MindfulnessContext ctx) async {
    final base = _heuristic(ctx);
    try {
      final ai = await _aiRecommend(ctx).timeout(
          const Duration(seconds: _timeoutSeconds));
      if (ai != null && ai.trim().isNotEmpty) return ai;
    } catch (e) {
      debugPrint('ℹ️ Mindfulness AI recommend fallback: $e');
    }
    return base;
  }

  String _heuristic(MindfulnessContext ctx) {
    // Sleep-driven.
    if (ctx.lastSleepMinutes != null && ctx.lastSleepMinutes! < 390) {
      return 'You slept a little less than usual. Try a 10-minute body scan '
          'today to support recovery.';
    }
    // Hydration-driven.
    if (ctx.hydrationPercent != null && ctx.hydrationPercent! < 40) {
      return 'Take a mindful pause, sip some water, and try a 5-minute calm '
          'breathing session.';
    }
    // Streak encouragement.
    if (ctx.currentStreak >= 7) {
      return "You're maintaining a wonderful streak. Try a longer guided "
          'session today to go deeper.';
    }
    // Time-of-day.
    if (ctx.hourOfDay >= 20) {
      return 'Wind down with a sleep meditation or 4-7-8 breathing before bed.';
    }
    if (ctx.hourOfDay < 11) {
      return 'Start your day grounded — a 6-minute Morning Spark meditation '
          'sets a calm tone.';
    }
    return 'Try a 5-minute breathing session to reset and reduce stress.';
  }

  Future<String?> _aiRecommend(MindfulnessContext ctx) async {
    final model = _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: 0.6,
        maxOutputTokens: 256,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(
        'You are a calm, supportive mindfulness coach. Suggest ONE short, '
        'specific practice for right now (breathing, guided meditation, body '
        'scan, or sleep meditation) based on the context. Non-clinical, '
        'encouraging, under 24 words. Respond ONLY with valid JSON.',
      ),
    );
    final prompt = '''
User wellness context (factual, privacy-safe):
${jsonEncode(ctx.toJsonContext())}
Respond ONLY as JSON: {"recommendation": "one short suggestion"}''';

    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) return null;
    final map = _decode(text);
    final rec = map?['recommendation'];
    if (rec is String && rec.trim().isNotEmpty) {
      return ContentSafetyFilter.sanitize(rec.trim());
    }
    return null;
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
