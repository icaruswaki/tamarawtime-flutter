// OSRM route/v1 response shape with the duration/distance observed in DevTools.
// Coordinates are representative GeoJSON positions, in longitude/latitude order.
Map<String, dynamic> osrmFixture({
  num duration = 810.9,
  num distance = 8085.2,
}) => {
  'code': 'Ok',
  'routes': [
    {
      'duration': duration,
      'distance': distance,
      'weight_name': 'routability',
      'weight': duration,
      'legs': [],
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [121.0, 14.6],
          [120.9884, 14.6043],
        ],
      },
    },
  ],
  'waypoints': [],
};
