const assert=require('node:assert/strict');
const J=require('./jeepney-routing.js');
const start={lat:14.600,lng:120.980},boarding={lat:14.6004,lng:120.9804},alight={lat:14.605,lng:120.988},destination={lat:14.6053,lng:120.9884};
const oldFetch=global.fetch;let n=0;
global.fetch=async (url)=>{n++;assert(String(url).includes('routed-foot'));return {ok:true,json:async()=>({routes:[{distance:410,duration:305,geometry:{coordinates:[[120.98,14.6],[120.9804,14.6004]]}}]})};};
(async()=>{const plan=await J.planWalkingLegs(start,destination,{board:boarding,alight});assert.equal(plan.access.status,'routed');assert.equal(plan.exit.status,'routed');assert.equal(plan.knownWalkingMinutes,12);assert.equal(n,2);
 global.fetch=async()=>{throw Error('offline')};const offline=await J.planWalkingLegs(start,destination,{board:boarding,alight});assert.equal(offline.access.status,'unavailable');assert.equal(offline.knownWalkingMinutes,null);console.log('PASS: pedestrian itineraries, routing geometry, partial duration, service fallback');})().finally(()=>{global.fetch=oldFetch});
