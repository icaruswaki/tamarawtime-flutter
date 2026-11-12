import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../transit/historical_transit_view.dart';
import '../transit/transit_directory.dart';
import '../transit/transit_reference_map.dart';
import '../transit/local_rail_layer.dart';
import '../transit/local_transit_provider.dart';
import 'planner.dart';
import 'routing.dart';
import 'theme.dart';
import 'journey.dart';
import 'journey_controller.dart';
import 'journey_widgets.dart';
import 'google_journey_map.dart';

export 'journey.dart' show trafficBufferMinutes, drivingAdjustedMinutes;

class Commute extends StatefulWidget {
  const Commute({super.key, required this.planner, required this.onSave});
  final Planner planner;
  final Future<void> Function() onSave;
  @override
  State<Commute> createState() => _CommuteState();
}

class _OriginDialog extends StatefulWidget {
  const _OriginDialog({this.initial});
  final LatLng? initial;
  @override
  State<_OriginDialog> createState() => _OriginDialogState();
}

class _OriginDialogState extends State<_OriginDialog> {
  final form = GlobalKey<FormState>();
  final label = TextEditingController(text: 'Starting point');
  late final latitude = TextEditingController(
    text: widget.initial?.latitude.toString(),
  );
  late final longitude = TextEditingController(
    text: widget.initial?.longitude.toString(),
  );
  @override
  void dispose() {
    label.dispose();
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  String? coordinate(String? value, double limit) {
    final n = double.tryParse(value ?? '');
    return n == null || !n.isFinite || n.abs() > limit
        ? 'Enter a value from -$limit to $limit.'
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your starting point'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter coordinates, or cancel and choose a point on the map.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: label,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Location name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: (v) => coordinate(v, 90),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: (v) => coordinate(v, 180),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, (
            LatLng(double.parse(latitude.text), double.parse(longitude.text)),
            label.text.trim(),
          ));
        },
        child: const Text('Use this origin'),
      ),
    ],
  );
}

class _RouteWorkspace extends StatefulWidget {
  const _RouteWorkspace({
    required this.revision,
    required this.onReady,
    required this.onClosed,
    required this.builder,
  });

  final ValueNotifier<int> revision;
  final void Function(MapController) onReady;
  final VoidCallback onClosed;
  final Widget Function(BuildContext, MapController) builder;

  @override
  State<_RouteWorkspace> createState() => _RouteWorkspaceState();
}

class _RouteWorkspaceState extends State<_RouteWorkspace> {
  final map = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady(map);
    });
  }

  @override
  void dispose() {
    widget.onClosed();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: widget.revision,
    builder: (context, _, child) => widget.builder(context, map),
  );
}

class _CommuteState extends State<Commute> {
  late final railGraph = LocalTransitProvider.loadBundledGraph();
  final map = MapController();
  final routeRevision = ValueNotifier(0);
  MapController? expandedMap;
  JourneyController get j => widget.planner.journey;
  JourneyOption? lastOption;
  bool tileError = false;
  final previewGoogleMap = GlobalKey<GoogleJourneyMapState>();
  final expandedGoogleMap = GlobalKey<GoogleJourneyMapState>();
  LatLng? position;
  LatLng? originOverride, destinationOverride;
  String originName = 'Your location';
  String? destinationName, picking;
  List<LatLng> line = [], access = [], exit = [];
  List<JeepneyPlan> jeepneys = [];
  JeepneyPlan? selected;
  JourneyOption? get drivingAlternative => j.drivingEstimate;
  bool get hasRouteDetails =>
      j.options.isNotEmpty ||
      jeepneys.isNotEmpty ||
      j.walkingEstimate != null ||
      drivingAlternative != null;
  bool showDrivingAlternative = false;
  String? classId;
  String routeMode = 'Transit';
  late final travel = TextEditingController(
    text: '${widget.planner.settings['travel']}',
  );
  late final prep = TextEditingController(
    text: '${widget.planner.settings['prep']}',
  );
  late final buffer = TextEditingController(
    text: '${widget.planner.settings['buffer']}',
  );
  String status =
      'GPS is off. Start tracking to plan from your current position.';
  bool busy = false, tracking = false;
  int serial = 0;
  DateTime? lastRoute;
  final form = GlobalKey<FormState>();
  Map<String, dynamic>? get chosen {
    final list = widget.planner.upcoming;
    return list.isEmpty
        ? null
        : list.firstWhere((c) => c['id'] == classId, orElse: () => list.first);
  }

  LatLng? get origin => originOverride ?? position;
  String get campus => chosen?['campus'] ?? widget.planner.settings['campus'];
  String get destinationLabel => destinationName ?? campus;
  LatLng get destination =>
      destinationOverride ??
      campusPoints[chosen?['campus'] ?? widget.planner.settings['campus']]!;
  bool get targetsClass {
    final c = chosen;
    final point = c == null ? null : campusPoints[c['campus']];
    return point != null &&
        point.latitude == destination.latitude &&
        point.longitude == destination.longitude;
  }

  bool get chosenOnline => chosen != null && isOnlineClass(chosen!);

  void update(VoidCallback change) {
    setState(change);
    routeRevision.value++;
  }

  @override
  void initState() {
    super.initState();
    final savedMode = widget.planner.settings['mode'];
    routeMode = const {'Walking', 'Driving'}.contains(savedMode)
        ? savedMode as String
        : 'Transit';
    j.bindLifecycle();
    position = j.origin;
    if (j.manualOrigin) originOverride = j.origin;
    originName = j.originLabel;
    j.addListener(sharedChanged);
    widget.planner.addListener(preferenceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncQuery();
      sharedChanged();
    });
  }

  void syncQuery({bool refresh = false}) {
    final c = chosen;
    if (c != null && isOnlineClass(c)) {
      j.setActive(false);
      return;
    }
    final target = !targetsClass
        ? null
        : widget.planner
              .nextPlannedOccurrence(c!, manilaNow())
              .subtract(
                Duration(hours: 8, minutes: int.tryParse(buffer.text) ?? 15),
              );
    j.configure(
      destination: destination,
      label: destinationLabel,
      mode: routeMode,
      arriveBy: target != null && target.isAfter(DateTime.now())
          ? target
          : null,
      autoRefresh: refresh,
    );
  }

  void sharedChanged() {
    if (!mounted) return;
    final option = j.selected;
    final changed = !identical(lastOption, option);
    update(() {
      position = j.origin;
      originOverride = j.manualOrigin ? j.origin : null;
      originName = j.originLabel;
      tracking = j.tracking;
      busy = j.loading;
      status = j.message;
      if (changed) {
        line = option?.points ?? [];
        final timed = journeyWithTrafficAllowance(
          option,
          routeMode,
          widget.planner.settings,
        );
        if (timed?.hasDuration == true) travel.text = '${timed!.minutes}';
      }
      if (j.permissionDenied || j.locating) {
        status = j.message;
      }
      lastOption = option;
    });
    if (changed && option != null && origin != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fit([origin!, destination, ...line]);
      });
    }
  }

  void preferenceChanged() {
    if (mounted) update(() {});
  }

  Future<void> openTransitDirectory() async {
    final target = await Navigator.of(context).push<TransitWalkingDestination>(
      MaterialPageRoute(
        builder: (_) => TransitDirectory(repository: widget.planner.transit),
      ),
    );
    if (!mounted || target == null) return;
    destinationOverride = target.point;
    destinationName = target.name;
    routeMode = 'Walking';
    reset();
  }

  @override
  void dispose() {
    serial++;
    j.removeListener(sharedChanged);
    widget.planner.removeListener(preferenceChanged);
    j.unbindLifecycle();
    map.dispose();
    routeRevision.dispose();
    travel.dispose();
    prep.dispose();
    buffer.dispose();
    super.dispose();
  }

  void stop() {
    j.stopTracking();
    serial++;
    if (mounted) {
      update(() {
        tracking = false;
        busy = false;
        status = 'Live GPS tracking stopped.';
      });
    }
  }

  void selectRouteMode(String mode) {
    if (mode == routeMode) return;
    routeMode = mode;
    unawaited(widget.planner.selectTravelMode(mode).catchError((Object _) {}));
    showDrivingAlternative = false;
    reset();
    if (origin != null && !j.matches(destination, mode)) unawaited(find());
  }

  void reset() {
    serial++;
    lastRoute = null;
    update(() {
      busy = false;
      line = [];
      access = [];
      exit = [];
      jeepneys = [];
      selected = null;
      showDrivingAlternative = false;
      status = switch (routeMode) {
        'Walking' =>
          'Walking directions to $destinationLabel selected. Find a route.',
        'Driving' =>
          'Driving directions to $destinationLabel selected. Find a route.',
        _ => 'Origin or destination changed. Find a public transit route.',
      };
    });
    syncQuery(refresh: true);
    if (origin != null && !j.matches(destination, routeMode)) {
      j.scheduleRefresh();
    }
    if (origin != null) {
      fit([origin!, destination]);
    } else {
      if (GoogleMapsSetup.available) {
        fit([destination]);
      } else {
        map.move(destination, 14);
        expandedMap?.move(destination, 14);
      }
    }
  }

  Future<void> start() async {
    await j.startTracking();
    if (j.tracking) {
      unawaited(widget.planner.log('gps_checked').catchError((Object _) {}));
    }
  }

  void fit(List<LatLng> points) {
    if (GoogleMapsSetup.available) {
      previewGoogleMap.currentState?.fitRoute();
      expandedGoogleMap.currentState?.fitRoute();
      return;
    }
    if (points.length > 1) {
      final camera = CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(45),
        maxZoom: 16,
      );
      map.fitCamera(camera);
      expandedMap?.fitCamera(camera);
    }
  }

  Future<void> find() async {
    syncQuery();
    if (origin == null) {
      await start();
      if (!mounted) return;
      if (origin == null) {
        update(
          () => status =
              '${j.message} Choose an origin on the map or enter coordinates to continue.',
        );
        return;
      }
    }
    if (busy) return;
    if (const Distance()(origin!, destination) < 10) {
      update(() => status = 'Choose different origin and destination points.');
      return;
    }
    final request = ++serial;
    update(() {
      busy = true;
      picking = null;
      line = [];
      access = [];
      exit = [];
      jeepneys = [];
      showDrivingAlternative = false;
      selected = null;
      status = 'Updating route…';
    });
    lastRoute = DateTime.now();
    try {
      unawaited(widget.planner.log('maps_opened').catchError((Object _) {}));
      await j.refresh();
    } catch (e) {
      if (mounted && request == serial) {
        update(
          () => status = 'Transit route unavailable: $e. No journey confirmed.',
        );
      }
    } finally {
      if (mounted && request == serial) update(() => busy = false);
    }
  }

  Future<void> select(JeepneyPlan route) async {
    final request = ++serial, from = origin!, dest = destination;
    update(() {
      selected = route;
      line = route.points;
      access = [];
      exit = [];
      busy = true;
    });
    fit([from, dest, ...line]);
    try {
      final legs = await Future.wait([
        Routing.road(from, route.board, 'Walking'),
        Routing.road(route.alight, dest, 'Walking'),
      ]);
      if (!mounted || request != serial) return;
      update(() {
        access = legs[0].points;
        exit = legs[1].points;
        status =
            'Walking connections: ${legs[0].minutes + legs[1].minutes} min. Total journey still uses your manual estimate, including waiting and riding.';
      });
    } catch (_) {
      if (mounted && request == serial) {
        update(
          () => status = 'Walking connections unavailable. Stop markers show mapped boarding and alighting locations.',
        );
      }
    } finally {
      if (mounted && request == serial) update(() => busy = false);
    }
  }

  Future<void> openRouteMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RouteWorkspace(
          revision: routeRevision,
          onReady: (controller) {
            expandedMap = controller;
            if (origin != null) fit([origin!, destination, ...line]);
            unawaited(find());
          },
          onClosed: () => expandedMap = null,
          builder: expandedContent,
        ),
      ),
    );
    if (!mounted) return;
    update(() => picking = null);
  }

  void chooseEndpoint(bool isOrigin, String value) {
    if (value == 'manual') {
      unawaited(enterOrigin());
      return;
    }
    if (value == 'pick') {
      update(() {
        picking = isOrigin ? 'origin' : 'destination';
        status = 'Tap the map to set your $picking.';
      });
      return;
    }
    if (isOrigin) {
      originOverride = value == 'gps' ? null : campusPoints[value]!;
      originName = value == 'gps' ? 'Your location' : value;
      if (value == 'gps') {
        j.useGpsOrigin();
      } else {
        j.setOrigin(originOverride!, originName, refresh: false);
      }
    } else {
      destinationOverride = campusPoints[value]!;
      destinationName = value;
      routeMode = 'Transit';
    }
    picking = null;
    reset();
  }

  void pickPoint(LatLng point) {
    if (picking == null) return;
    final label =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    if (picking == 'origin') {
      originOverride = point;
      originName = label;
      j.setOrigin(point, label, refresh: false);
    } else {
      destinationOverride = point;
      destinationName = label;
    }
    picking = null;
    reset();
  }

  Future<void> enterOrigin() async {
    final result = await showDialog<(LatLng, String)>(
      context: context,
      builder: (_) => _OriginDialog(initial: origin),
    );
    if (!mounted || result == null) return;
    j.setOrigin(result.$1, result.$2, refresh: false);
    reset();
  }

  Widget endpointField(bool isOrigin) {
    final label = isOrigin ? originName : destinationLabel;
    final value = isOrigin && originOverride == null
        ? 'gps'
        : campusPoints.containsKey(label)
        ? label
        : 'custom';
    return DropdownButtonFormField<String>(
      key: ValueKey('${isOrigin ? 'origin' : 'destination'}-$label'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isOrigin ? 'Origin' : 'Destination',
        prefixIcon: Icon(
          isOrigin ? Icons.trip_origin : Icons.location_on,
          color: isOrigin ? Colors.blue : Colors.red,
        ),
      ),
      items: [
        if (isOrigin)
          const DropdownMenuItem(value: 'gps', child: Text('Your location')),
        for (final campus in campusPoints.keys)
          DropdownMenuItem(value: campus, child: Text(campus)),
        if (value == 'custom')
          DropdownMenuItem(
            value: 'custom',
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem(value: 'pick', child: Text('Choose on map')),
        if (isOrigin)
          const DropdownMenuItem(
            value: 'manual',
            child: Text('Enter coordinates'),
          ),
      ],
      onChanged: (value) {
        if (value != null && value != 'custom') chooseEndpoint(isOrigin, value);
      },
    );
  }

  Widget routeModeControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<String>(
        key: const ValueKey('travel-mode-selector'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'Transit', label: Text('Transit')),
          ButtonSegment(value: 'Walking', label: Text('Walk')),
          ButtonSegment(value: 'Driving', label: Text('Drive')),
        ],
        selected: {routeMode},
        onSelectionChanged: (selection) => selectRouteMode(selection.single),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : find,
        icon: Icon(switch (routeMode) {
          'Walking' => Icons.directions_walk,
          'Driving' => Icons.directions_car_outlined,
          _ => Icons.directions_transit,
        }),
        label: Text(switch (routeMode) {
          'Walking' => 'Find walking route',
          'Driving' => 'Find driving route',
          _ => 'Find public transit',
        }),
      ),
    ],
  );

  Widget expandedContent(BuildContext context, MapController controller) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to commute planner',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Find route'),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 1000
              ? desktopWorkspace(controller)
              : Column(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .48,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      endpointField(true),
                                      const SizedBox(height: 10),
                                      endpointField(false),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Swap origin and destination',
                                  onPressed: origin == null
                                      ? null
                                      : () {
                                          final oldOrigin = origin!;
                                          final oldName = originName;
                                          originOverride = destination;
                                          originName = destinationLabel;
                                          destinationOverride = oldOrigin;
                                          destinationName =
                                              oldName == 'Your location'
                                              ? 'Previous location'
                                              : oldName;
                                          j.setOrigin(
                                            originOverride!,
                                            originName,
                                            refresh: false,
                                          );
                                          picking = null;
                                          reset();
                                        },
                                  icon: const Icon(Icons.swap_vert),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            routeModeControls(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: buildMap(controller)),
                          if (picking != null)
                            Positioned(
                              top: 12,
                              left: 12,
                              right: 12,
                              child: Material(
                                elevation: 3,
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: ListTile(
                                  title: Text('Tap to place your $picking'),
                                  trailing: IconButton(
                                    tooltip: 'Cancel map selection',
                                    onPressed: () =>
                                        update(() => picking = null),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 12,
                            top: hasRouteDetails ? 12 : null,
                            bottom: hasRouteDetails ? null : 32,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'route-gps',
                                  tooltip: tracking
                                      ? 'Stop tracking'
                                      : 'Start GPS',
                                  onPressed: tracking ? stop : start,
                                  child: Icon(
                                    tracking
                                        ? Icons.location_disabled
                                        : Icons.my_location,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FloatingActionButton.small(
                                  heroTag: 'route-fit',
                                  tooltip: 'Show entire route',
                                  onPressed: () {
                                    if (origin != null) {
                                      fit([
                                        origin!,
                                        destination,
                                        ...line,
                                        ...access,
                                        ...exit,
                                      ]);
                                    } else {
                                      if (GoogleMapsSetup.available) {
                                        fit([destination]);
                                      } else {
                                        controller.move(destination, 14);
                                      }
                                    }
                                  },
                                  child: const Icon(Icons.center_focus_strong),
                                ),
                              ],
                            ),
                          ),
                          if (picking == null && hasRouteDetails)
                            DraggableScrollableSheet(
                              key: const ValueKey('journey-details-sheet'),
                              initialChildSize: .28,
                              minChildSize: .18,
                              maxChildSize: .85,
                              builder: (context, scroll) => Material(
                                elevation: 8,
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(26),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  controller: scroll,
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: Container(
                                          width: 36,
                                          height: 4,
                                          margin: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .dividerColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SectionHeading(
                                        j.selected?.hasDuration != true
                                            ? 'Travel estimates'
                                            : '${j.selected!.minutes} min to your destination',
                                        subtitle: 'Swipe up for route options and steps',
                                      ),
                                      const SizedBox(height: 16),
                                      ...routeCards(),
                                      ExternalDirections(journey: j),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .24,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(status),
                            if (tileError)
                              const Text(
                                'Map tiles are unavailable. Check your connection.',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget desktopWorkspace(MapController controller) => Row(
    key: const ValueKey('desktop-journey-workspace'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: 390,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                endpointField(true),
                const SizedBox(height: 12),
                endpointField(false),
                const SizedBox(height: 12),
                routeModeControls(),
                const SizedBox(height: 12),
                Text(status),
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                ...routeCards(),
                ExternalDirections(journey: j),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(child: buildMap(controller)),
            if (picking != null)
              Positioned(
                top: 12,
                left: 12,
                right: 70,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Tap to place your $picking'),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'desktop-route-gps',
                tooltip: tracking ? 'Stop tracking' : 'Start GPS',
                onPressed: tracking ? stop : start,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget buildMap(MapController controller, {bool preview = false}) {
    final option = j.selected;
    final routes = <MapRouteLine>[
      if (!showDrivingAlternative)
        for (final other in j.options.where(
          (o) => !identical(o, option) && o.source != JourneySource.google,
        ))
          for (final step in other.steps)
            if (step.points.length > 1)
              MapRouteLine(
                step.points,
                const Color(0xffaa8d42).withValues(alpha: .25),
                walking: step.walking,
              ),
      if (option != null && option.steps.any((s) => s.points.isNotEmpty)) ...[
        for (var i = 0; i < option.steps.length; i++)
          if (option.steps[i].points.isNotEmpty)
            MapRouteLine(
              option.steps[i].points,
              option.steps[i].walking
                  ? Colors.grey
                  : i.isEven
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xff365cb5),
              walking: option.steps[i].walking,
            ),
      ] else if (line.isNotEmpty)
        MapRouteLine(line, Theme.of(context).colorScheme.primary),
      for (final leg in [access, exit])
        if (leg.isNotEmpty) MapRouteLine(leg, Colors.orange, walking: true),
      if (showDrivingAlternative && drivingAlternative != null)
        MapRouteLine(drivingAlternative!.points, Colors.blueGrey),
    ];
    if (GoogleMapsSetup.available) {
      return GoogleJourneyMap(
        key: preview ? previewGoogleMap : expandedGoogleMap,
        origin: origin,
        destination: destination,
        originLabel: originName,
        destinationLabel: destinationLabel,
        lines: routes,
        bottomOverlayFraction: !preview && picking == null && hasRouteDetails
            ? .28
            : 0,
        onTap: preview ? null : pickPoint,
      );
    }
    final googleContent = option?.source == JourneySource.google;
    return FlutterMap(
      key: ValueKey(preview ? 'commute-map' : 'expanded-route-map'),
      mapController: controller,
      options: MapOptions(
        initialCenter: destination,
        initialZoom: 14,
        onTap: preview ? null : (_, point) => pickPoint(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.tamarawtime.app',
          errorTileCallback: (_, error, trace) {
            if (!mounted || tileError) return;
            tileError = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) update(() {});
            });
          },
        ),
        LocalRailLayer(graph: railGraph),
        PolylineLayer(
          polylines: [
            if (!googleContent)
              for (final route in routes)
                Polyline(
                  points: route.points,
                  color: route.color,
                  strokeWidth: route.walking ? 4 : 6,
                  pattern: route.walking
                      ? const StrokePattern.dotted()
                      : const StrokePattern.solid(),
                ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: destination,
              child: Tooltip(
                message: 'Destination: $destinationLabel',
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 36,
                ),
              ),
            ),
            if (origin != null)
              Marker(
                point: origin!,
                child: Tooltip(
                  message: 'Origin: $originName',
                  child: const Icon(
                    Icons.trip_origin,
                    color: Colors.green,
                    size: 30,
                  ),
                ),
              ),
            if (selected != null) ...[
              Marker(
                point: selected!.board,
                child: const Icon(
                  Icons.directions_bus,
                  color: Colors.green,
                  size: 32,
                ),
              ),
              Marker(
                point: selected!.alight,
                child: const Icon(Icons.flag, color: Colors.orange, size: 32),
              ),
            ],
            if (option != null)
              for (final step in option.steps.where(
                (step) => step.transit,
              )) ...[
                if (step.boardingPoint != null)
                  Marker(
                    point: step.boardingPoint!,
                    child: Tooltip(
                      message:
                          'Board at ${step.boardingStop ?? 'provider stop'}',
                      child: const Icon(
                        Icons.directions_transit,
                        color: Colors.green,
                      ),
                    ),
                  ),
                if (step.alightingPoint != null)
                  Marker(
                    point: step.alightingPoint!,
                    child: Tooltip(
                      message:
                          'Alight at ${step.alightingStop ?? 'provider stop'}',
                      child: const Icon(Icons.flag, color: Colors.orange),
                    ),
                  ),
              ],
          ],
        ),
        Align(
          alignment: !preview && picking == null
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: Theme.of(context).colorScheme.surface,
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Text(
                '© OpenStreetMap contributors · ODbL',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        if (googleContent)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).colorScheme.surface,
              child: const Text(
                'Google Routes itinerary ready. Configure Google Maps to display its route.',
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> routeCards() => [
    if (routeMode == 'Transit' && j.options.isNotEmpty) ...[
      JourneyOptions(
        journey: j,
        repository: widget.planner.transit,
        studentDiscount: widget.planner.studentDiscount,
      ),
      if (j.selected != null) JourneyTimeline(option: j.selected!),
    ] else if (j.cachedTransitOption case final transit?) ...[
      JourneyOptions(
        journey: j,
        repository: widget.planner.transit,
        studentDiscount: widget.planner.studentDiscount,
        displayedOptions: [transit],
        isSelected: false,
        onSelected: () {
          if (routeMode == 'Transit') {
            unawaited(find());
          } else {
            selectRouteMode('Transit');
          }
        },
      ),
    ],
    RoadEstimates(
      journey: j,
      settings: widget.planner.settings,
      selectedMode: routeMode,
      onModeSelected: selectRouteMode,
    ),
    departureCard(),
  ];

  Widget departureCard() {
    final c = chosen;
    // A manually changed destination must not inherit a class arrival target.
    final advice = !targetsClass
        ? const DepartureAdvice(status: PunctualityStatus.unavailable)
        : DepartureAdvice.calculate(
            classStart: widget.planner
                .nextPlannedOccurrence(c!, manilaNow())
                .subtract(const Duration(hours: 8)),
            now: DateTime.now().toUtc(),
            preparation: Duration(minutes: int.tryParse(prep.text) ?? 45),
            buffer: Duration(minutes: int.tryParse(buffer.text) ?? 15),
            journey: journeyWithTrafficAllowance(
              j.matches(destination, routeMode) ? j.selected : null,
              routeMode,
              widget.planner.settings,
            ),
          );
    return MobilityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Departure recommendation'),
          if (advice.leaveAt == null)
            Text(
              targetsClass ? 'ETA unavailable' : 'Select a class and its campus destination for departure guidance.',
            )
          else ...[
            Text('Leave by ${journeyClock(advice.leaveAt!)}'),
            Text('Prepare by ${journeyClock(advice.prepareAt!)}'),
            Text('Estimated arrival ${journeyClock(advice.arriveAt!)}'),
            if (advice.timetableLimited)
              const Text(
                'An earlier departure is required to catch the scheduled service.',
              ),
            Text(
              '${j.selected!.sourceLabel} · Updated ${journeyClock(j.selected!.updatedAt)}',
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = chosen;
    if (chosenOnline) {
      return MobilityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.video_camera_front_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              'Online class',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Travel ETA, GPS, and travel preparation are disabled for online classes. Your regular schedule and reminders remain available.',
            ),
          ],
        ),
      );
    }
    final selectedJourney = journeyWithTrafficAllowance(
      j.matches(destination, routeMode) ? j.selected : null,
      routeMode,
      widget.planner.settings,
    );
    final valid = selectedJourney?.hasDuration == true;
    final journey = valid
        ? selectedJourney!.minutes
        : int.tryParse(travel.text) ?? 55;
    final preparation = int.tryParse(prep.text) ?? 45;
    final margin = int.tryParse(buffer.text) ?? 15;
    final when = targetsClass
        ? widget.planner.nextPlannedOccurrence(c!, manilaNow())
        : null;
    final advice = when == null
        ? const DepartureAdvice(status: PunctualityStatus.unavailable)
        : DepartureAdvice.calculate(
            classStart: when.subtract(const Duration(hours: 8)),
            now: DateTime.now().toUtc(),
            preparation: Duration(minutes: preparation),
            buffer: Duration(minutes: margin),
            journey: valid ? selectedJourney : null,
          );
    final providerTiming = advice.leaveAt != null;
    final leave = providerTiming
        ? advice.leaveAt!.add(const Duration(hours: 8))
        : !valid && widget.planner.settings['useManualEstimate'] == true
        ? when?.subtract(Duration(minutes: journey + margin))
        : null;
    Widget number(
      TextEditingController controller,
      String label,
      int min, {
      bool readOnly = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final value = int.tryParse(v ?? '');
          final max = controller == travel ? 2880 : 480;
          return value == null || value < min || value > max
              ? 'Enter $min–$max minutes'
              : null;
        },
        onChanged: (_) {
          update(() {});
          if (controller == buffer) syncQuery(refresh: true);
        },
      ),
    );
    return Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Commute Planner',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Your campus, without the guesswork.',
            style: TextStyle(color: TamarawPalette.of(context).muted),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: openTransitDirectory,
            icon: const Icon(Icons.train_outlined),
            label: const Text('Stations & routes'),
          ),
          const SizedBox(height: 16),
          MobilityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c != null) ...[
                  DropdownButtonFormField<String>(
                    initialValue: c['id'],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Choose a class',
                    ),
                    items: widget.planner.upcoming
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry['id'],
                            child: Text(
                              entry['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      classId = value;
                      final selectedClass = widget.planner.classes.firstWhere(
                        (item) => item['id'] == value,
                        orElse: () => <String, dynamic>{},
                      );
                      if (selectedClass.isNotEmpty) {
                        travel.text =
                            '${widget.planner.classTravelMinutes(selectedClass)}';
                      }
                      destinationOverride = null;
                      destinationName = null;
                      reset();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 4),
                Text(
                  'Your Commute to FEU',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.trip_origin,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        origin == null
                            ? 'Choose your starting point'
                            : originName,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 7),
                  child: Text('⋮'),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destinationLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (routeMode == 'Walking')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Walking directions to $destinationLabel'),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: openRouteMap,
                      icon: const Icon(Icons.route),
                      label: const Text('Find public transit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: tracking || j.locating ? null : start,
                      icon: const Icon(Icons.my_location),
                      label: Text(j.locating ? 'Locating…' : 'Start GPS'),
                    ),
                    if (tracking || j.locating)
                      OutlinedButton(
                        onPressed: stop,
                        child: const Text('Stop tracking'),
                      ),
                    if (j.permissionDenied)
                      TextButton(
                        onPressed: Geolocator.openAppSettings,
                        child: const Text('Location settings'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (busy || j.locating)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          Semantics(
            liveRegion: true,
            child: Text(status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (j.tracking && j.lastLocationUpdate != null)
            Text(
              'Location updated ${journeyClock(j.lastLocationUpdate!)} · Tracking is active while this page is open.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (tileError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Map tiles are unavailable. Check your connection.'),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  Positioned.fill(child: buildMap(map, preview: true)),
                  Positioned(
                    right: 12,
                    bottom: 28,
                    child: FloatingActionButton.small(
                      heroTag: 'preview-expand',
                      tooltip: 'Expand map',
                      onPressed: openRouteMap,
                      child: const Icon(Icons.fullscreen),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...routeCards(),
          ExternalDirections(journey: j),
          const SizedBox(height: 20),
          Card(
            child: ExpansionTile(
              title: const Text('Timing preferences'),
              subtitle: Text(
                valid
                    ? 'Journey duration supplied automatically'
                    : 'Optional manual fallback and arrival buffer',
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                number(
                  travel,
                  valid ? 'Provider journey minutes' : 'Manual journey minutes',
                  1,
                  readOnly: valid,
                ),
                if (!valid)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Manual minutes are a personal planning fallback, not a live travel estimate.',
                    ),
                  ),
                number(prep, 'Preparation minutes', 0),
                number(buffer, 'Arrival buffer minutes', 0),
                if (leave != null &&
                    (providerTiming ||
                        widget.planner.settings['useManualEstimate'] ==
                            true)) ...[
                  RoutineResults(
                    ready: clock(
                      leave.subtract(Duration(minutes: preparation)),
                    ),
                    leave: clock(leave),
                    arrive: providerTiming
                        ? journeyClock(advice.arriveAt!)
                        : clock(when!.subtract(Duration(minutes: margin))),
                  ),
                  if (!valid) const Text('Manual plan · ETA unavailable'),
                ],
                FilledButton(
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    widget.planner.settings.addAll({
                      'travel': journey,
                      'prep': preparation,
                      'buffer': margin,
                      'mode': routeMode,
                      'travelMode': routeMode,
                      'useManualEstimate': !valid,
                    });
                    final selectedClass = chosen;
                    if (selectedClass != null) {
                      final classes = widget.planner.classes;
                      final index = classes.indexWhere(
                        (item) => item['id'] == selectedClass['id'],
                      );
                      if (index >= 0) {
                        classes[index]['travel'] = journey;
                        widget.planner.payload['classes'] = classes;
                      }
                    }
                    await widget.onSave();
                  },
                  child: const Text('Save as default commute'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          HistoricalTransitExplorer(repository: widget.planner.transit),
          const SizedBox(height: 8),
          const Text(
            'GPS runs only in the foreground after permission. Coordinates are used for routes and kept in memory, never stored as location history or sent to the research database. Route estimates depend on provider coverage.',
          ),
        ],
      ),
    );
  }
}
