import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'journey.dart';
import 'journey_service.dart';

abstract interface class LocationGateway {
  Future<bool> enabled();
  Future<LocationPermission> permission();
  Future<LocationPermission> request();
  Future<LatLng> current();
  Stream<LatLng> updates();
}

class DeviceLocation implements LocationGateway {
  @override
  Future<bool> enabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> request() => Geolocator.requestPermission();
  @override
  Future<LatLng> current() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
    return LatLng(p.latitude, p.longitude);
  }

  @override
  Stream<LatLng> updates() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 30,
    ),
  ).map((p) => LatLng(p.latitude, p.longitude));
}

/// Foreground, in-memory journey state shared by dashboard and commute screen.
/// Coordinates are never part of Planner.payload or research activity events.
class JourneyController extends ChangeNotifier with WidgetsBindingObserver {
  JourneyController({
    required this.provider,
    LocationGateway? location,
    DateTime Function()? now,
  }) : location = location ?? DeviceLocation(),
       now = now ?? DateTime.now;
  final JourneyProvider provider;
  final LocationGateway location;
  final DateTime Function() now;
  LatLng? origin, destination;
  LatLng? _routedOrigin;
  String originLabel = 'Your location',
      destinationLabel = 'FEU Tech',
      mode = 'Transit';
  bool manualOrigin = false,
      loading = false,
      tracking = false,
      locating = false,
      permissionDenied = false;
  String message = 'Choose a starting point or enable your location.';
  List<JourneyOption> options = [];
  List<JourneyOption> walkingOptions = [], drivingOptions = [];
  final pendingModes = <String>{};
  JourneyOption? get walkingEstimate =>
      walkingOptions.where((option) => option.freshAt(now())).firstOrNull;
  JourneyOption? get drivingEstimate =>
      drivingOptions.where((option) => option.freshAt(now())).firstOrNull;
  int selectedIndex = 0, _serial = 0, _locationSerial = 0;
  DateTime? lastRequest, arriveBy;
  StreamSubscription<LatLng>? _gps;
  Timer? _refreshTimer, _deferred;
  bool _bound = false, _disposed = false, _foreground = true;
  bool active = true;
  int _clients = 0;
  JourneyOption? get selected =>
      options.isEmpty ? null : options[selectedIndex];
  JourneyQuery? get query => origin == null || destination == null
      ? null
      : JourneyQuery(
          origin: origin!,
          destination: destination!,
          mode: mode,
          arriveBy: arriveBy,
        );

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void bindLifecycle() {
    _clients++;
    if (_bound) return;
    _bound = true;
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground &&
          active &&
          mode != 'Jeepney' &&
          query != null &&
          (lastRequest == null ||
              now().difference(lastRequest!) >= const Duration(minutes: 5) ||
              (selected != null && !selected!.freshAt(now())))) {
        unawaited(refresh(automatic: true));
      }
    });
  }

  void unbindLifecycle() {
    if (_clients > 0) _clients--;
    if (_clients != 0 || !_bound) return;
    _refreshTimer?.cancel();
    _deferred?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _bound = false;
    stopTracking(notify: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed &&
        !(state == AppLifecycleState.inactive && locating)) {
      stopTracking();
    }
  }

  void setActive(bool value) {
    active = value;
    if (!value) stopTracking();
  }

  void configure({
    required LatLng destination,
    required String label,
    required String mode,
    DateTime? arriveBy,
    bool autoRefresh = true,
  }) {
    final changed =
        this.destination != destination ||
        this.mode != mode ||
        this.arriveBy != arriveBy;
    this.destination = destination;
    destinationLabel = label;
    this.mode = mode;
    this.arriveBy = arriveBy;
    if (changed) {
      invalidate();
      if (autoRefresh && origin != null) scheduleRefresh();
    }
  }

  void invalidate() {
    _serial++;
    _deferred?.cancel();
    options = [];
    walkingOptions = [];
    drivingOptions = [];
    pendingModes.clear();
    selectedIndex = 0;
    loading = false;
    message = origin == null
        ? 'Choose an origin on the map or start GPS for your location.'
        : 'Ready to find a route.';
    _emit();
  }

  void setOrigin(
    LatLng point,
    String label, {
    bool manual = true,
    bool refresh = true,
  }) {
    origin = point;
    originLabel = label;
    manualOrigin = manual;
    if (manual) stopTracking();
    invalidate();
    if (refresh) scheduleRefresh();
  }

  void useGpsOrigin() {
    origin = null;
    originLabel = 'Your location';
    manualOrigin = false;
    invalidate();
  }

  void scheduleRefresh() {
    _deferred?.cancel();
    _deferred = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(refresh(automatic: true)),
    );
  }

  Future<void> refresh({bool automatic = false}) async {
    final requestQuery = query;
    if (requestQuery == null ||
        _disposed ||
        (automatic && (!_foreground || !active || mode == 'Jeepney'))) {
      return;
    }
    if (const Distance()(requestQuery.origin, requestQuery.destination) < 10) {
      message = 'Choose different origin and destination points.';
      _emit();
      return;
    }
    if (automatic &&
        lastRequest != null &&
        now().difference(lastRequest!) < const Duration(seconds: 45)) {
      _deferred?.cancel();
      _deferred = Timer(
        const Duration(seconds: 45) - now().difference(lastRequest!),
        () => unawaited(refresh(automatic: true)),
      );
      return;
    }
    if (loading) return;
    final serial = ++_serial;
    lastRequest = now();
    _routedOrigin = origin;
    loading = true;
    options = [];
    walkingOptions = [];
    drivingOptions = [];
    selectedIndex = 0;
    message = 'Finding your commute options…';
    pendingModes.addAll({requestQuery.mode, 'Walking', 'Driving'});
    _emit();
    Future<void> fetchMode(String requestedMode) async {
      var result = <JourneyOption>[];
      try {
        result = await provider.fetch(
          JourneyQuery(
            origin: requestQuery.origin,
            destination: requestQuery.destination,
            mode: requestedMode,
            arriveBy: requestQuery.arriveBy,
          ),
        );
      } catch (_) {
        // Each mode can fail independently without discarding another ETA.
      }
      if (_disposed || serial != _serial) return;
      pendingModes.remove(requestedMode);
      if (requestedMode == 'Walking') walkingOptions = result;
      if (requestedMode == 'Driving') drivingOptions = result;
      if (requestedMode == requestQuery.mode) {
        options = result;
        message = result.isEmpty
            ? '${requestedMode == 'Transit' ? 'Public transit' : requestedMode} estimate unavailable.'
            : '${result.length} ${requestedMode.toLowerCase()} route ${result.length == 1 ? 'option' : 'options'} available.';
        final availability = provider is TransitAvailability
            ? provider as TransitAvailability
            : null;
        if (result.isEmpty &&
            !{'Walking', 'Driving'}.contains(requestedMode) &&
            availability?.transitUnavailableReason != null) {
          message = '$message ${availability!.transitUnavailableReason}';
        }
      }
      // Publish immediately: a slow or failed transit request must not delay
      // successful walking/driving data reaching either screen.
      _emit();
    }

    try {
      await Future.wait(
        {requestQuery.mode, 'Walking', 'Driving'}.map(fetchMode),
      );
    } finally {
      if (!_disposed && serial == _serial) {
        loading = false;
        _emit();
      }
    }
  }

  void select(int index) {
    if (index < 0 || index >= options.length) return;
    selectedIndex = index;
    _emit();
  }

  bool matches(LatLng point, String requestedMode) =>
      destination == point &&
      mode == requestedMode &&
      selected?.freshAt(now()) == true;

  /// Automatic restoration never prompts for permission. An explicit Start GPS
  /// action can prompt once; after denial the user can open the system settings.
  Future<void> restoreGrantedLocation() async {
    if (manualOrigin || origin != null || locating || tracking) return;
    try {
      final permission = await location.permission();
      if (!_disposed &&
          [
            LocationPermission.always,
            LocationPermission.whileInUse,
          ].contains(permission)) {
        await startTracking(requestPermission: false);
      }
    } catch (_) {
      /* Device APIs may not be installed on this platform. */
    }
  }

  Future<void> startTracking({bool requestPermission = true}) async {
    if (locating || tracking || _disposed) return;
    final locationSerial = ++_locationSerial;
    locating = true;
    message = 'Checking location permission…';
    _emit();
    try {
      if (!await location.enabled()) {
        throw StateError('Enable location services to use GPS.');
      }
      var permission = await location.permission();
      final preferences = await SharedPreferences.getInstance();
      if (permission == LocationPermission.denied &&
          requestPermission &&
          preferences.getBool('tamaraw_location_prompted') != true) {
        await preferences.setBool('tamaraw_location_prompted', true);
        permission = await location.request();
      }
      if (![
        LocationPermission.always,
        LocationPermission.whileInUse,
      ].contains(permission)) {
        permissionDenied = true;
        throw StateError(
          'Location permission is off. Choose an origin or enable permission in device settings.',
        );
      }
      if (_disposed || locationSerial != _locationSerial) return;
      final point = await location.current();
      if (_disposed || locationSerial != _locationSerial) return;
      permissionDenied = false;
      manualOrigin = false;
      tracking = true;
      origin = point;
      originLabel = 'Your location';
      invalidate();
      unawaited(refresh(automatic: true));
      _gps = location.updates().listen(
        (point) {
          if (_disposed || locationSerial != _locationSerial || !tracking) {
            return;
          }
          origin = point;
          _emit();
          if (_routedOrigin == null ||
              const Distance()(_routedOrigin!, point) >= 250) {
            invalidate();
            scheduleRefresh();
          }
        },
        onError: (Object _) {
          stopTracking();
          message = 'GPS is unavailable. Choose a starting point on the map.';
          _emit();
        },
      );
    } catch (error) {
      if (!_disposed && locationSerial == _locationSerial) {
        message = error is StateError
            ? error.message.toString()
            : 'Location is unavailable. Choose an origin on the map.';
      }
    } finally {
      if (!_disposed && locationSerial == _locationSerial) {
        locating = false;
        _emit();
      }
    }
  }

  void stopTracking({bool notify = true}) {
    _locationSerial++;
    unawaited(_gps?.cancel());
    _gps = null;
    tracking = false;
    locating = false;
    _deferred?.cancel();
    if (notify) _emit();
  }

  void clear() {
    stopTracking();
    origin = null;
    _routedOrigin = null;
    manualOrigin = false;
    lastRequest = null;
    invalidate();
  }

  @override
  void dispose() {
    _disposed = true;
    _serial++;
    _locationSerial++;
    _refreshTimer?.cancel();
    _deferred?.cancel();
    unawaited(_gps?.cancel());
    if (_bound) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
