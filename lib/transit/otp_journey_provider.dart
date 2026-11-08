import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../src/journey.dart';
import '../src/routing.dart';

const missingCurrentTransitData =
    'A current transit routing provider is not configured. Historical routes are reference only and cannot supply current transit ETAs.';

/// Talks to our validating gateway, never to Sakay's legacy endpoint or JSONP.
class OtpJourneyProvider {
  OtpJourneyProvider({this.endpoint, this.client});
  factory OtpJourneyProvider.fromEnvironment() {
    const url = String.fromEnvironment('OTP_PLANNER_URL');
    return OtpJourneyProvider(endpoint: url.isEmpty ? null : Uri.parse(url));
  }
  final Uri? endpoint;
  final http.Client? client;
  String? unavailableReason;

  Future<List<JourneyOption>> fetch(JourneyQuery query) async {
    unavailableReason = null;
    final url = endpoint;
    if (url == null) {
      unavailableReason = missingCurrentTransitData;
      return [];
    }
    if (url.scheme != 'https' &&
        !(url.scheme == 'http' &&
            {'localhost', '127.0.0.1', '10.0.2.2'}.contains(url.host))) {
      unavailableReason = 'The transit provider requires a secure connection.';
      return [];
    }
    try {
      final body = jsonEncode(query.toJson());
      final headers = {'Content-Type': 'application/json'};
      final response =
          await (client == null
                  ? http.post(url, headers: headers, body: body)
                  : client!.post(url, headers: headers, body: body))
              .timeout(const Duration(seconds: 25));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        // The gateway supplies actionable data/readiness reasons, not raw OTP
        // exceptions, credentials or a substitute road ETA.
        unavailableReason = payload['reason'] is String
            ? payload['reason'] as String
            : 'The current transit routing service is unavailable.';
        return [];
      }
      final result = parseOtpJourneys(
        payload,
        receivedAt: DateTime.now().toUtc(),
      );
      if (result.isEmpty) {
        unavailableReason = payload['reason'] is String
            ? payload['reason'] as String
            : 'No current scheduled transit connection was returned for this journey.';
      }
      return result;
    } catch (_) {
      unavailableReason = 'The transit routing service could not be reached or returned incomplete data. Walking and driving estimates remain available independently.';
      return [];
    }
  }
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value : null;
double? _number(dynamic value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
DateTime? _time(dynamic value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed?.isUtc == true ? parsed : null;
}

DateTime? _legTime(dynamic value) => value is Map
    ? _time((value['estimated'] as Map?)?['time']) ??
          _time(value['scheduledTime'])
    : null;
LatLng? _point(Map place) {
  final lat = place['lat'], lon = place['lon'];
  return lat is num &&
          lon is num &&
          lat.isFinite &&
          lon.isFinite &&
          lat.abs() <= 90 &&
          lon.abs() <= 180
      ? LatLng(lat.toDouble(), lon.toDouble())
      : null;
}

/// The gateway checks each trip's actual service date against the exact GTFS
/// used in its sealed graph. Static scheduled times are never called real-time.
List<JourneyOption> parseOtpJourneys(
  Map<String, dynamic> payload, {
  required DateTime receivedAt,
}) {
  final generatedAt = _time(payload['generatedAt']);
  if (payload['scheduleValidated'] != true ||
      payload['errors'] != null ||
      generatedAt == null ||
      receivedAt.difference(generatedAt).abs() > const Duration(minutes: 5)) {
    return [];
  }
  final connection = (payload['data'] as Map?)?['planConnection'] as Map?;
  final result = <JourneyOption>[];
  for (final edge in (connection?['edges'] as List? ?? []).whereType<Map>()) {
    try {
      final node = edge['node'] as Map;
      final seconds = _number(node['duration']);
      final start = _time(node['start']), end = _time(node['end']);
      if (seconds == null ||
          seconds <= 0 ||
          start == null ||
          end == null ||
          start.isBefore(receivedAt) ||
          !end.isAfter(start)) {
        continue;
      }
      final steps = <JourneyStep>[];
      for (final leg in (node['legs'] as List).cast<Map>()) {
        final transit = leg['transitLeg'] == true;
        final mode = _text(leg['mode']);
        if (!transit && mode != 'WALK') {
          throw const FormatException('Unsupported non-transit leg');
        }
        final departure = _legTime(leg['start']),
            arrival = _legTime(leg['end']);
        final duration = _number(leg['duration']);
        if (departure == null ||
            arrival == null ||
            duration == null ||
            arrival.isBefore(departure) ||
            (steps.isNotEmpty && departure.isBefore(steps.last.arrival!))) {
          throw const FormatException('Missing or inconsistent leg timing');
        }
        final from = leg['from'] as Map, to = leg['to'] as Map;
        final route = leg['route'] as Map? ?? {};
        final agency = leg['agency'] as Map? ?? {};
        final boarding = _text(from['name']), alighting = _text(to['name']);
        if (transit &&
            (boarding == null ||
                alighting == null ||
                _text((leg['trip'] as Map?)?['gtfsId']) == null ||
                _text(leg['serviceDate']) == null)) {
          throw const FormatException('Incomplete scheduled ride');
        }
        final encoded = (leg['legGeometry'] as Map?)?['points'];
        final geometry = encoded is String && encoded.isNotEmpty
            ? Routing.decodePolyline(encoded, precision: 5)
            : <LatLng>[];
        steps.add(
          JourneyStep(
            mode: transit ? 'TRANSIT' : 'WALK',
            vehicle: transit ? mode : null,
            lineName: _text(route['shortName']) ?? _text(route['longName']),
            lineUri: _text(route['url']),
            agencyUris: [if (_text(agency['url']) case final String uri) uri],
            boardingStop: transit ? boarding : null,
            alightingStop: transit ? alighting : null,
            boardingPoint: transit ? _point(from) : null,
            alightingPoint: transit ? _point(to) : null,
            headsign: _text(leg['headsign']),
            instruction: !transit && boarding != null && alighting != null
                ? 'Walk from $boarding to $alighting'
                : null,
            departure: departure,
            arrival: arrival,
            duration: Duration(microseconds: (duration * 1000000).round()),
            meters: _number(leg['distance']),
            points: geometry,
            interlineWithPreviousLeg: leg['interlineWithPreviousLeg'] == true,
          ),
        );
      }
      if (!steps.any((step) => step.transit) ||
          steps.isEmpty ||
          steps.first.departure != start ||
          steps.last.arrival != end) {
        continue;
      }
      final transfers = node['numberOfTransfers'];
      result.add(
        JourneyOption(
          id: 'otp-${result.length}',
          duration: Duration(microseconds: (seconds * 1000000).round()),
          points: steps.expand((step) => step.points).toList(),
          steps: List.unmodifiable(steps),
          meters: steps.any((step) => step.meters == null)
              ? null
              : steps.fold<double>(0, (total, step) => total + step.meters!),
          departure: start,
          arrival: end,
          source: JourneySource.openTripPlanner,
          updatedAt: receivedAt,
          providerTransfers: transfers is num && transfers >= 0
              ? transfers.toInt()
              : null,
        ),
      );
    } catch (_) {
      // A malformed option cannot invalidate another complete itinerary.
    }
  }
  return result;
}
