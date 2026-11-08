import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../transit/fare_estimator_view.dart';
import 'journey.dart';
import 'journey_widgets.dart';
import 'planner.dart';
import 'responsive.dart';
import 'routing.dart';
import 'theme.dart';

class PunctualityOverview extends StatelessWidget {
  const PunctualityOverview({
    super.key,
    required this.planner,
    required this.onCommute,
  });
  final Planner planner;
  final VoidCallback onCommute;
  @override
  Widget build(BuildContext context) {
    final p = TamarawPalette.of(context);
    final classes = planner.upcoming;
    final next = classes.isEmpty ? null : classes.first;
    final j = planner.journey;
    final start = next == null
        ? null
        : nextOccurrence(next, manilaNow()).subtract(const Duration(hours: 8));
    final prep = (planner.settings['prep'] as num).toInt();
    final buffer = (planner.settings['buffer'] as num).toInt();
    final option =
        next != null && j.matches(campusPoints[next['campus']]!, 'Transit')
        ? j.selected
        : null;
    final advice = start == null
        ? const DepartureAdvice(status: PunctualityStatus.unavailable)
        : DepartureAdvice.calculate(
            classStart: start,
            now: DateTime.now().toUtc(),
            preparation: Duration(minutes: prep),
            buffer: Duration(minutes: buffer),
            journey: option,
          );
    final nextCard = MobilityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            'Your Next Class',
            trailing: Chip(
              avatar: Icon(
                advice.status == PunctualityStatus.potentiallyLate
                    ? Icons.warning_amber_rounded
                    : Icons.circle,
                size: 13,
                color: advice.status == PunctualityStatus.potentiallyLate
                    ? Colors.deepOrange
                    : advice.status == PunctualityStatus.unavailable
                    ? p.muted
                    : p.link,
              ),
              label: Text(next == null ? 'Schedule needed' : advice.label),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            next?['name'] ?? 'A fresh start for your week',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? 'Add your first class to get departure guidance.'
                : '${next['campus']} · ${(next['room'] as String).isEmpty ? 'Room not set' : next['room']}',
            style: TextStyle(color: p.muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 30,
            runSpacing: 20,
            children: [
              _Metric(
                'Class starts',
                start == null ? '—' : journeyClock(start),
              ),
              _Metric(
                'Public transit',
                option == null ? 'Unavailable' : '${option.minutes} min',
              ),
              _Metric('Preparation', '$prep min'),
              _Metric('Arrival buffer', '$buffer min'),
            ],
          ),
          if (start != null) ...[
            const SizedBox(height: 20),
            LiveCountdown(target: start, prefix: 'Class in'),
          ],
          if (option != null) ...[
            const SizedBox(height: 14),
            Text(
              '${option.sourceLabel} · Updated ${journeyClock(option.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 18),
          RoadEstimates(journey: j, settings: planner.settings),
          FareEstimator(
            repository: planner.transit,
            journey: option,
            studentDiscount: planner.studentDiscount,
            onStudentDiscountChanged: planner.selectStudentDiscount,
          ),
        ],
      ),
    );
    final leaveCard = MobilityCard(
      color: p.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.route_outlined, color: p.link, size: 28),
          const SizedBox(height: 18),
          Text(
            'A little planning.\nA smoother morning.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          Text(
            advice.leaveAt == null
                ? 'Your departure time will appear with a valid route estimate.'
                : 'Leave by ${journeyClock(advice.leaveAt!)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (advice.prepareAt != null) ...[
            const SizedBox(height: 8),
            Text('Prepare by ${journeyClock(advice.prepareAt!)}'),
          ],
          if (advice.arriveAt != null)
            Text('Estimated arrival ${journeyClock(advice.arriveAt!)}'),
          if (advice.timetableLimited)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This itinerary requires an earlier departure to catch the scheduled service.',
              ),
            ),
          if (advice.leaveAt != null) ...[
            const SizedBox(height: 16),
            LiveCountdown(target: advice.leaveAt!),
          ],
          if (option == null &&
              start != null &&
              planner.settings['useManualEstimate'] == true) ...[
            const SizedBox(height: 12),
            Text(
              'Manual plan: leave ${journeyClock(start.subtract(Duration(minutes: (planner.settings['travel'] as num).toInt() + buffer)))}. This is not a live ETA.',
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCommute,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Plan my commute'),
          ),
          if (next != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: j.locating || j.tracking
                  ? null
                  : () => unawaited(j.startTracking()),
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(j.locating ? 'Locating…' : 'Use my location'),
            ),
            if (j.tracking)
              TextButton(
                onPressed: j.stopTracking,
                child: const Text('Stop tracking'),
              ),
            if (j.permissionDenied)
              TextButton(
                onPressed: Geolocator.openAppSettings,
                child: const Text('Location settings'),
              ),
            if (j.loading) const LinearProgressIndicator(),
            if (option == null && j.origin != null)
              Text(j.message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Good day, ${planner.settings['name']}!',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Make room for the journey. Arrive ready for class.',
          style: TextStyle(color: p.muted),
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, box) =>
              AppLayout.columns(
                box.maxWidth,
                textScale: AppLayout.textScale(context),
              )
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: nextCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: leaveCard),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [nextCard, leaveCard],
                ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 5),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
