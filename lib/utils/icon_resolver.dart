import 'package:flutter/material.dart';

/// Resolves a stored icon codePoint back to a known [IconData] constant.
///
/// Flutter's release tree-shaker requires all [IconData] usages to be
/// compile-time constants. Constructing [IconData] dynamically from a
/// runtime integer (e.g. `IconData(codePoint, fontFamily: 'MaterialIcons')`)
/// breaks release builds with `--tree-shake-icons`.
///
/// This function maps every icon codePoint used in the app to its explicit
/// constant counterpart, satisfying the tree shaker.
/// Falls back to [Icons.star_rounded] for any unrecognised codepoint.
IconData resolveIconData(int codePoint) {
  switch (codePoint) {
    // Dream / template icons (AddDreamScreen + DreamTemplates) — the *_rounded
    // variants have their own distinct codePoints (0xf0.. / 0xf7.. range).
    case 0xf01d4: return Icons.star_rounded;
    case 0xf738:  return Icons.favorite_rounded;
    case 0xf773:  return Icons.flight_takeoff_rounded;
    case 0xf012e: return Icons.school_rounded;
    case 0xf02c7: return Icons.work_rounded;
    case 0xf8ed:  return Icons.music_note_rounded;
    case 0xf767:  return Icons.fitness_center_rounded;
    case 0xf0041: return Icons.palette_rounded;

    // Wellness icons (AddDreamScreen picker + DreamTemplates).
    case 0xf0144: return Icons.self_improvement_rounded;
    case 0xf5b8:  return Icons.bedtime_rounded;
    case 0xf01ad: return Icons.spa_rounded;
    case 0xf6b8:  return Icons.directions_run_rounded;
    case 0xf75f:  return Icons.filter_vintage_rounded;
    case 0xf86a:  return Icons.local_drink_rounded;
    case 0xf00c4: return Icons.psychology_rounded;
    case 0xf542:  return Icons.air_rounded;
    case 0xf02ae: return Icons.wb_sunny_rounded;
    case 0xf029b: return Icons.volunteer_activism_rounded;
    case 0xf8f2:  return Icons.nature_people_rounded;

    // Journal group icons (AddGroupScreen) — *_rounded codePoints.
    case 0xf77e:  return Icons.folder_rounded;
    case 0xf7f5:  return Icons.home_rounded;
    case 0xf855:  return Icons.lightbulb_rounded;
    case 0xf0171: return Icons.shopping_cart_rounded;
    case 0xf0108: return Icons.restaurant_rounded;
    case 0xf772:  return Icons.flight_rounded;
    case 0xf01c7: return Icons.sports_soccer_rounded;

    // ---- Legacy (non-rounded) codePoints from older builds -----------------
    // Kept so intentions/groups saved before the fix still map to a sensible
    // icon instead of silently falling through to the default.
    case 0xe5f9: return Icons.star_rounded;
    case 0xe25a: return Icons.favorite_rounded;
    case 0xe1d5: return Icons.flight_takeoff_rounded;
    case 0xe80c: return Icons.school_rounded;
    case 0xe943: return Icons.work_rounded;
    case 0xe405: return Icons.music_note_rounded;
    case 0xe3a5: return Icons.fitness_center_rounded;
    case 0xe3b0: return Icons.palette_rounded;
    case 0xe2c7: return Icons.folder_rounded;
    case 0xe540: return Icons.home_rounded;
    case 0xe04f: return Icons.lightbulb_rounded;
    case 0xe59c: return Icons.shopping_cart_rounded;
    case 0xe56c: return Icons.restaurant_rounded;
    case 0xe1c6: return Icons.flight_rounded;
    case 0xe594: return Icons.sports_soccer_rounded;

    default:     return Icons.star_rounded;
  }
}
