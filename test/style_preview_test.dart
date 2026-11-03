import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamaraw_time/main.dart';
import 'package:tamaraw_time/src/planner.dart';

void main() {
  testWidgets('Phone and desktop navigation support every color scheme', (
    tester,
  ) async {
    const preview = bool.fromEnvironment('STYLE_PREVIEW');
    if (preview) {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (font.existsSync()) {
        await tester.runAsync(
          () =>
              (FontLoader('Roboto')..addFont(
                    Future.value(ByteData.sublistView(font.readAsBytesSync())),
                  ))
                  .load(),
        );
      }
      final icons = File(
        'E:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await tester.runAsync(
          () =>
              (FontLoader('MaterialIcons')..addFont(
                    Future.value(ByteData.sublistView(icons.readAsBytesSync())),
                  ))
                  .load(),
        );
      }
    }
    final payload = Planner.fresh();
    payload['onboarding'] = {'finished': true};
    payload['classes'] = [
      {
        'id': 'sample',
        'name': 'Data Structures',
        'day': 1,
        'time': '09:00',
        'end': '10:30',
        'room': 'Room 401',
        'campus': 'FEU Tech',
      },
    ];
    SharedPreferences.setMockInitialValues({
      'tamaraw_local': jsonEncode(payload),
    });
    final planner = Planner(null);
    final boundary = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TamarawTimeApp(planner: planner),
      ),
    );
    if (preview) {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/tamaraw-logo.png'),
          tester.element(find.byType(Image).first),
        ),
      );
    }
    await tester.tap(find.text('Continue on this device'));
    await tester.pumpAndSettle();
    for (final size in [
      const Size(320, 780),
      const Size(390, 844),
      const Size(1440, 1000),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      for (final theme in ['forest', 'ocean', 'sunset', 'night']) {
        planner.settings['theme'] = theme;
        await planner.save();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$theme at $size');
      }
      planner.settings['theme'] = 'forest';
      await planner.save();
      await tester.pumpAndSettle();
      if (size.width >= 1020) {
        expect(find.byType(NavigationBar), findsNothing);
        await tester.tap(find.text('Settings').first);
      } else {
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.tap(find.text('Settings').last);
      }
      await tester.pumpAndSettle();
      expect(find.text('Color scheme'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Settings at $size');
      await tester.tap(find.byIcon(Icons.dashboard_outlined).first);
      await tester.pumpAndSettle();
      if (preview && size.width != 320) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final target = File('build/style-preview-${size.width.toInt()}.png');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
