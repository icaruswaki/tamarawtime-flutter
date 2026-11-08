import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/journey_service.dart';
import 'package:tamaraw_time/src/routing.dart';

Map<String, dynamic> googleFixture() => {
  'routes': [
    {
      'duration': '1800s',
      'distanceMeters': 5200,
      'polyline': {'encodedPolyline': r'_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
      'legs': [
        {
          'steps': [
            {
              'travelMode': 'WALK',
              'staticDuration': '120s',
              'distanceMeters': 150,
              'navigationInstruction': {
                'instructions': 'Walk to Sample Station',
              },
            },
            {
              'travelMode': 'TRANSIT',
              'staticDuration': '1200s',
              'transitDetails': {
                'stopDetails': {
                  'departureStop': {'name': 'Sample Station'},
                  'arrivalStop': {'name': 'Campus Station'},
                  'departureTime': '2026-11-08T01:02:00Z',
                  'arrivalTime': '2026-11-08T01:22:00Z',
                },
                'headsign': 'Sample terminus',
                'stopCount': 4,
                'transitLine': {
                  'name': 'Fixture rail line',
                  'nameShort': 'L1',
                  'vehicle': {'type': 'SUBWAY'},
                },
              },
            },
            {
              'travelMode': 'WALK',
              'staticDuration': '180s',
              'distanceMeters': 250,
              'navigationInstruction': {'instructions': 'Walk to campus'},
            },
          ],
        },
      ],
      'travelAdvisory': {
        'transitFare': {
          'currencyCode': 'PHP',
          'units': '25',
          'nanos': 500000000,
        },
      },
    },
  ],
};

JourneyOption sampleJourney(
  DateTime now, {
  String id = 'test',
  int minutes = 30,
}) => JourneyOption(
  id: id,
  duration: Duration(minutes: minutes),
  points: const [],
  steps: const [],
  updatedAt: now,
);

class TestProvider implements JourneyProvider {
  final List<JourneyQuery> calls = [];
  Future<List<JourneyOption>> Function(JourneyQuery)? handler;
  @override
  Future<List<JourneyOption>> fetch(JourneyQuery query) {
    calls.add(query);
    return handler?.call(query) ?? Future.value([]);
  }
}

class TestLocation implements LocationGateway {
  LocationPermission allowed = LocationPermission.whileInUse;
  int prompts = 0, cancellations = 0;
  final positions = StreamController<LatLng>.broadcast();
  Completer<LatLng>? pending;
  @override
  Future<bool> enabled() async => true;
  @override
  Future<LocationPermission> permission() async => allowed;
  @override
  Future<LocationPermission> request() async {
    prompts++;
    return allowed;
  }

  @override
  Future<LatLng> current() async => pending?.future ?? const LatLng(14.6, 121);
  @override
  Stream<LatLng> updates() => positions.stream;
}

void configure(JourneyController controller) {
  controller.configure(
    destination: campusPoints['FEU Tech']!,
    label: 'FEU Tech',
    mode: 'Transit',
    autoRefresh: false,
  );
  controller.setOrigin(
    const LatLng(14.6, 121),
    'Starting point',
    refresh: false,
  );
}
