import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'operating_route_source.dart';
import 'rail_reference_repository.dart';
import 'sakay_reference.dart';
import 'transit_reference_map.dart';
import 'transit_repository.dart';

enum TransitDirectorySection { stations, terminals, transfers, routes, stops }

class TransitDirectory extends StatefulWidget {
  const TransitDirectory({super.key, required this.repository});
  final TransitRepository repository;
  @override
  State<TransitDirectory> createState() => _TransitDirectoryState();
}

class _DirectoryData {
  const _DirectoryData(this.rail, this.sakay, this.points);
  final RailNetwork rail;
  final SakayHistoricalCatalog sakay;
  final Map<String, ReviewedTransitPoint> points;
}

class _TransitDirectoryState extends State<TransitDirectory> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  late final Future<_DirectoryData> data = _load();
  Future<_DirectoryData> _load() async {
    final values = await Future.wait<Object>([
      widget.repository.rail.loadNetwork(),
      widget.repository.loadSakay(),
      widget.repository.loadReviewedPoints(),
    ]);
    return _DirectoryData(
      values[0] as RailNetwork,
      values[1] as SakayHistoricalCatalog,
      values[2] as Map<String, ReviewedTransitPoint>,
    );
  }

  TransitDirectorySection section = TransitDirectorySection.stations;
  String query = '', lineId = 'all', transport = 'all';
  int limit = 25;
  bool matches(String text) =>
      text.toLowerCase().contains(query.toLowerCase().trim());
  void change(VoidCallback callback) => setState(() {
    callback();
    limit = 25;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stations & routes')),
    body: FutureBuilder<_DirectoryData>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Transit reference could not be loaded. Please check the bundled data.',
            ),
          );
        }
        final catalog = snapshot.data;
        if (catalog == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          key: const ValueKey('transit-directory-list'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Explore your connections',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Rail station network reference. Service status and arrival times are not supplied.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: search,
              key: const ValueKey('transit-directory-search'),
              decoration: const InputDecoration(
                labelText: 'Search stations, terminals, routes or stops',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => change(() => query = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  TransitDirectorySection.stations: 'Rail stations',
                  TransitDirectorySection.terminals: 'Rail terminals',
                  TransitDirectorySection.transfers: 'Rail transfers',
                  TransitDirectorySection.routes: 'Historical routes',
                  TransitDirectorySection.stops: 'Historical stops',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: section == entry.key,
                    onSelected: (_) => change(() => section = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (section == TransitDirectorySection.routes ||
                section == TransitDirectorySection.stops) ...[
              const Text(
                'Historical route reference — verify before traveling.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'HISTORICAL / UNVERIFIED. Potential boarding/alighting locations only. Current service, physical terminals and ETAs are not verified.',
              ),
              const SizedBox(height: 12),
              Text(
                '${catalog.sakay.routes.length} historical routes · ${catalog.sakay.stops.length} sample stops',
              ),
              DropdownButtonFormField<String>(
                initialValue: transport,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Transport classification',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('All historical classifications'),
                  ),
                  DropdownMenuItem(
                    value: 'jeepney_reference',
                    child: Text('Jeepney reference'),
                  ),
                  DropdownMenuItem(
                    value: 'road_transit_unclassified',
                    child: Text('Unclassified road transit'),
                  ),
                  DropdownMenuItem(
                    value: 'rail_reference',
                    child: Text('Historical rail'),
                  ),
                ],
                onChanged: (value) => change(() => transport = value!),
              ),
              const SizedBox(height: 12),
              ...historicalResults(catalog),
              TextButton.icon(
                onPressed: () => showLicense(context),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Source, attribution & license'),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All lines'),
                    selected: lineId == 'all',
                    onSelected: (_) => change(() => lineId = 'all'),
                  ),
                  for (final line in catalog.rail.lines)
                    ChoiceChip(
                      label: Text(line.name),
                      selected: lineId == line.id,
                      onSelected: (_) => change(() => lineId = line.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...railResults(catalog),
            ],
          ],
        );
      },
    ),
  );

  List<Widget> railResults(_DirectoryData data) {
    final widgets = <Widget>[];
    if (section == TransitDirectorySection.transfers) {
      for (final transfer in data.rail.transfers) {
        final from = data.rail.station(transfer.from),
            to = data.rail.station(transfer.to);
        final fromLine = data.rail.lineFor(from.id),
            toLine = data.rail.lineFor(to.id);
        if ((lineId == 'all' || [fromLine.id, toLine.id].contains(lineId)) &&
            matches(
              '${fromLine.name} ${from.name} ${toLine.name} ${to.name}',
            )) {
          widgets.add(
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${fromLine.name} ${from.name} ↔ ${toLine.name} ${to.name}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('Walking interchange · separate stations'),
                    Text(transfer.note),
                    const Text(
                      'Walking time, path and accessibility are not verified.',
                    ),
                    TextButton(
                      onPressed: () => stationDetails(data, from),
                      child: const Text('View connection'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    } else {
      for (final line in data.rail.lines.where(
        (line) => lineId == 'all' || line.id == lineId,
      )) {
        final stations = line.stations
            .where(
              (station) =>
                  (section != TransitDirectorySection.terminals ||
                      station.terminal) &&
                  matches('${line.name} ${station.name}'),
            )
            .toList();
        if (stations.isEmpty) continue;
        widgets.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    line.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${line.stations.length} stations · reference order'),
                  Text('Beginning: ${line.beginning.name}'),
                  Text('Ending: ${line.ending.name}'),
                  const Divider(),
                  for (final station in stations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${station.order}')),
                      title: Text(station.name),
                      subtitle: Text(
                        station.id == line.beginning.id
                            ? 'Beginning terminal'
                            : station.id == line.ending.id
                            ? 'Ending terminal'
                            : data.rail.transfersAt(station.id).isNotEmpty
                            ? 'Station · walking interchange'
                            : 'Station',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => stationDetails(data, station),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return widgets.isEmpty
        ? [const Text('No matching rail references.')]
        : widgets;
  }

  List<Widget> historicalResults(_DirectoryData data) {
    final routes = data.sakay.routes
        .where((route) => transport == 'all' || route.mode == transport)
        .toList();
    if (section == TransitDirectorySection.stops) {
      final stops = <String, HistoricalSakayStop>{
        for (final route in routes)
          for (final stop in route.stops)
            if (matches(stop.name)) stop.id: stop,
      }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      return [
        Text('${stops.length} matching historical stops'),
        for (final stop in stops.take(limit))
          Card(
            child: ListTile(
              title: Text(stop.name),
              subtitle: const Text(
                'Historical potential boarding/alighting location',
              ),
              onTap: () => stopDetails(data, stop),
            ),
          ),
        ...pagination(stops.length),
      ];
    }
    final found = routes.where((route) => route.matches(query)).toList();
    return [
      Text('${found.length} matching historical routes'),
      for (final route in found.take(limit))
        Card(
          child: ListTile(
            title: Text(route.name),
            subtitle: Text(
              '${route.classification}\n${endpointSummary(route)}',
            ),
            isThreeLine: true,
            onTap: () => routeDetails(data, route),
          ),
        ),
      ...pagination(found.length),
    ];
  }

  List<Widget> pagination(int count) => [
    if (count == 0) const Text('No matching historical references.'),
    if (count > limit)
      TextButton(
        onPressed: () => setState(() => limit += 25),
        child: Text('Show more (${count - limit} remaining)'),
      ),
  ];
  String endpointSummary(HistoricalSakayRoute route) => route.stops.isEmpty
      ? 'No sample stops available'
      : 'Potential endpoints: ${route.stops.first.name} → ${route.stops.last.name}';

  Future<void> showDetails(String title, List<Widget> children) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  List<Widget> locationDetails(String name, ReviewedTransitPoint? location) =>
      location == null
      ? [
          const Text(
            'Map unavailable: reviewed coordinates are not supplied. No location or walking distance has been guessed.',
          ),
        ]
      : [
          const Text(
            'Reviewed location reference; entrances, accessibility and boarding platforms need local verification.',
          ),
          Text('Coordinate review: ${location.reviewedOn}'),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(location.sourceUrl)),
            child: const Text('Coordinate source'),
          ),
          TransitReferenceMap(name: name, location: location),
          FilledButton.icon(
            icon: const Icon(Icons.directions_walk),
            label: const Text('Plan a walk to this location'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, TransitWalkingDestination(name, location));
            },
          ),
        ];

  Future<void> stationDetails(_DirectoryData data, RailStation station) {
    final line = data.rail.lineFor(station.id);
    return showDetails('${line.name} · ${station.name}', [
      Text(
        'Station ${station.order} of ${line.stations.length} · ${station.terminal ? 'Line terminal' : 'Station'}',
      ),
      Text('Reference order: ${line.beginning.name} → ${line.ending.name}'),
      const Text('Train schedules and ETAs are not supplied.'),
      for (final transfer in data.rail.transfersAt(station.id)) ...[
        const Divider(),
        Text(
          'Walking transfer to ${data.rail.lineFor(transfer.other(station.id)).name} ${data.rail.station(transfer.other(station.id)).name}',
        ),
        Text(transfer.note),
        const Text('No walking time or accessible path has been verified.'),
      ],
      const Divider(),
      ...locationDetails(
        '${line.name} ${station.name}',
        data.points[station.id],
      ),
    ]);
  }

  Future<void> routeDetails(
    _DirectoryData data,
    HistoricalSakayRoute route,
  ) => showDetails(route.name, [
    const Text('Historical route reference — verify before traveling.'),
    Text(route.classification),
    if (route.description.isNotEmpty) Text(route.description),
    const Text(
      'Current operation, physical terminals and boarding permissions are unverified.',
    ),
    Text(endpointSummary(route)),
    const Text(
      'Endpoints belong to one historical sample trip; they are not confirmed physical terminals.',
    ),
    Text('Sample trip: ${route.sampleTripId ?? 'not supplied'}'),
    FutureBuilder<OperatingRouteEvidence?>(
      future: widget.repository.currentEvidence(
        route.id,
        DateTime.now().toUtc(),
      ),
      builder: (context, snapshot) => snapshot.data == null
          ? const Text('No separate current-service verification is available.')
          : Text(
              'Separate current-service evidence: ${snapshot.data!.sourceUrl}\nValidated ${snapshot.data!.validatedAt.toIso8601String()}. This imported sample remains historical.',
            ),
    ),
    const Divider(),
    for (final (index, stop) in route.stops.indexed)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${index + 1}. ${stop.name}'),
        subtitle: const Text(
          'Historical potential boarding/alighting location',
        ),
        onTap: () {
          Navigator.pop(context);
          stopDetails(data, stop);
        },
      ),
  ]);

  Future<void> stopDetails(_DirectoryData data, HistoricalSakayStop stop) =>
      showDetails(stop.name, [
        const Text(
          'HISTORICAL / UNVERIFIED · potential boarding/alighting location',
        ),
        const Text(
          'This is not a confirmed terminal or an instruction to board here.',
        ),
        if (stop.latitude != null)
          const Text(
            'Historical coordinates exist in the source; independent location review is required.',
          ),
        ...locationDetails(stop.name, data.points['sakay:${stop.id}']),
        const Divider(),
        const Text('Historical sample routes at this stop'),
        for (final route in data.sakay.routesAt(stop.id))
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              routeDetails(data, route);
            },
            child: Text(route.name),
          ),
      ]);

  Future<void> showLicense(BuildContext context) async {
    final text = await rootBundle.loadString(
      'assets/transit/sakay_gtfs_LICENSE.md',
    );
    if (!mounted) return;
    await showDetails('Sakay historical GTFS · license', [
      const Text(
        'Data provided by the Department of Transportation and Communications; historical feed adapted by Sakay.ph. Tamaraw Time is not endorsed by DOTC or Sakay.ph.',
      ),
      TextButton(
        onPressed: () =>
            launchUrl(Uri.parse('https://github.com/sakayph/gtfs')),
        child: const Text('Sakay.ph GTFS source and terms'),
      ),
      SelectableText(text),
    ]);
  }
}
