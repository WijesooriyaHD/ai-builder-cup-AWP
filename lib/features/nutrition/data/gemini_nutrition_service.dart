import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/content_safety_filter.dart';
import '../domain/nutrition_analysis_service.dart';
import '../domain/nutrition_models.dart';

/// [NutritionAnalysisService] backed by Gemini 2.5 Flash (Firebase Vertex AI)
/// for photo/text analysis and Open Food Facts for barcode lookups.
///
/// Uses the same Firebase AI Logic setup as the rest of the app (App Check +
/// Auth), so no API keys are required. All AI text is sanitized via
/// [ContentSafetyFilter].
class GeminiNutritionService implements NutritionAnalysisService {
  static const String _modelId = 'gemini-2.5-flash';
  static const int _timeoutSeconds = 25;

  final FirebaseAI _ai;
  final http.Client _http;

  GeminiNutritionService({FirebaseAI? ai, http.Client? httpClient})
      : _ai = ai ??
            FirebaseAI.vertexAI(
              appCheck: FirebaseAppCheck.instance,
              auth: FirebaseAuth.instance,
            ),
        _http = httpClient ?? http.Client();

  GenerativeModel _model() => _ai.generativeModel(
        model: _modelId,
        generationConfig: GenerationConfig(
          temperature: 0.4,
          maxOutputTokens: 1024,
          responseMimeType: 'application/json',
        ),
        systemInstruction: Content.system(
          'You are a knowledgeable, supportive nutrition coach with expertise '
          'in Sri Lankan cuisine (rice and curry, kottu, hoppers, string '
          'hoppers, pittu, milk rice, biriyani, roti, sambol) as well as '
          'Western and fast foods. Estimate nutrition realistically. Respond '
          'ONLY with valid JSON, no markdown or code fences. Use a calm, '
          'encouraging, non-clinical tone. Never diagnose or use medical '
          'language.',
        ),
      );

  /// The JSON schema instruction shared by photo and text prompts.
  String get _schemaInstruction => '''
Respond ONLY with valid JSON in EXACTLY this shape:
{
  "mealName": "short descriptive name",
  "detectedItems": ["item 1", "item 2"],
  "servingInfo": "estimated portion, e.g. 1 plate (~350g)",
  "calories": number (total kcal),
  "protein": number (grams),
  "carbs": number (grams),
  "fat": number (grams),
  "fiber": number (grams),
  "sugar": number (grams),
  "sodium": number (milligrams),
  "foodQualityScore": number 0-100 (based on protein quality, fiber, sugar, processing level, nutrient density),
  "aiInsights": ["2-4 short supportive insights about this meal"]
}''';

  // ---------------------------------------------------------------------------
  // Photo
  // ---------------------------------------------------------------------------
  @override
  Future<NutritionResult> analyzePhoto(File image) async {
    try {
      final bytes = await image.readAsBytes();
      final mime = _mimeForPath(image.path);
      final prompt = '''
Analyze this food photo. Identify each food item (recognize Sri Lankan dishes),
estimate the portion size shown, and estimate the total nutrition for the whole
plate/serving visible.

$_schemaInstruction''';

      final model = _model();
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          InlineDataPart(mime, bytes),
        ]),
      ]).timeout(const Duration(seconds: _timeoutSeconds));

      final map = _decode(response.text);
      if (map == null) {
        throw const NutritionAnalysisException(
            'Could not read the meal from that photo. Try again or describe it.');
      }
      return _resultFromMap(map, source: 'photo');
    } on NutritionAnalysisException {
      rethrow;
    } on TimeoutException {
      throw const NutritionAnalysisException(
          'Analysis timed out. Please try again.');
    } catch (e) {
      debugPrint('❌ GeminiNutritionService.analyzePhoto: $e');
      throw const NutritionAnalysisException(
          'Something went wrong analyzing that photo.');
    }
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------
  @override
  Future<NutritionResult> analyzeText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const NutritionAnalysisException('Please describe your meal.');
    }
    try {
      final prompt = '''
A user describes a meal: "$trimmed".
Extract the food items, estimate reasonable portion sizes, and estimate the
total nutrition. Recognize Sri Lankan dishes where relevant.

$_schemaInstruction''';

      final model = _model();
      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: _timeoutSeconds));

      final map = _decode(response.text);
      if (map == null) {
        throw const NutritionAnalysisException(
            'Could not analyze that description. Try rephrasing it.');
      }
      return _resultFromMap(map, source: 'text');
    } on NutritionAnalysisException {
      rethrow;
    } on TimeoutException {
      throw const NutritionAnalysisException(
          'Analysis timed out. Please try again.');
    } catch (e) {
      debugPrint('❌ GeminiNutritionService.analyzeText: $e');
      throw const NutritionAnalysisException(
          'Something went wrong analyzing that meal.');
    }
  }

  // ---------------------------------------------------------------------------
  // Barcode (Open Food Facts) with AI fallback for scoring/insights
  // ---------------------------------------------------------------------------
  @override
  Future<NutritionResult> analyzeBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) {
      throw const NutritionAnalysisException('Please enter a barcode number.');
    }
    Map<String, dynamic>? product;
    try {
      final uri = Uri.parse(
          'https://world.openfoodfacts.org/api/v2/product/$code.json'
          '?fields=product_name,brands,nutriments,serving_size,nutriscore_grade,nova_group');
      final resp = await _http.get(uri, headers: {
        'User-Agent': 'AIWellnessPal/1.0 (nutrition coach)',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        if (decoded['status'] == 1 && decoded['product'] is Map) {
          product = Map<String, dynamic>.from(decoded['product'] as Map);
        }
      }
    } catch (e) {
      debugPrint('❌ Open Food Facts lookup error: $e');
    }

    if (product == null) {
      throw BarcodeNotFoundException(code);
    }

    return _resultFromOpenFoodFacts(product, code);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  NutritionResult _resultFromOpenFoodFacts(
      Map<String, dynamic> product, String code) {
    final nutriments =
        (product['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = (product['product_name'] as String?)?.trim();
    final brand = (product['brands'] as String?)?.trim();
    final serving = (product['serving_size'] as String?)?.trim();

    // Open Food Facts reports per-serving where available, else per-100g.
    double n(String key) {
      final serv = nutriments['${key}_serving'];
      if (serv is num) return serv.toDouble();
      final per100 = nutriments['${key}_100g'] ?? nutriments[key];
      return (per100 is num) ? per100.toDouble() : 0.0;
    }

    final calories = n('energy-kcal').round();
    final macros = MacroNutrients(
      protein: n('proteins'),
      carbs: n('carbohydrates'),
      fat: n('fat'),
      fiber: n('fiber'),
      sugar: n('sugars'),
      // OFF sodium is in grams; convert to mg.
      sodiumMg: n('sodium') * 1000,
    );

    final score = _scoreFromOpenFoodFacts(product, macros);
    final insights = _insightsFromMacros(calories, macros, score);

    final displayName = [
      if (brand != null && brand.isNotEmpty) brand,
      if (name != null && name.isNotEmpty) name else 'Packaged product',
    ].join(' ');

    return NutritionResult(
      mealName: displayName,
      calories: calories,
      macros: macros,
      foodQualityScore: score,
      aiInsights: insights,
      detectedItems: [if (name != null && name.isNotEmpty) name],
      servingInfo: serving?.isNotEmpty == true ? serving : 'Per serving/100g',
      source: 'barcode',
    );
  }

  /// Derives a 0–100 quality score from Nutri-Score / NOVA when available,
  /// otherwise from the macro profile.
  int _scoreFromOpenFoodFacts(
      Map<String, dynamic> product, MacroNutrients macros) {
    final grade = (product['nutriscore_grade'] as String?)?.toLowerCase();
    const gradeScore = {'a': 90, 'b': 75, 'c': 60, 'd': 45, 'e': 30};
    if (grade != null && gradeScore.containsKey(grade)) {
      var s = gradeScore[grade]!;
      final nova = (product['nova_group'] as num?)?.toInt();
      if (nova == 4) s -= 10; // ultra-processed penalty
      return s.clamp(0, 100);
    }
    return _heuristicScore(macros);
  }

  /// A lightweight quality heuristic used when the AI/OFF gives no score.
  int _heuristicScore(MacroNutrients m) {
    var score = 55.0;
    score += (m.protein.clamp(0, 40)) * 0.6; // protein rewarded
    score += (m.fiber.clamp(0, 15)) * 1.2; // fiber rewarded
    score -= (m.sugar.clamp(0, 60)) * 0.5; // sugar penalized
    score -= ((m.sodiumMg / 1000).clamp(0, 3)) * 6; // sodium penalized
    return score.clamp(0, 100).round();
  }

  List<String> _insightsFromMacros(
      int calories, MacroNutrients m, int score) {
    final out = <String>[];
    if (m.protein >= 20) {
      out.add('Good protein source to support muscle recovery.');
    } else if (m.protein < 8) {
      out.add('Low in protein — pairing with eggs, fish, or dhal would help.');
    }
    if (m.sodiumMg >= 600) {
      out.add('High sodium. Consider drinking extra water today.');
    }
    if (m.fiber < 3) {
      out.add('Low fiber. Adding vegetables or fruit would improve it.');
    } else if (m.fiber >= 6) {
      out.add('Nicely fiber-rich, which supports steady energy.');
    }
    if (m.sugar >= 25) {
      out.add('Fairly high in sugar — enjoy mindfully.');
    }
    if (out.isEmpty) {
      out.add(score >= 70
          ? 'A balanced choice with a solid nutrient profile.'
          : 'A reasonable choice — balance it across your day.');
    }
    return out.take(4).toList();
  }

  NutritionResult _resultFromMap(Map<String, dynamic> m,
      {required String source}) {
    double d(String k) => (m[k] is num) ? (m[k] as num).toDouble() : 0.0;
    int i(String k) => (m[k] is num) ? (m[k] as num).round() : 0;

    final macros = MacroNutrients(
      protein: d('protein'),
      carbs: d('carbs'),
      fat: d('fat'),
      fiber: d('fiber'),
      sugar: d('sugar'),
      sodiumMg: d('sodium'),
    );

    var score = i('foodQualityScore');
    if (score <= 0 || score > 100) score = _heuristicScore(macros);

    final rawInsights = (m['aiInsights'] as List<dynamic>?)
            ?.map((e) => ContentSafetyFilter.sanitize(e.toString()))
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        <String>[];
    final insights =
        rawInsights.isNotEmpty ? rawInsights : _insightsFromMacros(i('calories'), macros, score);

    final items = (m['detectedItems'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    return NutritionResult(
      mealName: ContentSafetyFilter.sanitize(
          (m['mealName'] as String?)?.trim().isNotEmpty == true
              ? m['mealName'] as String
              : 'Meal'),
      calories: i('calories'),
      macros: macros,
      foodQualityScore: score,
      aiInsights: insights.take(4).toList(),
      detectedItems: items,
      servingInfo: (m['servingInfo'] as String?)?.trim(),
      source: source,
    );
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      var text = raw.replaceAll(RegExp(r'```json', caseSensitive: false), '');
      text = text.replaceAll('```', '').trim();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      try {
        final start = raw.indexOf('{');
        final end = raw.lastIndexOf('}');
        if (start != -1 && end > start) {
          final decoded = jsonDecode(raw.substring(start, end + 1));
          if (decoded is Map<String, dynamic>) return decoded;
        }
      } catch (_) {}
    }
    return null;
  }

  String _mimeForPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic') || p.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
