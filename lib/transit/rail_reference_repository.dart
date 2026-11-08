import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// A geographic reference reviewed against its named source, not a verified
/// platform entrance, accessible path or operating transit service.
class ReviewedTransitPoint {
  const ReviewedTransitPoint(this.point, this.sourceUrl, this.reviewedOn);
  final LatLng point;
  final String sourceUrl, reviewedOn;
  factory ReviewedTransitPoint.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] as num).toDouble();
    final lon = (json['longitude'] as num).toDouble();
    final source = json['source_url'] as String;
    final reviewed = json['reviewed_on'] as String;
    final uri = Uri.tryParse(source);
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        DateTime.tryParse(reviewed) == null) {
      throw const FormatException('Invalid reviewed coordinate provenance');
    }
    return ReviewedTransitPoint(LatLng(lat, lon), source, reviewed);
  }
}

class RailStation {
  const RailStation({
    required this.id,
    required this.name,
    required this.order,
    required this.kind,
  });
  final String id, name, kind;
  final int order;
  bool get terminal => kind == 'terminal';
  factory RailStation.fromJson(Map<String, dynamic> json) => RailStation(
    id: json['id'] as String,
    name: json['name'] as String,
    order: json['order'] as int,
    kind: json['kind'] as String,
  );
}

class RailLine {
  const RailLine({
    required this.id,
    required this.name,
    required this.stations,
  });
  final String id, name;
  final List<RailStation> stations;
  RailStation get beginning => stations.first;
  RailStation get ending => stations.last;
  factory RailLine.fromJson(Map<String, dynamic> json) {
    final stations =
        (json['stations'] as List)
            .map(
              (raw) =>
                  RailStation.fromJson(Map<String, dynamic>.from(raw as Map)),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (stations.length < 2 ||
        stations.indexed.any(
          (entry) =>
              entry.$2.order != entry.$1 + 1 ||
              entry.$2.id.isEmpty ||
              entry.$2.name.isEmpty,
        ) ||
        !stations.first.terminal ||
        !stations.last.terminal ||
        stations
            .skip(1)
            .take(stations.length - 2)
            .any((station) => station.terminal)) {
      throw const FormatException(
        'Rail order and endpoint terminals are invalid',
      );
    }
    return RailLine(
      id: json['id'] as String,
      name: json['name'] as String,
      stations: List.unmodifiable(stations),
    );
  }
}

class RailTransfer {
  const RailTransfer(this.from, this.to, this.note);
  final String from, to, note;
  String other(String id) => id == from ? to : from;
}

class RailNetwork {
  const RailNetwork(this.lines, this.transfers);
  final List<RailLine> lines;
  final List<RailTransfer> transfers;
  Iterable<RailStation> get stations => lines.expand((line) => line.stations);
  RailStation station(String id) =>
      stations.firstWhere((station) => station.id == id);
  RailLine lineFor(String id) =>
      lines.firstWhere((line) => line.stations.any((s) => s.id == id));
  List<RailTransfer> transfersAt(String id) =>
      transfers.where((t) => t.from == id || t.to == id).toList();

  factory RailNetwork.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['status'] != 'station_network_reference_not_live_service') {
      throw const FormatException('Rail data must be a station reference');
    }
    final lines = (json['lines'] as List)
        .map((raw) => RailLine.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
    final ids = lines
        .expand((line) => line.stations)
        .map((station) => station.id)
        .toList();
    if (ids.toSet().length != ids.length ||
        lines.map((line) => line.id).toSet().length != lines.length) {
      throw const FormatException('Duplicate rail identity');
    }
    final transfers = <RailTransfer>[];
    final seen = <String>{};
    for (final raw in json['walking_transfers'] as List) {
      final from = raw['from'] as String, to = raw['to'] as String;
      final key = ([from, to]..sort()).join('|');
      if (raw['type'] != 'walking_interchange' ||
          !ids.contains(from) ||
          !ids.contains(to) ||
          from == to ||
          !seen.add(key) ||
          lines.indexWhere((line) => line.stations.any((s) => s.id == from)) ==
              lines.indexWhere(
                (line) => line.stations.any((s) => s.id == to),
              )) {
        throw const FormatException('Invalid rail interchange');
      }
      transfers.add(RailTransfer(from, to, raw['note'] as String));
    }
    return RailNetwork(List.unmodifiable(lines), List.unmodifiable(transfers));
  }
}

class RailReferenceRepository {
  Future<RailNetwork>? _network;
  Future<RailNetwork> loadNetwork() => _network ??= _load();
  Future<List<RailLine>> load() async => (await loadNetwork()).lines;
  Future<RailNetwork> _load() async => RailNetwork.fromJsonString(
    await rootBundle.loadString('assets/transit/rail_network_2026.json'),
  );
}
