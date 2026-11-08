// Synthetic contract data only. These are not real Manila services or fares.
Map<String, dynamic> otpFixture(DateTime now) {
  final start = now.toUtc().add(const Duration(minutes: 10));
  Map<String, dynamic> place(String name, double lat, double lon) => {
    'name': name,
    'lat': lat,
    'lon': lon,
  };
  final a = place('Starting point', 14.6001, 121.001);
  final b = place('Fixture boarding station', 14.601, 121);
  final c = place('Fixture interchange', 14.602, 120.999);
  final d = place('Fixture bus stop', 14.6021, 120.998);
  final e = place('Fixture alighting stop', 14.604, 120.989);
  final f = place('FEU Tech', 14.6043, 120.9884);
  Map<String, dynamic> leg(
    String mode,
    int fromMinute,
    int toMinute,
    Map<String, dynamic> from,
    Map<String, dynamic> to,
    String? line,
  ) => {
    'mode': mode,
    'transitLeg': mode != 'WALK',
    'duration': (toMinute - fromMinute) * 60.0,
    'distance': mode == 'WALK' ? 200.0 : 3000.0,
    'start': {
      'scheduledTime': start
          .add(Duration(minutes: fromMinute))
          .toIso8601String(),
      'estimated': null,
    },
    'end': {
      'scheduledTime': start.add(Duration(minutes: toMinute)).toIso8601String(),
      'estimated': null,
    },
    'from': from,
    'to': to,
    'headsign': mode == 'RAIL'
        ? 'Fixture southbound terminal'
        : mode == 'BUS'
        ? 'Fixture campus direction'
        : null,
    'serviceDate': mode == 'WALK'
        ? null
        : '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
    'route': line == null
        ? null
        : {
            'gtfsId': 'fixture:$line',
            'shortName': line,
            'longName': 'Synthetic $line',
            'url': 'https://fixture.example/line/$line',
          },
    'agency': line == null ? null : {'url': 'https://fixture.example/operator'},
    'trip': line == null ? null : {'gtfsId': 'fixture:trip-$line'},
    'interlineWithPreviousLeg': false,
    'legGeometry': null,
  };
  return {
    'scheduleValidated': true,
    'generatedAt': now.toUtc().toIso8601String(),
    'data': {
      'planConnection': {
        'routingErrors': [],
        'edges': [
          {
            'node': {
              'duration': 2700,
              'start': start.toIso8601String(),
              'end': start.add(const Duration(minutes: 45)).toIso8601String(),
              'numberOfTransfers': 1,
              'legs': [
                leg('WALK', 0, 5, a, b, null),
                leg('RAIL', 7, 17, b, c, 'Fixture Rail'),
                leg('WALK', 17, 20, c, d, null),
                leg('BUS', 25, 40, d, e, 'Fixture Bus'),
                leg('WALK', 40, 45, e, f, null),
              ],
            },
          },
        ],
      },
    },
  };
}
