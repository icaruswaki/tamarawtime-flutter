import 'package:flutter/material.dart';

import 'transit_models.dart';
import 'transit_repository.dart';

/// Read-only reference exploration, deliberately disconnected from routing.
class HistoricalTransitExplorer extends StatefulWidget {
  const HistoricalTransitExplorer({super.key, required this.repository});
  final TransitRepository repository;
  @override
  State<HistoricalTransitExplorer> createState() =>
      _HistoricalTransitExplorerState();
}

class _HistoricalTransitExplorerState extends State<HistoricalTransitExplorer> {
  String query = '';
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Historical transit reference'),
      subtitle: const Text(
        'HISTORICAL / UNVERIFIED · not current travel guidance',
      ),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Past route names and stop sequences only. Current operation, fares and arrival times are not verified.',
        ),
        FutureBuilder<TransitCatalog>(
          future: widget.repository.loadCatalog(),
          builder: (context, snapshot) {
            final catalog = snapshot.data;
            if (snapshot.hasError) {
              return const Text('Historical catalog could not be loaded.');
            }
            if (catalog == null) {
              return const Text('Loading historical catalog…');
            }
            if (catalog.routes.isEmpty) {
              return const Text(
                'No generic historical catalog routes imported. Open Stations & routes for the Sakay historical directory.',
              );
            }
            final routes = catalog.routes
                .where(
                  (route) =>
                      route.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Source: ${catalog.source}'),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search historical routes',
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                if (routes.isEmpty)
                  const Text('No matching historical routes.'),
                for (final route in routes.take(25))
                  ExpansionTile(
                    key: ValueKey(route.id),
                    title: Text(route.name),
                    subtitle: Text('${route.mode} · HISTORICAL / UNVERIFIED'),
                    children: [
                      for (final (index, id)
                          in (catalog.routeStops[route.id] ?? <String>[])
                              .indexed)
                        ListTile(
                          title: Text(
                            '${index + 1}. ${catalog.stopById(id)!.name}',
                          ),
                        ),
                    ],
                  ),
                if (routes.length > 25)
                  const Text(
                    'Showing 25 matches. Refine the search for other routes.',
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
