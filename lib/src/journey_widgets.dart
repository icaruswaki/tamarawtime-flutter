import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'journey.dart';
import 'journey_controller.dart';
import 'planner.dart';
import 'theme.dart';

String journeyClock(DateTime time) =>
    clock(time.toUtc().add(const Duration(hours: 8)));
String distanceLabel(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
IconData vehicleIcon(String? vehicle) => switch (vehicle) {
  'WALK' => Icons.directions_walk,
  'DRIVE' => Icons.directions_car_outlined,
  'SUBWAY' ||
  'HEAVY_RAIL' ||
  'COMMUTER_TRAIN' ||
  'HIGH_SPEED_TRAIN' ||
  'RAIL' ||
  'TRAIN' ||
  'TRAM' ||
  'LIGHT_RAIL' => Icons.train_outlined,
  'BUS' || 'INTERCITY_BUS' || 'TROLLEYBUS' => Icons.directions_bus_outlined,
  'FERRY' => Icons.directions_boat_outlined,
  _ => Icons.directions_transit_outlined,
};

class MobilityCard extends StatelessWidget {
  const MobilityCard({
    super.key,
    required this.child,
    this.color,
    this.padding = 20,
  });
  final Widget child;
  final Color? color;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      ?trailing,
    ],
  );
}

class JourneyOptions extends StatelessWidget {
  const JourneyOptions({super.key, required this.journey});
  final JourneyController journey;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    final options = journey.options;
    final comparable = options.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++)
          Builder(
            builder: (context) {
              final option = options[i];
              final chosen = journey.selectedIndex == i;
              final labels = <String>[];
              if (comparable &&
                  options.every((other) => option.duration <= other.duration)) {
                labels.add('Fastest');
              }
              if (comparable &&
                  option.steps.any((s) => s.transit) &&
                  options.every(
                    (other) => option.transfers <= other.transfers,
                  )) {
                labels.add('Fewest transfers');
              }
              if (comparable &&
                  option.walkingMeters != null &&
                  options.every((o) => o.walkingMeters != null) &&
                  options.every(
                    (o) => option.walkingMeters! <= o.walkingMeters!,
                  )) {
                labels.add('Least walking');
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AnimatedContainer(
                  key: ValueKey('route-option-$i'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: chosen ? p.soft : p.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: chosen ? p.link : p.border,
                      width: chosen ? 2 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => journey.select(i),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${option.minutes} min',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                ),
                                Icon(
                                  chosen
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: p.link,
                                ),
                              ],
                            ),
                            Text(
                              option.hasArrivalEstimate
                                  ? 'Arrive ${journeyClock(option.arrivalAt(DateTime.now()))}'
                                  : 'Arrival time unavailable',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final mode
                                    in option.steps
                                        .map(
                                          (s) => s.walking
                                              ? 'WALK'
                                              : s.vehicle ?? s.mode,
                                        )
                                        .toSet())
                                  Chip(
                                    avatar: Icon(vehicleIcon(mode), size: 17),
                                    label: Text(
                                      mode == 'WALK'
                                          ? 'Walk'
                                          : mode == 'DRIVE'
                                          ? 'Drive'
                                          : mode.replaceAll('_', ' '),
                                    ),
                                  ),
                                if (option.steps.any((s) => s.transit))
                                  Chip(
                                    label: Text(
                                      '${option.transfers} ${option.transfers == 1 ? 'transfer' : 'transfers'}',
                                    ),
                                  ),
                                if (option.walkingMeters != null)
                                  Chip(
                                    label: Text(
                                      '${distanceLabel(option.walkingMeters!)} walking',
                                    ),
                                  ),
                                for (final label in labels)
                                  Chip(label: Text(label)),
                              ],
                            ),
                            if (option.fare != null)
                              Text('Provider fare: ${option.fare}'),
                            const SizedBox(height: 8),
                            Text(
                              '${option.sourceLabel} · Updated ${journeyClock(option.updatedAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({super.key, required this.option});
  final JourneyOption option;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    return MobilityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            'Your journey',
            subtitle: 'Steps from the routing provider',
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < option.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: p.soft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      vehicleIcon(
                        option.steps[i].walking
                            ? 'WALK'
                            : option.steps[i].vehicle ?? option.steps[i].mode,
                      ),
                      color: p.link,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _StepDetails(step: option.steps[i], number: i + 1),
                  ),
                ],
              ),
            ),
          Text(
            '${option.sourceLabel}. Check service notices before travelling.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StepDetails extends StatelessWidget {
  const _StepDetails({required this.step, required this.number});
  final JourneyStep step;
  final int number;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        step.transit
            ? '${number.toString().padLeft(2, '0')} · ${step.lineName ?? 'Transit segment'}'
            : '${number.toString().padLeft(2, '0')} · ${step.walking ? 'Walk' : 'Drive'}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (step.instruction != null && !step.transit) Text(step.instruction!),
      if (step.boardingStop != null) Text('Board at ${step.boardingStop}'),
      if (step.headsign != null) Text('Toward ${step.headsign}'),
      if (step.alightingStop != null) Text('Alight at ${step.alightingStop}'),
      if (step.stops != null)
        Text(
          '${step.stops} stops',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (step.departure != null)
        Text('Departs ${journeyClock(step.departure!)}'),
      if (step.arrival != null) Text('Arrives ${journeyClock(step.arrival!)}'),
      if (step.duration != null || step.meters != null)
        Text(
          [
            if (step.duration != null)
              '${(step.duration!.inSeconds / 60).ceil()} min',
            if (step.meters != null) distanceLabel(step.meters!),
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}

class ExternalDirections extends StatelessWidget {
  const ExternalDirections({super.key, required this.journey});
  final JourneyController journey;
  Future<void> open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Show an actionable message instead of failing silently. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open directions. Check your browser settings.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton.icon(
        icon: const Icon(Icons.open_in_new, size: 17),
        label: const Text('Google Maps directions'),
        onPressed: journey.destination == null
            ? null
            : () => open(
                context,
                Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  if (journey.origin != null)
                    'origin':
                        '${journey.origin!.latitude},${journey.origin!.longitude}',
                  'destination':
                      '${journey.destination!.latitude},${journey.destination!.longitude}',
                  'travelmode': journey.mode == 'Walking'
                      ? 'walking'
                      : journey.mode == 'Driving'
                      ? 'driving'
                      : 'transit',
                }),
              ),
      ),
      TextButton.icon(
        onPressed: () => open(context, Uri.https('sakay.ph', '/')),
        icon: const Icon(Icons.open_in_new, size: 17),
        label: const Text('Explore Sakay.ph'),
      ),
    ],
  );
}

class LiveCountdown extends StatefulWidget {
  const LiveCountdown({
    super.key,
    required this.target,
    this.prefix = 'Leave in',
  });
  final DateTime target;
  final String prefix;
  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class LivePlannerClock extends StatefulWidget {
  const LivePlannerClock({super.key});
  @override
  State<LivePlannerClock> createState() => _LivePlannerClockState();
}

class _LivePlannerClockState extends State<LivePlannerClock> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = manilaNow();
    final time =
        '${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
    return Text(
      '${days[now.weekday % 7]}, ${now.month}/${now.day}/${now.year} · $time PHT',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.target.difference(DateTime.now().toUtc()).inSeconds;
    final label = seconds < 0
        ? 'Recommended time has passed'
        : '${widget.prefix} ${seconds ~/ 3600 > 0 ? '${seconds ~/ 3600}h ' : ''}${seconds ~/ 60 % 60}m ${seconds % 60}s';
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: Text(
        label,
        key: ValueKey(label),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
