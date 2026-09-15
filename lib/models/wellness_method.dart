import 'package:flutter/material.dart';

/// A preferred wellness method the user can choose (Pilates, Yoga, etc.).
///
/// [id] is a STABLE identifier used for persistence and AI/fallback logic —
/// never rely on [label] for internal logic. [keywords] are used to match
/// curated fallback actions to a user's preferred methods.
class WellnessMethod {
  final String id;
  final String label;
  final IconData icon;

  /// Lowercase substrings used to detect whether a curated action title relates
  /// to this method (for the fallback selection).
  final List<String> keywords;

  const WellnessMethod({
    required this.id,
    required this.label,
    required this.icon,
    required this.keywords,
  });
}

/// The full catalog of selectable wellness methods, in display order.
/// Single source of truth for onboarding, settings, and plan generation.
const List<WellnessMethod> kWellnessMethods = [
  WellnessMethod(
    id: 'pilates',
    label: 'Pilates',
    icon: Icons.self_improvement_rounded,
    keywords: ['pilates', 'core', 'posture'],
  ),
  WellnessMethod(
    id: 'yoga',
    label: 'Yoga',
    icon: Icons.spa_rounded,
    keywords: ['yoga', 'vinyasa', 'sun salutation'],
  ),
  WellnessMethod(
    id: 'walking',
    label: 'Walking',
    icon: Icons.directions_walk_rounded,
    keywords: ['walk', 'walking', 'stroll', 'steps'],
  ),
  WellnessMethod(
    id: 'mobility',
    label: 'Mobility',
    icon: Icons.accessibility_new_rounded,
    keywords: ['mobility', 'joint', 'range of motion'],
  ),
  WellnessMethod(
    id: 'stretching',
    label: 'Stretching',
    icon: Icons.airline_seat_legroom_extra_rounded,
    keywords: ['stretch', 'stretching', 'flexibility'],
  ),
  WellnessMethod(
    id: 'strength_training',
    label: 'Strength Training',
    icon: Icons.fitness_center_rounded,
    keywords: ['strength', 'resistance', 'weights', 'bodyweight'],
  ),
  WellnessMethod(
    id: 'recovery_relaxation',
    label: 'Recovery & Relaxation',
    icon: Icons.hotel_rounded,
    keywords: ['recovery', 'relax', 'relaxation', 'restorative', 'rest'],
  ),
  WellnessMethod(
    id: 'meditation',
    label: 'Meditation',
    icon: Icons.nightlight_round,
    keywords: ['meditation', 'meditate', 'body scan', 'mindfulness'],
  ),
  WellnessMethod(
    id: 'breathing',
    label: 'Breathing Exercises',
    icon: Icons.air_rounded,
    keywords: ['breath', 'breathing', 'box breathing', 'pranayama'],
  ),
  WellnessMethod(
    id: 'mindful_movement',
    label: 'Mindful Movement',
    icon: Icons.directions_run_rounded,
    keywords: ['mindful movement', 'gentle movement', 'tai chi', 'qigong'],
  ),
];

/// Minimum number of methods a user must select.
const int kMinWellnessMethods = 3;

/// Looks up a [WellnessMethod] by its stable [id], or null if unknown.
WellnessMethod? wellnessMethodById(String id) {
  for (final m in kWellnessMethods) {
    if (m.id == id) return m;
  }
  return null;
}

/// Infers the wellness method associated with a free-text action [text]
/// (e.g. an action title like "10-minute Pilates core flow") by matching
/// against each method's [keywords], case-insensitively. Returns the first
/// matching method in catalog order, or null if none match.
WellnessMethod? wellnessMethodForText(String text) {
  final lower = text.toLowerCase();
  for (final m in kWellnessMethods) {
    for (final keyword in m.keywords) {
      if (lower.contains(keyword)) return m;
    }
  }
  return null;
}

/// Maps a list of method ids to their display labels (unknown ids skipped).
List<String> wellnessMethodLabels(List<String> ids) {
  final labels = <String>[];
  for (final id in ids) {
    final m = wellnessMethodById(id);
    if (m != null) labels.add(m.label);
  }
  return labels;
}
