import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'planner.dart';
import 'routing.dart';
import 'theme.dart';
import 'responsive.dart';

class Commute extends StatefulWidget {
  const Commute({super.key, required this.planner, required this.onSave});
  final Planner planner;
  final Future<void> Function() onSave;
  @override
  State<Commute> createState() => _CommuteState();
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

class _CommuteState extends State<Commute> with WidgetsBindingObserver {
  final map = MapController();
  final routeRevision = ValueNotifier(0);
  MapController? expandedMap;
  StreamSubscription<Position>? gps;
  LatLng? position;
  LatLng? originOverride, destinationOverride;
  String originName = 'Your location';
  String? destinationName, picking;
  List<LatLng> line = [], access = [], exit = [];
  List<JeepneyPlan> jeepneys = [];
  JeepneyPlan? selected;
  String? classId;
  late String mode = widget.planner.settings['mode'];
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

  void update(VoidCallback change) {
    setState(change);
    routeRevision.value++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    serial++;
    WidgetsBinding.instance.removeObserver(this);
    gps?.cancel();
    map.dispose();
    routeRevision.dispose();
    travel.dispose();
    prep.dispose();
    buffer.dispose();
    super.dispose();
  }

  void stop() {
    gps?.cancel();
    gps = null;
    serial++;
    if (mounted) {
      update(() {
        tracking = false;
        busy = false;
        status = 'Live GPS tracking stopped.';
      });
    }
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
      status = 'Origin, destination or mode changed. Find a new route.';
    });
    if (origin != null) {
      fit([origin!, destination]);
    } else {
      map.move(destination, 14);
      expandedMap?.move(destination, 14);
    }
  }

  Future<void> start() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Enable location services on your device.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is required. Enable it in app settings if blocked.',
        );
      }
      await gps?.cancel();
      if (!mounted) return;
      update(() {
        tracking = true;
        status = 'Waiting for GPS…';
      });
      gps =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 30,
            ),
          ).listen(
            (p) {
              if (!mounted) return;
              update(() {
                position = LatLng(p.latitude, p.longitude);
                status = 'GPS active · accuracy ${p.accuracy.round()} m';
              });
              // GPS updates position only. Routes are calculated by Find route.
            },
            onError: (Object e) {
              stop();
              if (mounted) update(() => status = 'GPS unavailable: $e');
            },
          );
      await widget.planner.log('gps_checked');
    } catch (e) {
      if (mounted) update(() => status = '$e');
    }
  }

  void fit(List<LatLng> points) {
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
    if (origin == null) {
      update(
        () => status =
            'Choose an origin on the map or start GPS for your location.',
      );
      return;
    }
    if (busy) return;
    if (const Distance()(origin!, destination) < 10) {
      update(() => status = 'Choose different origin and destination points.');
      return;
    }
    final request = ++serial,
        from = origin!,
        dest = destination,
        requestedMode = mode;
    update(() {
      busy = true;
      picking = null;
      line = [];
      access = [];
      exit = [];
      jeepneys = [];
      selected = null;
      status = 'Updating route…';
    });
    lastRoute = DateTime.now();
    try {
      await widget.planner.log('maps_opened');
      if (requestedMode == 'Jeepney') {
        final results = await Routing.jeepneys(from, dest);
        if (!mounted || request != serial) return;
        update(() {
          jeepneys = results;
          status = results.isEmpty
              ? 'No jeepney route could be confirmed. Map services may be offline or nearby mapped routes may be unavailable.'
              : 'Mapped candidates found. Confirm signage and current operation before boarding.';
        });
        fit([from, dest]);
      } else if (['Walking', 'Driving'].contains(requestedMode)) {
        final route = await Routing.road(from, dest, requestedMode);
        if (!mounted || request != serial) return;
        update(() {
          line = route.points;
          final total = journeyEstimateMinutes(route.minutes, requestedMode);
          travel.text = '$total';
          status =
              '${(route.meters / 1000).toStringAsFixed(1)} km · about $total min, including ${requestedMode.toLowerCase()} mode and local travel buffers. Route estimate, no live traffic.';
        });
        fit([from, dest, ...line]);
      } else {
        final route = await Routing.transit(from, dest, requestedMode);
        if (!mounted || request != serial) return;
        update(() {
          line = route.points;
          final total = journeyEstimateMinutes(route.minutes, requestedMode);
          travel.text = '$total';
          status = requestedMode == 'Train'
              ? '$requestedMode route ready · about $total min. Displayed geometry follows mapped rail lines where available; verify station access locally.'
              : '$requestedMode estimate ready · about $total min for walking, waiting, transfers and riding. Transit timetable coverage may be unavailable, so this uses the best available route estimate.';
        });
        fit([from, dest, ...line]);
      }
    } catch (e) {
      if (mounted && request == serial) {
        update(
          () => status =
              'Route unavailable: $e. Using the editable journey estimate.',
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
    } else {
      destinationOverride = campusPoints[value]!;
      destinationName = value;
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
    } else {
      destinationOverride = point;
      destinationName = label;
    }
    picking = null;
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
      ],
      onChanged: (value) {
        if (value != null && value != 'custom') chooseEndpoint(isOrigin, value);
      },
    );
  }

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
          builder: (context, constraints) => Column(
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
                                    destinationName = oldName == 'Your location'
                                        ? 'Previous location'
                                        : oldName;
                                    picking = null;
                                    reset();
                                  },
                            icon: const Icon(Icons.swap_vert),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ResponsiveFormActions(
                        field: DropdownButtonFormField<String>(
                          key: ValueKey('expanded-mode-$mode'),
                          initialValue: mode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Travel mode',
                          ),
                          items: modes
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    m,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            mode = value;
                            reset();
                          },
                        ),
                        action: FilledButton(
                          onPressed: busy ? null : find,
                          child: const Text('Find route'),
                        ),
                      ),
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
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: ListTile(
                            title: Text('Tap to place your $picking'),
                            trailing: IconButton(
                              tooltip: 'Cancel map selection',
                              onPressed: () => update(() => picking = null),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      bottom: 32,
                      child: Column(
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'route-gps',
                            tooltip: tracking ? 'Stop tracking' : 'Start GPS',
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
                                controller.move(destination, 14);
                              }
                            },
                            child: const Icon(Icons.center_focus_strong),
                          ),
                        ],
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
                    children: [Text(status), ...routeCards()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildMap(MapController controller, {bool preview = false}) {
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
        ),
        PolylineLayer(
          polylines: [
            if (line.isNotEmpty)
              Polyline(
                points: line,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 5,
              ),
            for (final leg in [access, exit])
              if (leg.isNotEmpty)
                Polyline(points: leg, color: Colors.orange, strokeWidth: 4),
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
                    color: Colors.blue,
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
          ],
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: Theme.of(context).colorScheme.surface,
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> routeCards() => [
    for (final route in jeepneys)
      Card(
        child: ListTile(
          title: Text(route.name),
          subtitle: Text(
            'Board: ${route.boardName}\nAlight: ${route.alightName}',
          ),
          onTap: busy ? null : () => select(route),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    if (selected != null)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '1. Walk to ${selected!.boardName}\n2. Board ${selected!.name}; verify signage\n3. Get off at ${selected!.alightName}\n4. Walk to $destinationLabel\n\nMapped service only. No live jeepney ETA or availability.',
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = chosen;
    final journey = int.tryParse(travel.text) ?? 55;
    final preparation = int.tryParse(prep.text) ?? 45;
    final margin = int.tryParse(buffer.text) ?? 15;
    final when = c == null ? null : nextOccurrence(c, manilaNow());
    final leave = when?.subtract(Duration(minutes: journey + margin));
    Widget number(TextEditingController controller, String label, int min) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < min || n > 480
                  ? 'Enter $min–480 minutes'
                  : null;
            },
            onChanged: (_) => setState(() {}),
          ),
        );
    return Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Commute Planner',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          if (c != null)
            DropdownButtonFormField<String>(
              initialValue: c['id'],
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Choose a class'),
              items: widget.planner.upcoming
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c['id'],
                      child: Text(
                        '${c['name']} · ${days[c['day']]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                classId = v;
                destinationOverride = null;
                destinationName = null;
                reset();
              },
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('commute-mode-$mode'),
            initialValue: mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Travel mode'),
            items: modes
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              mode = v!;
              reset();
            },
          ),
          const SizedBox(height: 16),
          number(travel, 'Total journey minutes', 1),
          number(prep, 'Preparation minutes', 0),
          number(buffer, 'Arrival buffer minutes', 0),
          if (leave != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your recommended routine',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                RoutineResults(
                  ready: clock(leave.subtract(Duration(minutes: preparation))),
                  leave: clock(leave),
                  arrive: clock(when!.subtract(Duration(minutes: margin))),
                ),
                const SizedBox(height: 16),
              ],
            ),
          FilledButton(
            onPressed: () async {
              if (form.currentState!.validate()) {
                widget.planner.settings.addAll({
                  'travel': journey,
                  'prep': preparation,
                  'buffer': margin,
                  'mode': mode,
                  'travelMode': mode,
                });
                await widget.onSave();
              }
            },
            child: const Text('Save as default commute'),
          ),
          const SizedBox(height: 24),
          Text(
            'Live GPS & commute routes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Starting GPS shares coordinates with routing providers for walking/driving estimates. Find route shares coordinates with map services for jeepney discovery. GPS is kept in memory only.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: tracking ? null : start,
                icon: const Icon(Icons.my_location),
                label: const Text('Start GPS'),
              ),
              OutlinedButton(
                onPressed: tracking ? stop : null,
                child: const Text('Stop tracking'),
              ),
              OutlinedButton(
                onPressed: openRouteMap,
                child: const Text('Find route'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          Text(status),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: buildMap(map, preview: true),
            ),
          ),
          ...routeCards(),
          const Text(
            'Walking, driving and public-transit directions use routing services. Jeepney routes use mapped OpenStreetMap services and must be checked locally. Route times are estimates and may change.',
          ),
        ],
      ),
    );
  }
}
