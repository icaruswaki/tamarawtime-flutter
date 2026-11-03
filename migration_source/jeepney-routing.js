/* Tamaraw Time: OSM-backed jeepney discovery.
 * No generated/hard-coded routes, stops, fares, or transit ETA.
 * OpenStreetMap data documents mapped service, NOT real-time operations.
 */
(function(root){
 'use strict';
 const endpoints=['https://overpass-api.de/api/interpreter','https://overpass.kumi.systems/api/interpreter'];
 const detailBase='https://openstreetmap.tools/public_transport_geojson/api/route/';
 const cache=new Map();
 const RAD=Math.PI/180;
 const distance=(a,b)=>{
  const p=(b.lat-a.lat)*RAD, l=(b.lng-a.lng)*RAD;
  const x=Math.sin(p/2)**2+Math.cos(a.lat*RAD)*Math.cos(b.lat*RAD)*Math.sin(l/2)**2;
  return 12742000*Math.asin(Math.min(1,Math.sqrt(x)));
 };
 const withinMetro=p=>Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&p.lat>=14.30&&p.lat<=14.92&&p.lng>=120.85&&p.lng<=121.22;
 const jeepneyTag=tags=>{
  if(!tags||!['bus','jeepney','share_taxi'].includes(tags.route))return false;
  const haystack=[tags.bus,tags.vehicle,tags['vehicle:type'],tags['service'],tags['route:type'],tags.name,tags.description,tags.network].join(' ').toLowerCase();
  // Philippine OSM routes use route=bus for jeepneys, buses and UV Express.
  if(/uv express|uvx|van service|p2p bus|edsa carousel/.test(haystack))return false;
  return tags.route==='jeepney'||/jeepney|jeep|share_taxi|\bpuj\b/.test(haystack)||/^T\d{2,4}[A-Z]?$/i.test(String(tags.ref||'').trim());
 };
 async function request(url,opts={},ms=13000){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),ms);
  try{const response=await fetch(url,{...opts,signal:controller.signal});if(!response.ok)throw new Error('Source returned HTTP '+response.status);return await response.json();}
  finally{clearTimeout(timer);}
 }
 async function candidateRelations(origin){
  const query=`[out:json][timeout:16];relation(around:1400,${origin.lat.toFixed(5)},${origin.lng.toFixed(5)})["type"="route"]["route"~"^(bus|jeepney|share_taxi)$"];out tags;`;
  let lastError;
  for(const endpoint of endpoints){
   try{
    const data=await request(endpoint,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},body:new URLSearchParams({data:query}).toString()},19000);
    if(!Array.isArray(data.elements))throw new Error('Invalid OSM response');
    return data.elements.filter(item=>item.type==='relation'&&Number.isInteger(item.id)&&jeepneyTag(item.tags)).slice(0,22);
   }catch(error){lastError=error;}
  }
  throw new Error('Public map-data service unavailable: '+(lastError?.message||'please retry later'));
 }
 function toStop(stop){
  const lat=Number(stop.lat),lng=Number(stop.lon??stop.lng);
  if(!Number.isFinite(lat)||!Number.isFinite(lng)||lat<-90||lat>90||lng<-180||lng>180)return null;
  return {lat,lng,name:String(stop.name||'Mapped stop').slice(0,100)};
 }
 function selectStops(stops,origin,dest){
  // Ordered stops belong to a single OSM direction relation.
  const list=(Array.isArray(stops)?stops:[]).map(toStop).filter(Boolean);
  if(list.length<2)return null;
  let best=null;
  for(let i=0;i<list.length-1;i++){
   const access=distance(origin,list[i]);if(access>900)continue;
   for(let j=i+1;j<list.length;j++){
    const exit=distance(dest,list[j]);if(exit>900)continue;
    const direct=distance(list[i],list[j]);if(direct<300)continue;
    // Avoid reversing direction or recommending a trip away from the destination.
    // Near-origin boarding and near-campus alighting must be materially better.
    if(access+exit+150>=distance(origin,list[j])+distance(dest,list[i]))continue;
    const candidate={board:list[i],alight:list[j],boardIndex:i,alightIndex:j,accessMeters:Math.round(access),exitMeters:Math.round(exit),score:access+exit};
    if(!best||candidate.score<best.score)best=candidate;
   }
  }
  return best;
 }
 function toRoute(data,relation,origin,dest){
  if(!data||!Array.isArray(data.stops))return null;
  const line=data.geojson?.features?.find(feature=>feature.geometry?.type==='LineString'&&Array.isArray(feature.geometry.coordinates)&&feature.geometry.coordinates.length>1)?.geometry.coordinates;
  if(!line)return null;
  const points=line.map(([lng,lat])=>[Number(lat),Number(lng)]).filter(([lat,lng])=>Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180);
  if(points.length<2)return null;
  const stopSelection=selectStops(data.stops,origin,dest);
  if(!stopSelection)return null;
  const props=relation.tags||{};
  return {id:relation.id,name:String(data.name||props.name||'Mapped jeepney route').slice(0,160),ref:String(data.ref||props.ref||'').slice(0,25),points,...stopSelection,source:'OpenStreetMap route relation',sourceUrl:`https://www.openstreetmap.org/relation/${relation.id}`};
 }
 async function findRoutes(origin,dest){
  if(!withinMetro(origin)||!withinMetro(dest))return {status:'outside',routes:[],message:'Jeepney discovery is currently limited to Metro Manila. Use another planner for this trip.'};
  const cacheKey=[origin.lat.toFixed(3),origin.lng.toFixed(3),dest.lat.toFixed(3),dest.lng.toFixed(3)].join(':');
  const saved=cache.get(cacheKey);if(saved&&Date.now()-saved.at<120000)return saved.result;
  const relations=await candidateRelations(origin);
  if(!relations.length)return {status:'none',routes:[],message:'No clearly identified jeepney route relations were found near your position in OpenStreetMap.'};
  const found=[];
  // Small batches protect community-hosted services and limit response time.
  // This is not exhaustive public-transit routing.
  let failed=0;
  for(let i=0;i<Math.min(12,relations.length)&&found.length<3;i+=3){
   const batch=relations.slice(i,i+3);
   const outcomes=await Promise.all(batch.map(async relation=>{
    try{const data=await request(detailBase+relation.id,{},8500);return {route:toRoute(data,relation,origin,dest)};}
    catch(_error){return {failed:true};}
   }));
   for(const outcome of outcomes){if(outcome.failed)failed++;if(outcome.route)found.push(outcome.route);}
  }
  found.sort((a,b)=>a.score-b.score);
  const result=found.length?{status:'found',routes:found,message:'Mapped route candidates found. Validate stops and current operation before boarding.'}:{status:failed>=Math.min(12,relations.length)?'error':'none',routes:[],message:'No one-seat jeepney connection with mapped boarding/alighting stops was confirmed near both points. Some routes or stops may be missing from OpenStreetMap.'};
  if(result.status!=='error')cache.set(cacheKey,{result,at:Date.now()});
  return result;
 }

 // Optional real pedestrian connectors. This service only plans walking; it does not
 // estimate jeepney travel time, frequency, fare, or whether a route is operating.
 async function pedestrianLeg(from,to){
  if(distance(from,to)<25)return {status:'short',distanceMeters:Math.round(distance(from,to)),minutes:0,points:[[from.lat,from.lng],[to.lat,to.lng]]};
  const url='https://routing.openstreetmap.de/routed-foot/route/v1/driving/'+
    [from.lng,from.lat].join(',')+';'+[to.lng,to.lat].join(',')+'?overview=full&geometries=geojson';
  try{
   const result=await request(url,{},11000),route=result.routes?.[0];
   if(!route?.geometry?.coordinates?.length||!Number.isFinite(route.distance))throw Error('No pedestrian route');
   // Pedestrian service duration is a model estimate, never a live traffic ETA.
   return {status:'routed',distanceMeters:Math.round(route.distance),minutes:Math.max(1,Math.ceil(route.duration/60)),points:route.geometry.coordinates.map(c=>[c[1],c[0]])};
  }catch(_){return {status:'unavailable',distanceMeters:null,minutes:null,points:[]};}
 }
 async function planWalkingLegs(origin,dest,route){
  const [access,exit]=await Promise.all([pedestrianLeg(origin,route.board),pedestrianLeg(route.alight,dest)]);
  return {access,exit,knownWalkingMinutes:access.minutes!==null&&exit.minutes!==null?access.minutes+exit.minutes:null};
 }
 const api={findRoutes,jeepneyTag,selectStops,toRoute,distance,withinMetro,pedestrianLeg,planWalkingLegs};
 root.JeepneyRouting=api;
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
