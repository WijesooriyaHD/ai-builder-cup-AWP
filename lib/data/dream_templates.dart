import 'package:flutter/material.dart';

class DreamTemplate {
  final String title;
  final int color;
  final IconData icon;
  final String socialProof;
  final List<Map<String, dynamic>> steps;

  const DreamTemplate({
    required this.title,
    required this.color,
    required this.icon,
    required this.socialProof,
    required this.steps,
  });
}

/// Curated wellness intention ideas shown as quick-pick chips.
/// Each focuses on a healthy habit or wellness practice.
final List<DreamTemplate> dreamTemplates = [
  const DreamTemplate(
    title: "Learn Yoga",
    color: 0xFF9C27B0,
    icon: Icons.self_improvement_rounded,
    socialProof: "312 people practicing this",
    steps: [
      {"title": "Set up a calm practice space", "isCompleted": false},
      {"title": "Follow a 10-minute beginner flow", "isCompleted": false},
      {"title": "Practice 3 sessions this week", "isCompleted": false},
      {"title": "Learn 5 foundational poses", "isCompleted": false},
      {"title": "Hold a 20-minute full flow", "isCompleted": false},
    ],
  ),
  const DreamTemplate(
    title: "Sleep Better",
    color: 0xFF2196F3,
    icon: Icons.bedtime_rounded,
    socialProof: "540 people working on this",
    steps: [
      {"title": "Set a consistent bedtime", "isCompleted": false},
      {"title": "No screens 30 min before bed", "isCompleted": false},
      {"title": "Try a wind-down routine", "isCompleted": false},
      {"title": "Wake at the same time daily", "isCompleted": false},
      {"title": "Reach 7+ hours for a week", "isCompleted": false},
    ],
  ),
  const DreamTemplate(
    title: "Reduce Stress",
    color: 0xFF009688,
    icon: Icons.spa_rounded,
    socialProof: "421 people working on this",
    steps: [
      {"title": "Learn a simple breathing exercise", "isCompleted": false},
      {"title": "Take one mindful break each day", "isCompleted": false},
      {"title": "Journal for 5 minutes", "isCompleted": false},
      {"title": "Try a guided meditation", "isCompleted": false},
      {"title": "Build a daily calm ritual", "isCompleted": false},
    ],
  ),
  const DreamTemplate(
    title: "Move Every Day",
    color: 0xFFE91E63,
    icon: Icons.directions_run_rounded,
    socialProof: "268 people working on this",
    steps: [
      {"title": "Take a 10-minute walk", "isCompleted": false},
      {"title": "Stretch for 5 minutes", "isCompleted": false},
      {"title": "Move for 20 minutes, 3 days", "isCompleted": false},
      {"title": "Try a new activity you enjoy", "isCompleted": false},
      {"title": "Stay active for 7 days straight", "isCompleted": false},
    ],
  ),
  const DreamTemplate(
    title: "Practice Mindfulness",
    color: 0xFFFFC107,
    icon: Icons.filter_vintage_rounded,
    socialProof: "197 people working on this",
    steps: [
      {"title": "Sit quietly for 3 minutes", "isCompleted": false},
      {"title": "Do a short body scan", "isCompleted": false},
      {"title": "Practice mindful eating once", "isCompleted": false},
      {"title": "Meditate 5 days this week", "isCompleted": false},
      {"title": "Build a 10-minute daily practice", "isCompleted": false},
    ],
  ),
];
