"""Build a conservative network model from inspected OSM API snapshots.

No schedules, speeds, wait times or fares are derived from OSM tags. Only
consecutive catalog stations with a connected path on a directed route relation
become ride edges. Missing access points disable boarding/alighting, not passage.
"""
import argparse
import heapq
import json
import math
from pathlib import Path

ROUTES = {110418: 'LRT-1', 8000260: 'LRT-1', 110410: 'LRT-2',
          8000264: 'LRT-2', 109159: 'MRT-3', 8000253: 'MRT-3'}


def distance(a, b):
    lat1, lat2 = math.radians(a['lat']), math.radians(b['lat'])
    dlat, dlon = lat2 - lat1, math.radians(b['lon'] - a['lon'])
    return 6371000 * 2 * math.asin(min(1, math.sqrt(math.sin(dlat/2)**2 +
        math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2)))


def normalize(name):
    return ''.join(c.lower() for c in name if c.isalnum())


def connected_path(ways, nodes, start, end):
    adjacency = {}
    for way in ways:
        if way.get('tags', {}).get('railway') not in ('subway', 'light_rail', 'rail'):
            continue
        for a, b in zip(way['nodes'], way['nodes'][1:]):
            if a not in nodes or b not in nodes:
                continue
            meters = distance(nodes[a], nodes[b])
            adjacency.setdefault(a, []).append((b, meters))
            adjacency.setdefault(b, []).append((a, meters))
    queue, best, parent = [(0, start)], {start: 0}, {}
    while queue:
        cost, point = heapq.heappop(queue)
        if cost != best[point]:
            continue
        if point == end:
            result = [point]
            while result[-1] != start:
                result.append(parent[result[-1]])
            return list(reversed(result))
        for nxt, meters in adjacency.get(point, []):
            if cost + meters < best.get(nxt, math.inf):
                best[nxt] = cost + meters
                parent[nxt] = point
                heapq.heappush(queue, (cost + meters, nxt))
    return None


def build(source, catalog, reviewed, expires):
    def review(url):
        return {'source_url': url, 'reviewed_on': reviewed, 'valid_until': expires}
    areas, memberships = {}, {}
    for file in source.glob('area-*.json'):
        elements = json.loads(file.read_bytes())['elements']
        rid = int(file.stem[5:])
        area = next(e for e in elements if e['type'] == 'relation' and e['id'] == rid)
        areas[rid] = (area, elements)
        for member in area['members']:
            if member['type'] == 'node':
                memberships.setdefault(member['ref'], []).append(rid)
    lines = {line['name']: line for line in catalog['lines']}
    station_defs = {s['id']: s for line in lines.values() for s in line['stations']}
    aliases = {'yamahamonumento': 'monumento', 'roosevelt': 'fernandopoejr'}
    def identity(line, node):
        names = [node.get('tags', {}).get('name', '')]
        names += [areas[r][0].get('tags', {}).get('name', '') for r in memberships.get(node['id'], [])]
        for name in names:
            key = normalize(name)
            key = aliases.get(key, key)
            if 'cubao' in key:
                key = normalize('Araneta-Cubao' if line == 'MRT-3' else 'Araneta Center-Cubao')
            for stop in lines[line]['stations']:
                if normalize(stop['name']) == key:
                    return stop['id']
        return None
    stops, edges, excluded, snapshots = {}, [], [], []
    for rid, line in ROUTES.items():
        path = source / f'route-{rid}.json'
        elements = json.loads(path.read_bytes())['elements']
        rel = next(e for e in elements if e['type'] == 'relation' and e['id'] == rid)
        nodes = {e['id']: e for e in elements if e['type'] == 'node'}
        ways = {e['id']: e for e in elements if e['type'] == 'way'}
        track = [ways[m['ref']] for m in rel['members'] if m['type'] == 'way' and not m['role']]
        ordered = [(m, nodes[m['ref']]) for m in rel['members']
                   if m['type'] == 'node' and m['role'].startswith('stop')]
        snapshots.append({'relation': rid, 'version': rel['version'], 'timestamp': rel['timestamp']})
        for member, node in ordered:
            sid = identity(line, node)
            if not sid:
                excluded.append(f'{rid}: unmatched stop {node["id"]}')
                continue
            entrances = []
            for area_id in memberships.get(node['id'], []):
                for e in areas[area_id][1]:
                    tags = e.get('tags', {})
                    if e['type'] == 'node' and tags.get('access') not in ('no', 'private', 'delivery') and tags.get('entrance') not in ('emergency', 'service', 'exit') and tags.get('level', '0') == '0' and (tags.get('railway') == 'subway_entrance' or tags.get('entrance') in ('yes', 'main', 'secondary')):
                        entrances.append(e)
            entrances = [e for e in entrances if distance(node, e) < 450]
            entrances.sort(key=lambda e: (distance(node, e), e['id']))
            chosen = entrances[0] if entrances else node
            existing = stops.get(sid)
            if existing and (existing['boarding_allowed'] or not entrances):
                continue
            stops[sid] = {'id': sid, 'name': station_defs[sid]['name'],
                'access_coordinates': [chosen['lon'], chosen['lat']],
                'boarding_allowed': bool(entrances), 'alighting_allowed': bool(entrances),
                'access_kind': 'mapped_station_entrance' if entrances else 'track_stop_not_pedestrian_access',
                'review': review(f'https://www.openstreetmap.org/node/{chosen["id"]}')}
        for (am, a), (bm, b) in zip(ordered, ordered[1:]):
            sa, sb = identity(line, a), identity(line, b)
            if not sa or not sb or abs(station_defs[sa]['order'] - station_defs[sb]['order']) != 1:
                excluded.append(f'{rid}: nonconsecutive/unmatched {a["id"]}->{b["id"]}')
                continue
            route = connected_path(track, nodes, a['id'], b['id'])
            if not route:
                excluded.append(f'{rid}: disconnected track {sa}->{sb}')
                continue
            edges.append({'id': f'osm-{rid}-{a["id"]}-{b["id"]}', 'from': sa, 'to': sb,
                'line': line, 'direction': rel['tags']['to'], 'vehicle': 'RAIL',
                'line_uri': 'https://www.openstreetmap.org/relation/' + {'LRT-1': '8000262', 'LRT-2': '8000265', 'MRT-3': '8000255'}[line],
                'boarding_allowed': am['role'] != 'stop_exit_only',
                'alighting_allowed': bm['role'] != 'stop_entry_only',
                'review': review(f'https://www.openstreetmap.org/relation/{rid}'),
                'geometry': {'type': 'LineString', 'coordinates': [[nodes[n]['lon'], nodes[n]['lat']] for n in route]},
                'ride_seconds': None, 'boarding_wait_seconds': None, 'traveled_meters': None})
    transfers = []
    for t in catalog['walking_transfers']:
        for a, b in [(t['from'], t['to']), (t['to'], t['from'])]:
            if a in stops and b in stops and stops[a]['alighting_allowed'] and stops[b]['boarding_allowed']:
                transfers.append({'from': a, 'to': b, 'review': review('https://www.lrta.gov.ph/railway-operations/')})
    graph = {'status': 'reviewed_network_model',
        'notice': 'OSM network reference, not a timetable or live operating guarantee. Public entrance to platform paths are not modeled. No OSM duration/interval/fare tags are imported.',
        'license': 'ODbL 1.0', 'attribution': 'OpenStreetMap contributors',
        'source_snapshots': snapshots, 'stops': list(stops.values()), 'edges': edges, 'transfers': transfers,
        'excluded': excluded}
    return graph


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--reviewed-on', required=True)
    parser.add_argument('--valid-until', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    catalog = json.loads((root / 'assets/transit/rail_network_2026.json').read_text())
    graph = build(args.source_dir, catalog, args.reviewed_on, args.valid_until)
    (root / 'assets/transit/local_transit_graph.json').write_text(json.dumps(graph, indent=2) + '\n', encoding='utf-8')
    geo = {'type': 'FeatureCollection', 'attribution': 'OpenStreetMap contributors', 'license': 'ODbL 1.0',
        'features': [{'type': 'Feature', 'geometry': e['geometry'], 'properties': {k: e[k] for k in ('id', 'line', 'from', 'to', 'direction', 'review')}} for e in graph['edges']]}
    (root / 'assets/transit/rail_tracks.geojson').write_text(json.dumps(geo) + '\n', encoding='utf-8')
    print(json.dumps({'stops': len(graph['stops']), 'boardable': sum(s['boarding_allowed'] for s in graph['stops']), 'edges': len(graph['edges']), 'transfers': len(graph['transfers']), 'excluded': graph['excluded']}))
