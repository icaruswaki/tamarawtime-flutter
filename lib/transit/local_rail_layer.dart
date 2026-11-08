import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'local_transit_graph.dart';

/// A reference overlay. Each polyline is an actual connected OSM segment;
/// the layer never joins coordinates across missing track geometry.
class LocalRailLayer extends StatelessWidget {
  const LocalRailLayer({super.key, required this.graph});
  final Future<TransitGraph> graph;
  @override
  Widget build(BuildContext context) => FutureBuilder<TransitGraph>(
    future: graph,
    builder: (context, snapshot) {
      final network = snapshot.data;
      if (network == null) return const SizedBox.shrink();
      return Stack(
        children: [
          PolylineLayer(
            polylines: [
              for (final edge in network.edges)
                if (edge.geometry.length > 1)
                  Polyline(
                    points: edge.geometry,
                    color:
                        (edge.line == 'LRT-1'
                                ? const Color(0xff318060)
                                : edge.line == 'LRT-2'
                                ? const Color(0xff785c9b)
                                : const Color(0xffbd9b37))
                            .withValues(alpha: .35),
                    strokeWidth: 3,
                  ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final stop in network.stops)
                Marker(
                  point: stop.point,
                  width: 28,
                  height: 28,
                  child: Tooltip(
                    message: stop.name,
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(stop.name),
                          content: SingleChildScrollView(
                            child: Text(
                              '${stop.id.split(':').first}\n'
                              '${stop.board ? 'Mapped public station entrance; pedestrian access must be routed.' : 'Station reference only; no reviewed boarding access point.'}\n'
                              'Source: ${stop.review.source}\n'
                              'This map does not confirm operating hours, accessible platforms or train arrivals.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.train,
                        size: 18,
                        color: stop.board
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
