import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

export 'map_configuration.dart';

class MapRouteLine {
  const MapRouteLine(this.points, this.color, {this.walking = false});
  final List<LatLng> points;
  final Color color;
  final bool walking;
}

class GoogleJourneyMap extends StatefulWidget {
  const GoogleJourneyMap({
    super.key,
    required this.destination,
    required this.destinationLabel,
    required this.lines,
    this.origin,
    this.originLabel = 'Origin',
    this.onTap,
    this.bottomOverlayFraction = 0,
  });
  final LatLng? origin;
  final LatLng destination;
  final String originLabel, destinationLabel;
  final List<MapRouteLine> lines;
  final ValueChanged<LatLng>? onTap;
  final double bottomOverlayFraction;
  @override
  State<GoogleJourneyMap> createState() => GoogleJourneyMapState();
}

class GoogleJourneyMapState extends State<GoogleJourneyMap> {
  google.GoogleMapController? _controller;
  google.LatLng convert(LatLng point) =>
      google.LatLng(point.latitude, point.longitude);
  @override
  void didUpdateWidget(covariant GoogleJourneyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination ||
        (oldWidget.origin == null && widget.origin != null) ||
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.lines.indexed.any(
          (entry) => !identical(entry.$2.points, widget.lines[entry.$1].points),
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitRoute();
      });
    }
  }

  void fitRoute() {
    final points = [
      if (widget.origin != null) widget.origin!,
      widget.destination,
      ...widget.lines.expand((l) => l.points),
    ];
    final bounds = points.fold<List<double>>(
      [90, -90, 180, -180],
      (b, p) => [
        p.latitude < b[0] ? p.latitude : b[0],
        p.latitude > b[1] ? p.latitude : b[1],
        p.longitude < b[2] ? p.longitude : b[2],
        p.longitude > b[3] ? p.longitude : b[3],
      ],
    );
    if (bounds[0] == bounds[1] && bounds[2] == bounds[3]) {
      _controller?.moveCamera(
        google.CameraUpdate.newLatLngZoom(convert(widget.destination), 14),
      );
    } else {
      _controller?.moveCamera(
        google.CameraUpdate.newLatLngBounds(
          google.LatLngBounds(
            southwest: google.LatLng(bounds[0], bounds[2]),
            northeast: google.LatLng(bounds[1], bounds[3]),
          ),
          45,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => google.GoogleMap(
      padding: EdgeInsets.only(
        bottom: box.maxHeight * widget.bottomOverlayFraction,
      ),
      initialCameraPosition: google.CameraPosition(
        target: convert(widget.destination),
        zoom: 14,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        fitRoute();
      },
      onTap: (p) => widget.onTap?.call(LatLng(p.latitude, p.longitude)),
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
      markers: {
        google.Marker(
          markerId: const google.MarkerId('destination'),
          position: convert(widget.destination),
          infoWindow: google.InfoWindow(title: widget.destinationLabel),
        ),
        if (widget.origin != null)
          google.Marker(
            markerId: const google.MarkerId('origin'),
            position: convert(widget.origin!),
            infoWindow: google.InfoWindow(title: widget.originLabel),
            icon: google.BitmapDescriptor.defaultMarkerWithHue(
              google.BitmapDescriptor.hueGreen,
            ),
          ),
      },
      polylines: {
        for (var i = 0; i < widget.lines.length; i++)
          google.Polyline(
            polylineId: google.PolylineId('leg-$i'),
            points: widget.lines[i].points.map(convert).toList(),
            color: widget.lines[i].color,
            width: widget.lines[i].walking ? 4 : 6,
            patterns: widget.lines[i].walking
                ? [google.PatternItem.dash(10), google.PatternItem.gap(8)]
                : [],
          ),
      },
    ),
  );
}
