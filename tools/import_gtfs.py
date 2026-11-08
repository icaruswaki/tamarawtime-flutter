#!/usr/bin/env python3
"""Convert a local (permission-cleared) GTFS directory into a SMALL historical catalog.

Requires routes.txt, stops.txt, trips.txt, stop_times.txt. No network requests.
Output is intended ONLY for offline/historical route exploration. GTFS service
validity, real-time operation, fares, and walking routes are not inferred.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def rows(path):
    with path.open('r', encoding='utf-8-sig', newline='') as fp:
        yield from csv.DictReader(fp)


def infer_mode(record):
    route_id = record.get('route_id', '').upper()
    agency = record.get('agency_id', '').upper()
    name = ' '.join([record.get('route_short_name', ''), record.get('route_long_name', '')]).upper()
    if 'PUJ' in route_id or 'JEEP' in name:
        return 'jeepney'
    if 'PUB' in route_id or 'BUS' in name:
        return 'bus'
    if record.get('route_type') == '2' or 'LRT' in name or 'MRT' in name:
        return 'train'
    if record.get('route_type') == '3' and agency == 'LTFRB':
        return 'unspecified_road_transit'
    return 'other'


def import_feed(src, max_routes, *, source='User-supplied local GTFS',
                license_reference='Not recorded; clearance required before distribution'):
    if max_routes < 0:
        raise ValueError('max_routes must be zero or positive')
    required = ['routes.txt', 'stops.txt', 'trips.txt', 'stop_times.txt']
    missing = [filename for filename in required if not (src / filename).is_file()]
    if missing:
        raise ValueError('GTFS missing: ' + ', '.join(missing))

    all_routes = list(rows(src / 'routes.txt'))
    chosen = all_routes[:max_routes] if max_routes else all_routes
    chosen_ids = {r['route_id'] for r in chosen}
    trip_to_route = {}
    for trip in rows(src / 'trips.txt'):
        if trip.get('route_id') in chosen_ids:
            trip_to_route[trip['trip_id']] = trip['route_id']

    route_stop_order = defaultdict(list)
    # Preserve the stop order of the FIRST trip per route, not concatenated trips.
    first_trip = {}
    for trip_id, route_id in trip_to_route.items():
        first_trip.setdefault(route_id, trip_id)
    selected_trips = set(first_trip.values())
    trip_stops = defaultdict(list)
    for stop in rows(src / 'stop_times.txt'):
        trip_id = stop.get('trip_id')
        if trip_id in selected_trips:
            try:
                sequence = int(stop.get('stop_sequence', '0'))
            except ValueError:
                continue
            if sequence < 0:
                continue
            trip_stops[trip_id].append((sequence, stop['stop_id']))
    for route_id, trip_id in first_trip.items():
        route_stop_order[route_id] = [stop_id for _, stop_id in sorted(trip_stops[trip_id])]

    used_stops = {sid for ids in route_stop_order.values() for sid in ids}
    stops = []
    for stop in rows(src / 'stops.txt'):
        if stop.get('stop_id') not in used_stops:
            continue
        try:
            lat, lon = float(stop['stop_lat']), float(stop['stop_lon'])
        except (ValueError, KeyError):
            continue
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            continue
        stops.append({'id': stop['stop_id'], 'name': stop.get('stop_name', 'Unnamed stop'), 'lat': lat, 'lon': lon})

    valid_ids = {stop['id'] for stop in stops}
    return {
        'data_status': 'unverified_historical',
        'source': source,
        'license_reference': license_reference,
        'notice': 'Never present these routes as current, verified or operational without independent validation.',
        'routes': [
            {'id': route['route_id'],
             'name': route.get('route_short_name') or route.get('route_long_name') or route['route_id'],
             'mode': infer_mode(route), 'historical': True}
            for route in chosen
        ],
        'stops': stops,
        'route_stops': {route_id: [sid for sid in stop_ids if sid in valid_ids]
                        for route_id, stop_ids in route_stop_order.items()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('assets/transit/transit_catalog.json'))
    parser.add_argument('--max-routes', type=int, default=250,
                        help='Limit for Flutter asset size; use 0 for all routes')
    parser.add_argument('--source', required=True,
                        help='Feed publisher and version/date; no personal paths')
    parser.add_argument('--license-reference', required=True,
                        help='License URL or permission reference; verify redistribution rights')
    args = parser.parse_args()
    if args.max_routes < 0:
        parser.error('--max-routes must be zero or positive')
    result = import_feed(args.input, args.max_routes, source=args.source,
                         license_reference=args.license_reference)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print(f"Imported {len(result['routes'])} historical routes and {len(result['stops'])} stops to {args.output}")


if __name__ == '__main__':
    main()
