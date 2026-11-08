import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/punctuality_overview.dart';
import 'package:tamaraw_time/src/routing.dart';
import 'package:tamaraw_time/src/theme.dart';
import 'package:tamaraw_time/transit/fare_estimator_view.dart';
import 'package:tamaraw_time/transit/historical_transit_view.dart';
import 'package:tamaraw_time/transit/transit_models.dart';

import 'support/journey_fixture.dart';
import 'support/transit_fixture.dart';

Widget testApp(Widget child, {double scale = 1}) => MaterialApp(
  theme: tamarawTheme('forest'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'Student discount is opt-in, rounded and reflows at double text size',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now().toUtc();
      final planner = Planner(
        null,
        transit: FixtureTransitRepository(verifiedEstimator(now)),
      );
      await tester.pumpWidget(
        testApp(
          ListenableBuilder(
            listenable: planner,
            builder: (context, _) => FareEstimator(
              repository: planner.transit,
              journey: fareJourney(now),
              studentDiscount: planner.studentDiscount,
              onStudentDiscountChanged: planner.selectStudentDiscount,
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Regular: PHP 17.50'), findsOneWidget);
      expect(find.textContaining('Student estimate:'), findsNothing);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('Student estimate: PHP 14.00'), findsOneWidget);
      expect(find.textContaining('2026-09-28'), findsOneWidget);
      expect(find.textContaining('not certified'), findsOneWidget);
      expect(tester.takeException(), isNull);
      planner.clearMemory();
      await tester.pump();
      expect(planner.studentDiscount, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );

  testWidgets(
    'Unknown fares stay unavailable, provider quote gets no blanket discount',
    (tester) async {
      final now = DateTime.now().toUtc();
      final repository = FixtureTransitRepository(verifiedEstimator(now));
      await tester.pumpWidget(
        testApp(
          FareEstimator(
            repository: repository,
            journey: JourneyOption(
              id: 'rail',
              duration: const Duration(minutes: 20),
              points: const [],
              updatedAt: now,
              fare: 'PHP 25.50',
              steps: const [
                JourneyStep(mode: 'TRANSIT', vehicle: 'SUBWAY', meters: 5000),
              ],
            ),
            studentDiscount: true,
            onStudentDiscountChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fare not available'), findsOneWidget);
      expect(find.text('Provider fare: PHP 25.50'), findsOneWidget);
      expect(find.textContaining('Student estimate:'), findsNothing);
      expect(
        find.textContaining('student discount is not applied'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Partial fares are visibly incomplete and never called a trip total',
    (tester) async {
      final now = DateTime.now().toUtc();
      await tester.pumpWidget(
        testApp(
          FareEstimator(
            repository: FixtureTransitRepository(verifiedEstimator(now)),
            journey: fareJourney(
              now,
              steps: [
                verifiedBus(),
                const JourneyStep(mode: 'TRANSIT', vehicle: 'SUBWAY'),
              ],
            ),
            studentDiscount: false,
            onStudentDiscountChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Estimated subtotal · incomplete trip cost'),
        findsOneWidget,
      );
      expect(find.text('Estimated trip fare'), findsNothing);
      expect(find.textContaining('This is not a trip total.'), findsOneWidget);
    },
  );

  testWidgets(
    'Historical exploration shows ordered stops without an active ride flow',
    (tester) async {
      final catalog = TransitCatalog.fromJsonString('''{
      "data_status":"unverified_historical", "source":"Synthetic fixture",
      "routes":[{"id":"r1","name":"Historic fixture","mode":"bus"}],
      "stops":[{"id":"s1","name":"Old first stop","lat":14.6,"lon":121},
        {"id":"s2","name":"Old second stop","lat":14.61,"lon":121.01}],
      "route_stops":{"r1":["s1","s2"]}
    }''');
      await tester.pumpWidget(
        testApp(
          HistoricalTransitExplorer(
            repository: FixtureTransitRepository(
              verifiedEstimator(DateTime.now().toUtc()),
              catalog: catalog,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Historical transit reference'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HISTORICAL / UNVERIFIED'), findsWidgets);
      await tester.tap(find.text('Historic fixture'));
      await tester.pumpAndSettle();
      expect(find.text('1. Old first stop'), findsOneWidget);
      expect(find.text('2. Old second stop'), findsOneWidget);
      expect(find.text('Find route'), findsNothing);
      expect(find.textContaining('Leave by'), findsNothing);
      await tester.enterText(find.byType(TextField), 'No match');
      await tester.pumpAndSettle();
      expect(find.text('No matching historical routes.'), findsOneWidget);
    },
  );

  testWidgets(
    'Dashboard and commute share verified fares, student choice and class departure',
    (tester) async {
      final now = DateTime.now().toUtc();
      final provider = TestProvider()
        ..handler = (_) async => [fareJourney(now)];
      final controller = JourneyController(provider: provider);
      final planner = Planner(
        null,
        journey: controller,
        transit: FixtureTransitRepository(verifiedEstimator(now)),
      )..local = true;
      final classStart = manilaNow().add(const Duration(hours: 2));
      planner.payload['classes'] = [
        {
          'id': 'class',
          'name': 'Next lab',
          'campus': 'FEU Tech',
          'room': '401',
          'day': classStart.weekday % 7,
          'time':
              '${classStart.hour.toString().padLeft(2, '0')}:${classStart.minute.toString().padLeft(2, '0')}',
          'end': '23:59',
        },
      ];
      controller.configure(
        destination: campusPoints['FEU Tech']!,
        label: 'FEU Tech',
        mode: 'Transit',
        autoRefresh: false,
        arriveBy: nextOccurrence(
          planner.classes.single,
          manilaNow(),
        ).subtract(const Duration(hours: 8, minutes: 15)),
      );
      controller.setOrigin(
        const LatLng(14.6, 121),
        'Fixture start',
        refresh: false,
      );
      await controller.refresh();
      await tester.pumpWidget(
        testApp(
          ListenableBuilder(
            listenable: planner,
            builder: (context, _) =>
                PunctualityOverview(planner: planner, onCommute: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Regular: PHP 17.50'), findsOneWidget);
      expect(find.textContaining('Leave by '), findsOneWidget);
      planner.selectStudentDiscount(true);
      await tester.pumpAndSettle();
      expect(find.text('Student estimate: PHP 14.00'), findsOneWidget);
      await tester.pumpWidget(
        testApp(Commute(planner: planner, onSave: () async {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Student estimate: PHP 14.00'), findsOneWidget);
      expect(find.textContaining('Leave by '), findsOneWidget);
      expect(find.text('Departure recommendation'), findsOneWidget);
      // Changing the destination to another campus must clear the class target,
      // even if the provider returns another usable route.
      await tester.ensureVisible(find.text('Find public transit'));
      await tester.tap(find.text('Find public transit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Destination',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('FEU Manila').last);
      await tester.pumpAndSettle();
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.arriveBy, isNull);
      await tester.tap(find.byTooltip('Back to commute planner'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Leave by '), findsNothing);
      expect(
        find.text(
          'Select a class and its campus destination for departure guidance.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );
}
