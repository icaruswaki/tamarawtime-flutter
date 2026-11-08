import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/theme.dart';

Future<void> openRoutes(WidgetTester tester, {double textScale = 1}) async {
  final planner = Planner(null)..local = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: tamarawTheme('forest'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Commute(planner: planner, onSave: () async {}),
        ),
      ),
    ),
  );
  await tester.ensureVisible(find.text('Find route'));
  await tester.tap(find.text('Find route'));
  await tester.pumpAndSettle();
}

Finder endpoint(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label,
);

Future<void> choose(WidgetTester tester, String label, String option) async {
  await tester.tap(endpoint(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Expanded routes reflow with large text on a small phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openRoutes(tester, textScale: 2);
    expect(find.byKey(const ValueKey('expanded-route-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Find route expands without GPS and supports map endpoints', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openRoutes(tester);

    final expandedMap = find.byKey(const ValueKey('expanded-route-map'));
    expect(endpoint('Origin'), findsOneWidget);
    expect(endpoint('Destination'), findsOneWidget);
    expect(tester.getSize(expandedMap).height, greaterThan(360));
    expect(find.textContaining('Choose an origin on the map'), findsOneWidget);

    await choose(tester, 'Origin', 'Choose on map');
    expect(find.text('Tap to place your origin'), findsOneWidget);
    await tester.tapAt(tester.getCenter(expandedMap) + const Offset(-45, 20));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Tap to place your origin'), findsNothing);
    expect(find.byTooltip('Swap origin and destination'), findsOneWidget);
    final map = tester.widget<FlutterMap>(expandedMap);
    final markers = map.children.whereType<MarkerLayer>().single.markers;
    expect(markers, hasLength(2));

    await tester.tap(find.byTooltip('Swap origin and destination'));
    await tester.pumpAndSettle();
    final swapped = tester
        .widget<FlutterMap>(expandedMap)
        .children
        .whereType<MarkerLayer>()
        .single
        .markers;
    expect(swapped.first.point, markers.last.point);
    expect(swapped.last.point, markers.first.point);

    await tester.tap(find.byTooltip('Back to commute planner'));
    await tester.pumpAndSettle();
    expect(expandedMap, findsNothing);
    final preview = tester.widget<FlutterMap>(
      find.byKey(const ValueKey('commute-map')),
    );
    expect(
      preview.children.whereType<MarkerLayer>().single.markers.first.point,
      swapped.first.point,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Route fields fit small screens and reject identical endpoints', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openRoutes(tester);
    await choose(tester, 'Origin', 'FEU Tech');
    await tester.tap(find.widgetWithText(FilledButton, 'Find route'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose different origin and destination points.'),
      findsOneWidget,
    );
    await choose(tester, 'Travel mode', 'Walking');

    tester.view.physicalSize = const Size(740, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to commute planner'));
    await tester.pumpAndSettle();
    expect(find.text('Walking'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
