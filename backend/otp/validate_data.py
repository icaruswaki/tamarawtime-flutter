"""Conservative routing eligibility checks. Never rewrites a GTFS service date.

This is not a replacement for the MobilityData GTFS validator or operator review.
All data stays local and outside Flutter assets and student records.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import re
import sys
import zipfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

MANILA = timezone(timedelta(hours=8))


def today():
    return datetime.now(MANILA).date()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def local_file(directory, name):
    path = (directory / name).resolve()
    if not path.is_relative_to(directory.resolve()) or not path.is_file():
        raise ValueError('Dataset file is missing or outside the data directory.')
    return path


def provenance(record, day):
    for key in ('source_url', 'license_url'):
        url = urlparse(record.get(key, ''))
        if url.scheme != 'https' or not url.netloc:
            raise ValueError('Each dataset needs its actual HTTPS source and license URL.')
    verified = date.fromisoformat(record['verified_on'])
    expires = date.fromisoformat(record['valid_until'])
    if verified > day or expires < day or expires < verified:
        raise ValueError('Dataset provenance review is not current.')
    return expires


def audit_gtfs(path, day, expires):
    with zipfile.ZipFile(path) as archive:
        names = {}
        for info in archive.infolist():
            name = Path(info.filename).name
            if name.endswith('.txt'):
                if name in names:
                    raise ValueError('Ambiguous GTFS table: ' + name)
                names[name] = info.filename

        def rows(name, required=False):
            if name not in names:
                if required:
                    raise ValueError('Missing GTFS table: ' + name)
                return []
            with archive.open(names[name]) as raw:
                return list(csv.DictReader(io.TextIOWrapper(raw, encoding='utf-8-sig')))

        agencies = rows('agency.txt', True)
        routes, stops = rows('routes.txt', True), rows('stops.txt', True)
        trips, stop_times = rows('trips.txt', True), rows('stop_times.txt', True)
        calendar, exceptions = rows('calendar.txt'), rows('calendar_dates.txt')
        feed_info = rows('feed_info.txt')
    if not agencies or any(r.get('agency_timezone') != 'Asia/Manila' for r in agencies):
        raise ValueError('Metro Manila feeds must declare agency_timezone Asia/Manila.')

    def index(records, key):
        result = {r[key]: r for r in records}
        if len(result) != len(records) or not result or '' in result:
            raise ValueError('Empty or duplicate GTFS identities: ' + key)
        return result

    route_ids, stop_ids = index(routes, 'route_id'), index(stops, 'stop_id')
    trip_ids = index(trips, 'trip_id')
    services = {}
    coverage_end = None
    for row in calendar:
        start = datetime.strptime(row['start_date'], '%Y%m%d').date()
        end = datetime.strptime(row['end_date'], '%Y%m%d').date()
        coverage_end = max(coverage_end or end, end)
        if end < start or (end - start).days > 3660:
            raise ValueError('Invalid or excessive calendar range.')
        sid = row['service_id']
        if sid in services:
            raise ValueError('Duplicate calendar service_id.')
        days = set()
        cursor = max(start, day - timedelta(days=1))
        while cursor <= min(end, expires):
            if row[('monday','tuesday','wednesday','thursday','friday','saturday','sunday')[cursor.weekday()]] == '1':
                days.add(cursor.strftime('%Y%m%d'))
            cursor += timedelta(days=1)
        services[sid] = days
    for row in exceptions:
        event = datetime.strptime(row['date'], '%Y%m%d').date()
        coverage_end = max(coverage_end or event, event)
        dates = services.setdefault(row['service_id'], set())
        if row['exception_type'] == '1' and day - timedelta(days=1) <= event <= expires:
            dates.add(row['date'])
        elif row['exception_type'] == '2':
            dates.discard(row['date'])
        elif row['exception_type'] != '1':
            raise ValueError('Invalid calendar exception.')
    for info in feed_info:
        if info.get('feed_end_date'):
            feed_end = datetime.strptime(info['feed_end_date'], '%Y%m%d').date()
            for sid in services:
                services[sid] = {d for d in services[sid] if d <= feed_end.strftime('%Y%m%d')}
    visits = {tid: [] for tid in trip_ids}

    def seconds(value):
        if not re.fullmatch(r'\d{1,3}:\d{2}:\d{2}', value):
            raise ValueError('Missing or invalid scheduled stop time.')
        h, m, s = map(int, value.split(':'))
        if m >= 60 or s >= 60:
            raise ValueError('Invalid scheduled stop time.')
        return h * 3600 + m * 60 + s

    for row in stop_times:
        tid, sid = row['trip_id'], row['stop_id']
        if tid not in trip_ids or sid not in stop_ids:
            raise ValueError('Stop time references a missing trip or stop.')
        stop = stop_ids[sid]
        lat, lon = float(stop['stop_lat']), float(stop['stop_lon'])
        if not (math.isfinite(lat) and math.isfinite(lon) and abs(lat) <= 90 and abs(lon) <= 180):
            raise ValueError('Invalid boarding/alighting coordinates.')
        arrival, departure = seconds(row['arrival_time']), seconds(row['departure_time'])
        if departure < arrival:
            raise ValueError('Stop departure precedes arrival.')
        visits[tid].append((int(row['stop_sequence']), arrival, departure))
    for tid, trip in trip_ids.items():
        if trip['route_id'] not in route_ids or trip['service_id'] not in services:
            raise ValueError('Trip references a missing route or service calendar.')
        times = sorted(visits[tid])
        if len(times) < 2 or len({v[0] for v in times}) != len(times):
            raise ValueError('Trip needs at least two uniquely ordered stop times.')
        if any(b[1] < a[2] for a, b in zip(times, times[1:])):
            raise ValueError('Stop times are not chronological.')
    active = {t['service_id'] for t in trips if services[t['service_id']]}
    if not active:
        raise ValueError(f'No usable current scheduled trips. Last source service date: {coverage_end}. Historical dates were not modified.')
    return {
        'counts': {'routes': len(routes), 'stops': len(stops), 'trips': len(trips), 'stop_times': len(stop_times)},
        'service_dates': {sid: sorted(services[sid]) for sid in active},
        'trip_services': {tid: t['service_id'] for tid, t in trip_ids.items() if t['service_id'] in active},
    }


def prepare(directory, day=None):
    day = day or today()
    catalog = json.loads((directory / 'datasets.json').read_text(encoding='utf-8'))
    if not catalog.get('feeds') or not catalog.get('osm'):
        raise ValueError('Current GTFS schedules and a matching OSM PBF are missing. Historical routes cannot supply public-transit ETAs.')
    hashes = {'datasets.json': digest(directory / 'datasets.json')}
    feeds, config_feeds = {}, []
    for record in catalog['feeds']:
        fid = record['id']
        if not re.fullmatch(r'[A-Za-z0-9_-]+', fid) or fid in feeds:
            raise ValueError('Feed IDs must be unique and contain letters, digits, underscore or dash.')
        expires = provenance(record, day)
        path = local_file(directory, record['file'])
        if not path.name.endswith('.gtfs.zip'):
            raise ValueError('Name current feeds *.gtfs.zip for OTP.')
        feeds[fid] = {**audit_gtfs(path, day, expires), 'valid_until': str(expires)}
        hashes[record['file']] = digest(path)
        config_feeds.append({'type': 'gtfs', 'feedId': fid, 'source': 'file:///var/opentripplanner/' + record['file']})
    osm = catalog['osm']
    provenance(osm, day)
    path = local_file(directory, osm['file'])
    if not path.name.endswith('.osm.pbf') or path.stat().st_size == 0:
        raise ValueError('A nonempty, geographically matching *.osm.pbf is required.')
    hashes[osm['file']] = digest(path)
    configs = {
        'otp-config.json': {'otpFeatures': {'GtfsGraphQlApi': True}},
        'build-config.json': {'transitFeeds': config_feeds, 'osm': [{'source': 'file:///var/opentripplanner/' + osm['file'], 'timeZone': 'Asia/Manila'}]},
        'router-config.json': {'configVersion': 'tamaraw-otp-2.8.1', 'routingDefaults': {'locale': 'en'}},
    }
    for name, config in configs.items():
        (directory / name).write_text(json.dumps(config, indent=2), encoding='utf-8')
        hashes[name] = digest(directory / name)
    pending = {'otp_version': '2.8.1', 'validated_on': str(day), 'input_hashes': hashes, 'feeds': feeds}
    (directory / 'pending-validation.json').write_text(json.dumps(pending), encoding='utf-8')
    return pending


def checked_graph(directory, day=None, pending=False):
    day = day or today()
    manifest = directory / ('pending-validation.json' if pending else 'graph-validation.json')
    if not manifest.exists():
        raise ValueError('No validated current GTFS/OSM routing graph is configured. Historical routes are reference only.')
    result = json.loads(manifest.read_text(encoding='utf-8'))
    for name, checksum in result['input_hashes'].items():
        if digest(local_file(directory, name)) != checksum:
            raise ValueError('Routing inputs changed. Validate and rebuild the graph.')
    graph = local_file(directory, 'graph.obj')
    if pending:
        if graph.stat().st_mtime_ns < manifest.stat().st_mtime_ns:
            raise ValueError('Graph predates input validation; build it before sealing.')
    elif digest(graph) != result['graph_sha256']:
        raise ValueError('Graph does not match the validated dataset build.')
    if not result['feeds'] or any(date.fromisoformat(f['valid_until']) < day for f in result['feeds'].values()):
        raise ValueError('Transit dataset review has expired; refresh current data and rebuild.')
    if not any(d >= (day - timedelta(days=1)).strftime('%Y%m%d') for f in result['feeds'].values() for dates in f['service_dates'].values() for d in dates):
        raise ValueError('GTFS service calendars have expired. Historical dates were not modified.')
    return result


def seal(directory):
    result = checked_graph(directory, pending=True)
    result['graph_sha256'] = digest(directory / 'graph.obj')
    (directory / 'graph-validation.json').write_text(json.dumps(result), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'seal', 'check'])
    parser.add_argument('--data', type=Path, default=Path(__file__).parent / 'data')
    args = parser.parse_args()
    try:
        result = prepare(args.data) if args.action == 'prepare' else seal(args.data) if args.action == 'seal' else checked_graph(args.data)
        print('Validation completed. No GTFS service dates were changed.')
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
