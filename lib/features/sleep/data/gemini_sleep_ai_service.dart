import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../services/ai_models.dart';
import '../../../services/content_safety_filter.dart';
import '../domain/sleep_ai_service.dart';
import '../domain/sleep_models.dart';

/// [SleepAIService] backed by Gemini Flash (Firebase Vertex AI), with a
/// deterministic heuristic so the dashboard always has an insight even when AI
/// is unavailable. Only structured, privacy-safe context is sent — no
/// identifiers, tokens, or personal details.
class GeminiSleepAIService implements SleepAIService {
  static const String _modelId = kGeminiFlashModel;
  static const int _timeoutSeconds = 15;

  FirebaseAI? _override;
  FirebaseAI? _lazy;

  GeminiSleepAIService({FirebaseAI? ai}) : _override = ai;

  FirebaseAI get _ai => _override ??= (_lazy ??= FirebaseAI.agentPlatform());

  @override
  Future<SleepInsight> analyze(SleepAnalysisRequest request) async {
    // Heuristic baseline — always available.
    final base = _heuristic(request);
    try {
      final ai = await _aiInsight(request, base)
          .timeout(const Duration(seconds: _timeoutSeconds));
      if (ai != null) return ai;
    } catch (e) {
      debugPrint('ℹ️ Sleep AI insight fallback: $e');
    }
    return base;
  }

  // ---------------------------------------------------------------------------
  // Heuristic
  // ---------------------------------------------------------------------------
  SleepInsight _heuristic(SleepAnalysisRequest r) {
    final durText = SleepSession.formatDuration(r.sleepMinutes);

    // "What happened" — compare with previous night if present.
    String summary;
    if (r.previousSleepMinutes != null) {
      final diff = r.sleepMinutes - r.previousSleepMinutes!;
      if (diff.abs() < 15) {
        summary = 'You slept $durText — steady with your recent nights.';
      } else if (diff > 0) {
        summary = 'Your sleep improved by ${diff.abs()} minutes.';
      } else {
        summary = 'You slept ${diff.abs()} minutes less than the night before.';
      }
    } else {
      summary = 'You slept $durText.';
    }

    // "Why" — cautious factor associations.
    final contributing = <String>[];
    final positives =
        r.factors.where((f) => f.status.isPositive).toList();
    final concerns = r.factors
        .where((f) =>
            f.status == FactorStatus.needsAttention ||
            f.status == FactorStatus.belowTarget ||
            f.status == FactorStatus.aboveTarget)
        .toList();

    for (final f in positives.take(2)) {
      contributing.add('Your ${f.label.toLowerCase()} looked good, which may '
          'have supported your rest.');
    }
    for (final f in concerns.take(2)) {
      contributing.add('Your ${f.label.toLowerCase()} '
          '(${f.value ?? f.status.label.toLowerCase()}) could be affecting '
          'your sleep.');
    }
    if (contributing.isEmpty) {
      contributing.add('Log more of your day to uncover what may be shaping '
          'your sleep.');
    }

    return SleepInsight(
      summary: summary,
      contributingFactors: contributing,
      confidence: concerns.isEmpty && positives.isNotEmpty ? 'medium' : 'low',
      recommendation: _heuristicRecommendation(r, concerns),
    );
  }

  SleepRecommendation _heuristicRecommendation(
      SleepAnalysisRequest r, List<SleepFactor> concerns) {
    for (final f in concerns) {
      switch (f.key) {
        case 'dinner_timing':
          return const SleepRecommendation(
            title: 'Dinner before 8:30 PM',
            detail:
                'Try finishing dinner about 45 minutes earlier tonight to help '
                'your body wind down.',
          );
        case 'caffeine':
          return const SleepRecommendation(
            title: 'No caffeine after 2 PM',
            detail: 'Skipping late caffeine may help you fall asleep more easily.',
          );
        case 'hydration':
          return const SleepRecommendation(
            title: 'Steady daytime hydration',
            detail:
                'Spread your water earlier in the day so late sips don\'t '
                'interrupt sleep.',
          );
        case 'exercise':
          return const SleepRecommendation(
            title: '30 min light evening activity',
            detail:
                'A gentle evening walk may support deeper, more restful sleep.',
          );
      }
    }
    if (r.sleepMinutes < 420) {
      return const SleepRecommendation(
        title: 'Wind down 20 minutes earlier',
        detail: 'Starting your bedtime routine a little earlier may add rest.',
      );
    }
    return const SleepRecommendation(
      title: 'Keep a consistent bedtime',
      detail: 'Aim for the same wind-down time tonight to protect your rhythm.',
    );
  }

  // ---------------------------------------------------------------------------
  // Gemini
  // ---------------------------------------------------------------------------
  Future<SleepInsight?> _aiInsight(
      SleepAnalysisRequest r, SleepInsight fallback) async {
    final model = _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 768,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(
        'You are a supportive sleep coach. Explain what happened, why it may '
        'have happened, and one specific action for tonight. Use cautious, '
        'non-medical language ("may have contributed", "your data suggests"). '
        'Never claim something definitely caused poor sleep. Never diagnose. '
        'Respond ONLY with valid JSON.',
      ),
    );

    final prompt = '''
Analyze this sleep night (factual, privacy-safe context):
${jsonEncode(r.toContext())}

Return ONLY JSON:
{
  "summary": "one sentence: what happened",
  "contributingFactors": ["1-3 short cautious 'why' statements"],
  "confidence": "low|medium|high",
  "recommendation": {"title": "short actionable habit", "detail": "one supportive sentence"}
}''';

    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) return null;
    final map = _decode(text);
    if (map == null) return null;

    final rec = map['recommendation'];
    final recMap = rec is Map ? Map<String, dynamic>.from(rec) : null;

    return SleepInsight(
      summary: ContentSafetyFilter.sanitize(
          (map['summary'] as String?)?.trim().isNotEmpty == true
              ? map['summary'] as String
              : fallback.summary),
      contributingFactors: (map['contributingFactors'] as List<dynamic>?)
              ?.map((e) => ContentSafetyFilter.sanitize(e.toString()))
              .where((s) => s.trim().isNotEmpty)
              .take(3)
              .toList() ??
          fallback.contributingFactors,
      confidence: (map['confidence'] as String?) ?? fallback.confidence,
      recommendation: recMap == null
          ? fallback.recommendation
          : SleepRecommendation(
              title: ContentSafetyFilter.sanitize(
                  (recMap['title'] as String?)?.trim().isNotEmpty == true
                      ? recMap['title'] as String
                      : fallback.recommendation.title),
              detail: ContentSafetyFilter.sanitize(
                  (recMap['detail'] as String?)?.trim().isNotEmpty == true
                      ? recMap['detail'] as String
                      : fallback.recommendation.detail),
            ),
    );
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
