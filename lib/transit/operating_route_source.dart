/// Contract for a future authorized backend. Historical GTFS cannot implement
/// this interface by asserting operation, distances, boarding points or ETAs.
abstract interface class OperatingRouteSource {
  Future<OperatingRouteEvidence?> lookup(String routeId);
}

class UnavailableOperatingRouteSource implements OperatingRouteSource {
  const UnavailableOperatingRouteSource();
  @override
  Future<OperatingRouteEvidence?> lookup(String routeId) async => null;
}

class OperatingRouteEvidence {
  const OperatingRouteEvidence({
    required this.routeId,
    required this.sourceUrl,
    required this.validatedAt,
    required this.validUntil,
    required this.operatingStatus,
    required this.boardingVerified,
    required this.alightingVerified,
  });
  final String routeId, sourceUrl, operatingStatus;
  final DateTime validatedAt, validUntil;
  final bool boardingVerified, alightingVerified;

  bool validFor(String id, DateTime now) {
    final source = Uri.tryParse(sourceUrl);
    return routeId == id &&
        operatingStatus == 'independently_verified_operating' &&
        source?.scheme == 'https' &&
        source!.host.isNotEmpty &&
        validatedAt.isUtc &&
        validUntil.isUtc &&
        !now.isBefore(validatedAt) &&
        now.isBefore(validUntil) &&
        boardingVerified &&
        alightingVerified;
  }
}
