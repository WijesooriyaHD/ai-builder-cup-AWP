/// Shared accent-color name → ARGB int map used by BOTH voice surfaces:
/// the tap-to-speak Assistant ([VoiceIntentParser]) and the Gemini Live
/// "Talk" bridge ([LiveToolBridge]). Keeping a single source of truth means
/// both understand the same color names and apply identical values.
class AccentColors {
  AccentColors._();

  /// Spoken color name → ARGB int. Some names are synonyms of the same swatch
  /// (e.g. coral/orange, turquoise/teal, purple/violet).
  static const Map<String, int> byName = {
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

  /// The distinct color names a user can ask for (deduplicated is not needed;
  /// synonyms are intentionally offered to the model as valid choices).
  static List<String> get names => byName.keys.toList();

  /// Resolves a spoken/typed [name] to its ARGB int, or null if unknown.
  /// Matching is case-insensitive and tolerant of surrounding words
  /// (e.g. "make it teal please" resolves to teal).
  static int? resolve(String? name) {
    if (name == null) return null;
    final n = name.toLowerCase().trim();
    // Exact match first.
    final exact = byName[n];
    if (exact != null) return exact;
    // Otherwise find a known color name contained in the phrase.
    for (final entry in byName.entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
