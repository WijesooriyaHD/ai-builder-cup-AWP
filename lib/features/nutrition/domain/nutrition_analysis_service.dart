import 'dart:io';

import 'nutrition_models.dart';

/// Provider-agnostic contract for analyzing food into a [NutritionResult].
///
/// Implementations wrap a specific backend (e.g. Gemini 2.5 Flash via Firebase
/// Vertex AI, Open Food Facts for barcodes, or a future provider). The
/// presentation and repository layers depend only on this interface, so the
/// underlying AI can be swapped without touching UI code.
abstract class NutritionAnalysisService {
  /// Analyzes a food [image] (from camera or gallery), detecting items,
  /// estimating portions, calories, macros, and generating insights.
  Future<NutritionResult> analyzePhoto(File image);

  /// Analyzes a free-text food description, e.g.
  /// "2 egg hoppers and a cup of milk tea".
  Future<NutritionResult> analyzeText(String text);

  /// Looks up a packaged product by [barcode] and returns its nutrition.
  ///
  /// Implementations should throw [BarcodeNotFoundException] when the product
  /// is not found so the UI can offer manual entry or AI estimation.
  Future<NutritionResult> analyzeBarcode(String barcode);
}

/// Thrown by [NutritionAnalysisService.analyzeBarcode] when a product cannot be
/// found in the backing database.
class BarcodeNotFoundException implements Exception {
  final String barcode;
  const BarcodeNotFoundException(this.barcode);

  @override
  String toString() => 'BarcodeNotFoundException: no product for $barcode';
}

/// Thrown when analysis fails (network/AI error/timeout) so the UI can show a
/// friendly retry message.
class NutritionAnalysisException implements Exception {
  final String message;
  const NutritionAnalysisException(this.message);

  @override
  String toString() => 'NutritionAnalysisException: $message';
}
