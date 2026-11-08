import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/journey.dart';
import 'fare_estimator.dart';
import 'transit_repository.dart';

/// Shared dashboard/planner view; student pricing is always an explicit choice.
class FareEstimator extends StatelessWidget {
  const FareEstimator({
    super.key,
    required this.repository,
    required this.journey,
    required this.studentDiscount,
    required this.onStudentDiscountChanged,
  });
  final TransitRepository repository;
  final JourneyOption? journey;
  final bool studentDiscount;
  final ValueChanged<bool> onStudentDiscountChanged;

  @override
  Widget build(BuildContext context) => FutureBuilder<FareEstimatorService>(
    future: repository.loadEstimator(),
    builder: (context, snapshot) {
      final service = snapshot.data;
      final estimate = service?.estimate(journey, now: DateTime.now().toUtc());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estimated travel cost',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (journey?.fare case final String quote) ...[
            Text('Provider fare: $quote'),
            const Text(
              'Provider quote; student discount is not applied to this amount.',
            ),
            const SizedBox(height: 8),
          ],
          if (estimate == null || estimate.legs.isEmpty) ...[
            const Text('Fare not available'),
            Text(
              snapshot.hasError
                  ? 'Fare reference could not be loaded.'
                  : service == null
                  ? 'Loading fare reference…'
                  : estimate!.reason!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              estimate.complete
                  ? 'Estimated trip fare'
                  : 'Estimated subtotal · incomplete trip cost',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text('Regular: PHP ${estimate.regular.toStringAsFixed(2)}'),
            if (studentDiscount)
              Text(
                'Student estimate: PHP ${estimate.student.toStringAsFixed(2)}',
              ),
            for (final leg in estimate.legs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${leg.step.lineName ?? 'Transit ride'} · '
                  '${service!.calculator.rules[leg.service.fareMode]!.label}\n'
                  '${(leg.step.meters! / 1000).toStringAsFixed(2)} km traveled · '
                  'PHP ${(studentDiscount ? leg.estimate.studentFare : leg.estimate.fullFare).toStringAsFixed(2)} estimated',
                ),
              ),
            if (!estimate.complete)
              Text(
                '${estimate.unavailableLegs} other ride(s): Fare not available. This is not a trip total.',
              ),
            const SizedBox(height: 8),
            const Text(
              'Reference estimate only. Illustrative PHP 0.25 rounding; confirm the posted LTFRB/operator matrix.',
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: studentDiscount,
            title: const Text('Apply 20% student discount'),
            subtitle: const Text(
              'Select only if eligible. Estimates are rounded after discount; show valid student identification to the operator.',
            ),
            onChanged: (value) => onStudentDiscountChanged(value ?? false),
          ),
          if (service != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'LTFRB reference · ${service.calculator.effectiveDate}',
              ),
              subtitle: const Text(
                'Estimates, not certified fare-matrix prices',
              ),
              children: [
                for (final source in service.calculator.sources)
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(source),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(source),
                  ),
                if (estimate != null)
                  for (final leg in estimate.legs)
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(leg.service.evidenceUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        'Service verification: ${leg.service.evidenceUrl}',
                      ),
                    ),
              ],
            ),
        ],
      );
    },
  );
}
