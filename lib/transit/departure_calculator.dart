class DepartureRecommendation {
  final DateTime leaveAt;
  final DateTime prepareAt;
  final DateTime estimatedArrival;
  const DepartureRecommendation(
    this.leaveAt,
    this.prepareAt,
    this.estimatedArrival,
  );
}

DepartureRecommendation? calculateDeparture({
  required DateTime classStart,
  required Duration? travelEstimate,
  Duration arrivalBuffer = const Duration(minutes: 15),
  Duration preparationDuration = const Duration(minutes: 20),
}) {
  if (travelEstimate == null ||
      travelEstimate <= Duration.zero ||
      arrivalBuffer.isNegative ||
      preparationDuration.isNegative) {
    return null;
  }
  final leaveAt = classStart.subtract(travelEstimate).subtract(arrivalBuffer);
  return DepartureRecommendation(
    leaveAt,
    leaveAt.subtract(preparationDuration),
    leaveAt.add(travelEstimate),
  );
}
