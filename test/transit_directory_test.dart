import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/theme.dart';
import 'package:tamaraw_time/transit/rail_reference_repository.dart';
import 'package:tamaraw_time/transit/sakay_reference.dart';
import 'package:tamaraw_time/transit/transit_directory.dart';
import 'package:tamaraw_time/transit/transit_reference_map.dart';
import 'package:tamaraw_time/transit/transit_repository.dart';

class _DirectoryRepository extends TransitRepository {
  _DirectoryRepository({bool reviewed = false})
    : points = Future.value(
        reviewed
            ? {
                'LRT-1:Fernando Poe Jr.': const ReviewedTransitPoint(
                  LatLng(14.6, 121),
                  'https://fixture.example/reviewed-location',
                  '2026-11-08',
                ),
              }
            : {},
      ),
      super(rail: _FixtureRailRepository());
  final Future<Map<String, ReviewedTransitPoint>> points;
  final catalog = Future.value(
    SakayHistoricalCatalog.fromJsonString('''{
    "schema_version":1,"status":"historical_reference_only","source":"Synthetic fixture",
    "source_url":"https://fixture.example","license_url":"https://fixture.example/license",
    "routes":[{"id":"old-puj","name":"Old campus jeepney","mode":"jeepney_reference",
    "historical_only":true,"validated_current_operation":false,"trip_example_id":"old-trip",
    "ordered_stops_from_one_sample_trip":[
      {"stop_id":"s1","name":"Old market","sequence":1,"lat":14.6,"lon":121},
      {"stop_id":"s2","name":"Old campus","sequence":2,"lat":null,"lon":null}]}]
  }'''),
  );
  @override
  Future<SakayHistoricalCatalog> loadSakay() => catalog;
  @override
  Future<Map<String, ReviewedTransitPoint>> loadReviewedPoints() => points;
}

class _FixtureRailRepository extends RailReferenceRepository {
  final network = Future.value(
    RailNetwork.fromJsonString(
      File('assets/transit/rail_network_2026.json').readAsStringSync(),
    ),
  );
  @override
  Future<RailNetwork> loadNetwork() => network;
}

Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: tamarawTheme('forest'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

Future<void> selectSection(WidgetTester tester, String label) async {
  await directoryVisible(tester, find.widgetWithText(ChoiceChip, label), -300);
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

Future<void> directoryVisible(
  WidgetTester tester,
  Finder target,
  double delta,
) => tester.scrollUntilVisible(
  target,
  delta,
  maxScrolls: 60,
  scrollable: find
      .descendant(
        of: find.byKey(const ValueKey('transit-directory-list')),
        matching: find.byType(Scrollable),
      )
      .first,
);

void main() {
  testWidgets(
    'Search, six termini and three transfers reflow on a narrow phone',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(TransitDirectory(repository: _DirectoryRepository()), scale: 2),
      );
      await tester.pumpAndSettle();
      await directoryVisible(
        tester,
        find.byKey(const ValueKey('transit-directory-search')),
        300,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transit-directory-search')),
        'Dr. Santos',
      );
      await tester.pumpAndSettle();
      await directoryVisible(tester, find.text('Dr. Santos').last, 300);
      expect(find.text('Ending terminal'), findsOneWidget);
      await directoryVisible(
        tester,
        find.byKey(const ValueKey('transit-directory-search')),
        -300,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transit-directory-search')),
        '',
      );
      await selectSection(tester, 'Rail transfers');
      await directoryVisible(
        tester,
        find.textContaining('Doroteo Jose ↔ LRT-2 Recto'),
        300,
      );
      expect(find.textContaining('Doroteo Jose ↔ LRT-2 Recto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Station detail has no invented coordinate, fare or train arrival',
    (tester) async {
      await tester.pumpWidget(
        app(TransitDirectory(repository: _DirectoryRepository())),
      );
      await tester.pumpAndSettle();
      await directoryVisible(tester, find.text('Fernando Poe Jr.'), 300);
      await tester.tap(find.text('Fernando Poe Jr.'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Train fare not available.'), findsOneWidget);
      expect(find.textContaining('Map unavailable:'), findsOneWidget);
      expect(find.byType(TransitReferenceMap), findsNothing);
      expect(find.text('Plan a walk to this location'), findsNothing);
    },
  );

  testWidgets(
    'Historical route and stop searches expose sample endpoints without current boarding claims',
    (tester) async {
      await tester.pumpWidget(
        app(TransitDirectory(repository: _DirectoryRepository())),
      );
      await tester.pumpAndSettle();
      await selectSection(tester, 'Historical routes');
      await tester.enterText(
        find.byKey(const ValueKey('transit-directory-search')),
        'market',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Old campus jeepney'));
      await tester.tap(find.text('Old campus jeepney'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not confirmed physical terminals'),
        findsOneWidget,
      );
      expect(find.text('1. Old market'), findsOneWidget);
      expect(find.text('2. Old campus'), findsOneWidget);
      expect(
        find.textContaining('No separate current-service verification'),
        findsOneWidget,
      );
      expect(find.text('Find route'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await selectSection(tester, 'Historical stops');
      expect(find.text('1 matching historical stops'), findsOneWidget);
      await tester.ensureVisible(find.text('Old market'));
      await tester.tap(find.text('Old market'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('independent location review is required'),
        findsOneWidget,
      );
      expect(find.textContaining('Map unavailable:'), findsOneWidget);
    },
  );

  testWidgets('Commute directory returns only a reviewed walking destination', (
    tester,
  ) async {
    final planner = Planner(null, transit: _DirectoryRepository(reviewed: true))
      ..local = true;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: Commute(planner: planner, onSave: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Stations & routes'));
    await tester.tap(find.text('Stations & routes'));
    await tester.pumpAndSettle();
    await directoryVisible(tester, find.text('Fernando Poe Jr.'), 300);
    await tester.tap(find.text('Fernando Poe Jr.'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitReferenceMap), findsOneWidget);
    await tester.ensureVisible(find.text('Plan a walk to this location'));
    await tester.tap(find.text('Plan a walk to this location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Walking directions to'), findsOneWidget);
    expect(find.text('LRT-1 Fernando Poe Jr.'), findsOneWidget);
    expect(planner.journey.mode, 'Walking');
    expect(planner.journey.arriveBy, isNull);
    expect(planner.payload.containsKey('coordinates'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
  });
}
