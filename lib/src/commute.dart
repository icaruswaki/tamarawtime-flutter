import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'planner.dart';
import 'routing.dart';
import 'theme.dart';

class Commute extends StatefulWidget {
  const Commute({super.key, required this.planner, required this.onSave});
  final Planner planner;
  final Future<void> Function() onSave;
  @override
  State<Commute> createState() => _CommuteState();
}

class _CommuteState extends State<Commute> with WidgetsBindingObserver {
  final map = MapController();
  StreamSubscription<Position>? gps;
  LatLng? position;
  List<LatLng> line = [], access = [], exit = [];
  List<JeepneyPlan> jeepneys = [];
  JeepneyPlan? selected;
  String? classId;
  late String mode = widget.planner.settings['mode'];
  late final travel = TextEditingController(
    text:
        '${widget.planner.upcoming.isEmpty ? widget.planner.settings['travel'] : widget.planner.classTravelMinutes(widget.planner.upcoming.first)}',
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

  LatLng get destination =>
      campusPoints[chosen?['campus'] ?? widget.planner.settings['campus']]!;
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
      setState(() {
        tracking = false;
        busy = false;
        status = 'Live GPS tracking stopped.';
      });
    }
  }

  void reset() {
    serial++;
    lastRoute = null;
    setState(() {
      busy = false;
      line = [];
      access = [];
      exit = [];
      jeepneys = [];
      selected = null;
      status = 'Destination or mode changed. Find a new route.';
    });
    map.move(destination, 14);
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
      setState(() {
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
              setState(() {
                position = LatLng(p.latitude, p.longitude);
                status = 'GPS active · accuracy ${p.accuracy.round()} m';
              });
              // GPS updates position only. Routes are calculated by Find route.
            },
            onError: (Object e) {
              stop();
              if (mounted) setState(() => status = 'GPS unavailable: $e');
            },
          );
      await widget.planner.log('gps_checked');
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    }
  }

  void fit(List<LatLng> points) {
    if (points.length > 1) {
      map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(35),
        ),
      );
    }
  }

  Future<void> find() async {
    if (position == null) {
      setState(() => status = 'Start GPS and wait for your position first.');
      return;
    }
    if (busy) return;
    final request = ++serial,
        origin = position!,
        dest = destination,
        requestedMode = mode;
    setState(() {
      busy = true;
      status = 'Updating route…';
      selected = requestedMode == 'Jeepney' ? null : selected;
      if (requestedMode == 'Jeepney') {
        jeepneys = [];
        access = [];
        exit = [];
      }
    });
    lastRoute = DateTime.now();
    try {
      await widget.planner.log('maps_opened');
      if (requestedMode == 'Jeepney') {
        final results = await Routing.jeepneys(origin, dest);
        if (!mounted || request != serial) return;
        setState(() {
          jeepneys = results;
          status = results.isEmpty
              ? 'No jeepney route could be confirmed. Map services may be offline or nearby mapped routes may be unavailable.'
              : 'Mapped candidates found. Confirm signage and current operation before boarding.';
        });
      } else if (['Walking', 'Driving'].contains(requestedMode)) {
        final route = await Routing.road(origin, dest, requestedMode);
        if (!mounted || request != serial) return;
        setState(() {
          line = route.points;
          final total = journeyEstimateMinutes(route.minutes, requestedMode);
          travel.text = '$total';
          status =
              '${(route.meters / 1000).toStringAsFixed(1)} km · about $total min, including ${requestedMode.toLowerCase()} mode and local travel buffers. Route estimate, no live traffic.';
        });
        fit([origin, dest, ...line]);
      } else {
        final route = await Routing.transit(origin, dest, requestedMode);
        if (!mounted || request != serial) return;
        setState(() {
          line = route.points;
          final total = journeyEstimateMinutes(route.minutes, requestedMode);
          travel.text = '$total';
          status = requestedMode == 'Train'
              ? '$requestedMode route ready · about $total min. Displayed geometry follows mapped rail lines where available; verify station access locally.'
              : '$requestedMode estimate ready · about $total min for walking, waiting, transfers and riding. Transit timetable coverage may be unavailable, so this uses the best available route estimate.';
        });
        fit([origin, dest, ...line]);
      }
    } catch (e) {
      if (mounted && request == serial) {
        setState(
          () => status =
              'Route unavailable: $e. Using the editable journey estimate.',
        );
      }
    } finally {
      if (mounted && request == serial) setState(() => busy = false);
    }
  }

  Future<void> select(JeepneyPlan route) async {
    final request = ++serial, origin = position!, dest = destination;
    setState(() {
      selected = route;
      line = route.points;
      access = [];
      exit = [];
      busy = true;
    });
    fit([origin, dest, ...line]);
    try {
      final legs = await Future.wait([
        Routing.road(origin, route.board, 'Walking'),
        Routing.road(route.alight, dest, 'Walking'),
      ]);
      if (!mounted || request != serial) return;
      setState(() {
        access = legs[0].points;
        exit = legs[1].points;
        status =
            'Walking connections: ${legs[0].minutes + legs[1].minutes} min. Total journey still uses your manual estimate, including waiting and riding.';
      });
    } catch (_) {
      if (mounted && request == serial) {
        setState(
          () => status = 'Walking connections unavailable. Stop markers show mapped boarding and alighting locations.',
        );
      }
    } finally {
      if (mounted && request == serial) setState(() => busy = false);
    }
  }

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
                final selectedClass = widget.planner.classes.firstWhere(
                  (item) => item['id'] == v,
                  orElse: () => {},
                );
                if (selectedClass.isNotEmpty) {
                  travel.text =
                      '${widget.planner.classTravelMinutes(selectedClass)}';
                }
                reset();
              },
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Travel mode'),
            items: modes
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
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
                if (chosen != null) {
                  final classes = widget.planner.classes;
                  final index = classes.indexWhere(
                    (item) => item['id'] == chosen!['id'],
                  );
                  if (index >= 0) {
                    classes[index]['travel'] = journey;
                    widget.planner.payload['classes'] = classes;
                  }
                }
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
                onPressed: busy ? null : find,
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
              child: FlutterMap(
                mapController: map,
                options: MapOptions(
                  initialCenter: destination,
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                          Polyline(
                            points: leg,
                            color: Colors.orange,
                            strokeWidth: 4,
                          ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: destination,
                        child: const Tooltip(
                          message: 'FEU campus',
                          child: Icon(
                            Icons.school,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ),
                      if (position != null)
                        Marker(
                          point: position!,
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 30,
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
                          child: const Icon(
                            Icons.flag,
                            color: Colors.orange,
                            size: 32,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SimpleAttributionWidget(
                    source: Text('© OpenStreetMap contributors'),
                  ),
                ],
              ),
            ),
          ),
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
                  '1. Walk to ${selected!.boardName}\n2. Board ${selected!.name}; verify signage\n3. Get off at ${selected!.alightName}\n4. Walk to ${c?['campus'] ?? widget.planner.settings['campus']}\n\nMapped service only. No live jeepney ETA or availability.',
                ),
              ),
            ),
          const Text(
            'Walking, driving and public-transit directions use routing services. Jeepney routes use mapped OpenStreetMap services and must be checked locally. Route times are estimates and may change.',
          ),
        ],
      ),
    );
  }
}
