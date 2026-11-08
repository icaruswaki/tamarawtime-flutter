import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? state, String unused, String url);

void clearAuthUrl(Uri uri) {
  final query = Map<String, String>.from(uri.queryParameters)
    ..removeWhere(
      (key, _) => const {
        'code',
        'access_token',
        'refresh_token',
        'expires_in',
        'expires_at',
        'token_type',
        'type',
        'error',
        'error_code',
        'error_description',
        'recovery',
      }.contains(key),
    );
  _replaceState(
    null,
    '',
    uri
        .replace(
          queryParameters: query.isEmpty ? null : query,
          query: query.isEmpty ? '' : null,
          fragment: '',
        )
        .toString(),
  );
}
