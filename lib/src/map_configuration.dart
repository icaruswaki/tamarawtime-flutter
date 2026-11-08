import 'package:flutter/foundation.dart';

import 'maps_loader.dart' if (dart.library.js_interop) 'maps_loader_web.dart';

class GoogleMapsSetup {
  static bool available = false;
  static Future<void> initialize() async {
    const enabled = bool.fromEnvironment('GOOGLE_MAPS_ENABLED');
    const webKey = String.fromEnvironment('GOOGLE_MAPS_WEB_KEY');
    if (kIsWeb) {
      if (webKey.isNotEmpty) {
        try {
          available = await loadGoogleMaps(webKey);
        } catch (_) {
          available = false;
        }
      }
    } else {
      available =
          enabled &&
          [
            TargetPlatform.android,
            TargetPlatform.iOS,
          ].contains(defaultTargetPlatform);
    }
  }
}
