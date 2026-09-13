import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared "Customize Toolkit" state + bottom sheet.
///
/// Both the Life Toolkit screen (`SheStacksScreen`) and the Habit Builder
/// "Jump to tool" section use this so the visible/hidden tool set stays in
/// sync. Visibility is persisted under a single SharedPreferences key.
class ToolkitCustomize {
  static const String hiddenToolsKey = 'toolkit_hidden_tools';

  /// The customizable tools, in display order. Ids must match the ones used by
  /// the Life Toolkit screen's registry so both stay in sync.
  static const List<ToolkitToolEntry> tools = [
    ToolkitToolEntry('nutrition', 'AI Nutrition Coach', Icons.restaurant_rounded),
    ToolkitToolEntry('meal_planner', 'Meal Planner', Icons.set_meal_rounded),
    ToolkitToolEntry(
        'calorie_budget', 'Calorie Budget', Icons.local_fire_department_rounded),
    ToolkitToolEntry('hydration', 'Hydration Coach', Icons.water_drop_rounded),
    ToolkitToolEntry('sleep', 'Sleep Coach', Icons.nightlight_round),
    ToolkitToolEntry('meditation', 'Meditation Pal', Icons.self_improvement_rounded),
    ToolkitToolEntry('travel', 'Mindful Travel', Icons.flight_takeoff_rounded),
    ToolkitToolEntry('period', 'Period Tracker', Icons.favorite_rounded),
    ToolkitToolEntry('weight', 'Body Weight', Icons.monitor_weight_rounded),
  ];

  /// Loads the set of hidden tool ids from storage.
  static Future<Set<String>> loadHiddenTools() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(hiddenToolsKey);
      if (raw != null && raw.isNotEmpty) {
        return Set<String>.from(jsonDecode(raw) as List);
      }
    } catch (e) {
      debugPrint('❌ ToolkitCustomize.loadHiddenTools: $e');
    }
    return <String>{};
  }

  /// Persists the set of hidden tool ids.
  static Future<void> saveHiddenTools(Set<String> hidden) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(hiddenToolsKey, jsonEncode(hidden.toList()));
    } catch (e) {
      debugPrint('❌ ToolkitCustomize.saveHiddenTools: $e');
    }
  }
}

/// A tool that can be toggled on/off in the Customize Toolkit sheet.
class ToolkitToolEntry {
  final String id;
  final String label;
  final IconData icon;
  const ToolkitToolEntry(this.id, this.label, this.icon);
}

/// Shows the Customize Toolkit bottom sheet. Toggling a tool persists the
/// change immediately to shared storage. Returns when the sheet is dismissed;
/// callers should reload their hidden-tool set afterwards to refresh their UI.
Future<void> showToolkitCustomizeSheet(BuildContext context) async {
  final hidden = await ToolkitCustomize.loadHiddenTools();
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Theme.of(sheetContext).cardColor : Colors.white,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text('Customize Toolkit',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(
                    'Choose which tools appear in your Life Toolkit.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: ToolkitCustomize.tools.map((e) {
                      final visible = !hidden.contains(e.id);
                      final primary = Theme.of(sheetContext).colorScheme.primary;
                      return SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 24),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(e.icon, color: primary, size: 20),
                        ),
                        title: Text(e.label,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        value: visible,
                        activeColor: primary,
                        onChanged: (val) {
                          setSheetState(() {
                            if (val) {
                              hidden.remove(e.id);
                            } else {
                              hidden.add(e.id);
                            }
                          });
                          ToolkitCustomize.saveHiddenTools(hidden);
                        },
                        dense: true,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
