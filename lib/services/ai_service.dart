import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/check_in.dart';
import '../models/daily_plan.dart';
import '../models/journal_entry.dart';
import '../models/voice_command.dart';
import '../models/wellness_enums.dart';
import '../models/wellness_intention.dart';
import 'content_safety_filter.dart';

/// Service that generates AI-powered wellness content using Firebase AI Logic
/// (Vertex AI) with the Gemini 2.5 Flash model.
///
/// Calls the model directly from the client via `FirebaseAI.vertexAI()` — no
/// Gemini API key and no Gemini Developer API. Requests are protected by the
/// Firebase AI Logic proxy (App Check / Firebase Auth).
///
/// All responses are passed through [ContentSafetyFilter.sanitize] before
/// being returned to the caller.
///
/// Requirements: 1.8, 2.8, 3.12, 8.2, 8.4, 8.8
class AIService {
  /// The Gemini model ID used for all generation, via Vertex AI.
  static const String _modelId = 'gemini-2.5-flash';

  static const int _planTimeoutSeconds = 20;
  static const int _promptTimeoutSeconds = 10;

  static const List<String> _validCategories = [
    'flexibility',
    'stress',
    'sleep',
    'movement',
    'recovery',
    'energy',
    'mentalClarity',
    'mindfulness',
    'general',
  ];

  static const List<String> _validIntensityLevels = ['low', 'medium', 'high'];

  static const List<String> _fallbackPrompts = [
    'How are you feeling today?',
    'Where is your body asking for extra care?',
    'What would feel supportive today?',
  ];

  final FirebaseAI _ai;
  final Random _random = Random();

  /// Creates an [AIService].
  ///
  /// If [ai] is not provided, a Vertex AI–backed [FirebaseAI] instance is used
  /// with App Check and Auth wired in. Passing [FirebaseAppCheck] is REQUIRED
  /// for projects that enforce App Check on Firebase AI Logic — without it the
  /// SDK never attaches the `X-Firebase-AppCheck` header and every request is
  /// rejected with "Firebase App Check token is invalid".
  AIService({FirebaseAI? ai})
      : _ai = ai ??
            FirebaseAI.vertexAI(
              appCheck: FirebaseAppCheck.instance,
              auth: FirebaseAuth.instance,
            );

  /// Builds a [GenerativeModel] for the Gemini 2.5 Flash model.
  ///
  /// [temperature] and [systemInstruction] mirror the previous server-side
  /// configuration. When [jsonOutput] is true the model is asked to return
  /// `application/json`.
  GenerativeModel _model({
    double temperature = 0.7,
    int maxOutputTokens = 1024,
    String? systemInstruction,
    bool jsonOutput = false,
  }) {
    return _ai.generativeModel(
      model: _modelId,
      generationConfig: GenerationConfig(
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        responseMimeType: jsonOutput ? 'application/json' : 'text/plain',
      ),
      systemInstruction:
          systemInstruction != null ? Content.system(systemInstruction) : null,
    );
  }

  /// Runs [prompt] and returns the trimmed text response, or null on failure.
  Future<String?> _generateText(
    String prompt, {
    double temperature = 0.7,
    int maxOutputTokens = 1024,
    String? systemInstruction,
    Duration? timeout,
  }) async {
    final model = _model(
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
    );
    Future<GenerateContentResponse> call =
        model.generateContent([Content.text(prompt)]);
    if (timeout != null) {
      call = call.timeout(timeout);
    }
    final response = await call;
    final text = response.text?.trim();
    if (kDebugMode) {
      final finish = response.candidates.isNotEmpty
          ? response.candidates.first.finishReason
          : null;
      debugPrint('🧠 Gemini reply (finish=$finish, len=${text?.length ?? 0}): '
          '${text ?? "<null>"}');
    }
    return (text != null && text.isNotEmpty) ? text : null;
  }

  /// Runs [prompt] expecting JSON, returning the decoded object, or null.
  Future<dynamic> _generateJson(
    String prompt, {
    double temperature = 0.7,
    int maxOutputTokens = 1024,
    String? systemInstruction,
    Duration? timeout,
  }) async {
    final model = _model(
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction,
      jsonOutput: true,
    );
    Future<GenerateContentResponse> call =
        model.generateContent([Content.text(prompt)]);
    if (timeout != null) {
      call = call.timeout(timeout);
    }
    final response = await call;
    final raw = response.text?.trim();
    if (raw == null || raw.isEmpty) return null;
    return _parseJson(raw);
  }

  /// Tolerant JSON parse: strips code fences and extracts the JSON body.
  dynamic _parseJson(String raw) {
    try {
      var text = raw.replaceAll(RegExp(r'```json', caseSensitive: false), '');
      text = text.replaceAll('```', '').trim();
      return jsonDecode(text);
    } catch (_) {
      // Try to extract the first {...} or [...] block.
      try {
        final objStart = raw.indexOf('{');
        final objEnd = raw.lastIndexOf('}');
        if (objStart != -1 && objEnd > objStart) {
          return jsonDecode(raw.substring(objStart, objEnd + 1));
        }
        final arrStart = raw.indexOf('[');
        final arrEnd = raw.lastIndexOf(']');
        if (arrStart != -1 && arrEnd > arrStart) {
          return jsonDecode(raw.substring(arrStart, arrEnd + 1));
        }
      } catch (_) {}
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Daily plan
  // ---------------------------------------------------------------------------

  /// Generates a personalized [DailyPlan] using Gemini 2.5 Flash.
  ///
  /// Enforces a 20-second timeout. Returns a [DailyPlan] on success, or `null`
  /// on timeout/error so callers can use a fallback.
  Future<DailyPlan?> generatePlan({
    required String userId,
    required CheckIn checkIn,
    required List<WellnessIntention> intentions,
    required List<DailyPlan> recentPlans,
    String? cycleContext,
    String? travelContext,
  }) async {
    try {
      final prompt = _buildPlanPrompt(
          checkIn, intentions, recentPlans, cycleContext, travelContext);

      final decoded = await _generateJson(
        prompt,
        temperature: 0.7,
        maxOutputTokens: 1024,
        systemInstruction:
            'You are a supportive wellness planning assistant. Respond only '
            'with valid JSON, no markdown or code fences.',
        timeout: const Duration(seconds: _planTimeoutSeconds),
      );

      if (decoded is! Map) return null;
      final plan = Map<String, dynamic>.from(decoded);

      final enforced = _enforcePlanConstraints(plan, checkIn);

      // Sanitize string fields before constructing the model.
      enforced['todaysFocus'] =
          ContentSafetyFilter.sanitize(enforced['todaysFocus'] as String? ?? '');
      if (enforced['aiInsight'] != null) {
        enforced['aiInsight'] =
            ContentSafetyFilter.sanitize(enforced['aiInsight'] as String);
      }
      enforced['actions'] = (enforced['actions'] as List<dynamic>).map((a) {
        final actionMap = Map<String, dynamic>.from(a as Map);
        actionMap['title'] =
            ContentSafetyFilter.sanitize(actionMap['title'] as String? ?? '');
        return actionMap;
      }).toList();

      return DailyPlan.fromMap(enforced);
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generatePlan timed out after ${_planTimeoutSeconds}s');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.generatePlan error: $e');
      return null;
    }
  }

  int _timeUpperBound(AvailableTimeRange? availableTime) {
    switch (availableTime) {
      case AvailableTimeRange.under10:
        return 10;
      case AvailableTimeRange.range10_20:
        return 20;
      case AvailableTimeRange.range20_40:
        return 40;
      case AvailableTimeRange.range40_60:
        return 60;
      case AvailableTimeRange.over60:
        return 90;
      default:
        return 30;
    }
  }

  String _buildPlanPrompt(
    CheckIn checkIn,
    List<WellnessIntention> intentions,
    List<DailyPlan> recentPlans, [
    String? cycleContext,
    String? travelContext,
  ]) {
    final energyLabel = checkIn.energyScore != null
        ? 'Energy: ${checkIn.energyScore}/5'
        : 'Energy: not provided';
    final moodLabel = checkIn.moodState != null
        ? 'Mood: ${checkIn.moodState!.name}'
        : 'Mood: not provided';
    final recoveryLabel = checkIn.recoveryStatus != null
        ? 'Recovery: ${checkIn.recoveryStatus!.name}'
        : 'Recovery: not provided';
    final timeLabel = checkIn.availableTime != null
        ? 'Available time: ${checkIn.availableTime!.name}'
        : 'Available time: not provided';
    final cycleLabel = (cycleContext != null && cycleContext.trim().isNotEmpty)
        ? '\n$cycleContext\nWhen relevant, gently tailor intensity and tone to '
            'this cycle phase (e.g. softer, restorative activities during the '
            'menstrual phase; more energizing options mid-cycle). Do not use '
            'clinical language.'
        : '';

    final travelLabel =
        (travelContext != null && travelContext.trim().isNotEmpty)
            ? '\n\n$travelContext'
            : '';

    final maxTime = _timeUpperBound(checkIn.availableTime);
    const actionCount = '2 to 4';

    final intensityConstraint =
        (checkIn.energyScore != null && checkIn.energyScore! <= 2)
            ? "IMPORTANT: The user has low energy. Do NOT include any action with "
                "intensityLevel 'high'. Only use 'low' or 'medium' intensity."
            : '';

    final intentionsList = intentions.isNotEmpty
        ? intentions.map((i) => '- ${i.title} (${i.category.name})').join('\n')
        : '- No specific intentions set';

    final recentPlansSummary = recentPlans.isNotEmpty
        ? recentPlans.take(7).map((p) {
            final completed = p.actions
                .where((a) => a.isCompleted)
                .map((a) => a.title)
                .join(', ');
            return '- ${p.date.toIso8601String().split("T").first}: completed [$completed]';
          }).join('\n')
        : 'No recent plan history';

    return '''You are a supportive wellness planning assistant. Generate a personalized daily wellness plan.

USER STATE:
$energyLabel
$moodLabel
$recoveryLabel
$timeLabel$cycleLabel$travelLabel

WELLNESS INTENTIONS:
$intentionsList

RECENT PLAN HISTORY (last 7 days):
$recentPlansSummary

CONSTRAINTS:
- Generate exactly $actionCount wellness actions.
- Total time of all actions MUST NOT exceed $maxTime minutes.
- Each action must have: id (short unique string), title, durationMinutes, category, intensityLevel.
- Valid categories: ${_validCategories.join(", ")}
- Valid intensity levels: low, medium, high
$intensityConstraint
- Provide a "todaysFocus" label (2-5 words) that captures the theme of today's plan.
- Optionally provide an "aiInsight" (30-80 words) explaining the reasoning behind today's plan.
- Do NOT use clinical or therapeutic language. Avoid words like: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical.
- The tone must be calm, supportive, and non-judgmental.

Respond ONLY with valid JSON in this exact format:
{
  "todaysFocus": "string",
  "actions": [
    { "id": "string", "title": "string", "durationMinutes": number, "category": "string", "intensityLevel": "string" }
  ],
  "aiInsight": "string or null"
}''';
  }

  /// Enforces plan constraints (2–4 actions, time cap, intensity for low
  /// energy) and returns a map compatible with [DailyPlan.fromMap].
  Map<String, dynamic> _enforcePlanConstraints(
    Map<String, dynamic> plan,
    CheckIn checkIn,
  ) {
    final today = DateTime.now().toIso8601String().split('T').first;
    final planId = 'plan_${_randomId(8)}';

    var actions = <Map<String, dynamic>>[];
    if (plan['actions'] is List) {
      var idx = 0;
      for (final a in plan['actions'] as List) {
        final am = Map<String, dynamic>.from(a as Map);
        idx++;
        final category = (am['category'] is String &&
                _validCategories.contains(am['category']))
            ? am['category'] as String
            : 'general';
        final intensity = (am['intensityLevel'] is String &&
                _validIntensityLevels.contains(am['intensityLevel']))
            ? am['intensityLevel'] as String
            : 'low';
        actions.add({
          'id': am['id'] is String ? am['id'] : 'a$idx',
          'title': am['title'] is String ? am['title'] : 'Wellness Activity',
          'durationMinutes': am['durationMinutes'] is num
              ? max(1, (am['durationMinutes'] as num).round())
              : 5,
          'category': category,
          'intensityLevel': intensity,
          'isCompleted': false,
        });
      }
    }

    // Constraint: 2–4 actions.
    while (actions.length < 2) {
      actions.add({
        'id': 'a${actions.length + 1}',
        'title': '5-Minute Deep Breathing',
        'durationMinutes': 5,
        'category': 'mindfulness',
        'intensityLevel': 'low',
        'isCompleted': false,
      });
    }
    if (actions.length > 4) {
      actions = actions.sublist(0, 4);
    }

    // Constraint: energy ≤ 2 → no high intensity.
    final energyScore = checkIn.energyScore;
    if (energyScore != null && energyScore <= 2) {
      for (final a in actions) {
        if (a['intensityLevel'] == 'high') a['intensityLevel'] = 'medium';
      }
    }

    // Time constraints.
    final maxTime = _timeUpperBound(checkIn.availableTime);
    int totalTime() =>
        actions.fold<int>(0, (sum, a) => sum + (a['durationMinutes'] as int));

    if (checkIn.availableTime == AvailableTimeRange.under10 && totalTime() > 10) {
      final scale = 10 / totalTime();
      for (final a in actions) {
        a['durationMinutes'] =
            max(1, ((a['durationMinutes'] as int) * scale).floor());
      }
      while (totalTime() > 10 && actions.length > 2) {
        final last = actions.last;
        if ((last['durationMinutes'] as int) > 1) {
          last['durationMinutes'] = (last['durationMinutes'] as int) - 1;
        } else {
          actions.removeLast();
        }
      }
    } else if (totalTime() > maxTime) {
      final scale = maxTime / totalTime();
      for (final a in actions) {
        a['durationMinutes'] =
            max(1, ((a['durationMinutes'] as int) * scale).floor());
      }
    }

    final focus = (plan['todaysFocus'] is String &&
            (plan['todaysFocus'] as String).isNotEmpty)
        ? plan['todaysFocus'] as String
        : 'Daily Wellness';
    final insight = (plan['aiInsight'] is String &&
            (plan['aiInsight'] as String).isNotEmpty)
        ? plan['aiInsight'] as String
        : null;

    return {
      'id': planId,
      'date': today,
      'todaysFocus': focus,
      'actions': actions,
      'totalTime': totalTime(),
      'aiInsight': insight,
    };
  }

  String _randomId(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)])
        .join();
  }

  // ---------------------------------------------------------------------------
  // Reflection prompts
  // ---------------------------------------------------------------------------

  /// Generates exactly 3 reflection prompts using Gemini 2.5 Flash.
  ///
  /// Enforces a 10-second timeout. On timeout or error, returns 3 pre-written
  /// fallback prompts.
  Future<List<String>> generateReflectionPrompts({
    required String userId,
    CheckIn? checkIn,
    List<WellnessIntention>? intentions,
  }) async {
    try {
      final prompt = _buildReflectionPromptsPrompt(checkIn, intentions);
      final decoded = await _generateJson(
        prompt,
        temperature: 0.8,
        maxOutputTokens: 512,
        systemInstruction:
            'You are a supportive wellness companion. Respond only with a JSON '
            'array of exactly 3 short reflection prompt strings.',
        timeout: const Duration(seconds: _promptTimeoutSeconds),
      );

      if (decoded is! List) return List.unmodifiable(_fallbackPrompts);
      final prompts = decoded
          .map((p) => p.toString())
          .where((p) => p.trim().isNotEmpty)
          .toList();
      if (prompts.isEmpty) return List.unmodifiable(_fallbackPrompts);

      return prompts.map((p) => ContentSafetyFilter.sanitize(p)).toList();
    } on TimeoutException catch (_) {
      debugPrint(
          '⏱️ AIService.generateReflectionPrompts timed out after ${_promptTimeoutSeconds}s');
      return List.unmodifiable(_fallbackPrompts);
    } catch (e) {
      debugPrint('❌ AIService.generateReflectionPrompts error: $e');
      return List.unmodifiable(_fallbackPrompts);
    }
  }

  /// Generates a reply for the "Discuss" conversation about a journal entry.
  ///
  /// The reply is grounded in the entry's [entryTitle]/[entryContent], the
  /// prior [history] turns, and the [userMessage], all through a supportive
  /// wellness lens. Returns null on timeout/error so the UI can show a
  /// friendly fallback.
  ///
  /// [history] is an ordered list of {'role': 'user'|'ai', 'text': ...} maps.
  Future<String?> discussJournalEntry({
    required String entryTitle,
    required String entryContent,
    required List<Map<String, String>> history,
    required String userMessage,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln("The user wrote this journal entry:");
    buffer.writeln('Title: ${entryTitle.isEmpty ? "(untitled)" : entryTitle}');
    buffer.writeln('Entry: ${entryContent.isEmpty ? "(no body text)" : entryContent}');
    buffer.writeln();

    if (history.isNotEmpty) {
      buffer.writeln('Conversation so far:');
      for (final turn in history) {
        final who = turn['role'] == 'ai' ? 'You (coach)' : 'User';
        buffer.writeln('$who: ${turn['text']}');
      }
      buffer.writeln();
    }

    buffer.writeln('User\'s latest message: $userMessage');
    buffer.writeln();
    buffer.writeln(
        'Respond to the user\'s latest message. Stay specific to what they '
        'wrote in the entry and the conversation — reference their own words '
        'where helpful. Keep a warm, wellness-focused tone.');

    try {
      final reply = await _generateText(
        buffer.toString(),
        temperature: 0.75,
        maxOutputTokens: 600,
        systemInstruction:
            'You are a warm, insightful wellness companion inside a journaling '
            'app. You help the user reflect on their own journal entry through '
            'a wellness lens — emotional wellbeing, self-care, stress, energy, '
            'sleep, relationships, and healthy habits. Ground every reply in '
            'the specific content of their entry and the conversation; never '
            'give generic filler. Be supportive and non-judgmental, ask one '
            'gentle follow-up question when useful, and offer small, doable '
            'suggestions. Do not give medical diagnoses or clinical advice — '
            'suggest professional support for serious concerns. Reply in plain '
            'text (short paragraphs, no code fences), 2–5 sentences.',
        timeout: const Duration(seconds: 20),
      );
      if (reply == null || reply.trim().isEmpty) return null;
      return ContentSafetyFilter.sanitize(reply.trim());
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.discussJournalEntry timed out');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.discussJournalEntry error: $e');
      return null;
    }
  }

  String _buildReflectionPromptsPrompt(
    CheckIn? checkIn,
    List<WellnessIntention>? intentions,
  ) {
    final context = StringBuffer();
    if (checkIn != null) {
      if (checkIn.energyScore != null) {
        context.writeln('Energy: ${checkIn.energyScore}/5');
      }
      if (checkIn.moodState != null) {
        context.writeln('Mood: ${checkIn.moodState!.name}');
      }
      if (checkIn.recoveryStatus != null) {
        context.writeln('Recovery: ${checkIn.recoveryStatus!.name}');
      }
    }
    if (intentions != null && intentions.isNotEmpty) {
      context.writeln(
          'Intentions: ${intentions.map((i) => i.title).join(", ")}');
    }
    final contextBlock = context.isEmpty
        ? 'No personalization data available.'
        : context.toString().trim();

    return '''Generate exactly 3 short, supportive wellness reflection prompts for a user.

USER CONTEXT:
$contextBlock

CONSTRAINTS:
- Each prompt is a single gentle, open-ended question (under 15 words).
- Calm, supportive, non-judgmental tone.
- Do NOT use clinical or therapeutic language.

Respond ONLY with a JSON array of exactly 3 strings, e.g.:
["How are you feeling today?", "What would feel supportive?", "Where do you need care?"]''';
  }

  // ---------------------------------------------------------------------------
  // Wellness insight
  // ---------------------------------------------------------------------------

  /// Generates a 30–80 word wellness insight using Gemini 2.5 Flash.
  ///
  /// Provide either a [plan] (uses its structured summary) or a plain-text
  /// [summary] (e.g. an intention summary). At least one must be non-null.
  ///
  /// Returns `null` on error.
  Future<String?> generateWellnessInsight({
    required String userId,
    DailyPlan? plan,
    String? summary,
  }) async {
    assert(plan != null || summary != null,
        'generateWellnessInsight requires either a plan or a summary');
    try {
      final planSummary = plan != null ? _planSummaryText(plan) : summary!;
      final prompt = _buildInsightPrompt(planSummary);
      final text = await _generateText(
        prompt,
        temperature: 0.7,
        maxOutputTokens: 200,
        systemInstruction:
            'You are a supportive wellness companion. Respond only with plain '
            'text, no JSON or formatting.',
      );
      if (text == null) return null;
      return ContentSafetyFilter.sanitize(text);
    } catch (e) {
      debugPrint('❌ AIService.generateWellnessInsight error: $e');
      return null;
    }
  }

  String _planSummaryText(DailyPlan plan) {
    final buffer = StringBuffer();
    buffer.writeln("Today's focus: ${plan.todaysFocus}");
    if (plan.actions.isNotEmpty) {
      buffer.writeln('Actions:');
      for (final a in plan.actions) {
        buffer.writeln(
            '- ${a.title} (${a.category.name}) — ${a.durationMinutes} min');
      }
    }
    buffer.writeln('Total time: ${plan.totalTime} min');
    return buffer.toString().trim();
  }

  String _buildInsightPrompt(String planSummary) {
    return '''You are a supportive wellness companion. Based on the following daily wellness plan summary, generate a brief personalized insight explaining why this plan was chosen for the user today.

PLAN SUMMARY:
$planSummary

CONSTRAINTS:
- Your response must be between 30 and 80 words.
- Use a calm, supportive, and non-judgmental tone.
- Explain the reasoning behind today's plan choices.
- Do NOT use clinical or therapeutic language. Avoid words like: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical.
- Do NOT mention calorie counts, step counts, streaks, or productivity metrics.
- Speak directly to the user using "you" and "your".

Respond ONLY with the insight text (no JSON, no quotes, no labels). Just the plain text insight.''';
  }

  /// Generates a supportive AI insight for a reflection journal entry.
  ///
  /// Enforces a 10-second timeout per Requirement 8.4.
  /// Returns `null` on timeout/error so callers can use a fallback.
  Future<String?> generateReflectionInsight({
    required String userId,
    required String entryContent,
    String? entryTitle,
  }) async {
    try {
      final summary = StringBuffer();
      if (entryTitle != null && entryTitle.trim().isNotEmpty) {
        summary.writeln('Title: $entryTitle');
      }
      summary.writeln('Reflection: $entryContent');

      final prompt = _buildInsightPrompt(summary.toString().trim());
      final text = await _generateText(
        prompt,
        temperature: 0.7,
        maxOutputTokens: 200,
        systemInstruction:
            'You are a supportive wellness companion. Respond only with plain '
            'text, no JSON or formatting.',
        timeout: const Duration(seconds: _promptTimeoutSeconds),
      );
      if (text == null) return null;
      return ContentSafetyFilter.sanitize(text);
    } on TimeoutException catch (_) {
      debugPrint(
          '⏱️ AIService.generateReflectionInsight timed out after ${_promptTimeoutSeconds}s');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.generateReflectionInsight error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Weekly summary
  // ---------------------------------------------------------------------------

  /// Generates an 80–200 word weekly reflection summary using Gemini 2.5 Flash.
  ///
  /// Returns `null` on error.
  Future<String?> generateWeeklySummary({
    required String userId,
    required List<JournalEntry> weekEntries,
  }) async {
    try {
      final entriesText = weekEntries.isNotEmpty
          ? weekEntries
              .map((e) => '- ${e.title.isNotEmpty ? "${e.title}: " : ""}'
                  '${e.content}')
              .join('\n')
          : 'No entries this week.';

      final prompt =
          '''You are a supportive wellness companion. Write a weekly reflection summary based on the user's journal entries below.

JOURNAL ENTRIES:
$entriesText

CONSTRAINTS:
- Your response must be between 80 and 200 words.
- Use a calm, supportive, and non-judgmental tone.
- Reflect back themes and gently encourage the user.
- Do NOT use clinical or therapeutic language.

Respond ONLY with the summary text (no JSON, no labels).''';

      final text = await _generateText(
        prompt,
        temperature: 0.7,
        maxOutputTokens: 400,
        systemInstruction:
            'You are a supportive wellness companion. Respond only with plain '
            'text, no JSON or formatting.',
      );
      if (text == null) return null;
      return ContentSafetyFilter.sanitize(text);
    } catch (e) {
      debugPrint('❌ AIService.generateWeeklySummary error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Voice command intent parsing
  // ---------------------------------------------------------------------------

  /// Command type names the model is allowed to return. Excludes `unknown`
  /// (we return null instead, so the caller can fall back to keyword parsing).
  static const List<String> _voiceCommandTypeNames = [
    'setThemeDark',
    'setThemeLight',
    'setAccentColor',
    'increaseTextSize',
    'decreaseTextSize',
    'resetTextSize',
    'toggleWinterMode',
    'setEnergyScore',
    'setMood',
    'setRecoveryStatus',
    'setAvailableTime',
    'submitCheckIn',
    'logIntention',
    'openSettings',
    'openCheckIn',
    'openJournal',
    'openHome',
    'openIntentions',
    'openHabitBuilder',
    'refreshPlan',
    'openNutritionCoach',
    'openMealPlanner',
    'openCalorieBudget',
    'openHydration',
    'openSleepCoach',
    'openMeditation',
    'openPeriodTracker',
    'openWeightTracker',
    'openMindfulTravel',
    'openChallenges',
    'logWater',
    'startBreathing',
    'startMeditation',
    'greeting',
    'howAmI',
    'help',
    'unknown',
  ];

  static const List<String> _voiceMoodValues = [
    'calm',
    'anxious',
    'tired',
    'energized',
    'stressed',
    'content',
  ];

  static const List<String> _voiceRecoveryValues = [
    'wellRested',
    'sore',
    'fatigued',
    'recovering',
  ];

  static const List<String> _voiceTimeValues = [
    'under10',
    'range10_20',
    'range20_40',
    'range40_60',
    'over60',
  ];

  static const List<String> _voiceColorNames = [
    'coral',
    'orange',
    'turquoise',
    'teal',
    'yellow',
    'purple',
    'violet',
    'pink',
    'blue',
    'green',
    'red',
  ];

  static const Map<String, int> _voiceColorValues = {
    'coral': 0xFFFF7F50,
    'orange': 0xFFFF7F50,
    'turquoise': 0xFF4ECDC4,
    'teal': 0xFF4ECDC4,
    'yellow': 0xFFFFD93D,
    'purple': 0xFF9B59B6,
    'violet': 0xFF9B59B6,
    'pink': 0xFFE91E63,
    'blue': 0xFF2196F3,
    'green': 0xFF4CAF50,
    'red': 0xFFF44336,
  };

  /// Interprets free-form [speech] into a structured [VoiceCommand] using
  /// Gemini 2.5 Flash with a constrained JSON response schema.
  ///
  /// Returns `null` on timeout, error, or when the model is unsure (type
  /// `unknown`), so the caller can fall back to the keyword-based
  /// [VoiceIntentParser].
  ///
  /// The returned command uses the exact param keys the voice handler expects:
  /// `score` (int 1-5), `mood`, `status`, `time`, `color`+`colorName`,
  /// `enabled` (bool).
  Future<VoiceCommand?> parseVoiceCommand(String speech) async {
    if (speech.trim().isEmpty) return null;

    final schema = Schema.object(
      properties: {
        'type': Schema.enumString(
          enumValues: _voiceCommandTypeNames,
          description: 'The recognized command type.',
        ),
        'score': Schema.integer(
          description: 'Energy score 1-5, only for setEnergyScore.',
          nullable: true,
          minimum: 1,
          maximum: 5,
        ),
        'mood': Schema.enumString(
          enumValues: _voiceMoodValues,
          description: 'Mood, only for setMood.',
          nullable: true,
        ),
        'status': Schema.enumString(
          enumValues: _voiceRecoveryValues,
          description: 'Recovery status, only for setRecoveryStatus.',
          nullable: true,
        ),
        'time': Schema.enumString(
          enumValues: _voiceTimeValues,
          description: 'Available time range, only for setAvailableTime.',
          nullable: true,
        ),
        'colorName': Schema.enumString(
          enumValues: _voiceColorNames,
          description: 'Accent color name, only for setAccentColor.',
          nullable: true,
        ),
        'enabled': Schema.boolean(
          description: 'On/off flag, only for toggleWinterMode.',
          nullable: true,
        ),
        'title': Schema.string(
          description:
              'The wellness intention title, only for logIntention. Extract '
              'just the goal, e.g. "Learn Yoga" from "add an intention to '
              'learn yoga". Null if not provided.',
          nullable: true,
        ),
        'amountMl': Schema.integer(
          description:
              'Water amount in millilitres, only for logWater. Convert litres '
              'to ml (1 litre = 1000) and glasses to ml (1 glass = 250). '
              'e.g. "log 100 ml" -> 100, "add half a litre" -> 500, '
              '"log two glasses" -> 500. Null if no amount is stated.',
          nullable: true,
          minimum: 1,
          maximum: 5000,
        ),
      },
      optionalProperties: [
        'score',
        'mood',
        'status',
        'time',
        'colorName',
        'enabled',
        'title',
        'amountMl',
      ],
    );

    const systemInstruction =
        'You map a user\'s spoken input in a wellness app to ONE command. '
        'Commands: setThemeDark/setThemeLight (dark/light mode), setAccentColor '
        '(change accent color; set colorName), increaseTextSize/decreaseTextSize/'
        'resetTextSize, toggleWinterMode (set enabled true/false), setEnergyScore '
        '(set score 1-5 from how energetic they feel), setMood (set mood), '
        'setRecoveryStatus (set status), setAvailableTime (set time), '
        'submitCheckIn (finish/submit check-in), '
        'logIntention (create/add/set a wellness intention or goal — set title '
        'to the goal, e.g. "add an intention to learn yoga" -> title "Learn '
        'Yoga"; if they want to add an intention but give no goal, still '
        'return logIntention with title null), '
        'openSettings/openCheckIn/openJournal/openHome (navigation), '
        'openIntentions (wellness intentions tab), '
        'openHabitBuilder (habit builder / my habits tab), '
        'openChallenges (wellness challenges), refreshPlan (new daily plan). '
        'Tool navigation: openNutritionCoach (nutrition/food logging), '
        'openMealPlanner (meal plans), openCalorieBudget (calories), '
        'openHydration (water/hydration tool), openSleepCoach (sleep), '
        'openMeditation (meditation pal), openPeriodTracker (period/cycle), '
        'openWeightTracker (body weight), openMindfulTravel (trips/travel). '
        'Quick actions: logWater (user says they drank/log water, or states an '
        'amount like "log 100 ml", "add half a litre", "log two glasses" — set '
        'amountMl in millilitres, or null to default to one glass), '
        'startBreathing (start a breathing exercise), startMeditation '
        '(start a meditation session). '
        'Prefer a quick action over navigation when the user wants to DO '
        'something (e.g. "I drank water" -> logWater, not openHydration). '
        'greeting (hi/hello), howAmI (progress question), help. '
        'If the input does not clearly match any command, return type "unknown". '
        'Only set a parameter field for its matching command; leave others null.';

    try {
      final model = _ai.generativeModel(
        model: _modelId,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 128,
          responseMimeType: 'application/json',
          responseSchema: schema,
        ),
        systemInstruction: Content.system(systemInstruction),
      );

      final response = await model
          .generateContent([Content.text('User said: "$speech"')])
          .timeout(const Duration(seconds: _promptTimeoutSeconds));

      final raw = response.text?.trim();
      if (raw == null || raw.isEmpty) return null;

      final decoded = _parseJson(raw);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);

      final typeName = data['type'] as String?;
      if (typeName == null || typeName == 'unknown') return null;

      final type = VoiceCommandType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => VoiceCommandType.unknown,
      );
      if (type == VoiceCommandType.unknown) return null;

      return VoiceCommand(
        type: type,
        params: _voiceParamsFor(type, data),
        rawText: speech,
        confidence: 0.9,
      );
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.parseVoiceCommand timed out');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.parseVoiceCommand error: $e');
      return null;
    }
  }

  /// Generates a conversational spoken reply to a free-form voice question
  /// that didn't match any app command, using Gemini 2.5 Flash.
  ///
  /// Kept short (suitable for text-to-speech) and in a warm wellness-companion
  /// tone. Returns `null` on timeout/error so the caller can fall back to a
  /// canned message.
  Future<String?> generateVoiceReply(String question) async {
    if (question.trim().isEmpty) return null;
    try {
      final text = await _generateText(
        'The user said to the voice assistant: "$question"\n\n'
        'Reply helpfully. Always finish your sentences completely.',
        temperature: 0.7,
        // Gemini 2.5 Flash is a "thinking" model that spends output tokens on
        // internal reasoning before the visible answer, so a low cap can
        // truncate the reply mid-sentence. Give it ample room; the prompt
        // still keeps the spoken answer short.
        maxOutputTokens: 800,
        systemInstruction:
            'You are the friendly voice assistant inside a wellness app called '
            'AI Wellness Pal. Answer the user\'s question or respond to their '
            'message conversationally in 2-4 complete sentences suitable for '
            'being read aloud. Always finish your thought — never stop '
            'mid-sentence. Be warm, supportive, and practical. Do NOT use '
            'markdown, lists, or emojis. Do NOT give medical, legal, or '
            'financial advice, and avoid clinical language. If the request is '
            'something the app can do (themes, check-in, journal, plans), gently '
            'guide them.',
        timeout: const Duration(seconds: _promptTimeoutSeconds),
      );
      if (text == null) return null;
      return ContentSafetyFilter.sanitize(text);
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generateVoiceReply timed out');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.generateVoiceReply error: $e');
      return null;
    }
  }

  /// Extracts and validates the params for a given command type, matching the
  /// exact shape the voice handler / parser produces. Returns an empty map if
  /// a required param is missing or invalid.
  Map<String, dynamic> _voiceParamsFor(
      VoiceCommandType type, Map<String, dynamic> data) {
    switch (type) {
      case VoiceCommandType.setEnergyScore:
        final score = data['score'];
        if (score is int && score >= 1 && score <= 5) {
          return {'score': score};
        }
        if (score is num && score >= 1 && score <= 5) {
          return {'score': score.round()};
        }
        return {};
      case VoiceCommandType.setMood:
        final mood = data['mood'];
        return (mood is String && _voiceMoodValues.contains(mood))
            ? {'mood': mood}
            : {};
      case VoiceCommandType.setRecoveryStatus:
        final status = data['status'];
        return (status is String && _voiceRecoveryValues.contains(status))
            ? {'status': status}
            : {};
      case VoiceCommandType.setAvailableTime:
        final time = data['time'];
        return (time is String && _voiceTimeValues.contains(time))
            ? {'time': time}
            : {};
      case VoiceCommandType.setAccentColor:
        final name = data['colorName'];
        if (name is String && _voiceColorValues.containsKey(name)) {
          return {'color': _voiceColorValues[name], 'colorName': name};
        }
        return {};
      case VoiceCommandType.toggleWinterMode:
        final enabled = data['enabled'];
        return {'enabled': enabled == true};
      case VoiceCommandType.logIntention:
        final title = data['title'];
        return (title is String && title.trim().isNotEmpty)
            ? {'title': title.trim()}
            : {};
      case VoiceCommandType.logWater:
        final ml = data['amountMl'];
        return (ml is num && ml > 0) ? {'amountMl': ml.round()} : {};
      default:
        return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Wellness intention task steps
  // ---------------------------------------------------------------------------

  /// Generates a short, tidy wellness-intention title from a longer/raw
  /// spoken phrase using Gemini 2.5 Flash (e.g. "i really want to get better
  /// at doing yoga every morning" -> "Morning Yoga Practice").
  ///
  /// Returns a concise Title Case string (≤ 4 words), or `null` on
  /// timeout/error so the caller can fall back to the raw input.
  Future<String?> generateIntentionTitle(String rawInput) async {
    if (rawInput.trim().isEmpty) return null;
    try {
      final text = await _generateText(
        'Turn this into a short wellness intention title:\n"$rawInput"',
        temperature: 0.3,
        maxOutputTokens: 200,
        systemInstruction:
            'You create concise wellness intention titles. Respond with ONLY '
            'the title — 2 to 4 words, Title Case, no quotes, no punctuation, '
            'no emojis, no extra text. Keep the core goal (e.g. "Learn Yoga", '
            '"Better Sleep", "Reduce Stress").',
        timeout: const Duration(seconds: _promptTimeoutSeconds),
      );
      if (text == null) return null;
      // Sanitize + tidy: single line, strip quotes/trailing punctuation.
      var title = ContentSafetyFilter.sanitize(text)
          .split('\n')
          .first
          .trim()
          .replaceAll('"', '')
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      if (title.isEmpty) return null;
      if (title.length > 40) title = title.substring(0, 40).trim();
      return title;
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generateIntentionTitle timed out');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.generateIntentionTitle error: $e');
      return null;
    }
  }

  /// Breaks a wellness intention (e.g. "Learn Yoga") into [days] small daily
  /// task steps using Gemini 2.5 Flash.
  ///
  /// Returns a list of `{title, duration, isCompleted}` maps. On failure,
  /// returns a generic sequence so callers always receive usable tasks.
  Future<List<Map<String, dynamic>>> generateDreamTasks({
    required String dream,
    int days = 7,
  }) async {
    final clampedDays = days.clamp(1, 30);
    try {
      final prompt =
          '''You are a supportive wellness companion. A user has set this wellness intention:

"$dream"

Break this intention into exactly $clampedDays small, encouraging daily steps that gradually build toward it. Each step should be a single short action the user can complete in one day.

CONSTRAINTS:
- Return exactly $clampedDays steps, ordered from easiest first to most advanced last.
- Each step title must be 3 to 8 words, action-oriented, and beginner-friendly.
- Keep a calm, supportive, non-judgmental wellness tone.
- Do NOT use clinical or therapeutic language (avoid: diagnose, treat, therapy, therapist, disorder, symptom, condition, clinical).

Respond ONLY with a valid JSON array of strings, e.g.:
["Set up a calm practice space", "Follow a 10-minute beginner flow"]''';

      final decoded = await _generateJson(
        prompt,
        temperature: 0.7,
        maxOutputTokens: 1024,
        systemInstruction:
            'You are a supportive wellness companion. Respond ONLY with a JSON '
            'array of short step strings.',
        timeout: const Duration(seconds: _planTimeoutSeconds),
      );

      final steps = <String>[];
      if (decoded is List) {
        for (final item in decoded) {
          final title = item.toString().trim();
          if (title.isNotEmpty) steps.add(ContentSafetyFilter.sanitize(title));
        }
      }
      return _assembleTaskSteps(steps, dream, clampedDays);
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generateDreamTasks timed out');
      return _assembleTaskSteps(const [], dream, clampedDays);
    } catch (e) {
      debugPrint('❌ AIService.generateDreamTasks error: $e');
      return _assembleTaskSteps(const [], dream, clampedDays);
    }
  }

  List<Map<String, dynamic>> _assembleTaskSteps(
      List<String> rawSteps, String dream, int days) {
    final fallback = <String>[
      'Reflect on why "$dream" matters to you',
      'Take one small step toward it today',
      'Set aside a few calm minutes to practice',
      'Notice how it makes you feel',
      'Build a gentle daily habit around it',
      'Celebrate a small win',
      'Keep going at your own pace',
    ];

    final cleaned = List<String>.from(rawSteps);
    while (cleaned.length < days) {
      cleaned.add(fallback[cleaned.length % fallback.length]);
    }
    final finalTitles = cleaned.sublist(0, days);

    return finalTitles
        .map((title) => <String, dynamic>{
              'title': title,
              'duration': 15,
              'isCompleted': false,
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Personalized Wellness Studio recommendations
  // ---------------------------------------------------------------------------

  /// Valid Wellness Studio categories the AI may recommend into.
  static const List<String> _studioCategories = [
    'Breathing Exercises',
    'Recovery Challenges',
    'Mindfulness Sessions',
    'Wellness Quizzes',
    'Pilates Knowledge Cards',
    'Stress Recovery Activities',
  ];

  /// Generates a small set of personalized Wellness Studio activities tailored
  /// to the user's recent wellness journey, using Gemini 2.5 Flash.
  ///
  /// Inputs: today's/most-recent [checkIn], recent [recentPlans] (focus +
  /// completed actions), and the user's [intentions]. Returns up to [count]
  /// activities as maps: `{title, category, durationMinutes, reason}`.
  ///
  /// Returns an empty list on timeout/error so the caller can hide the section.
  Future<List<Map<String, dynamic>>> generateStudioRecommendations({
    required CheckIn? checkIn,
    required List<DailyPlan> recentPlans,
    required List<WellnessIntention> intentions,
    int count = 4,
  }) async {
    try {
      final schema = Schema.array(
        items: Schema.object(
          properties: {
            'title': Schema.string(
                description: 'Short activity title, 3-6 words.'),
            'category': Schema.enumString(
              enumValues: _studioCategories,
              description: 'One of the fixed studio categories.',
            ),
            'durationMinutes': Schema.integer(
                description: 'Duration in minutes, 3-15.'),
            'reason': Schema.string(
                description:
                    'One short sentence on why this fits the user today.'),
          },
          optionalProperties: const [],
        ),
      );

      final context = _buildStudioContext(checkIn, recentPlans, intentions);

      final model = _ai.generativeModel(
        model: _modelId,
        generationConfig: GenerationConfig(
          temperature: 0.6,
          maxOutputTokens: 1024,
          responseMimeType: 'application/json',
          responseSchema: schema,
        ),
        systemInstruction: Content.system(
          'You are a wellness studio curator. Recommend short, doable '
          'activities personalized to the user\'s recent wellness journey. '
          'Only use the allowed categories. Keep a calm, supportive tone and '
          'avoid clinical or therapeutic language.',
        ),
      );

      final response = await model.generateContent([
        Content.text(
          'Recommend exactly $count personalized wellness studio activities '
          'for this user based on their recent journey:\n\n$context',
        )
      ]).timeout(const Duration(seconds: _planTimeoutSeconds));

      final decoded = _parseJson(response.text ?? '');
      if (decoded is! List) return const [];

      final results = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final title = (m['title'] as String?)?.trim() ?? '';
        final category = m['category'] as String?;
        if (title.isEmpty ||
            category == null ||
            !_studioCategories.contains(category)) {
          continue;
        }
        final dur = m['durationMinutes'];
        final durationMinutes = dur is num ? dur.round().clamp(3, 15) : 5;
        results.add({
          'title': ContentSafetyFilter.sanitize(title),
          'category': category,
          'durationMinutes': durationMinutes,
          'reason': ContentSafetyFilter.sanitize(
              (m['reason'] as String?)?.trim() ?? ''),
        });
      }
      return results.take(count).toList();
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generateStudioRecommendations timed out');
      return const [];
    } catch (e) {
      debugPrint('❌ AIService.generateStudioRecommendations error: $e');
      return const [];
    }
  }

  String _buildStudioContext(
    CheckIn? checkIn,
    List<DailyPlan> recentPlans,
    List<WellnessIntention> intentions,
  ) {
    final buffer = StringBuffer();
    if (checkIn != null) {
      if (checkIn.energyScore != null) {
        buffer.writeln('Latest energy: ${checkIn.energyScore}/5');
      }
      if (checkIn.moodState != null) {
        buffer.writeln('Latest mood: ${checkIn.moodState!.name}');
      }
      if (checkIn.recoveryStatus != null) {
        buffer.writeln('Latest recovery: ${checkIn.recoveryStatus!.name}');
      }
      if (checkIn.availableTime != null) {
        buffer.writeln('Available time: ${checkIn.availableTime!.name}');
      }
    }
    if (intentions.isNotEmpty) {
      buffer.writeln(
          'Wellness intentions: ${intentions.map((i) => i.title).join(", ")}');
    }
    if (recentPlans.isNotEmpty) {
      buffer.writeln('Recent daily focuses & completed actions:');
      for (final p in recentPlans.take(7)) {
        final completed =
            p.actions.where((a) => a.isCompleted).map((a) => a.title).join(', ');
        buffer.writeln(
            '- ${p.todaysFocus}${completed.isNotEmpty ? " (did: $completed)" : ""}');
      }
    }
    final s = buffer.toString().trim();
    return s.isEmpty ? 'No recent data available.' : s;
  }

  /// Generates step-by-step guidance text for a Wellness Studio activity,
  /// shown when the user taps a personalized recommendation.
  ///
  /// Returns `null` on timeout/error so the caller can show a fallback.
  Future<String?> generateActivityGuidance({
    required String title,
    required String category,
    required int durationMinutes,
  }) async {
    try {
      final text = await _generateText(
        'Give the user simple guidance for this wellness activity so they can '
        'do it right now.\n\nActivity: "$title"\nCategory: $category\n'
        'Duration: about $durationMinutes minutes.',
        temperature: 0.7,
        maxOutputTokens: 700,
        systemInstruction:
            'You are a supportive wellness guide. Explain how to do the '
            'activity in a few short, encouraging steps the user can follow '
            'immediately. Use plain text (you may use simple numbered steps), '
            'no markdown headers or emojis. Keep it concise and calming. Do '
            'NOT use clinical or therapeutic language, and do not give medical '
            'advice.',
        timeout: const Duration(seconds: _promptTimeoutSeconds),
      );
      if (text == null) return null;
      return ContentSafetyFilter.sanitize(text);
    } on TimeoutException catch (_) {
      debugPrint('⏱️ AIService.generateActivityGuidance timed out');
      return null;
    } catch (e) {
      debugPrint('❌ AIService.generateActivityGuidance error: $e');
      return null;
    }
  }
}
