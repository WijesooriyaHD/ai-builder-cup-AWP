import 'dart:convert';

/// Unit the user prefers for displaying/entering body weight.
enum WeightUnit { kg, lb }

extension WeightUnitInfo on WeightUnit {
  String get label => this == WeightUnit.kg ? 'kg' : 'lb';

  /// Converts a value stored in kilograms into this unit.
  double fromKg(double kg) => this == WeightUnit.kg ? kg : kg * 2.2046226218;

  /// Converts a value entered in this unit into kilograms for storage.
  double toKg(double value) =>
      this == WeightUnit.kg ? value : value / 2.2046226218;
}

/// A single body-weight measurement. [weightKg] is always stored in kilograms
/// so the unit preference can change without rewriting history.
class WeightEntry {
  final String id;
  final DateTime date;
  final double weightKg;
  final String? note;

  const WeightEntry({
    required this.id,
    required this.date,
    required this.weightKg,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'note': note,
      };

  factory WeightEntry.fromMap(Map<String, dynamic> map) => WeightEntry(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
        weightKg: (map['weightKg'] as num).toDouble(),
        note: map['note'] as String?,
      );
}

/// The BMI band a weight falls into (WHO adult categories).
enum BmiCategory { underweight, healthy, overweight, obese, unknown }

extension BmiCategoryInfo on BmiCategory {
  String get label {
    switch (this) {
      case BmiCategory.underweight:
        return 'Underweight';
      case BmiCategory.healthy:
        return 'Healthy';
      case BmiCategory.overweight:
        return 'Overweight';
      case BmiCategory.obese:
        return 'Obese';
      case BmiCategory.unknown:
        return 'Add height for BMI';
    }
  }
}

/// Holds all body-weight tracking data and derives trends and BMI.
///
/// Weights are stored internally in kilograms; [unit] controls display/entry.
/// [heightCm] is optional and only used to compute BMI.
class WeightData {
  final List<WeightEntry> entries;
  final WeightUnit unit;
  final double? heightCm;

  const WeightData({
    this.entries = const [],
    this.unit = WeightUnit.kg,
    this.heightCm,
  });

  bool get hasData => entries.isNotEmpty;

  /// Entries sorted oldest → newest.
  List<WeightEntry> get sortedEntries {
    final list = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// The most recent entry, or null.
  WeightEntry? get latest {
    final s = sortedEntries;
    return s.isEmpty ? null : s.last;
  }

  /// The earliest entry, or null.
  WeightEntry? get first {
    final s = sortedEntries;
    return s.isEmpty ? null : s.first;
  }

  /// Current weight in kilograms (most recent entry).
  double? get currentKg => latest?.weightKg;

  /// Current weight converted to the user's preferred unit.
  double? get currentInUnit =>
      currentKg == null ? null : unit.fromKg(currentKg!);

  /// Net change (kg) from the first to the most recent entry.
  double? get totalChangeKg {
    if (entries.length < 2) return null;
    return latest!.weightKg - first!.weightKg;
  }

  /// Change (kg) between the two most recent entries.
  double? get lastChangeKg {
    final s = sortedEntries;
    if (s.length < 2) return null;
    return s.last.weightKg - s[s.length - 2].weightKg;
  }

  double? get minKg {
    if (entries.isEmpty) return null;
    return entries.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b);
  }

  double? get maxKg {
    if (entries.isEmpty) return null;
    return entries.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b);
  }

  /// BMI from the current weight and [heightCm], or null if height unknown.
  double? get bmi {
    final kg = currentKg;
    final h = heightCm;
    if (kg == null || h == null || h <= 0) return null;
    final m = h / 100.0;
    return kg / (m * m);
  }

  BmiCategory get bmiCategory {
    final b = bmi;
    if (b == null) return BmiCategory.unknown;
    if (b < 18.5) return BmiCategory.underweight;
    if (b < 25) return BmiCategory.healthy;
    if (b < 30) return BmiCategory.overweight;
    return BmiCategory.obese;
  }

  WeightData copyWith({
    List<WeightEntry>? entries,
    WeightUnit? unit,
    double? heightCm,
    bool clearHeight = false,
  }) {
    return WeightData(
      entries: entries ?? this.entries,
      unit: unit ?? this.unit,
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
    );
  }

  /// Adds an entry (weight given in kg), replacing any existing entry on the
  /// same calendar day so a day has one canonical measurement.
  WeightData addEntry(WeightEntry entry) {
    final sameDay = entries.where((e) =>
        e.date.year == entry.date.year &&
        e.date.month == entry.date.month &&
        e.date.day == entry.date.day);
    final without = entries.where((e) => !sameDay.contains(e)).toList();
    return copyWith(entries: [...without, entry]);
  }

  WeightData removeEntry(String id) {
    return copyWith(entries: entries.where((e) => e.id != id).toList());
  }

  Map<String, dynamic> toMap() => {
        'entries': sortedEntries.map((e) => e.toMap()).toList(),
        'unit': unit.name,
        'heightCm': heightCm,
      };

  String toJson() => jsonEncode(toMap());

  factory WeightData.fromMap(Map<String, dynamic> map) {
    final rawEntries = (map['entries'] as List<dynamic>?) ?? const [];
    final entries = rawEntries
        .map((e) => WeightEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final unitName = map['unit'] as String?;
    final unit = WeightUnit.values.firstWhere(
      (u) => u.name == unitName,
      orElse: () => WeightUnit.kg,
    );
    return WeightData(
      entries: entries,
      unit: unit,
      heightCm: (map['heightCm'] as num?)?.toDouble(),
    );
  }

  factory WeightData.fromJson(String source) =>
      WeightData.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
