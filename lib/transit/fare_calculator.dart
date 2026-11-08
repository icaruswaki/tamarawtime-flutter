import 'dart:convert';
import 'dart:math' as math;

/// Reference fare model; not an official LTFRB fare matrix.
class FareRule {
  final String label;
  final double baseKm;
  final double baseFare;
  final double additionalPerKm;

  const FareRule({
    required this.label,
    required this.baseKm,
    required this.baseFare,
    required this.additionalPerKm,
  });

  factory FareRule.fromJson(Map<String, dynamic> data) => FareRule(
    label: data['label'] as String,
    baseKm: (data['base_km'] as num).toDouble(),
    baseFare: (data['base_fare'] as num).toDouble(),
    additionalPerKm: (data['additional_per_km'] as num).toDouble(),
  );

  bool get valid =>
      label.trim().isNotEmpty &&
      baseKm.isFinite &&
      baseKm > 0 &&
      baseFare.isFinite &&
      baseFare > 0 &&
      additionalPerKm.isFinite &&
      additionalPerKm >= 0;
}

class FareEstimate {
  final double fullFare;
  final double studentFare;
  final String disclaimer;

  const FareEstimate(this.fullFare, this.studentFare, this.disclaimer);
}

class FareCalculator {
  final Map<String, FareRule> rules;
  final double studentDiscount;
  final String effectiveDate;
  final List<String> sources;

  FareCalculator._(
    this.rules,
    this.studentDiscount,
    this.effectiveDate,
    this.sources,
  );

  factory FareCalculator.fromJsonString(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final raw = data['modes'] as Map<String, dynamic>;
    final rules = raw.map(
      (key, value) => MapEntry(
        key,
        FareRule.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
    final discount = (data['discount']['student'] as num).toDouble();
    final metadata = data['metadata'] as Map? ?? {};
    final effective = metadata['effective_date'] as String? ?? '';
    if (rules.values.any((rule) => !rule.valid) ||
        !discount.isFinite ||
        discount != 0.2 ||
        DateTime.tryParse(effective) == null) {
      throw const FormatException('Invalid reference fare configuration');
    }
    return FareCalculator._(
      Map.unmodifiable(rules),
      discount,
      effective,
      List<String>.unmodifiable(metadata['sources'] as List? ?? []),
    );
  }

  /// Uses fractional kilometers and rounds to the nearest P0.25.
  /// The actual fare can differ due to official distance bands and operator matrices.
  FareEstimate? estimate(String mode, double kilometers) {
    if (!kilometers.isFinite || kilometers <= 0) return null;
    // Only these four regulated categories are covered by this reference kit.
    if (!const {
      'traditional_jeepney',
      'modern_jeepney',
      'ordinary_city_bus',
      'aircon_city_bus',
    }.contains(mode)) {
      return null;
    }
    final rule = rules[mode];
    if (rule == null) return null;
    final raw =
        rule.baseFare +
        math.max(0.0, kilometers - rule.baseKm) * rule.additionalPerKm;
    if (!raw.isFinite || !(raw * 4).isFinite) return null;
    final full = (raw * 4).round() / 4;
    final discounted = (raw * (1 - studentDiscount) * 4).round() / 4;
    return FareEstimate(
      full,
      discounted,
      'Reference estimate only; confirm with the posted LTFRB fare matrix.',
    );
  }
}
