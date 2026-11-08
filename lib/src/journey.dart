import 'package:latlong2/latlong.dart';

import 'routing.dart';

const liveEstimatesUnavailable =
    'Live travel estimates are currently unavailable.';

Duration? providerDuration(dynamic value) {
  if (value is! String || !value.endsWith('s')) return null;
  final seconds = double.tryParse(value.substring(0, value.length - 1));
  if (seconds == null || !seconds.isFinite || seconds < 0) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

enum JourneySource { google, openStreetMap }

class JourneyStep {
  const JourneyStep({
    required this.mode,
    this.instruction,
    this.lineName,
    this.vehicle,
    this.boardingStop,
    this.alightingStop,
    this.headsign,
    this.stops,
    this.departure,
    this.arrival,
    this.duration,
    this.meters,
    this.points = const [],
  });
  final String mode;
  final String? instruction,
      lineName,
      vehicle,
      boardingStop,
      alightingStop,
      headsign;
  final int? stops;
  final DateTime? departure, arrival;
  final Duration? duration;
  final double? meters;
  final List<LatLng> points;
  bool get transit => mode == 'TRANSIT';
  bool get walking => mode == 'WALK';
}

class JourneyOption {
  const JourneyOption({
    required this.id,
    required this.duration,
    required this.points,
    required this.steps,
    required this.updatedAt,
    this.meters,
    this.fare,
    this.departure,
    this.arrival,
    this.source = JourneySource.google,
  });
  final String id;
  final Duration duration;
  final double? meters;
  final List<LatLng> points;
  final List<JourneyStep> steps;
  final String? fare;
  final DateTime updatedAt;
  final DateTime? departure, arrival;
  final JourneySource source;
  int get minutes => (duration.inSeconds / 60).ceil();
  int get transfers => (steps.where((s) => s.transit).length - 1).clamp(0, 100);
  double? get walkingMeters {
    final walking = steps.where((s) => s.walking).toList();
    if (walking.isEmpty || walking.any((s) => s.meters == null)) return null;
    return walking.fold<double>(0, (sum, s) => sum + s.meters!);
  }

  bool freshAt(DateTime now) =>
      now.difference(updatedAt) <= const Duration(minutes: 5) &&
      (arrival == null || arrival!.isAfter(now)) &&
      !steps
          .where((s) => s.transit)
          .take(1)
          .any((s) => s.departure != null && s.departure!.isBefore(now));
  String get sourceLabel => source == JourneySource.google
      ? 'Google Routes'
      : 'OpenStreetMap · no live traffic';
  bool get hasArrivalEstimate =>
      arrival != null || departure != null || !steps.any((s) => s.transit);
  DateTime arrivalAt(DateTime now) =>
      arrival ?? (departure ?? now).add(duration);
}

class JourneyQuery {
  const JourneyQuery({
    required this.origin,
    required this.destination,
    required this.mode,
    this.arriveBy,
  });
  final LatLng origin, destination;
  final String mode;
  final DateTime? arriveBy;
  Map<String, dynamic> toJson() => {
    'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
    'destination': {
      'latitude': destination.latitude,
      'longitude': destination.longitude,
    },
    'mode': mode,
    if (arriveBy != null && arriveBy!.isAfter(DateTime.now()))
      'arriveBy': arriveBy!.toUtc().toIso8601String(),
  };
}

List<LatLng> _geometry(dynamic polyline) {
  final encoded = polyline is Map ? polyline['encodedPolyline'] : null;
  if (encoded is! String || encoded.isEmpty) return [];
  try {
    return Routing.decodePolyline(encoded, precision: 5);
  } catch (_) {
    return [];
  }
}

double? _meters(dynamic value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// Parse only provider-returned durations and itinerary details. Missing transit
/// data never becomes a driving route, a guessed fare, or a synthetic transfer.
List<JourneyOption> parseGoogleJourneys(
  Map<String, dynamic> body, {
  required String requestedMode,
  required DateTime receivedAt,
}) {
  final result = <JourneyOption>[];
  final routes = body['routes'];
  if (routes is! List) return result;
  for (final raw in routes.whereType<Map>()) {
    final duration = providerDuration(raw['duration']);
    if (duration == null || duration <= Duration.zero) continue;
    final steps = <JourneyStep>[];
    for (final leg in (raw['legs'] as List? ?? []).whereType<Map>()) {
      for (final step in (leg['steps'] as List? ?? []).whereType<Map>()) {
        final transit = step['transitDetails'] as Map? ?? {};
        final stops = transit['stopDetails'] as Map? ?? {};
        final line = transit['transitLine'] as Map? ?? {};
        final navigation = step['navigationInstruction'] as Map? ?? {};
        steps.add(
          JourneyStep(
            mode: step['travelMode'] as String? ?? '',
            instruction: _text(navigation['instructions']),
            lineName: _text(line['nameShort']) ?? _text(line['name']),
            vehicle: _text((line['vehicle'] as Map?)?['type']),
            boardingStop: _text((stops['departureStop'] as Map?)?['name']),
            alightingStop: _text((stops['arrivalStop'] as Map?)?['name']),
            headsign: _text(transit['headsign']),
            stops: transit['stopCount'] is int
                ? transit['stopCount'] as int
                : null,
            departure: DateTime.tryParse(
              stops['departureTime'] as String? ?? '',
            ),
            arrival: DateTime.tryParse(stops['arrivalTime'] as String? ?? ''),
            duration: providerDuration(step['staticDuration']),
            meters: _meters(step['distanceMeters']),
            points: _geometry(step['polyline']),
          ),
        );
      }
    }
    final isTransit = !['Walking', 'Driving'].contains(requestedMode);
    if (isTransit && !steps.any((s) => s.transit)) continue;
    // Preferences are not guarantees: expose the actual returned modes.
    DateTime? departure, arrival;
    final rides = steps.indexed.where((s) => s.$2.transit).toList();
    if (rides.isNotEmpty) {
      final before = steps.take(rides.first.$1).toList();
      final after = steps.skip(rides.last.$1 + 1).toList();
      if (before.every((s) => s.duration != null)) {
        departure = rides.first.$2.departure?.subtract(
          before.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration!),
        );
      }
      if (after.every((s) => s.duration != null)) {
        arrival = rides.last.$2.arrival?.add(
          after.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration!),
        );
      }
    }
    final fare = (raw['travelAdvisory'] as Map?)?['transitFare'] as Map?;
    String? fareText;
    if (fare != null && fare['currencyCode'] is String) {
      final units = double.tryParse('${fare['units'] ?? 0}');
      final nanos = fare['nanos'] is num
          ? (fare['nanos'] as num).toDouble()
          : 0.0;
      if (units != null) {
        fareText =
            '${fare['currencyCode']} ${(units + nanos / 1e9).toStringAsFixed(2)}';
      }
    }
    if (arrival != null) departure = arrival.subtract(duration);
    result.add(
      JourneyOption(
        id: 'google-${result.length}',
        duration: duration,
        meters: _meters(raw['distanceMeters']),
        points: _geometry(raw['polyline']),
        steps: List.unmodifiable(steps),
        fare: fareText,
        updatedAt: receivedAt,
        departure: departure,
        arrival: arrival,
      ),
    );
  }
  return result;
}

enum PunctualityStatus {
  onTrack,
  prepareSoon,
  leaveNow,
  potentiallyLate,
  unavailable,
}

class DepartureAdvice {
  const DepartureAdvice({
    required this.status,
    this.leaveAt,
    this.prepareAt,
    this.arriveAt,
    this.travelDuration,
    this.timetableLimited = false,
  });
  final PunctualityStatus status;
  final DateTime? leaveAt, prepareAt, arriveAt;
  final Duration? travelDuration;
  final bool timetableLimited;
  String get label => switch (status) {
    PunctualityStatus.onTrack => 'On track',
    PunctualityStatus.prepareSoon => 'Prepare soon',
    PunctualityStatus.leaveNow => 'Leave now',
    PunctualityStatus.potentiallyLate => 'Potentially late',
    PunctualityStatus.unavailable => 'ETA unavailable',
  };
  static DepartureAdvice calculate({
    required DateTime classStart,
    required DateTime now,
    required Duration preparation,
    required Duration buffer,
    JourneyOption? journey,
  }) {
    if (journey == null ||
        !journey.freshAt(now) ||
        !journey.hasArrivalEstimate) {
      return const DepartureAdvice(status: PunctualityStatus.unavailable);
    }
    final calculatedLeave = classStart.subtract(journey.duration + buffer);
    final timetableLimited =
        journey.departure != null &&
        journey.departure!.isBefore(calculatedLeave);
    final leave = timetableLimited ? journey.departure! : calculatedLeave;
    final prepare = leave.subtract(preparation);
    final arrival = journey.arrivalAt(now);
    final status = arrival.isAfter(classStart)
        ? PunctualityStatus.potentiallyLate
        : !now.isBefore(leave)
        ? PunctualityStatus.leaveNow
        : !now.isBefore(prepare)
        ? PunctualityStatus.prepareSoon
        : PunctualityStatus.onTrack;
    return DepartureAdvice(
      status: status,
      leaveAt: leave,
      prepareAt: prepare,
      arriveAt: arrival,
      travelDuration: journey.duration,
      timetableLimited: timetableLimited,
    );
  }
}
