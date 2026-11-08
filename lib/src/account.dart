import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_url_cleanup.dart'
    if (dart.library.js_interop) 'auth_url_cleanup_web.dart';

const passwordMinimum =
    6; // Keep existing accounts and server policy compatible.
bool validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
String? validatePassword(String? value) =>
    (value?.length ?? 0) < passwordMinimum
    ? 'Use at least $passwordMinimum characters.'
    : null;

/// The SDK owns session serialization and persistent storage. Our preference
/// gates its storage hook; unchecked sessions stay only in the SDK's memory.
class RememberMeStorage extends LocalStorage {
  RememberMeStorage(this.delegate);
  final LocalStorage delegate;
  late SharedPreferences preferences;
  bool remember = true;
  Future<void> _queue = Future.value();

  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.catchError((Object _) {}).then((_) => action());
    _queue = next;
    return next;
  }

  @override
  Future<void> initialize() async {
    preferences = await SharedPreferences.getInstance();
    remember = preferences.getBool('tamaraw_remember_me') ?? true;
    await delegate.initialize();
    if (!remember) await delegate.removePersistedSession();
  }

  Future<void> setRemember(bool value) => _serialize(() async {
    // Stop future writes before removing any old SDK session.
    remember = value;
    if (!value) await delegate.removePersistedSession();
    if (!await preferences.setBool('tamaraw_remember_me', value)) {
      throw StateError('Could not save the sign-in preference.');
    }
  });

  @override
  Future<bool> hasAccessToken() async =>
      remember && await delegate.hasAccessToken();
  @override
  Future<String?> accessToken() async =>
      remember ? await delegate.accessToken() : null;
  @override
  Future<void> persistSession(String value) => _serialize(() async {
    // A different browser tab can change the preference before the SDK
    // broadcasts its auth event. Re-read it before allowing a persistent write.
    await preferences.reload();
    if (remember && preferences.getBool('tamaraw_remember_me') != false) {
      await delegate.persistSession(value);
    } else {
      await delegate.removePersistedSession();
    }
  });
  @override
  Future<void> removePersistedSession() =>
      _serialize(delegate.removePersistedSession);
}

String accountError(Object error) {
  if (error is AuthException) {
    if (error.statusCode == '401' && error.code != 'invalid_credentials') {
      return 'Your session expired. Sign in again or request a new recovery link.';
    }
    return switch (error.code) {
      'invalid_credentials' => 'The email or current password is incorrect.',
      'weak_password' =>
        'Choose a stronger password that meets the account policy.',
      'same_password' =>
        'Choose a password different from your current password.',
      'reauthentication_needed' || 'reauthentication_not_valid' => 'Request a verification code, then enter the latest code from your email.',
      'session_not_found' ||
      'refresh_token_not_found' ||
      'refresh_token_already_used' =>
        'Your session expired. Sign in again or request a new recovery link.',
      'otp_expired' || 'flow_state_expired' || 'flow_state_not_found' => 'This link has expired or was already used. Request a new recovery link.',
      'over_request_rate_limit' || 'over_email_send_rate_limit' =>
        'Too many requests. Wait a few minutes and try again.',
      _ => 'The account request could not be completed. Please try again.',
    };
  }
  return 'Could not connect to the account service. Check your connection and try again.';
}

class AccountAuth extends ChangeNotifier {
  AccountAuth(this.client, {this.storage}) {
    _auth = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) recovering = true;
        if (state.event == AuthChangeEvent.signedOut) recovering = false;
        notifyListeners();
      },
      onError: (Object error) {
        callbackError = accountError(error);
        notifyListeners();
      },
    );
  }

  final SupabaseClient client;
  final RememberMeStorage? storage;
  late final StreamSubscription<AuthState> _auth;
  StreamSubscription<Uri>? _links;
  bool recovering = false, handlingLink = false;
  String? callbackError;
  final Set<String> _handledLinks = {};
  bool get remember => storage?.remember ?? true;

  String get recoveryRedirect {
    const configured = String.fromEnvironment('AUTH_REDIRECT_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) {
      // Keep subdirectory hosting; discard query and hash auth parameters.
      final base = Uri.base;
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: base.path,
        queryParameters: {'recovery': '1'},
      ).toString();
    }
    return 'com.tamarawtime.app://auth-callback/';
  }

  Future<void> initializeLinks() async {
    if (kIsWeb) {
      await handleCallback(Uri.base);
    } else {
      final links = AppLinks();
      _links = links.uriLinkStream.listen(
        (uri) => unawaited(handleCallback(uri)),
        onError: (Object _) {
          callbackError =
              'Could not open the recovery link. Request a new link.';
          notifyListeners();
        },
      );
      try {
        final initial = await links.getInitialLink();
        if (initial != null) await handleCallback(initial);
      } catch (_) {
        callbackError = 'Recovery links are unavailable on this platform.';
      }
    }
  }

  Future<void> handleCallback(Uri uri) async {
    final fragment = Uri.splitQueryString(uri.fragment);
    final params = {...uri.queryParameters, ...fragment};
    if (!params.containsKey('code') &&
        !params.containsKey('access_token') &&
        !params.containsKey('error') &&
        !params.containsKey('error_code')) {
      return;
    }
    // Only accept our configured callback location; never treat arbitrary links
    // as sessions. The SDK validates the PKCE code and authenticates the user.
    final allowed = Uri.parse(recoveryRedirect);
    if (uri.scheme != allowed.scheme ||
        uri.host != allowed.host ||
        uri.port != allowed.port ||
        uri.path != allowed.path) {
      return;
    }
    if (!_handledLinks.add(uri.toString())) return;
    handlingLink = true;
    callbackError = null;
    notifyListeners();
    try {
      if (params.containsKey('error') || params.containsKey('error_code')) {
        throw const AuthException('Invalid recovery link', code: 'otp_expired');
      }
      final response = await client.auth.getSessionFromUrl(uri);
      if (response.redirectType == AuthChangeEvent.passwordRecovery.name ||
          response.redirectType == 'recovery') {
        recovering = true;
      }
    } catch (error) {
      callbackError = accountError(error);
    } finally {
      if (kIsWeb) clearAuthUrl(uri);
      handlingLink = false;
      notifyListeners();
    }
  }

  Future<void> setRemember(bool value) async => storage?.setRemember(value);

  Future<void> requestReset(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: recoveryRedirect,
      );
    } on AuthException catch (error) {
      // Account-specific failures must not reveal whether an email is registered.
      if (error.statusCode == '429' ||
          error.statusCode == '422' ||
          error.statusCode == '400' ||
          error.code == 'user_not_found') {
        return;
      }
      rethrow;
    }
  }

  Future<void> changePassword(
    String password, {
    String? current,
    String? nonce,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in again', code: 'session_not_found');
    }
    if (current != null) {
      final verified = await client.auth.signInWithPassword(
        email: user.email!,
        password: current,
      );
      if (verified.user?.id != user.id) {
        throw const AuthException('Sign in again', code: 'session_not_found');
      }
    } else if (!recovering) {
      throw const AuthException('Recovery required', code: 'session_not_found');
    }
    await client.auth.updateUser(
      UserAttributes(
        password: password,
        currentPassword: current,
        nonce: nonce == null || nonce.trim().isEmpty ? null : nonce.trim(),
      ),
    );
  }

  Future<void> signOut() async {
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } finally {
      await storage?.removePersistedSession();
    }
  }

  @override
  void dispose() {
    unawaited(_auth.cancel());
    unawaited(_links?.cancel());
    super.dispose();
  }
}
