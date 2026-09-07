import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'content_safety_filter.dart';

/// Context passed to [TravelWellnessService] when requesting guidance.
///
/// Only plain-text fields — no coordinates. The destination name and the
/// user's own notes are richer context for Gemini than raw lat/lng anyway.
class TravelWellnessContext {
  /// Name of the destination as entered by the user (city, country, landmark).
  final String place;

  /// Optional notes the user wrote about the trip.
  final String? note;

  /// Whether today falls within the travel period.
  final bool isActiveNow;

  /// Days remaining on the trip (null when no end date is set).
  final int? daysRemaining;

  const TravelWellnessContext({
    required this.place,
    this.note,
    this.isActiveNow = false,
    this.daysRemaining,
  });
}

/// Generates travel-specific wellness guidance using Gemini 2.5 Flash,
/// degrading gracefully to a curated heuristic when AI is unavailable.
///
/// Guidance is intentionally non-clinical: practical tips on hydration,
/// jet-lag recovery, movement, local nature, and mindful presence — all
/// grounded in the destination name the user typed.
class TravelWellnessService {
  static const String _modelId = 'gemini-2.5-flash';
  static const int _timeoutSeconds = 15;

  FirebaseAI? _override;
  FirebaseAI? _lazy;

  TravelWellnessService({FirebaseAI? ai}) : _override = ai;

  FirebaseAI get _ai =>
      _override ??= (_lazy ??= FirebaseAI.vertexAI(
        appCheck: FirebaseAppCheck.instance,
        auth: FirebaseAuth.instance,
      ));

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns wellness guidance for the given travel context.
  /// Uses Gemini with a heuristic fallback.
  Future<String> getGuidance(TravelWellnessContext ctx) async {
    final heuristic = _heuristicGuidance(ctx);
    try {
      final ai =
          await _aiGuidance(ctx).timeout(Duration(seconds: _timeoutSeconds));
      if (ai != null && ai.trim().isNotEmpty) return ai;
    } catch (e) {
      debugPrint('ℹ️ TravelWellnessService fallback: $e');
    }
    return heuristic;
  }

  // ---------------------------------------------------------------------------
  // Heuristic — works fully offline, no API call
  // ---------------------------------------------------------------------------

  String _heuristicGuidance(TravelWellnessContext ctx) {
    final tips = <String>[];
    final p = ctx.place.toLowerCase();

    // Climate / region hints from the place name.
    if (_matchesAny(p, ['bali', 'thailand', 'sri lanka', 'vietnam', 'malaysia',
        'indonesia', 'singapore', 'philippines', 'miami', 'hawaii', 'cancun',
        'maldives', 'caribbean', 'kenya', 'tanzania', 'ghana', 'nigeria',
        'india', 'bangladesh', 'colombia', 'brazil'])) {
      tips.add(
          'Tropical destinations are warm and humid — you lose fluids faster '
          'than you realise. Sip water consistently throughout the day and '
          'reach for fresh coconut water or electrolyte drinks when available.');
    } else if (_matchesAny(p, ['iceland', 'norway', 'finland', 'sweden',
        'alaska', 'greenland', 'canada', 'new zealand south',
        'patagonia', 'siberia', 'antarctica'])) {
      tips.add(
          'Cold air suppresses your sense of thirst, so drink warm herbal '
          'teas regularly even when you don\'t feel dehydrated. Keep your '
          'core warm to maintain good energy and mood.');
    } else if (_matchesAny(p, ['dubai', 'abu dhabi', 'riyadh', 'doha', 'qatar',
        'sahara', 'arizona', 'las vegas', 'egypt', 'morocco', 'jordan',
        'rajasthan', 'oman'])) {
      tips.add(
          'Desert heat can be deceptive. Carry water at all times, avoid '
          'peak sun hours (11 am – 3 pm), and wear light, breathable layers '
          'to protect your skin and regulate body temperature.');
    } else if (_matchesAny(p, ['alps', 'himalayas', 'andes', 'kilimanjaro',
        'nepal', 'tibet', 'colorado', 'peru', 'bolivia', 'cusco',
        'machu picchu'])) {
      tips.add(
          'Higher altitudes mean less oxygen — give your body 24–48 hours '
          'to acclimatise before strenuous activity. Drink plenty of water '
          'and avoid alcohol on your first day at altitude.');
    } else {
      tips.add(
          'A 10-minute mindful walk each morning is one of the simplest ways '
          'to ground yourself in a new place — it eases travel fatigue and '
          'helps your circadian rhythm adjust.');
    }

    // Jet-lag hint based on well-known long-haul destinations.
    if (_matchesAny(p, ['japan', 'tokyo', 'osaka', 'australia', 'sydney',
        'melbourne', 'new zealand', 'singapore', 'hong kong', 'seoul',
        'beijing', 'shanghai', 'india', 'thailand', 'bali', 'los angeles',
        'new york', 'london', 'paris', 'dubai', 'south africa',
        'johannesburg', 'cape town', 'brazil', 'argentina', 'mexico',
        'chicago', 'toronto', 'vancouver'])) {
      tips.add(
          'Long-haul travel often means crossing multiple time zones. '
          'Get daylight exposure within the first hour of waking at your '
          'destination — it\'s the fastest cue to reset your body clock. '
          'Avoid heavy meals late at night for the first couple of days.');
    }

    // Trip phase hints.
    if (ctx.isActiveNow) {
      if (ctx.daysRemaining != null && ctx.daysRemaining! <= 2) {
        tips.add(
            'You\'re nearly at the end of your trip. Rather than packing '
            'in last-minute activities, allow yourself a gentler final day — '
            'journal three things that moved you, and give your nervous '
            'system space to transition back home.');
      } else {
        tips.add(
            'While travelling, sensory and social stimulation runs high. '
            'Build in at least 20 screen-free minutes each day — a short '
            'meditation, a quiet café sit, or simply watching the world '
            'go by — to let your mind decompress.');
      }
    } else if (ctx.daysRemaining != null && ctx.daysRemaining! > 0) {
      tips.add(
          'Before you leave, start nudging your sleep time by 30 minutes '
          'toward your destination\'s timezone — it makes the first day '
          'significantly easier.');
    }

    // Notes-based personalisation.
    if (ctx.note != null && ctx.note!.trim().isNotEmpty) {
      tips.add(
          'You wrote: "${ctx.note!.trim()}". Use that intention as a '
          'mindfulness anchor — revisit it each morning on this trip and '
          'notice how it shapes what you pay attention to.');
    }

    return tips.join('\n\n');
  }

  bool _matchesAny(String haystack, List<String> needles) =>
      needles.any((n) => haystack.contains(n));

  // ---------------------------------------------------------------------------
  // AI guidance via Gemini — place-name only, no coordinates
  // ---------------------------------------------------------------------------

  Future<String?> _aiGuidance(TravelWellnessContext ctx) async {
    final model = _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: 0.65,
        maxOutputTokens: 400,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(
        'You are a supportive travel wellness advisor. Give practical, '
        'uplifting guidance that connects the specific destination to physical '
        'and mental wellbeing — topics like local climate and hydration, '
        'movement or nature activities unique to that place, jet-lag/sleep, '
        'and mindful presence. '
        'Never use clinical or diagnostic language. Keep the tone warm, '
        'specific, and grounded in the real character of the destination. '
        'Respond ONLY with valid JSON.',
      ),
    );

    final contextLines = [
      'Destination: ${ctx.place}',
      if (ctx.note != null && ctx.note!.trim().isNotEmpty)
        'User\'s notes: "${ctx.note!.trim()}"',
      if (ctx.isActiveNow) 'Trip status: currently travelling there.',
      if (ctx.daysRemaining != null && ctx.daysRemaining! > 0)
        'Days remaining: ${ctx.daysRemaining}.',
      if (!ctx.isActiveNow &&
          (ctx.daysRemaining == null || ctx.daysRemaining! <= 0))
        'Trip status: past trip / planning stage.',
    ].join('\n');

    final prompt = '''
$contextLines

Write personalised wellness guidance for a traveller visiting ${ctx.place}.
Choose 2–3 angles most relevant to this specific destination:
- Climate-appropriate hydration and nutrition
- Local movement, nature, or outdoor activities
- Sleep and jet-lag management if relevant
- Mindful presence practices that suit this place
- How this destination can support mental wellbeing

Keep it under 120 words. Be specific to ${ctx.place}, not generic.

Respond ONLY as JSON: {"guidance": "your text here"}''';

    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) return null;

    final decoded = _decode(text);
    final guidance = decoded?['guidance'];
    if (guidance is String && guidance.trim().isNotEmpty) {
      return ContentSafetyFilter.sanitize(guidance.trim());
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
