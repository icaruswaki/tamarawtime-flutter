import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tamaraw_time/src/account.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

// Keep SDK JSON work inside Flutter's fake clock; no background isolates or I/O.
class TestJsonIsolate implements YAJsonIsolate {
  @override
  String? get debugName => 'account-test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<dynamic> decode(String value) async => jsonDecode(value);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}

class MemoryAuthStorage extends LocalStorage {
  String? value;
  int writes = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<void> persistSession(String value) async {
    this.value = value;
    writes++;
  }

  @override
  Future<void> removePersistedSession() async {
    value = null;
  }
}

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class AccountFixture {
  AccountFixture({RememberMeStorage? storage}) {
    client = SupabaseClient(
      'https://accounts.example',
      'public-test-key',
      isolate: TestJsonIsolate(),
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: pkce,
      ),
      httpClient: MockClient((request) async {
        final result = await respond(request);
        return http.Response(
          result.body,
          result.statusCode,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    account = AccountAuth(client, storage: storage);
    planner = Planner(client);
  }

  final pkce = MemoryPkceStorage();
  late final SupabaseClient client;
  late final AccountAuth account;
  late final Planner planner;
  final requests = <http.Request>[];
  bool rejectPassword = false,
      failRecovery = false,
      failUpdate = false,
      expiredRefresh = false;
  Completer<void>? recoveryGate, updateGate;
  final saved = Planner.fresh()..['onboarding'] = {'finished': true};
  Map<String, dynamic> get user => {
    'id': 'student-a',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'student@example.com',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-01-01T00:00:00Z',
  };
  Map<String, dynamic> get session {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    return {
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': 'student-a', 'exp': expiry})}.test',
      'refresh_token': 'test-refresh',
      'expires_in': 3600,
      'expires_at': expiry,
      'token_type': 'bearer',
      'user': user,
    };
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    Map<String, dynamic> body() =>
        jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/recover')) {
      await recoveryGate?.future;
      if (failRecovery) return http.Response('{"message":"unavailable"}', 503);
      return http.Response('{}', 200);
    }
    if (path.endsWith('/token')) {
      if (expiredRefresh &&
          request.url.queryParameters['grant_type'] == 'refresh_token') {
        return http.Response(
          '{"code":"refresh_token_not_found","msg":"Session expired"}',
          400,
        );
      }
      if (rejectPassword && body()['password'] == 'wrong-password') {
        return http.Response(
          '{"code":"invalid_credentials","msg":"Invalid login credentials"}',
          400,
        );
      }
      return http.Response(jsonEncode(session), 200);
    }
    if (path.endsWith('/user') && request.method == 'PUT') {
      await updateGate?.future;
      if (failUpdate) {
        return http.Response(
          '{"code":"reauthentication_needed","msg":"Verification required"}',
          400,
        );
      }
      return http.Response(jsonEncode(user), 200);
    }
    if (path.endsWith('/user')) return http.Response(jsonEncode(user), 200);
    if (path.endsWith('/logout')) return http.Response('', 204);
    if (path.endsWith('/reauthenticate')) return http.Response('{}', 200);
    if (path.endsWith('/app_states') && request.method == 'GET') {
      return http.Response(jsonEncode({'payload': saved}), 200);
    }
    return http.Response('{}', 200);
  }

  Future<void> signIn() async {
    await client.auth.signInWithPassword(
      email: 'student@example.com',
      password: 'old-password',
    );
  }

  Future<void> dispose() async {
    account.dispose();
    planner.dispose();
    await client.dispose();
  }
}
