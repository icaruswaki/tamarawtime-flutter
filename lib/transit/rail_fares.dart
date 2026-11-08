import 'dart:convert';

import '../src/journey.dart';
import 'local_transit_graph.dart';

class ReviewedRailFare {
  ReviewedRailFare(
    this.lineUri,
    this.label,
    this.review,
    this.stations,
    this.fares,
  ) {
    if (!lineUri.startsWith('https://') ||
        stations.toSet().length != stations.length ||
        fares.length != stations.length ||
        fares.any(
          (row) =>
              row.length != stations.length ||
              row.any((price) => !price.isFinite || price <= 0),
        )) {
      throw const FormatException('Invalid rail fare matrix');
    }
  }
  final String lineUri, label;
  final NetworkReview review;
  final List<String> stations;
  final List<List<double>> fares;
  double? quote(JourneyStep step, DateTime now) {
    if (!review.current(now) ||
        !step.transit ||
        step.lineUri != lineUri ||
        !{'RAIL', 'SUBWAY', 'TRAM'}.contains(step.vehicle)) {
      return null;
    }
    final from = stations.indexOf(step.boardingStop ?? ''),
        to = stations.indexOf(step.alightingStop ?? '');
    return from < 0 || to < 0 || from == to ? null : fares[from][to];
  }

  static List<ReviewedRailFare> parse(String source) => [
    for (final raw in jsonDecode(source)['tables'] as List)
      ReviewedRailFare(
        raw['line_uri'] as String,
        raw['label'] as String,
        NetworkReview.fromJson(raw as Map),
        List<String>.from(raw['stations'] as List),
        [
          for (final row in raw['fares'] as List)
            [for (final value in row as List) (value as num).toDouble()],
        ],
      ),
  ];
}
