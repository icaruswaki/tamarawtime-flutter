import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rail_reference_repository.dart';

/// Location references only. Never joins stops with an invented transit route.
class TransitReferenceMap extends StatelessWidget {
  const TransitReferenceMap({
    super.key,
    required this.name,
    required this.location,
  });
  final String name;
  final ReviewedTransitPoint location;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: FlutterMap(
      key: const ValueKey('transit-reference-map'),
      options: MapOptions(
        initialCenter: location.point,
        initialZoom: 16,
        minZoom: 4,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.tamaraw_time',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: location.point,
              width: 48,
              height: 48,
              child: Tooltip(
                message: name,
                child: const Icon(
                  Icons.location_on,
                  size: 40,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class TransitWalkingDestination {
  const TransitWalkingDestination(this.name, this.location);
  final String name;
  final ReviewedTransitPoint location;
  LatLng get point => location.point;
}
