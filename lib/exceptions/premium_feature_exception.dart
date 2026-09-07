/// Exception thrown when a non-Premium user attempts to access a Premium-gated feature.
class PremiumFeatureException implements Exception {
  /// Identifier of the feature that was locked (e.g., "theme:lavender").
  final String featureId;

  const PremiumFeatureException(this.featureId);

  @override
  String toString() => 'PremiumFeatureException: $featureId is a Premium feature.';
}
