import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/journey_service.dart';
import 'package:tamaraw_time/src/routing.dart';

import 'support/account_fixture.dart';

import 'support/journey_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Timetables can require an earlier departure and a missed boarding is unavailable', () {
    final now = DateTime.utc(2026, 11, 8, 1);
    final option = JourneyOption(
      id: 'scheduled',
      duration: const Duration(minutes: 30),
      points: const [],
      updatedAt: now,
      departure: now.add(const Duration(minutes: 15)),
      arrival: now.add(const Duration(minutes: 45)),
      steps: [
        JourneyStep(
          mode: 'TRANSIT',
          departure: now.add(const Duration(minutes: 20)),
        ),
      ],
    );
    final advice = DepartureAdvice.calculate(
      classStart: now.add(const Duration(hours: 2)),
      now: now,
      preparation: const Duration(minutes: 10),
      buffer: const Duration(minutes: 15),
      journey: option,
    );
    expect(advice.leaveAt, option.departure);
    expect(advice.timetableLimited, isTrue);
    final missed = JourneyOption(
      id: 'missed',
      duration: const Duration(minutes: 30),
      points: const [],
      updatedAt: now,
      arrival: now.add(const Duration(minutes: 20)),
      steps: [
        JourneyStep(
          mode: 'TRANSIT',
          departure: now.subtract(const Duration(minutes: 1)),
        ),
      ],
    );
    expect(missed.freshAt(now), isFalse);
  });

  test('Google itinerary parsing preserves stops, modes, geometry, fares and scheduled times', () {
    final received = DateTime.utc(2026, 11, 8, 1);
    final option = parseGoogleJourneys(
      googleFixture(),
      requestedMode: 'Train',
      receivedAt: received,
    ).single;
    expect(option.duration, const Duration(minutes: 30));
    expect(option.points, hasLength(3));
    expect(option.points.first.latitude, 38.5);
    expect(option.steps[1].boardingStop, 'Sample Station');
    expect(option.steps[1].alightingStop, 'Campus Station');
    expect(option.steps[1].lineName, 'L1');
    expect(option.steps[1].vehicle, 'SUBWAY');
    expect(option.steps[1].headsign, 'Sample terminus');
    expect(option.steps[1].stops, 4);
    expect(option.transfers, 0);
    expect(option.walkingMeters, 400);
    expect(option.fare, 'PHP 25.50');
    expect(option.departure, received.subtract(const Duration(minutes: 5)));
    expect(option.arrival, DateTime.utc(2026, 11, 8, 1, 25));
  });

  test('Provider parsing retains line and agency identities without inferring fare category', () {
    final fixture = googleFixture();
    final step = fixture['routes'][0]['legs'][0]['steps'][1];
    step['distanceMeters'] = 6000;
    step['transitDetails']['transitLine']['uri'] =
        'https://fixture.example/service/1';
    step['transitDetails']['transitLine']['agencies'] = [
      {'name': 'Fixture operator', 'uri': 'https://fixture.example/operator'},
    ];
    final ride = parseGoogleJourneys(
      fixture,
      requestedMode: 'Transit',
      receivedAt: DateTime.utc(2026, 11, 8, 1),
    ).single.steps[1];
    expect(ride.lineUri, 'https://fixture.example/service/1');
    expect(ride.agencyUris, ['https://fixture.example/operator']);
    expect(ride.meters, 6000);
    expect(ride.vehicle, 'SUBWAY');
  });

  test(
    'Missing duration and non-transit responses never become transit ETAs',
    () {
      final fixture = googleFixture();
      (fixture['routes'] as List).first.remove('duration');
      expect(
        parseGoogleJourneys(
          fixture,
          requestedMode: 'Transit',
          receivedAt: DateTime.now(),
        ),
        isEmpty,
      );
      final roadOnly = {
        'routes': [
          {
            'duration': '900s',
            'legs': [
              {
                'steps': [
                  {'travelMode': 'DRIVE'},
                ],
              },
            ],
          },
        ],
      };
      expect(
        parseGoogleJourneys(
          roadOnly,
          requestedMode: 'Train',
          receivedAt: DateTime.now(),
        ),
        isEmpty,
      );
      expect(providerDuration('unknown'), isNull);
      expect(providerDuration('-10s'), isNull);
    },
  );

  test('Absent optional information stays absent instead of generating stop names or fares', () {
    final body = {
      'routes': [
        {
          'duration': '60s',
          'legs': [
            {
              'steps': [
                {'travelMode': 'TRANSIT'},
              ],
            },
          ],
        },
      ],
    };
    final option = parseGoogleJourneys(
      body,
      requestedMode: 'Transit',
      receivedAt: DateTime.now(),
    ).single;
    expect(option.steps.single.boardingStop, isNull);
    expect(option.steps.single.headsign, isNull);
    expect(option.walkingMeters, isNull);
    expect(option.fare, isNull);
  });

  test(
    'Departure formula separates travel, arrival buffer and preparation',
    () {
      final now = DateTime.utc(2026, 11, 8, 1);
      final result = DepartureAdvice.calculate(
        classStart: now.add(const Duration(hours: 2)),
        now: now,
        preparation: const Duration(minutes: 45),
        buffer: const Duration(minutes: 15),
        journey: sampleJourney(now),
      );
      expect(result.leaveAt, now.add(const Duration(minutes: 75)));
      expect(result.prepareAt, now.add(const Duration(minutes: 30)));
      expect(result.arriveAt, now.add(const Duration(minutes: 30)));
      expect(result.status, PunctualityStatus.onTrack);
    },
  );

  test('Statuses require fresh route data and never infer lateness from manual minutes', () {
    final start = DateTime.utc(2026, 11, 8, 3);
    DepartureAdvice advice(DateTime now, JourneyOption? journey) =>
        DepartureAdvice.calculate(
          classStart: start,
          now: now,
          preparation: const Duration(minutes: 45),
          buffer: const Duration(minutes: 15),
          journey: journey,
        );
    final prepareTime = start.subtract(const Duration(minutes: 80));
    expect(
      advice(prepareTime, sampleJourney(prepareTime)).status,
      PunctualityStatus.prepareSoon,
    );
    final leaveTime = start.subtract(const Duration(minutes: 40));
    expect(
      advice(leaveTime, sampleJourney(leaveTime)).status,
      PunctualityStatus.leaveNow,
    );
    final lateTime = start.subtract(const Duration(minutes: 10));
    expect(
      advice(lateTime, sampleJourney(lateTime)).status,
      PunctualityStatus.potentiallyLate,
    );
    expect(advice(lateTime, null).status, PunctualityStatus.unavailable);
    expect(
      advice(
        lateTime,
        sampleJourney(lateTime.subtract(const Duration(minutes: 6))),
      ).leaveAt,
      isNull,
    );
  });

  test('The authenticated backend supplies routes and never receives a Google server key', () async {
    final fixture = AccountFixture()..routesResponse = googleFixture();
    addTearDown(fixture.dispose);
    await fixture.signIn();
    final service = JourneyService(fixture.client, googleReady: () => true);
    final options = await service.fetch(
      const JourneyQuery(
        origin: LatLng(14.6, 121),
        destination: LatLng(14.6043, 120.9884),
        mode: 'Train',
      ),
    );
    expect(options.single.source, JourneySource.google);
    final request = fixture.requests.last;
    expect(request.headers['authorization'], startsWith('Bearer '));
    expect((jsonDecode(request.body) as Map)['mode'], 'Train');
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('x-goog-api-key')),
    );
  });

  test('Transit failure remains unavailable; road fallback has its own source and raw duration', () async {
    var roadCalls = 0;
    final service = JourneyService(
      null,
      local: TestProvider(),
      road: (from, to, mode) async {
        roadCalls++;
        return RoutePlan([from, to], 21, 5000);
      },
    );
    const from = LatLng(14.6, 121), to = LatLng(14.6043, 120.9884);
    expect(
      await service.fetch(
        const JourneyQuery(origin: from, destination: to, mode: 'Transit'),
      ),
      isEmpty,
    );
    expect(roadCalls, 0);
    final road = (await service.fetch(
      const JourneyQuery(origin: from, destination: to, mode: 'Walking'),
    )).single;
    expect(road.minutes, 21);
    expect(road.source, JourneySource.openStreetMap);
    expect(road.sourceLabel, contains('no live traffic'));
  });

  test('Obsolete requests cannot overwrite the current destination or selected itinerary', () async {
    final first = Completer<List<JourneyOption>>(),
        second = Completer<List<JourneyOption>>();
    final provider = TestProvider();
    provider.handler = (_) =>
        provider.calls.length == 1 ? first.future : second.future;
    final controller = JourneyController(provider: provider);
    addTearDown(controller.dispose);
    configure(controller);
    final oldRequest = controller.refresh();
    expect(controller.loading, isTrue);
    controller.configure(
      destination: campusPoints['FEU Diliman']!,
      label: 'FEU Diliman',
      mode: 'Transit',
      autoRefresh: false,
    );
    final currentRequest = controller.refresh();
    second.complete([sampleJourney(DateTime.now(), id: 'new')]);
    await currentRequest;
    first.complete([sampleJourney(DateTime.now(), id: 'obsolete')]);
    await oldRequest;
    expect(controller.selected!.id, 'new');
    expect(controller.loading, isFalse);
  });

  testWidgets(
    'Automatic refreshes are throttled and a stale ETA is refreshed',
    (tester) async {
      var now = DateTime.utc(2026, 11, 8);
      final provider = TestProvider()
        ..handler = (_) async => [sampleJourney(now)];
      final controller = JourneyController(provider: provider, now: () => now);
      configure(controller);
      await controller.refresh();
      await controller.refresh(automatic: true);
      expect(
        provider.calls.where((query) => query.mode == 'Transit'),
        hasLength(1),
      );
      now = now.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(
        provider.calls.where((query) => query.mode == 'Transit'),
        hasLength(2),
      );
      controller.bindLifecycle();
      now = now.add(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 1));
      expect(
        provider.calls.where((query) => query.mode == 'Transit'),
        hasLength(3),
      );
      controller.unbindLifecycle();
      controller.dispose();
    },
  );

  test(
    'Permission denial is not repeatedly prompted and tracking stops cleanly',
    () async {
      final location = TestLocation()..allowed = LocationPermission.denied;
      final controller = JourneyController(
        provider: TestProvider(),
        location: location,
      );
      addTearDown(() async {
        controller.dispose();
        await location.positions.close();
      });
      await controller.startTracking();
      await controller.startTracking();
      expect(location.prompts, 1);
      expect(controller.permissionDenied, isTrue);
      location.allowed = LocationPermission.whileInUse;
      await controller.startTracking();
      expect(controller.tracking, isTrue);
      final before = controller.origin;
      controller.stopTracking();
      location.positions.add(const LatLng(14.7, 121));
      await Future<void>.delayed(Duration.zero);
      expect(controller.origin, before);
      expect(controller.tracking, isFalse);
    },
  );

  test('Stopping a pending location request prevents it from starting a stream later', () async {
    final location = TestLocation()..pending = Completer<LatLng>();
    final controller = JourneyController(
      provider: TestProvider(),
      location: location,
    );
    addTearDown(() async {
      controller.dispose();
      await location.positions.close();
    });
    final start = controller.startTracking();
    await Future<void>.delayed(Duration.zero);
    controller.stopTracking();
    location.pending!.complete(const LatLng(14.6, 121));
    await start;
    expect(controller.tracking, isFalse);
    expect(controller.origin, isNull);
  });
}
