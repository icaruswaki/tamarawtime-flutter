import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/journey_service.dart';
import 'package:tamaraw_time/src/journey_widgets.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/routing.dart';
import 'package:tamaraw_time/src/theme.dart';
import 'package:tamaraw_time/transit/local_transit_graph.dart';
import 'package:tamaraw_time/transit/local_transit_provider.dart';
import 'package:tamaraw_time/transit/fare_estimator.dart';
import 'package:tamaraw_time/transit/rail_fares.dart';

import 'support/transit_fixture.dart';

final moment = DateTime.utc(2026, 11, 9, 1);
final review = NetworkReview(
  'https://fixture.example/review',
  moment.subtract(const Duration(days: 1)),
  moment.add(const Duration(days: 10)),
);
const a = LatLng(14.6, 121), b = LatLng(14.62, 121), c = LatLng(14.64, 121);
const origin = LatLng(14.599, 121), destination = LatLng(14.641, 121);

TransitGraph fixtureGraph({
  bool timed = true,
  bool connected = true,
  bool boardMiddle = true,
}) {
  GraphStop stop(String id, LatLng point) => GraphStop(
    id: id,
    name: 'Fixture $id',
    point: point,
    review: review,
    board: id != 'B' || boardMiddle,
    entryTime: const Duration(minutes: 1),
    exitTime: const Duration(minutes: 1),
    timingReview: review,
  );
  GraphEdge edge(String from, String to, LatLng p, LatLng q) => GraphEdge(
    id: '$from-$to',
    from: from,
    to: to,
    line: 'Fixture LRT-2',
    direction: 'Fixture Recto',
    review: review,
    geometry: [p, q],
    rideTime: timed ? const Duration(minutes: 4) : null,
    boardingWait: timed ? const Duration(minutes: 3) : null,
    timingReview: timed ? review : null,
  );
  return TransitGraph(
    stops: [stop('A', a), stop('B', b), stop('C', c)],
    edges: [edge('A', 'B', a, b), if (connected) edge('B', 'C', b, c)],
  );
}

Future<RoutePlan> fixtureWalk(LatLng from, LatLng to, String mode) async {
  expect(mode, 'Walking');
  return RoutePlan.timed([from, to], const Duration(minutes: 2), 180);
}

const query = JourneyQuery(
  origin: origin,
  destination: destination,
  mode: 'Transit',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Directed Dijkstra preserves stop order and boarding constraints', () {
    final graph = fixtureGraph(boardMiddle: false);
    expect(searchGraph(graph, 'A', 'C', now: moment).single.map((e) => e.id), [
      'A-B',
      'B-C',
    ]);
    expect(searchGraph(graph, 'C', 'A', now: moment), isEmpty);
    expect(searchGraph(graph, 'B', 'C', now: moment), isEmpty);
    expect(
      searchGraph(fixtureGraph(connected: false), 'A', 'C', now: moment),
      isEmpty,
    );
    expect(
      searchGraph(graph, 'A', 'C', now: moment.add(const Duration(days: 11))),
      isEmpty,
    );
  });

  test('Direct modeled journey includes pedestrian legs, boarding wait and station access', () async {
    final provider = LocalTransitProvider(
      load: () async => fixtureGraph(),
      walk: fixtureWalk,
      now: () => moment,
    );
    final journey = (await provider.fetch(query)).single;
    expect(journey.steps.map((s) => s.mode), ['WALK', 'TRANSIT', 'WALK']);
    expect(
      journey.duration,
      const Duration(minutes: 17),
    ); // 4 walk + 8 ride + 3 wait + 2 station
    expect(journey.walkingMeters, 360);
    expect(journey.steps[1].boardingStop, 'Fixture A');
    expect(journey.steps[1].alightingStop, 'Fixture C');
    expect(journey.steps[1].headsign, 'Fixture Recto');
    expect(journey.steps[1].points, [a, b, b, c]);
    expect(journey.sourceLabel, contains('not live arrivals'));
    final advice = DepartureAdvice.calculate(
      classStart: moment.add(const Duration(hours: 1)),
      now: moment,
      preparation: const Duration(minutes: 20),
      buffer: const Duration(minutes: 10),
      journey: journey,
    );
    expect(advice.leaveAt, moment.add(const Duration(minutes: 33)));
  });

  test(
    'Missing ride timing produces instructions without total or departure ETA',
    () async {
      final journey = (await LocalTransitProvider(
        load: () async => fixtureGraph(timed: false),
        walk: fixtureWalk,
        now: () => moment,
      ).fetch(query)).single;
      expect(journey.estimatedDuration, isNull);
      expect(journey.hasArrivalEstimate, isFalse);
      expect(
        journey.steps.where((s) => s.walking).every((s) => s.duration != null),
        isTrue,
      );
      expect(journey.limitations.join(' '), contains('station-access times'));
      expect(
        DepartureAdvice.calculate(
          classStart: moment.add(const Duration(hours: 1)),
          now: moment,
          preparation: Duration.zero,
          buffer: Duration.zero,
          journey: journey,
        ).leaveAt,
        isNull,
      );
    },
  );

  test(
    'No accessible walk or disconnected graph never becomes an itinerary',
    () async {
      final failedWalk = LocalTransitProvider(
        load: () async => fixtureGraph(),
        walk: (a, b, m) async => throw Exception('No pedestrian access'),
        now: () => moment,
      );
      expect(await failedWalk.fetch(query), isEmpty);
      final disconnected = LocalTransitProvider(
        load: () async => fixtureGraph(connected: false),
        walk: fixtureWalk,
        now: () => moment,
      );
      expect(await disconnected.fetch(query), isEmpty);
    },
  );

  test(
    'Rail interchange requires an explicit reviewed pedestrian connection',
    () {
      final old = fixtureGraph();
      final other = GraphStop(
        id: 'D',
        name: 'Fixture MRT platform',
        point: const LatLng(14.621, 121),
        review: review,
      );
      final graph = TransitGraph(
        stops: [...old.stops, other],
        edges: [
          old.edges.first,
          GraphEdge(
            id: 'D-C',
            from: 'D',
            to: 'C',
            line: 'Fixture MRT-3',
            direction: 'Fixture terminal',
            review: review,
          ),
        ],
      );
      expect(searchGraph(graph, 'A', 'C', now: moment), isEmpty);
      final path = searchGraph(
        graph,
        'A',
        'C',
        now: moment,
        walkingTransfers: [
          GraphEdge(
            id: 'B-D',
            from: 'B',
            to: 'D',
            line: 'Interchange',
            direction: 'D',
            vehicle: 'WALK',
            review: review,
            geometry: [b, other.point],
          ),
        ],
      ).single;
      expect(path.map((e) => e.id), ['A-B', 'B-D', 'D-C']);
    },
  );

  test('Multiple journeys rank comparable durations; unknown timing is never fastest', () {
    JourneyOption option(String id, Duration? duration, int transfers) =>
        JourneyOption(
          id: id,
          duration: duration,
          points: [],
          steps: [],
          updatedAt: moment,
          providerTransfers: transfers,
        );
    final options = [
      option('unknown', null, 0),
      option('slow', const Duration(minutes: 40), 0),
      option('fast', const Duration(minutes: 25), 1),
    ]..sort(compareLocalJourneys);
    expect(options.map((e) => e.id), ['fast', 'slow', 'unknown']);
  });

  test('Provider returns three ordered alternatives and keeps unsupported geometry empty', () async {
    final original = fixtureGraph();
    final graph = TransitGraph(
      stops: original.stops,
      edges: [
        for (var i = 3; i >= 0; i--)
          GraphEdge(
            id: 'variant-$i',
            from: 'A',
            to: 'C',
            line: 'Synthetic line $i',
            direction: 'C',
            review: review,
            rideTime: Duration(minutes: 10 + i),
            boardingWait: const Duration(minutes: 2),
            timingReview: review,
          ),
      ],
    );
    final options = await LocalTransitProvider(
      load: () async => graph,
      walk: fixtureWalk,
      now: () => moment,
    ).fetch(query);
    expect(options, hasLength(3));
    expect(options[0].duration, lessThan(options[1].duration));
    expect(options[1].duration, lessThan(options[2].duration));
    expect(options.every((o) => o.steps[1].points.isEmpty), isTrue);
    expect(
      options.first.limitations.join(' '),
      contains('no straight-line rail segment'),
    );
  });

  test('Failed OTP falls through to instruction-only local state while roads remain independent', () async {
    final local = LocalTransitProvider(
      load: () async => fixtureGraph(timed: false),
      walk: fixtureWalk,
      now: () => moment,
    );
    final controller = JourneyController(
      provider: JourneyService(
        null,
        local: local,
        road: (from, to, mode) async => RoutePlan.timed(
          [from, to],
          const Duration(milliseconds: 810900),
          8085.2,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.configure(
      destination: destination,
      label: 'Fixture destination',
      mode: 'Transit',
      autoRefresh: false,
    );
    controller.setOrigin(origin, 'Fixture origin', refresh: false);
    await controller.refresh();
    expect(controller.selected!.source, JourneySource.localGraph);
    expect(controller.selected!.hasDuration, isFalse);
    expect(controller.drivingEstimate!.duration.inMilliseconds, 810900);
    expect(controller.walkingEstimate!.kilometers, 8.0852);
    expect(controller.message, isNot(contains('provider is not configured')));
  });

  test(
    'Untimed alternatives do not add detours worse on every known criterion',
    () async {
      final base = fixtureGraph(timed: false);
      final graph = TransitGraph(
        stops: base.stops,
        edges: [
          ...base.edges,
          GraphEdge(
            id: 'direct',
            from: 'A',
            to: 'C',
            line: 'Synthetic express',
            direction: 'C',
            review: review,
          ),
        ],
      );
      final options = await LocalTransitProvider(
        load: () async => graph,
        walk: fixtureWalk,
        now: () => moment,
      ).fetch(query);
      expect(options, hasLength(1));
      expect(options.single.id, 'local-direct');
      expect(options.single.hasDuration, isFalse);
    },
  );

  test('Provider requires the interchange walk and shows both boarding instructions', () async {
    final old = fixtureGraph();
    const d = LatLng(14.621, 121);
    final graph = TransitGraph(
      stops: [
        ...old.stops,
        GraphStop(
          id: 'D',
          name: 'Connecting station',
          point: d,
          review: review,
        ),
      ],
      edges: [
        old.edges.first,
        GraphEdge(
          id: 'D-C',
          from: 'D',
          to: 'C',
          line: 'Fixture MRT-3',
          direction: 'Terminal C',
          review: review,
          geometry: [d, c],
        ),
      ],
      transfers: [GraphTransfer('B', 'D', review)],
    );
    final provider = LocalTransitProvider(
      load: () async => graph,
      walk: fixtureWalk,
      now: () => moment,
    );
    final route = (await provider.fetch(query)).single;
    expect(route.steps.map((s) => s.mode), [
      'WALK',
      'TRANSIT',
      'WALK',
      'TRANSIT',
      'WALK',
    ]);
    expect(route.transfers, 1);
    expect(route.steps[2].instruction, contains('Transfer on foot'));
    expect(route.steps[3].boardingStop, 'Connecting station');
    expect(route.steps[3].headsign, 'Terminal C');
    expect(route.hasDuration, isFalse);
    final blocked = LocalTransitProvider(
      load: () async => graph,
      walk: (from, to, mode) async {
        if (from == b && to == d) throw StateError('Interchange closed');
        return fixtureWalk(from, to, mode);
      },
      now: () => moment,
    );
    expect(await blocked.fetch(query), isEmpty);
  });

  test('Bundled graph preserves all rail station orders and actual connected GeoJSON', () async {
    final graph = await LocalTransitProvider.loadBundledGraph();
    expect(graph.stops, hasLength(51));
    expect(graph.stops.where((s) => s.board), hasLength(24));
    expect(graph.edges, hasLength(95));
    expect(graph.transfers, hasLength(6));
    final path = searchGraph(
      graph,
      'LRT-2:Katipunan',
      'LRT-2:Recto',
      now: moment,
    ).first;
    expect(path.first.direction, 'Recto');
    expect(path.last.to, 'LRT-2:Recto');
    expect(path.first.geometry.first.latitude, inInclusiveRange(14, 15));
    expect(path.first.geometry.first.longitude, inInclusiveRange(120, 122));
    final catalog = jsonDecode(
      File('assets/transit/rail_network_2026.json').readAsStringSync(),
    );
    final order = <String, int>{
      for (final line in catalog['lines'])
        for (final s in line['stations']) s['id'] as String: s['order'] as int,
    };
    for (final edge in graph.edges) {
      expect((order[edge.from]! - order[edge.to]!).abs(), 1);
      expect(edge.geometry.length, greaterThan(1));
      expect(edge.rideTime, isNull);
      for (var i = 1; i < edge.geometry.length; i++) {
        expect(
          const Distance()(edge.geometry[i - 1], edge.geometry[i]),
          lessThan(1500),
        );
      }
    }
  });

  test('Historical data and malformed geometry are rejected by the active graph parser', () {
    expect(
      () =>
          TransitGraph.fromJsonString('{"status":"historical_reference_only"}'),
      throwsFormatException,
    );
    final data = jsonDecode(
      File('assets/transit/local_transit_graph.json').readAsStringSync(),
    );
    data['edges'][0]['geometry']['coordinates'][0] = [
      14.6,
      121.0,
    ]; // reversed/invalid latitude
    expect(
      () => TransitGraph.fromJsonString(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('LRT-2 published fares are station-pair quotes with no stacked student discount', () {
    final tables = ReviewedRailFare.parse(
      File('assets/transit/rail_fares_reviewed.json').readAsStringSync(),
    );
    const rail = JourneyStep(
      mode: 'TRANSIT',
      vehicle: 'RAIL',
      lineName: 'LRT-2',
      lineUri: 'https://www.openstreetmap.org/relation/8000265',
      boardingStop: 'Katipunan',
      alightingStop: 'Recto',
    );
    final estimator = FareEstimatorService(
      referenceFares(),
      [],
      railFares: tables,
    );
    final result = estimator.estimate(
      fareJourney(moment, steps: [rail], source: JourneySource.localGraph),
      now: moment,
    );
    expect(result.complete, isTrue);
    expect(result.regular, 13);
    expect(result.student, 13);
    final incomplete = estimator.estimate(
      fareJourney(
        moment,
        steps: [
          rail,
          const JourneyStep(
            mode: 'TRANSIT',
            vehicle: 'RAIL',
            lineName: 'MRT-3',
          ),
        ],
      ),
      now: moment,
    );
    expect(incomplete.complete, isFalse);
    expect(incomplete.unavailableLegs, 1);
    expect(
      tables.single.quote(rail, moment.add(const Duration(days: 40))),
      isNull,
    );
  });

  test('Verified local bus legs reuse LTFRB distance rules, never a guessed vehicle category', () {
    final estimator = verifiedEstimator(moment);
    final fare = estimator.estimate(
      fareJourney(moment, source: JourneySource.localGraph),
      now: moment,
    );
    expect(fare.complete, isTrue);
    expect(fare.student, lessThan(fare.regular));
    expect(
      FareEstimatorService(referenceFares(), [])
          .estimate(
            fareJourney(moment, source: JourneySource.localGraph),
            now: moment,
          )
          .complete,
      isFalse,
    );
  });

  testWidgets(
    'Instruction-only results render in a mobile sheet and desktop sidebar',
    (tester) async {
      final clock = DateTime.now().toUtc();
      final graph = fixtureGraph(timed: false);
      final options = await LocalTransitProvider(
        load: () => Future.value(graph),
        walk: fixtureWalk,
        now: () => moment,
      ).fetch(query);
      final untimed = JourneyOption(
        id: 'screen',
        duration: null,
        points: options.single.points,
        steps: options.single.steps,
        updatedAt: clock,
        source: JourneySource.localGraph,
        limitations: options.single.limitations,
      );
      final controller = JourneyController(provider: _OnlyOptions(untimed));
      final planner = Planner(null, journey: controller)..local = true;
      controller.configure(
        destination: campusPoints['FEU Tech']!,
        label: 'FEU Tech',
        mode: 'Transit',
        autoRefresh: false,
      );
      controller.setOrigin(origin, 'Fixture origin', refresh: false);
      await controller.refresh();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: tamarawTheme('forest'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Commute(planner: planner, onSave: () async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Route 1 · timing incomplete'), findsOneWidget);
      expect(find.text('Fastest'), findsNothing);
      await tester.ensureVisible(find.text('Find public transit'));
      await tester.tap(find.text('Find public transit'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('journey-details-sheet')),
        findsOneWidget,
      );
      final sheetHeading = find.text('Travel estimates');
      final beforeDrag = tester.getTopLeft(sheetHeading).dy;
      await tester.drag(sheetHeading, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(sheetHeading).dy, lessThan(beforeDrag));
      expect(find.byType(JourneyTimeline), findsWidgets);
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-journey-workspace')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('journey-details-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );
}

class _OnlyOptions implements JourneyProvider {
  _OnlyOptions(this.option);
  final JourneyOption option;
  @override
  Future<List<JourneyOption>> fetch(JourneyQuery query) async =>
      query.mode == 'Transit' ? [option] : [];
}
