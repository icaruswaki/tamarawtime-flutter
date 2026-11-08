import 'dart:js_interop';

@JS('loadTamarawGoogleMaps')
external JSPromise<JSBoolean> _load(JSString key);

Future<bool> loadGoogleMaps(String key) async =>
    (await _load(key.toJS).toDart).toDart;
