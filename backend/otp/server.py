"""Local development gateway. OTP computes journeys; this server validates data
eligibility and proxies only the pinned GraphQL query. No student data is stored.
"""
import argparse
import json
import math
import os
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

from validate_data import MANILA, checked_graph

QUERY = (Path(__file__).parent / 'plan.graphql').read_text(encoding='utf-8')
RAIL_MODES = ('RAIL', 'SUBWAY', 'TRAM')
# Leave time for OTP computation and delivery to Flutter. Requesting exactly
# "now" can make an initial walking leg already departed on receipt, causing
# the otherwise valid itinerary to be rejected by freshness checks.
REQUEST_LEAD = timedelta(seconds=60)


def instant(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('A timezone is required.')
    return parsed


def variables(body, now, allow_road_transit=False):
    def location(name):
        value = body[name]
        for key, limit in (('latitude', 90), ('longitude', 180)):
            n = value[key]
            if isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) or abs(n) > limit:
                raise ValueError('Invalid journey coordinates.')
        return {'location': {'coordinate': {key: value[key] for key in ('latitude', 'longitude')}}}
    if body.get('mode', 'Transit') not in ('Transit', 'Train', 'Bus / UV'):
        raise ValueError('Walking and driving remain with the existing OSRM client.')
    arrive = instant(body['arriveBy']) if body.get('arriveBy') else None
    if arrive is not None and (arrive <= now or arrive > now + timedelta(days=7)):
        raise ValueError('Arrival target must be in the next seven days.')
    transit = {'access': ['WALK'], 'egress': ['WALK'], 'transfer': ['WALK']}
    if body.get('mode') == 'Train' or not allow_road_transit:
        if body.get('mode') == 'Bus / UV':
            raise ValueError('Road transit coverage has not been enabled.')
        transit['transit'] = [{'mode': m} for m in RAIL_MODES]
    elif body.get('mode') == 'Bus / UV':
        # This is a bus preference, never a guarantee of UV Express coverage.
        transit['transit'] = [{'mode': 'BUS'}]
    else:
        transit['transit'] = [{'mode': m} for m in (*RAIL_MODES, 'BUS')]
    return {
        'origin': location('origin'), 'destination': location('destination'),
        'dateTime': {'latestArrival': arrive.isoformat()} if arrive else {'earliestDeparture': (now + REQUEST_LEAD).isoformat()},
        'modes': {'transitOnly': True, 'transit': transit},
    }


def validate_itineraries(payload, manifest, now, arrive_by=None, allowed_modes=RAIL_MODES):
    if payload.get('errors'):
        raise ValueError('OTP GraphQL query failed. No transit ETA is confirmed.')
    connection = (payload.get('data') or {}).get('planConnection')
    if not isinstance(connection, dict):
        raise ValueError('OTP returned no journey connection.')
    accepted = []
    for edge in connection.get('edges') or []:
        try:
            node = edge['node']
            start, end = instant(node['start']), instant(node['end'])
            if start < now or end <= start or (arrive_by and end > arrive_by):
                continue
            rides = [leg for leg in node['legs'] if leg.get('transitLeg') is True]
            if not rides:
                continue
            for leg in rides:
                if leg.get('mode') not in allowed_modes:
                    raise ValueError('Itinerary contains a mode outside the reviewed routing scope.')
                fid, tid = leg['trip']['gtfsId'].split(':', 1)
                feed = manifest['feeds'][fid]
                service = feed['trip_services'][tid]
                if leg['serviceDate'] not in feed['service_dates'][service]:
                    raise ValueError('Itinerary uses a service outside its source calendar.')
                if leg['serviceDate'] > feed['valid_until'].replace('-', ''):
                    raise ValueError('Service review expired.')
            accepted.append(edge)
        except (KeyError, ValueError, TypeError):
            continue
    connection['edges'] = accepted
    return payload


class Gateway:
    def __init__(self, directory, otp_url, clock=None, allow_road_transit=False):
        self.directory, self.otp_url = directory, otp_url
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.allow_road_transit = allow_road_transit

    def graphql(self, query, args=None):
        request = Request(self.otp_url, json.dumps({'query': query, 'variables': args or {}}).encode(), {'Content-Type': 'application/json'})
        with urlopen(request, timeout=20) as response:
            return json.load(response)

    def health(self):
        try:
            checked_graph(self.directory, self.clock().astimezone(MANILA).date())
            result = self.graphql('query TamarawHealth { __typename }')
            if result.get('errors') or not (result.get('data') or {}).get('__typename'):
                raise ValueError('OTP GraphQL is unavailable.')
            return 200, {'ready': True, 'otpVersion': '2.8.1', 'timing': 'scheduled'}
        except (OSError, ValueError, KeyError, URLError):
            return 503, {'ready': False, 'reason': 'A validated current GTFS/OSM graph and running OTP server are required. Historical routes cannot supply current transit ETAs.'}

    def plan(self, body):
        now = self.clock()
        if body.get('mode') == 'Bus / UV' and not self.allow_road_transit:
            return 503, {'reason': 'This provider currently supports rail planning only. Current bus/jeepney datasets must be reviewed before road transit is enabled.'}
        try:
            args = variables(body, now, self.allow_road_transit)
        except (KeyError, ValueError, TypeError):
            return 400, {'reason': 'Use valid origin/destination coordinates and a future arrival target within seven days.'}
        try:
            manifest = checked_graph(self.directory, now.astimezone(MANILA).date())
        except (OSError, ValueError, KeyError) as error:
            return 503, {'reason': str(error)}
        try:
            result = validate_itineraries(self.graphql(QUERY, args), manifest, now,
                instant(args['dateTime']['latestArrival']) if 'latestArrival' in args['dateTime'] else None,
                allowed_modes=tuple(mode['mode'] for mode in args['modes']['transit']['transit']))
            result['scheduleValidated'] = True
            result['generatedAt'] = now.isoformat()
            if not result['data']['planConnection']['edges']:
                result['reason'] = 'No current scheduled transit connection was returned for these locations and this time.'
            return 200, result
        except (OSError, URLError, ValueError, KeyError, TypeError):
            return 502, {'reason': 'The current transit routing service could not return a validated itinerary. Walking and driving estimates remain independent.'}


def handler_for(gateway):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Do not log coordinates or request bodies.

        def reply(self, status, payload=None):
            self.send_response(status)
            # Local dev only. Production needs HTTPS, authentication and quotas.
            origin = self.headers.get('Origin', '')
            if origin.startswith(('http://localhost:', 'http://127.0.0.1:')):
                self.send_header('Access-Control-Allow-Origin', origin)
                self.send_header('Vary', 'Origin')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            if payload is not None:
                self.wfile.write(json.dumps(payload, allow_nan=False).encode())

        def do_OPTIONS(self):
            self.reply(204)

        def do_GET(self):
            self.reply(*gateway.health()) if self.path == '/health' else self.reply(404, {'reason': 'Not found'})

        def do_POST(self):
            if self.path != '/plan':
                self.reply(404, {'reason': 'Not found'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 16384:
                    raise ValueError('Invalid request size')
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('Expected an object')
            except (ValueError, TypeError):
                self.reply(400, {'reason': 'Invalid JSON request'})
                return
            self.reply(*gateway.plan(body))
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, default=Path(__file__).parent / 'data')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8090)
    parser.add_argument('--otp', default='http://127.0.0.1:8080/otp/gtfs/v1')
    args = parser.parse_args()
    print(f'Gateway listening on {args.host}:{args.port}; /health reports actual readiness.', flush=True)
    ThreadingHTTPServer((args.host, args.port), handler_for(Gateway(
        args.data, args.otp,
        allow_road_transit=os.environ.get('OTP_ENABLE_ROAD_TRANSIT', 'false').lower() == 'true',
    ))).serve_forever()
