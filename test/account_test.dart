import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamaraw_time/main.dart';
import 'package:tamaraw_time/src/account.dart';
import 'package:tamaraw_time/src/account_widgets.dart';
import 'package:tamaraw_time/src/theme.dart';

import 'support/account_fixture.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> pumpAccount(WidgetTester tester, AccountFixture fixture) async {
  await tester.pumpWidget(
    TamarawTimeApp(planner: fixture.planner, account: fixture.account),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Cloud planner restores the authenticated payload', () async {
    final fixture = AccountFixture();
    addTearDown(fixture.dispose);
    await fixture.signIn();
    await fixture.planner.load();
    expect(fixture.planner.settings['name'], 'Tamaraw');
  });

  testWidgets(
    'An expired provider session returns to sign-in without deleting classes',
    (tester) async {
      final fixture = AccountFixture();
      addTearDown(fixture.dispose);
      await fixture.signIn();
      await pumpAccount(tester, fixture);
      expect(find.text('Good day, Tamaraw!'), findsOneWidget);
      fixture.expiredRefresh = true;
      await expectLater(
        fixture.client.auth.refreshSession(),
        throwsA(isA<Exception>()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(fixture.client.auth.currentSession, isNull);
      expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Recovery service failures leave a usable form and safe feedback',
    (tester) async {
      final fixture = AccountFixture()..failRecovery = true;
      addTearDown(fixture.dispose);
      await pumpAccount(tester, fixture);
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email address'), 'student@example.com');
      await tester.tap(find.text('Send reset instructions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be completed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send reset instructions'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Remember me delegates persistent sessions and clears them when disabled',
    () async {
      final sdk = MemoryAuthStorage();
      final store = RememberMeStorage(sdk);
      await store.initialize();
      await store.persistSession('opaque-sdk-session');
      expect(await store.hasAccessToken(), isTrue);
      final pending = store.persistSession('refreshed-sdk-session');
      await store.setRemember(false);
      await pending;
      await store.persistSession('memory-only-session');
      expect(sdk.value, isNull);
      expect(await store.accessToken(), isNull);
      final restored = RememberMeStorage(sdk);
      await restored.initialize();
      expect(restored.remember, isFalse);
      expect(await restored.hasAccessToken(), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {'tamaraw_remember_me'});
      await restored.setRemember(true);
      await restored.persistSession('new-sdk-session');
      expect(await restored.accessToken(), 'new-sdk-session');
      await restored.removePersistedSession();
      expect(await restored.hasAccessToken(), isFalse);
    },
  );

  for (final remember in [false, true]) {
    testWidgets('Login uses the Remember me preference: $remember', (
      tester,
    ) async {
      final storage = RememberMeStorage(MemoryAuthStorage());
      await storage.initialize();
      final fixture = AccountFixture(storage: storage);
      addTearDown(fixture.dispose);
      await pumpAccount(tester, fixture);
      if (!remember) {
        await tester.ensureVisible(find.text('Remember me'));
        await tester.tap(find.text('Remember me'));
      }
      await tester.enterText(field('Student email'), 'student@example.com');
      await tester.enterText(
        field('Password (at least 6 characters)'),
        'old-password',
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.text('Good day, Tamaraw!'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      expect(storage.remember, remember);
      expect(
        (await SharedPreferences.getInstance()).getBool('tamaraw_remember_me'),
        remember,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Logout cancellation preserves the session; confirmation keeps schedules',
    (tester) async {
      final fixture = AccountFixture();
      fixture.saved['classes'] = [
        {
          'id': 'saved',
          'name': 'Algorithms',
          'day': 1,
          'time': '09:00',
          'end': '10:30',
          'room': '401',
          'campus': 'FEU Tech',
        },
      ];
      await fixture.signIn();
      addTearDown(fixture.dispose);
      await pumpAccount(tester, fixture);
      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out of Tamaraw Time?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.client.auth.currentUser, isNotNull);
      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(fixture.client.auth.currentSession, isNull);
      expect(find.text('Sign in'), findsOneWidget);
      expect(fixture.saved['classes'], hasLength(1));
      expect(fixture.planner.classes, isEmpty);
      expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Recovery validates email, prevents duplicate requests and gives neutral feedback',
    (tester) async {
      final fixture = AccountFixture();
      addTearDown(fixture.dispose);
      fixture.recoveryGate = Completer<void>();
      await pumpAccount(tester, fixture);
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send reset instructions'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(field('Email address'), 'student@example.com');
      await tester.tap(find.text('Send reset instructions'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send reset instructions'),
            )
            .onPressed,
        isNull,
      );
      fixture.recoveryGate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'If an account exists for this email, password reset instructions have been sent.',
        ),
        findsOneWidget,
      );
      final request = fixture.requests.singleWhere(
        (r) => r.url.path.endsWith('/recover'),
      );
      expect(
        request.url.queryParameters['redirect_to'],
        'com.tamarawtime.app://auth-callback/',
      );
      expect((jsonDecode(request.body) as Map)['code_challenge'], isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'PKCE recovery callback opens the reset form and updates the password',
    (tester) async {
      final fixture = AccountFixture();
      addTearDown(fixture.dispose);
      await fixture.account.requestReset('student@example.com');
      // Simulate the verified email redirect, including a cold-start callback.
      await fixture.account.handleCallback(
        Uri.parse('com.tamarawtime.app://auth-callback/?code=test-code'),
      );
      expect(
        fixture.account.recovering,
        isTrue,
        reason: fixture.account.callbackError,
      );
      await pumpAccount(tester, fixture);
      expect(find.text('Reset your password'), findsOneWidget);
      expect(find.text('Good day, Tamaraw!'), findsNothing);
      await tester.enterText(field('New password'), 'new-password');
      await tester.enterText(
        field('Confirm new password'),
        'different-password',
      );
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(fixture.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(field('Confirm new password'), 'new-password');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where(
          (r) => r.method == 'PUT' && r.url.path.endsWith('/user'),
        ),
        hasLength(1),
      );
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(fixture.client.auth.currentSession, isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Expired recovery links give safe feedback; unrelated links are ignored',
    () async {
      final fixture = AccountFixture();
      addTearDown(fixture.dispose);
      await fixture.account.handleCallback(
        Uri.parse('unrelated://other/?code=ignored'),
      );
      expect(fixture.requests, isEmpty);
      await fixture.account.handleCallback(
        Uri.parse(
          'com.tamarawtime.app://auth-callback/?error=access_denied&error_code=otp_expired',
        ),
      );
      expect(fixture.account.callbackError, contains('expired'));
      expect(fixture.account.recovering, isFalse);
    },
  );

  test('Password change reauthenticates before update and handles provider challenges', () async {
    final fixture = AccountFixture();
    addTearDown(fixture.dispose);
    await fixture.signIn();
    fixture.rejectPassword = true;
    await expectLater(
      fixture.account.changePassword('new-password', current: 'wrong-password'),
      throwsA(isA<Exception>()),
    );
    expect(fixture.requests.where((r) => r.method == 'PUT'), isEmpty);
    fixture.failUpdate = true;
    await expectLater(
      fixture.account.changePassword('new-password', current: 'old-password'),
      throwsA(isA<Exception>()),
    );
    fixture.failUpdate = false;
    await fixture.account.changePassword(
      'new-password',
      current: 'old-password',
      nonce: '123456',
    );
    final change = jsonDecode(fixture.requests.last.body) as Map;
    expect(change['current_password'], 'old-password');
    expect(change['nonce'], '123456');
    expect(
      fixture.requests.where((r) => r.url.path.contains('app_states')),
      isEmpty,
    );
    await fixture.account.signOut();
    await expectLater(
      fixture.account.changePassword('new-password', current: 'old-password'),
      throwsA(isA<Exception>()),
    );
  });

  testWidgets(
    'Change password dialog validates, toggles visibility and submits securely',
    (tester) async {
      final fixture = AccountFixture();
      addTearDown(fixture.dispose);
      await fixture.signIn();
      await tester.pumpWidget(
        MaterialApp(
          theme: tamarawTheme('forest'),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showChangePassword(context, fixture.account),
                child: const Text('Open security'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open security'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'old-password');
      await tester.enterText(field('New password'), 'new-password');
      await tester.enterText(field('Confirm new password'), 'new-password');
      await tester.tap(find.byTooltip('Show new password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(field('New password')).obscureText,
        isFalse,
      );
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Password updated.'), findsOneWidget);
      expect(find.text('Change password'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
