"""Synthetic contract/integration tests, never evidence of live Manila service."""
import copy
import csv
import io
import json
import tempfile
import threading
import unittest
import zipfile
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import Gateway, handler_for, validate_itineraries, variables
from validate_data import audit_gtfs, checked_graph, prepare, seal

NOW = datetime(2026, 11, 8, 1, tzinfo=timezone.utc)


def feed(path, end='20261130', exception=None):
    tables = {
        'agency.txt': [['agency_id','agency_name','agency_url','agency_timezone'], ['fixture','Synthetic test operator','https://fixture.example','Asia/Manila']],
        'routes.txt': [['route_id','route_short_name','route_long_name','route_type'], ['r','T','Synthetic route','2']],
        'stops.txt': [['stop_id','stop_name','stop_lat','stop_lon'], ['a','Fixture A','14.6','121'], ['b','Fixture B','14.6043','120.9884']],
        'trips.txt': [['route_id','service_id','trip_id'], ['r','s','t']],
        'stop_times.txt': [['trip_id','arrival_time','departure_time','stop_id','stop_sequence'], ['t','09:05:00','09:05:00','a','1'], ['t','09:20:00','09:20:00','b','2']],
        'calendar.txt': [['service_id','monday','tuesday','wednesday','thursday','friday','saturday','sunday','start_date','end_date'], ['s','1','1','1','1','1','1','1','20261101',end]],
    }
    if exception:
        tables['calendar_dates.txt'] = [['service_id','date','exception_type'], ['s','20261108',exception]]
    with zipfile.ZipFile(path, 'w') as archive:
        for name, rows in tables.items():
            text = io.StringIO()
            csv.writer(text).writerows(rows)
            archive.writestr(name, text.getvalue())


def inputs(directory):
    feed(directory / 'fixture.gtfs.zip')
    # Nonempty sentinel only. Tests never build an OTP graph from this file.
    (directory / 'fixture.osm.pbf').write_bytes(b'SYNTHETIC NOT REAL OSM')
    common = {'source_url': 'https://fixture.example/source', 'license_url': 'https://fixture.example/license', 'verified_on': '2026-11-08', 'valid_until': '2026-11-30'}
    (directory / 'datasets.json').write_text(json.dumps({
        'feeds': [{'id': 'fixture', 'file': 'fixture.gtfs.zip', **common}],
        'osm': {'file': 'fixture.osm.pbf', **common},
    }))
    result = prepare(directory, NOW.date())
    (directory / 'graph.obj').write_bytes(b'SYNTHETIC GRAPH; NEVER USED BY OTP')
    # Seal with a fixed test day without changing system time or source dates.
    checked_graph(directory, NOW.date(), pending=True)
    from validate_data import digest
    result['graph_sha256'] = digest(directory / 'graph.obj')
    (directory / 'graph-validation.json').write_text(json.dumps(result))
    return result


def itinerary():
    start, end = NOW + timedelta(minutes=5), NOW + timedelta(minutes=20)
    def timing(time):
        return {'scheduledTime': time.isoformat(), 'estimated': None}
    leg = {
        'mode': 'RAIL', 'transitLeg': True, 'duration': 900, 'distance': 4000,
        'start': timing(start), 'end': timing(end), 'serviceDate': '20261108',
        'from': {'name': 'Fixture A', 'lat': 14.6, 'lon': 121},
        'to': {'name': 'Fixture B', 'lat': 14.6043, 'lon': 120.9884},
        'trip': {'gtfsId': 'fixture:t'}, 'route': {'gtfsId': 'fixture:r', 'shortName': 'Test'},
        'legGeometry': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
    }
    return {'data': {'planConnection': {'routingErrors': [], 'edges': [{'node': {
        'start': start.isoformat(), 'end': end.isoformat(), 'duration': 900,
        'numberOfTransfers': 0, 'legs': [leg],
    }}]}}}


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def test_expired_schedule_rejected_without_date_changes(self):
        path = self.directory / 'old.gtfs.zip'
        feed(path, end='20200630')
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            audit_gtfs(path, NOW.date(), NOW.date() + timedelta(days=30))
        self.assertEqual(path.read_bytes(), before)

    def test_weekday_service_and_calendar_exception(self):
        path = self.directory / 'current.gtfs.zip'
        feed(path, exception='2')
        audit = audit_gtfs(path, NOW.date(), NOW.date() + timedelta(days=30))
        self.assertNotIn('20261108', audit['service_dates']['s'])
        feed(path, exception='1')
        audit = audit_gtfs(path, NOW.date(), NOW.date() + timedelta(days=30))
        self.assertIn('20261108', audit['service_dates']['s'])

    def test_changed_inputs_or_graph_fail_closed(self):
        inputs(self.directory)
        checked_graph(self.directory, NOW.date())
        (self.directory / 'graph.obj').write_bytes(b'DIFFERENT GRAPH')
        with self.assertRaisesRegex(ValueError, 'Graph does not match'):
            checked_graph(self.directory, NOW.date())
        inputs(self.directory)
        (self.directory / 'fixture.osm.pbf').write_bytes(b'CHANGED INPUT')
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            checked_graph(self.directory, NOW.date())

    def test_missing_data_does_not_contact_otp(self):
        gateway = Gateway(self.directory, 'http://127.0.0.1:1', clock=lambda: NOW)
        status, body = gateway.plan({'origin': {'latitude': 14.6, 'longitude': 121}, 'destination': {'latitude': 14.6043, 'longitude': 120.9884}})
        self.assertEqual(status, 503)
        self.assertIn('Historical routes', body['reason'])
        self.assertEqual(gateway.health()[0], 503)

    def test_real_trip_service_date_is_checked(self):
        manifest = inputs(self.directory)
        payload = itinerary()
        payload['data']['planConnection']['edges'][0]['node']['legs'][0]['serviceDate'] = '20200630'
        self.assertEqual(validate_itineraries(payload, manifest, NOW)['data']['planConnection']['edges'], [])

    def test_missed_departure_and_arrive_by_are_not_recommended(self):
        manifest = inputs(self.directory)
        self.assertEqual(validate_itineraries(itinerary(), manifest, NOW + timedelta(hours=1))['data']['planConnection']['edges'], [])
        self.assertEqual(validate_itineraries(itinerary(), manifest, NOW, NOW + timedelta(minutes=10))['data']['planConnection']['edges'], [])

    def test_request_uses_graphql_oneof_and_walking_connectors(self):
        args = variables({'origin': {'latitude': 14.6, 'longitude': 121}, 'destination': {'latitude': 14.6043, 'longitude': 120.9884}, 'arriveBy': (NOW + timedelta(hours=1)).isoformat()}, NOW)
        self.assertEqual(set(args['dateTime']), {'latestArrival'})
        self.assertEqual(args['origin']['location']['coordinate']['latitude'], 14.6)
        self.assertEqual(args['modes']['transit']['access'], ['WALK'])
        self.assertTrue(args['modes']['transitOnly'])
        self.assertEqual(args['modes']['transit']['transit'],
                         [{'mode': m} for m in ('RAIL', 'SUBWAY', 'TRAM')])

    def test_depart_now_request_allows_response_delivery_without_changing_route_times(self):
        body = {'origin': {'latitude': 14.6, 'longitude': 121},
                'destination': {'latitude': 14.6043, 'longitude': 120.9884}}
        args = variables(body, NOW)
        self.assertEqual(args['dateTime'],
                         {'earliestDeparture': (NOW + timedelta(seconds=60)).isoformat()})
        result = validate_itineraries(itinerary(), inputs(self.directory), NOW)
        # The lead is a requested departure time, not an invented travel duration.
        self.assertEqual(result['data']['planConnection']['edges'][0]['node']['duration'], 900)
        self.assertEqual(result['data']['planConnection']['edges'][0]['node']['start'],
                         (NOW + timedelta(minutes=5)).isoformat())

    def test_road_transit_requires_explicit_enablement_and_current_calendar(self):
        body = {'origin': {'latitude': 14.6, 'longitude': 121},
                'destination': {'latitude': 14.6043, 'longitude': 120.9884},
                'mode': 'Bus / UV'}
        gateway = Gateway(self.directory, 'http://127.0.0.1:1', clock=lambda: NOW)
        status, result = gateway.plan(body)
        self.assertEqual(status, 503)
        self.assertIn('rail planning only', result['reason'])
        args = variables(body, NOW, allow_road_transit=True)
        self.assertEqual(args['modes']['transit']['transit'], [{'mode': 'BUS'}])
        # Enabling a mode cannot bypass current data checks.
        enabled = Gateway(self.directory, 'http://127.0.0.1:1', clock=lambda: NOW,
                          allow_road_transit=True)
        self.assertEqual(enabled.plan(body)[0], 503)
        manifest = inputs(self.directory)
        bus = itinerary()
        bus['data']['planConnection']['edges'][0]['node']['legs'][0]['mode'] = 'BUS'
        self.assertEqual(validate_itineraries(copy.deepcopy(bus), manifest, NOW)
                         ['data']['planConnection']['edges'], [])
        self.assertEqual(len(validate_itineraries(copy.deepcopy(bus), manifest, NOW,
                             allowed_modes=('BUS',))['data']['planConnection']['edges']), 1)
        bus['data']['planConnection']['edges'][0]['node']['legs'][0]['serviceDate'] = '20200630'
        self.assertEqual(validate_itineraries(bus, manifest, NOW, allowed_modes=('BUS',))
                         ['data']['planConnection']['edges'], [])

    def test_http_gateway_to_synthetic_otp_contract(self):
        inputs(self.directory)
        captured = []
        class FakeOtp(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                captured.append(request)
                body = {'data': {'__typename': 'QueryType'}} if '__typename' in request['query'] else itinerary()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())
        def serve(handler):
            server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)
            return f'http://127.0.0.1:{server.server_port}'
        upstream = serve(FakeOtp)
        gateway = Gateway(self.directory, upstream, clock=lambda: NOW)
        base = serve(handler_for(gateway))
        with urlopen(base + '/health') as response:
            self.assertTrue(json.load(response)['ready'])
        query = {'origin': {'latitude': 14.6, 'longitude': 121}, 'destination': {'latitude': 14.6043, 'longitude': 120.9884}, 'mode': 'Transit'}
        request = Request(base + '/plan', json.dumps(query).encode(), {'Content-Type': 'application/json', 'Origin': 'http://localhost:5000'})
        with urlopen(request) as response:
            result = json.load(response)
            self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://localhost:5000')
        self.assertTrue(result['scheduleValidated'])
        self.assertEqual(len(result['data']['planConnection']['edges']), 1)
        self.assertIn('planConnection', captured[-1]['query'])
        self.assertNotIn('/plan?', captured[-1]['query'])
        self.assertNotIn('latestArrival', captured[-1]['variables']['dateTime'])
        self.assertNotIn('scheduleValidated', itinerary())


if __name__ == '__main__':
    unittest.main()
