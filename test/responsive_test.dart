import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamaraw_time/main.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/theme.dart';

void main() {
  testWidgets(
    'Every planner section adapts to phones, tablets, desktops and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final payload = Planner.fresh()..['onboarding'] = {'finished': true};
      payload['classes'] = [
        {
          'id': 'sample',
          'name': 'A long subject name that needs to wrap on a phone',
          'day': 1,
          'time': '09:00',
          'end': '10:30',
          'room': '401',
          'campus': 'FEU Tech',
        },
      ];
      SharedPreferences.setMockInitialValues({
        'tamaraw_local': jsonEncode(payload),
      });
      double scale = 1;
      await tester.pumpWidget(TamarawTimeApp());
      await tester.tap(find.text('Continue on this device'));
      await tester.pumpAndSettle();
      for (final size in [
        const Size(320, 740),
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1024, 800),
        const Size(1440, 1000),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          find.byType(NavigationBar),
          size.width < 600 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationRail),
          size.width >= 600 && size.width < 1024
              ? findsOneWidget
              : findsNothing,
        );
        for (final icon in [
          Icons.calendar_month,
          Icons.settings_outlined,
          Icons.route,
          Icons.dashboard_outlined,
        ]) {
          await tester.tap(find.byIcon(icon).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$icon at $size');
        }
      }
      // Build with an explicit text scaler to cover accessibility independently
      // of the host OS. The shell and forms must continue to scroll and reflow.
      tester.view.physicalSize = const Size(320, 740);
      final planner = Planner(null);
      await planner.load(deviceOnly: true);
      await tester.pumpWidget(const SizedBox.shrink());
      scale = 2;
      await tester.pumpWidget(
        MaterialApp(
          theme: tamarawTheme('forest'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Dashboard(planner: planner, onExit: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      for (final icon in [
        Icons.calendar_month,
        Icons.settings_outlined,
        Icons.route,
        Icons.dashboard_outlined,
      ]) {
        await tester.tap(find.byIcon(icon).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$icon with large text');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );
}
