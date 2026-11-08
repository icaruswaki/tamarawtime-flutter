#!/usr/bin/env python3
"""Local historical Sakay.ph GTFS -> compact route/stop JSON for Tamaraw Time.
Download and review license yourself; this tool makes no external requests.
Examples:
 python tools/import_sakay_gtfs.py --input path/to/sakay-gtfs.zip --output data/sakay_historical.json --accept-license
 python tools/import_sakay_gtfs.py --input path/to/extracted-gtfs --output data/sakay_historical.json --accept-license
"""
import argparse,csv,io,json,zipfile,math,hashlib
from pathlib import Path
from collections import defaultdict

def read_gtfs(source, filename):
    if source.is_dir():
        path=source/filename
        if not path.is_file(): return []
        raw=path.read_bytes().decode('utf-8-sig')
    else:
        with zipfile.ZipFile(source) as z:
            matches=[x for x in z.namelist() if x.rsplit('/',1)[-1]==filename]
            if len(matches)>1: raise ValueError('Ambiguous GTFS file: '+filename)
            match=matches[0] if matches else None
            if match is None:return []
            raw=z.read(match).decode('utf-8-sig')
    return list(csv.DictReader(io.StringIO(raw)))

def convert(source):
    routes=read_gtfs(source,'routes.txt')
    stops=read_gtfs(source,'stops.txt')
    trips=read_gtfs(source,'trips.txt')
    stop_times=read_gtfs(source,'stop_times.txt')
    if not routes or not stops or not trips or not stop_times:
        raise ValueError('GTFS requires routes.txt, stops.txt, trips.txt and stop_times.txt')
    stop_dict={s['stop_id']:s for s in stops if s.get('stop_id')}
    first_trip={}
    for t in trips:
        if t.get('route_id') and t.get('trip_id'):
            first_trip.setdefault(t['route_id'],t['trip_id'])
    times=defaultdict(list)
    valid=set(first_trip.values())
    for s in stop_times:
        if s.get('trip_id') in valid:
            try: sequence=int(s.get('stop_sequence') or '')
            except (TypeError,ValueError): continue
            if sequence<0: continue
            times[s['trip_id']].append({**s,'stop_sequence':sequence})
    for parts in times.values():
        parts.sort(key=lambda s:int(s.get('stop_sequence') or 0))
    result=[]
    counts=defaultdict(int)
    for r in routes:
        rid=r.get('route_id','')
        if not rid: continue
        # Sakay feed uses LTFRB_PUJ for many historical jeepney routes.
        is_jeepney=('PUJ' in rid.upper() or 'JEEP' in (r.get('route_long_name','')+' '+r.get('route_short_name','')).upper())
        mode='jeepney_reference' if is_jeepney else 'rail_reference' if r.get('route_type') in ('0','1','2') else 'road_transit_unclassified'
        trip_id=first_trip.get(rid)
        ordered=times.get(trip_id,[]) if trip_id else []
        stop_list=[]
        for step in ordered:
            s=stop_dict.get(step.get('stop_id',''))
            if not s: continue
            def floating(k):
                try:
                    value=float(s[k])
                    limit=90 if k=='stop_lat' else 180
                    return value if math.isfinite(value) and abs(value)<=limit else None
                except (ValueError,KeyError,TypeError):return None
            lat,lon=floating('stop_lat'),floating('stop_lon')
            if lat is None or lon is None: lat,lon=None,None
            stop_list.append({'stop_id':s['stop_id'],'name':s.get('stop_name') or s['stop_id'],'lat':lat,'lon':lon,'sequence':int(step.get('stop_sequence') or 0),'coordinate_status':'historical_unreviewed'})
        result.append({'id':rid,'name':r.get('route_long_name') or r.get('route_short_name') or rid,'short_name':r.get('route_short_name',''),'description':r.get('route_desc',''),'mode':mode,'historical_only':True,'validated_current_operation':False,'ordered_stops_from_one_sample_trip':stop_list,'trip_example_id':trip_id})
        counts[mode]+=1
    provenance={}
    if source.is_file(): provenance['archive_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
    feed=read_gtfs(source,'feed_info.txt')
    if feed: provenance['feed_info']=feed[0]
    return {'schema_version':1,'source':'Sakay.ph historical GTFS (user-supplied archive)','source_url':'https://github.com/sakayph/gtfs','license_url':'https://github.com/sakayph/gtfs/blob/master/LICENSE.md','license_asset':'assets/transit/sakay_gtfs_LICENSE.md','provenance':provenance,'status':'historical_reference_only','warning':'Do not show as currently operating or calculate live arrivals; route endpoints and stops require verification. Example stop sequences are from one trip and may not represent variants.','counts_by_mode':dict(counts),'routes':result}

def compact_catalog(doc):
    """Deduplicate named stop records, preserving each trip's ordered visits."""
    stops={}
    routes=[]
    for route in doc['routes']:
        visits=[]
        for stop in route['ordered_stops_from_one_sample_trip']:
            stops[stop['stop_id']]={k:v for k,v in stop.items() if k not in ('stop_id','sequence')}
            visits.append({'stop_id':stop['stop_id'],'sequence':stop['sequence']})
        routes.append({**route,'ordered_stops_from_one_sample_trip':visits})
    return {**doc,'schema_version':2,'stops':stops,'routes':routes}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    ap.add_argument('--accept-license',action='store_true',help='Confirm that you reviewed and accept the source GTFS license')
    args=ap.parse_args()
    if not args.accept_license:
        ap.error('Review https://github.com/sakayph/gtfs/blob/master/LICENSE.md then rerun with --accept-license')
    doc=compact_catalog(convert(args.input))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n',encoding='utf-8')
    print(f"Wrote {len(doc['routes'])} historical routes to {args.output}")
    print('Classifications:',dict(doc['counts_by_mode']))
    print('Unique sample stops:',len({s['stop_id'] for r in doc['routes'] for s in r['ordered_stops_from_one_sample_trip']}))
    print('Not a live/verified operating network.')
if __name__=='__main__':main()
