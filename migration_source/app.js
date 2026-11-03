'use strict';
/* Tamaraw Time v4 — focused attendance/commute planner.
   Student data is stored in Supabase. No planner data is written to localStorage.
   GPS is kept only in memory and is never uploaded to Tamaraw Time's database. */
const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const campusOptions = {
 'FEU Tech':'FEU Institute of Technology, P. Paredes Street, Manila, Philippines',
 'FEU Manila':'Far Eastern University, Nicanor Reyes Street, Manila, Philippines',
 'FEU Diliman':'Far Eastern University Diliman, Quezon City, Philippines',
 'FEU Alabang':'Far Eastern University Alabang, Muntinlupa, Philippines'
};
const defaults = {classes:[],tasks:[],settings:{name:'Tamaraw',campus:'FEU Tech',travel:55,prep:45,buffer:15,mode:'Transit',theme:'forest'},onboarding:{finished:false}};
let state = structuredClone(defaults), currentPage='home', loadedUser=null, authCounter=0;
let writeQueue = Promise.resolve(), tutorialIndex=0, gpsPosition=null;
let mapOriginText='', shownMapSignature='';
let liveMap=null, liveMarker=null, campusMarker=null, liveRoute=null, gpsWatchId=null, routeSeq=0, lastRouteAt=0;
let mapResizeObserver=null, mapAnimationCleanup=null, mapResizeTimers=[];
let activeRouteEstimate=null, routeRequestBusy=false, lastRouteOrigin=null, autoRouteTimer=null;
let jeepneyOptions=[], jeepneyMarkers=[], jeepneyWalkLayers=[], jeepneySelectionSerial=0, jeepneyRequestSerial=0, jeepneyRequestBusy=false;
const themeNames={forest:'FEU Forest',ocean:'Coastal Blue',sunset:'Golden Hour',night:'Midnight'};
function currentTravel(c,mode=state.settings.mode){
 const campus=c?.campus||state.settings.campus;
 if(activeRouteEstimate && activeRouteEstimate.campus===campus && activeRouteEstimate.mode===mode && Date.now()-activeRouteEstimate.at<15*60*1000)return activeRouteEstimate.minutes;
 return Math.max(1,Number(state.settings.travel)||55);
}
function applyTheme(name){document.documentElement.dataset.theme=themeNames[name]?name:'forest';}
function effectiveMode(c){return activeRouteEstimate && activeRouteEstimate.campus===(c?.campus||state.settings.campus)&&Date.now()-activeRouteEstimate.at<15*60*1000?activeRouteEstimate.mode:state.settings.mode;}
function currentDeparture(c,travel=currentTravel(c,effectiveMode(c)),buffer=state.settings.buffer,prep=state.settings.prep){return departure(c,travel,buffer,prep);}
function distanceMeters(a,b){const r=Math.PI/180,dl=(b.lng-a.lng)*r,dp=(b.lat-a.lat)*r,phi1=a.lat*r,phi2=b.lat*r,x=Math.sin(dp/2)**2+Math.cos(phi1)*Math.cos(phi2)*Math.sin(dl/2)**2;return 12742000*Math.asin(Math.sqrt(x));}
const campusCoords={'FEU Tech':[14.6043,120.9884],'FEU Manila':[14.6046,120.9867],'FEU Diliman':[14.6994,121.0648],'FEU Alabang':[14.4195,121.0438]};
const uid = () => globalThis.crypto?.randomUUID?.() ?? `tt-${Date.now()}-${Math.random().toString(36).slice(2)}`;
const fmtDate = date => date.toLocaleDateString('en-PH',{month:'short',day:'numeric',year:'numeric'});
const ampm = time => {const [h,m]=String(time).split(':').map(Number);return `${h%12||12}:${String(m).padStart(2,'0')} ${h>=12?'PM':'AM'}`;};
const timeMinutes = time => {const [h,m]=String(time).split(':').map(Number);return h*60+m;};
const minsToTime = val => {const n=(val%1440+1440)%1440;return ampm(`${String(Math.floor(n/60)).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`);};
const formatClock = () => {
 const now=new Date();
 $('#today').textContent=now.toLocaleDateString('en-PH',{weekday:'short',month:'short',day:'numeric',year:'numeric',timeZone:'Asia/Manila'});
 $('#clock').textContent=now.toLocaleTimeString('en-PH',{hour:'numeric',minute:'2-digit',second:'2-digit',hour12:true,timeZone:'Asia/Manila'});
 refreshDepartureCountdown();
};
function nextClassDate(c){
 const now=new Date(), wd=Number(c.day), delta=(wd-now.getDay()+7)%7;
 const d=new Date(now.getFullYear(),now.getMonth(),now.getDate()+delta);
 const [h,m]=c.time.split(':').map(Number);d.setHours(h,m,0,0);
 if(d<=now)d.setDate(d.getDate()+7);
 return d;
}
const upcoming = () => state.classes.map(c=>({...c,when:nextClassDate(c)})).sort((a,b)=>a.when-b.when);
function refreshDepartureCountdown(){
 const node=$('#leave-countdown');if(!node)return;
 const next=upcoming()[0];if(!next){node.textContent='Add your first class to calculate your leave time.';return;}
 const departAt=next.when.getTime()-(currentTravel(next,effectiveMode(next))+Number(state.settings.buffer||0))*60000;
 const seconds=Math.ceil((departAt-Date.now())/1000);
 if(seconds>0){const h=Math.floor(seconds/3600),m=Math.ceil((seconds%3600)/60);node.textContent=h?`⏳ Leave in ${h} hr ${m} min`:`⏳ Leave in ${m} min`;node.dataset.urgency=seconds<1800?'soon':'normal';}
 else{const elapsed=Math.ceil(-seconds/60);node.textContent=elapsed<180?`⚠️ Recommended departure ${elapsed} min ago`:'⚠️ Scheduled departure time passed';node.dataset.urgency='late';}
}

const departure = (c,travel=state.settings.travel,buffer=state.settings.buffer,prep=state.settings.prep) => {
 const start=timeMinutes(c.time);return {leave:minsToTime(start-travel-buffer),wake:minsToTime(start-travel-buffer-prep),arrive:minsToTime(start-buffer)};
};
function toast(text){const el=$('#toast');el.textContent=text;el.style.display='block';clearTimeout(window.__ttToast);window.__ttToast=setTimeout(()=>el.style.display='none',3500);}
function snapshot(){return {classes:structuredClone(state.classes),tasks:structuredClone(state.tasks),settings:structuredClone(state.settings),onboarding:structuredClone(state.onboarding)};}
function saveToCloud(eventType){
 const data=snapshot();
 const job=writeQueue.catch(()=>{}).then(async()=>{
  await CloudStore.savePayload(data);
  if(eventType)await CloudStore.logEvent(eventType);
 });
 writeQueue=job;job.catch(err=>toast('Could not save online: '+(err.message||err)));
 return job;
}
async function logActivity(type){
 try{await writeQueue.catch(()=>{});await CloudStore.logEvent(type);}catch(err){toast('Activity log failed: '+(err.message||err));}
}
const tutorialSteps=[
 {title:'Your day, already planned',label:'01 · DASHBOARD',tip:'Upcoming class and departure time appear automatically.',scene:'dashboard'},
 {title:'Choose your class time',label:'02 · CLASS SCHEDULE',tip:'Use the visible AM/PM buttons when adding your subject.',scene:'schedule'},
 {title:'Find your best departure',label:'03 · AUTOMATIC TIMING',tip:'Arrival buffer + travel estimate + get-ready time = your routine.',scene:'departure'},
 {title:'See your commute live',label:'04 · GPS TRACKING',tip:'Allow location permission to see a moving pin and automatic walking/driving estimates.',scene:'map'},
 {title:'Make Tamaraw Time yours',label:'05 · PERSONALIZE',tip:'Change your color theme any time under Settings.',scene:'theme'}
];
function tutorialVisual(scene){
 if(scene==='dashboard')return `<div class="visual-demo visual-dashboard"><div class="visual-header"><i></i><span>Good morning, Tamaraw!</span><b>☀</b></div><div class="visual-tiles"><div><small>NEXT CLASS</small><strong>Data Structures</strong><em>9:00 AM</em></div><div><small>LEAVE BY</small><strong class="visual-big">7:50 AM</strong><em>Calculated for you</em></div></div><div class="visual-progress"><span></span></div></div>`;
 if(scene==='schedule')return `<div class="visual-demo visual-schedule"><div class="visual-header">📚 <span>New class</span></div><div class="visual-input">Data Structures</div><div class="visual-switch"><span>9 : 00</span><span class="visual-chip selected">AM</span><span class="visual-chip">PM</span></div><div class="visual-input">Monday · FEU Tech</div></div>`;
 if(scene==='departure')return `<div class="visual-demo visual-depart"><div class="visual-equation"><span>Class<br><b>9:00 AM</b></span><span>−</span><span>Travel<br><b>55 min</b></span><span>−</span><span>Buffer<br><b>15 min</b></span></div><div class="visual-answer">🚶 LEAVE BY <strong>7:50 AM</strong></div><div class="visual-prepare">☀ GET READY <b>7:05 AM</b></div></div>`;
 if(scene==='map')return `<div class="visual-demo visual-map"><div class="visual-street street-a"></div><div class="visual-street street-b"></div><div class="visual-street street-c"></div><div class="visual-map-route"></div><span class="visual-location">●</span><span class="visual-campus">🎓</span><div class="visual-map-label">📍 Live commute</div></div>`;
 return `<div class="visual-demo visual-themes"><div class="visual-header">🎨 <span>Choose your colors</span></div><div class="visual-theme-sample forest">Forest</div><div class="visual-theme-sample ocean">Ocean</div><div class="visual-theme-sample sunset">Sunset</div><div class="visual-theme-sample night">Night</div></div>`;
}
function drawTutorial(){
 const step=tutorialSteps[tutorialIndex];
 $('#tutorial-step').innerHTML=`<div class="tutorial-visual-wrap" key="${tutorialIndex}">${tutorialVisual(step.scene)}</div><div class="tutorial-caption"><div class="tutorial-tag">${esc(step.label)}</div><h2 id="tutorial-title">${esc(step.title)}</h2><p>${esc(step.tip)}</p></div>`;
 $('#tutorial-dots').innerHTML=tutorialSteps.map((_,i)=>`<span class="${i===tutorialIndex?'active':''}"></span>`).join('');
 $('#tutorial-count').textContent=`${tutorialIndex+1} / ${tutorialSteps.length}`;
 $('#tutorial-prev').disabled=tutorialIndex===0;
 $('#tutorial-next').textContent=tutorialIndex===tutorialSteps.length-1?'Start using the app →':'Next →';
}
function showTutorial(){tutorialIndex=0;drawTutorial();if(!$('#tutorial-dialog').open)$('#tutorial-dialog').showModal();}
function finishTutorial(){state.onboarding.finished=true;$('#tutorial-dialog').close();saveToCloud();}
const badge = label=>`<span class="badge">${esc(label)}</span>`;
const classCard = c => `<div class="item"><div><b>${esc(c.name)}</b><small>${esc(days[Number(c.day)])} · ${ampm(c.time)}–${ampm(c.end)} · ${esc(c.room||'Room not set')}</small><small>${esc(c.campus||state.settings.campus)}</small></div><div class="actions-inline"><button class="iconbutton" type="button" data-action="del-class" data-id="${esc(c.id)}" aria-label="Delete ${esc(c.name)}">×</button></div></div>`;
function navigate(next){if(currentPage==='commute'&&next!=='commute'){cleanupMapSizing();stopGps();++routeSeq;++jeepneyRequestSerial;jeepneyRequestBusy=false;clearJeepneyMap();if(liveMap){liveMap.remove();liveMap=null;}}
 currentPage=next;
 document.querySelectorAll('#nav button').forEach(b=>b.classList.toggle('active',b.dataset.page===next));
 const title={home:['Good day, '+state.settings.name+'! 👋','Focus on arriving to class on time.'],schedule:['Class Schedule','Your weekly class timetable.'],commute:['Commute Planner','Know when to get ready and when to leave.'],settings:['Settings','Adjust your punctuality preferences.']}[next];
 $('#page-title').textContent=title[0];$('#page-subtitle').textContent=title[1];
 $('#quick-add').hidden=next==='settings';
 render();
}
function render(){
 let html='';const next=upcoming()[0],recommendation=next?currentDeparture(next):null;
 if(currentPage==='home'){
  html=`<div class="grid three"><div class="card stat accent"><div class="label">NEXT CLASS</div><div class="value" style="font-size:25px">${next?esc(next.name):'No classes yet'}</div><div class="note">${next?`${esc(days[Number(next.day)])} · ${ampm(next.time)}`:'Add your first class to begin'}</div></div><div class="card stat"><div class="label">SUGGESTED LEAVE TIME</div><div class="value">${recommendation?recommendation.leave:'—'}</div><div class="note">${next?'Calculated from class start, journey and arrival buffer':'Once a class is scheduled'}</div></div><div class="card stat"><div class="label">TRAVEL ESTIMATE</div><div class="value">${esc(currentTravel(next,effectiveMode(next)))} <span style="font-size:17px">min</span></div><div class="note">${activeRouteEstimate&&next&&currentTravel(next,effectiveMode(next))===activeRouteEstimate.minutes?'Auto from GPS route':'Default estimate'} · ${esc(effectiveMode(next))}</div></div></div>
  <div class="section-head"><h2>Plan for punctuality</h2></div><div class="hero"><div><small>${next?'UPCOMING CLASS · '+esc(days[Number(next.day)]):'YOUR PUNCTUALITY ASSISTANT'}</small><h2>${recommendation?'Leave by '+recommendation.leave:'Add your schedule to start'}</h2><small>${recommendation?'Prepare by '+recommendation.wake+' · Aim to arrive '+recommendation.arrive:'Get a personalized departure recommendation'}</small><div id="leave-countdown" class="leave-countdown" aria-live="off"></div></div><button class="primary" data-action="go-commute">Plan my commute →</button></div>
  <div class="card" style="margin-top:21px"><div class="section-head" style="margin:0 0 8px"><h2>Upcoming classes</h2><button class="linkbtn" data-action="go-schedule">View schedule →</button></div>${upcoming().slice(0,4).map(classCard).join('')||'<div class="empty">Your class list is empty. Add a class to get started.</div>'}</div>`;
 }else if(currentPage==='schedule'){
  html=`<div class="section-head"><h2>Weekly class schedule</h2><button class="primary" data-action="add-class">+ Add class</button></div><div class="card">${state.classes.length?[...state.classes].sort((a,b)=>Number(a.day)-Number(b.day)||a.time.localeCompare(b.time)).map(classCard).join(''):'<div class="empty">No classes saved yet.</div>'}</div><div class="alert" style="margin-top:18px">Add your real class times. This app does not automatically import FEU attendance records.</div>`;
 }else if(currentPage==='commute'){
  const opts=upcoming().map(c=>`<option value="${esc(c.id)}">${esc(c.name)} — ${esc(days[Number(c.day)])} ${ampm(c.time)}</option>`).join('');
  html=`<div class="grid two"><div class="card"><h2>Plan your next trip</h2><div class="field"><label for="class-select">Choose a class</label><select id="class-select">${opts||'<option value="">Add a class first</option>'}</select></div><div class="field"><label for="trip-mode">Travel mode</label><select id="trip-mode">${['Transit','Jeepney','Train','Bus / UV','Driving','Walking'].map(m=>`<option ${state.settings.mode===m?'selected':''}>${m}</option>`).join('')}</select></div><div class="field"><label for="trip-travel">Journey time (minutes) <span class="auto-indicator" id="eta-status">${activeRouteEstimate?'Auto from GPS':'Fallback estimate'}</span></label><input id="trip-travel" type="number" min="1" max="480" value="${currentTravel(upcoming()[0])}"><p class="mini muted">Walking/driving route times update automatically. Jeepney mode shows mapped OSM routes and stops when available, but uses your editable travel estimate (no live jeepney ETA).</p></div><div class="formgrid"><div class="field"><label for="trip-prep">Preparation minutes</label><input id="trip-prep" type="number" min="0" max="240" value="${state.settings.prep}"></div><div class="field"><label for="trip-buffer">Arrival buffer minutes</label><input id="trip-buffer" type="number" min="0" max="120" value="${state.settings.buffer}"></div></div><button class="secondary" data-action="save-commute">Save these as default settings</button><div style="margin-top:22px"><h2>Your recommended routine</h2><div id="commute-output"></div></div></div>
  <div class="card map-card"><div class="section-head" style="margin:0 0 8px"><h2>Live GPS & commute routes</h2>${badge('OpenStreetMap')}</div><p class="mini muted">Track your position on the map while this page is open. Select a transport option to see what routing information is available.</p><div class="map-buttons"><button class="primary" type="button" data-action="location">◎ Start live GPS</button><button class="secondary" type="button" data-action="stop-location">Stop tracking</button><button class="secondary" type="button" data-action="show-map">Find route</button></div><p class="mini muted" id="gps-output" role="status">GPS is off. Location permission is required to track you.</p><div id="map-host" class="map-host" aria-label="Interactive OpenStreetMap"></div><div id="route-info" class="route-info" aria-live="polite"></div><div class="transport-notes"><h3>Commute options</h3><p class="mini muted">Jeepney: search OpenStreetMap route relations near your GPS position and campus. Direct routes require mapped stops in the correct order; service availability is NOT live-verified. For other transit modes, see Sakay.ph. Walking/driving use a public routing service with no live traffic data.</p><a href="https://sakay.ph/" target="_blank" rel="noopener noreferrer">Check verified public transit options on Sakay.ph ↗</a></div><p class="mini muted">Map data © OpenStreetMap contributors. When you press Find route, your GPS coordinates are shared with external map/routing providers (including Overpass for Jeepney). They are not uploaded to the Tamaraw Time student database. Mapped routes may be outdated: confirm stops and service locally.</p></div></div>`;
 }else if(currentPage==='settings'){
  html=`<div class="grid two"><div class="card"><h2>Student preferences</h2><form id="settings-form"><div class="field"><label>Name</label><input name="name" maxlength="40" required value="${esc(state.settings.name)}"></div><div class="field"><label>Preferred FEU campus</label><select name="campus">${Object.keys(campusOptions).map(c=>`<option ${state.settings.campus===c?'selected':''}>${esc(c)}</option>`).join('')}</select></div><div class="field"><label>Travel mode</label><select name="mode">${['Transit','Jeepney','Train','Bus / UV','Driving','Walking'].map(m=>`<option ${state.settings.mode===m?'selected':''}>${m}</option>`).join('')}</select></div><div class="field"><label>Default travel time (min)</label><input name="travel" type="number" min="1" max="480" required value="${state.settings.travel}"></div><div class="field"><label>Get-ready time (min)</label><input name="prep" type="number" min="0" max="240" required value="${state.settings.prep}"></div><div class="field"><label>Arrival buffer (min)</label><input name="buffer" type="number" min="0" max="120" required value="${state.settings.buffer}"></div><div class="field"><label>Color scheme</label><div class="theme-grid" role="radiogroup" aria-label="App color scheme">${Object.entries(themeNames).map(([key,label])=>`<button type="button" role="radio" aria-checked="${(state.settings.theme||'forest')===key}" class="theme-choice ${(state.settings.theme||'forest')===key?'selected':''}" data-theme-choice="${key}"><span class="theme-swatch theme-${key}" aria-hidden="true"></span><span>${label}</span><span class="theme-check">✓</span></button>`).join('')}</div><input type="hidden" name="theme" value="${esc(state.settings.theme||'forest')}"></div><button class="primary" type="submit">Save settings</button></form></div><div class="stack"><div class="card"><h2>Your account</h2><p class="muted">Your class schedule and commute preferences are saved in your Tamaraw Time account in Supabase. Study activity is recorded privately for the research team, not shown as a student progress score.</p><button type="button" class="secondary" data-action="refresh-cloud">Refresh cloud data</button><button type="button" class="secondary" data-action="export">Export your schedule (JSON)</button><button type="button" class="danger" data-action="reset">Clear schedule and preferences</button><div class="settings-help"><h3>First-time guide</h3><p class="mini muted">Replay the short punctuality and commute tutorial.</p><button type="button" class="secondary" data-action="tutorial">Replay tutorial</button></div></div></div></div>`;
 }
 $('#content').classList.remove('tt-enter');
 $('#content').innerHTML=html;
 void $('#content').offsetWidth;
 $('#content').classList.add('tt-enter');
 refreshDepartureCountdown();
 if(currentPage==='commute'){
  updateCommute();
  $('#class-select').addEventListener('change',()=>{++routeSeq;++jeepneyRequestSerial;jeepneyRequestBusy=false;if(activeRouteEstimate?.campus!==(selectedClass()?.campus||state.settings.campus))activeRouteEstimate=null;$('#trip-travel').value=currentTravel(selectedClass(),$('#trip-mode').value);updateCommute();resetMapForCampus();scheduleAutoRoute(true);});
  for(const id of ['trip-travel','trip-buffer','trip-prep'])$('#'+id).addEventListener('input',updateCommute);
  $('#trip-mode').addEventListener('change',()=>{++routeSeq;++jeepneyRequestSerial;jeepneyRequestBusy=false;activeRouteEstimate=null;clearRouteOverlays();$('#trip-travel').value=currentTravel(selectedClass(),$('#trip-mode').value);updateCommute();renderTransportNote();scheduleAutoRoute(true);});
  initLiveMap();
 }
}
function selectedClass(){return state.classes.find(c=>c.id===$('#class-select')?.value)||upcoming()[0]||null;}
function updateCommute(){
 const target=$('#commute-output');if(!target)return;
 const c=selectedClass();if(!c){target.innerHTML='<div class="empty">Add a class to calculate departure times.</div>';return;}
 const value=id=>Math.max(0,Number($('#'+id)?.value)||0);
 const travel=value('trip-travel'),buffer=value('trip-buffer'),prep=value('trip-prep');
 const result=departure(c,travel,buffer,prep);
 const auto=activeRouteEstimate&&activeRouteEstimate.campus===(c.campus||state.settings.campus)&&activeRouteEstimate.mode===$('#trip-mode')?.value&&Math.abs(activeRouteEstimate.minutes-travel)<.01;
 if($('#eta-status'))$('#eta-status').textContent=auto?'✓ Auto from GPS route':'Fallback / editable estimate';
 target.innerHTML=`<div class="highlight"><strong>${esc(c.name)}</strong><div class="mini">${esc(days[Number(c.day)])} · Starts ${ampm(c.time)} · ${esc(c.campus||state.settings.campus)}</div></div><div class="results"><div class="result"><span>Get ready</span><b>${result.wake}</b></div><div class="result"><span>Leave by</span><b>${result.leave}</b></div><div class="result"><span>Be there by</span><b>${result.arrive}</b></div></div><p class="mini muted">Automatically calculated: class start − ${travel} min journey − ${buffer} min arrival buffer = leave time. Get ready ${prep} min before leaving. ${auto?'Journey time comes from your latest walking/driving GPS route.':'Journey time uses your editable estimate.'} Not live-traffic predictions.</p>`;
}
function destinationCoords(){return campusCoords[selectedClass()?.campus||state.settings.campus]||campusCoords['FEU Tech'];}
// Leaflet must be resized AFTER animated containers finish changing size.
function cleanupMapSizing(){
 if(mapResizeObserver){mapResizeObserver.disconnect();mapResizeObserver=null;}
 if(mapAnimationCleanup){mapAnimationCleanup();mapAnimationCleanup=null;}
 mapResizeTimers.forEach(clearTimeout);mapResizeTimers=[];
}
function installMapSizing(map){
 cleanupMapSizing();
 const host=document.getElementById('map-host');
 if(!host)return;
 let queued=false;
 const resize=()=>{
  if(queued)return;
  queued=true;
  requestAnimationFrame(()=>{
   queued=false;
   if(liveMap!==map||!host.isConnected||!host.getClientRects().length)return;
   map.invalidateSize({pan:false,animate:false});
  });
 };
 if(typeof ResizeObserver!=='undefined'){
  mapResizeObserver=new ResizeObserver(resize);
  mapResizeObserver.observe(host);
 }
 // Animation of the page/card itself can also affect Leaflet's initial measurements.
 const parents=[host,host.closest('.card'),document.getElementById('content')].filter(Boolean);
 for(const node of parents){node.addEventListener('animationend',resize);node.addEventListener('transitionend',resize);}
 mapAnimationCleanup=()=>{for(const node of parents){node.removeEventListener('animationend',resize);node.removeEventListener('transitionend',resize);}};
 [0,150,400,700,1100].forEach(ms=>mapResizeTimers.push(setTimeout(resize,ms)));
}
function initLiveMap(){
 if(!window.L){$('#map-host').textContent='Map library unavailable. Check your internet connection.';return;}
 if(liveMap){cleanupMapSizing();liveMap.remove();liveMap=null;}
 const dest=destinationCoords();liveMap=L.map('map-host',{zoomControl:true}).setView(dest,14);
 L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'}).addTo(liveMap);
 campusMarker=L.marker(dest).addTo(liveMap).bindPopup('Your selected FEU campus');
 if(gpsPosition)updateGpsMarker();renderTransportNote();installMapSizing(liveMap);
}
function resetMapForCampus(){if(!liveMap)return;const dest=destinationCoords();campusMarker.setLatLng(dest);clearRouteOverlays();if(gpsPosition)liveMap.fitBounds([dest,[gpsPosition.lat,gpsPosition.lng]],{padding:[35,35]});else liveMap.setView(dest,14);renderTransportNote();}
function updateGpsMarker(){if(!liveMap||!gpsPosition)return;const p=[gpsPosition.lat,gpsPosition.lng];if(!liveMarker){liveMarker=L.circleMarker(p,{radius:11,color:'#ffffff',weight:3,fillColor:'#1976d2',fillOpacity:1,className:'tt-gps-marker'}).addTo(liveMap).bindPopup('Your live position');}else liveMarker.setLatLng(p);liveMap.fitBounds([p,destinationCoords()],{padding:[45,45],maxZoom:16});}
function stopGps(){if(gpsWatchId!==null){navigator.geolocation.clearWatch(gpsWatchId);gpsWatchId=null;}if(autoRouteTimer){clearTimeout(autoRouteTimer);autoRouteTimer=null;}const el=$('#gps-output');if(el)el.textContent='Live GPS tracking stopped.';}
function scheduleAutoRoute(force=false){
 if(autoRouteTimer)clearTimeout(autoRouteTimer);
 const mode=$('#trip-mode')?.value;if(!gpsPosition||!liveMap||!['Walking','Driving'].includes(mode))return;
 if(!force&&routeRequestBusy)return;
 if(!force&&lastRouteOrigin&&distanceMeters(gpsPosition,lastRouteOrigin)<200&&Date.now()-lastRouteAt<120000)return;
 autoRouteTimer=setTimeout(()=>{autoRouteTimer=null;findLiveRoute(true);},force?300:1400);
}
function clearJeepneyMap(){jeepneySelectionSerial++;for(const marker of [...jeepneyMarkers,...jeepneyWalkLayers])if(liveMap)liveMap.removeLayer(marker);jeepneyMarkers=[];jeepneyWalkLayers=[];jeepneyOptions=[];}
function clearRouteOverlays(){if(liveRoute&&liveMap)liveMap.removeLayer(liveRoute);liveRoute=null;clearJeepneyMap();}
function renderTransportNote(){
 const el=$('#route-info');if(!el)return;
 const mode=$('#trip-mode')?.value||'Transit';
 if(mode==='Jeepney')el.innerHTML='<div class="alert">Select <b>Find route</b> after enabling GPS. We find mapped direct jeepney services and, where available, show pedestrian directions to boarding and alighting points. Results are not live-confirmed operating services. No fares or transit ETAs are generated.</div>';
 else if(['Train','Bus / UV','Transit'].includes(mode))el.innerHTML='<div class="alert">'+esc(mode)+' routing is not available within this app yet. Use Sakay.ph for transit planning. Departure uses your editable journey estimate.</div>';
 else el.innerHTML='<div class="alert">'+esc(mode)+' route preview is available when GPS is enabled. Times are estimates, not real-time traffic predictions.</div>';
}
async function selectJeepneyRoute(index){
 const route=jeepneyOptions[index];if(!route||!liveMap||!gpsPosition)return;
 const seq=++jeepneySelectionSerial,origin={...gpsPosition},campus=destinationCoords();
 if(liveRoute)liveMap.removeLayer(liveRoute);
 for(const marker of [...jeepneyMarkers,...jeepneyWalkLayers])liveMap.removeLayer(marker);
 jeepneyMarkers=[];jeepneyWalkLayers=[];
 liveRoute=L.polyline(route.points,{color:'#ed9d25',weight:6,opacity:.96,className:'tt-route-line'}).addTo(liveMap);
 const stops=[{point:route.board,caption:'Mapped boarding stop',color:'#1e9b73'},{point:route.alight,caption:'Mapped alighting stop',color:'#cc6239'}];
 for(const item of stops){const marker=L.circleMarker([item.point.lat,item.point.lng],{radius:9,color:'#fff',weight:3,fillColor:item.color,fillOpacity:1}).addTo(liveMap).bindPopup('<b>'+item.caption+'</b><br>'+esc(item.point.name));jeepneyMarkers.push(marker);}
 const bounds=L.latLngBounds([route.board.lat,route.board.lng],[route.alight.lat,route.alight.lng]);
 bounds.extend([origin.lat,origin.lng]);bounds.extend(campus);liveMap.fitBounds(bounds,{padding:[40,40],maxZoom:15});
 document.querySelectorAll('.jeepney-route').forEach((node,i)=>{node.classList.toggle('selected',i===index);node.setAttribute('aria-pressed',String(i===index));});
 const details=$('#jeepney-plan');if(!details)return;
 details.innerHTML='<div class="jeepney-loading">Checking pedestrian paths to and from mapped stops…</div>';
 const step=(number,title,content)=>'<li><b>'+number+'. '+title+'</b><span>'+content+'</span></li>';
 const distanceText=leg=>leg.status==='routed'?(leg.distanceMeters+' m · approximately '+leg.minutes+' min walking (routing estimate)'):(leg.status==='short'?'Nearby stop (short connection)':'Pedestrian route unavailable; see stop location on the map');
 try{
  const walk=await JeepneyRouting.planWalkingLegs(origin,{lat:campus[0],lng:campus[1]},route);
  if(seq!==jeepneySelectionSerial||currentPage!=='commute'||$('#trip-mode')?.value!=='Jeepney')return;
  for(const leg of [walk.access,walk.exit]){
   if(leg.status!=='routed')continue;
   jeepneyWalkLayers.push(L.polyline(leg.points,{color:'#1976d2',weight:5,dashArray:'7 8',opacity:.9}).addTo(liveMap));
  }
  let summary='Jeepney ride duration, waiting, and traffic are unknown.';
  if(walk.knownWalkingMinutes!==null)summary+=' Known walking segments: approximately '+walk.knownWalkingMinutes+' minutes total.';
  details.innerHTML='<div class="jeepney-plan"><h3>Suggested mapped journey · one jeepney</h3><ol>'+step(1,'Walk to boarding stop',esc(route.board.name)+' — '+esc(distanceText(walk.access)))+step(2,'Board jeepney',esc(route.ref?route.ref+' · '+route.name:route.name)+' (mapped service; verify signage and availability)')+step(3,'Get off',esc(route.alight.name)) +step(4,'Walk to campus',esc(distanceText(walk.exit)))+'</ol><p class="mini muted">'+esc(summary)+' The departure calculator continues using the manual total journey estimate, including all walking, waiting and riding.</p></div>';
 }catch(err){if(seq===jeepneySelectionSerial&&details)details.innerHTML='<div class="alert">The route line is mapped, but walking directions could not be loaded. Confirm walking access locally.</div>';}
}

async function findJeepneyRoutes(){
 const el=$('#route-info');if(!el||!liveMap)return;
 if(!gpsPosition){el.innerHTML='<div class="alert">Turn on live GPS first, then tap Find route.</div>';return;}
 if(jeepneyRequestBusy){el.textContent='A jeepney search is already in progress…';return;}
 if(!window.JeepneyRouting){el.textContent='Jeepney route service failed to load. Refresh the page or try Sakay.ph.';return;}
 const requestId=++jeepneyRequestSerial;
 const origin={...gpsPosition},dest=destinationCoords();
 clearRouteOverlays();jeepneyRequestBusy=true;
 el.innerHTML='<div class="jeepney-loading" role="status">🚌 Looking for mapped jeepney routes and stops near your location… This may take a few seconds.</div>';
 try{
  const result=await JeepneyRouting.findRoutes(origin,{lat:dest[0],lng:dest[1]});
  if(requestId!==jeepneyRequestSerial||currentPage!=='commute'||$('#trip-mode')?.value!=='Jeepney')return;
  if(result.status!=='found'){
   el.innerHTML='<div class="alert">'+esc(result.message)+'</div><p class="mini muted">Your departure time still uses your editable travel estimate. We cannot infer jeepney itineraries from a road route alone.</p><a class="jeepney-fallback" href="https://sakay.ph/" target="_blank" rel="noopener noreferrer">Check transit options on Sakay.ph ↗</a>';
   return;
  }
  jeepneyOptions=result.routes;
  el.innerHTML='<div class="jeepney-results-title"><strong>'+result.routes.length+' mapped jeepney connection'+(result.routes.length===1?'':'s')+'</strong><span class="mini muted">OSM data · single-ride candidates, not live-verified</span></div><div class="jeepney-list">'+result.routes.map((r,i)=>'<button type="button" class="jeepney-route" data-action="select-jeepney" data-index="'+i+'" aria-pressed="false"><span class="jeepney-route-head">🚌 '+esc(r.ref?`${r.ref} · ${r.name}`:r.name)+'</span><span class="jeepney-route-step">Board at mapped stop: <b>'+esc(r.board.name)+'</b> ('+r.accessMeters+' m straight-line distance)</span><span class="jeepney-route-step">Alight at mapped stop: <b>'+esc(r.alight.name)+'</b> ('+r.exitMeters+' m straight-line distance)</span><span class="jeepney-route-source">OSM relation #'+r.id+' · View route on map</span></button><a class="jeepney-osm-source" href="'+r.sourceUrl+'" target="_blank" rel="noopener noreferrer">View OSM source #'+r.id+' ↗</a>').join('')+'</div><div id="jeepney-plan" aria-live="polite"></div><div class="alert">Mapped stop coordinates are not walking directions or proof that boarding is legally permitted today. Confirm route, direction, boarding rules, and fares locally. Jeepney departure still uses your editable estimate—no live transit ETA is available.</div><a class="jeepney-fallback" href="https://sakay.ph/" target="_blank" rel="noopener noreferrer">Cross-check with Sakay.ph ↗</a>';
  selectJeepneyRoute(0);
 }catch(error){
  if(requestId!==jeepneyRequestSerial||currentPage!=='commute')return;
  el.innerHTML='<div class="alert">Jeepney map data could not be loaded ('+esc(error.message||'network error')+'). Your manual travel estimate remains unchanged.</div><a class="jeepney-fallback" href="https://sakay.ph/" target="_blank" rel="noopener noreferrer">Find transit directions on Sakay.ph ↗</a>';
 }finally{if(requestId===jeepneyRequestSerial)jeepneyRequestBusy=false;}
}

async function findLiveRoute(automatic=false){
 const el=$('#route-info');if(!liveMap||!el)return;
 if(!gpsPosition){el.textContent='Start live GPS first to calculate a route from your position.';return;}
 const mode=$('#trip-mode')?.value||'Transit';if(mode==='Jeepney'){await findJeepneyRoutes();return;}if(!['Walking','Driving'].includes(mode)){renderTransportNote();return;}
 const profile=mode==='Walking'?'foot':'driving',dest=destinationCoords(),origin=gpsPosition,seq=++routeSeq;
 lastRouteAt=Date.now();lastRouteOrigin={...origin};
 if(routeRequestBusy)return;
 routeRequestBusy=true;
 el.textContent=automatic?'Automatically calculating your journey time…':'Calculating route…';
 try{
  const url=`https://routing.openstreetmap.de/routed-${profile}/route/v1/driving/${origin.lng},${origin.lat};${dest[1]},${dest[0]}?overview=full&geometries=geojson`;
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),12000);
  let res;try{res=await fetch(url,{signal:controller.signal});}finally{clearTimeout(timeout);}
  if(!res.ok)throw Error('Routing service unavailable');const data=await res.json();if(seq!==routeSeq||currentPage!=='commute')return;
  const route=data.routes?.[0];if(!route?.geometry?.coordinates?.length)throw Error('No route returned');
  if(liveRoute)liveMap.removeLayer(liveRoute);
  liveRoute=L.polyline(route.geometry.coordinates.map(p=>[p[1],p[0]]),{color:'#208c69',weight:5,opacity:.9,className:'tt-route-line'}).addTo(liveMap);
  liveMap.fitBounds(liveRoute.getBounds(),{padding:[40,40]});const minutes=Math.max(1,Math.ceil(route.duration/60));
  lastRouteAt=Date.now();lastRouteOrigin={...origin};activeRouteEstimate={minutes,mode,campus:selectedClass()?.campus||state.settings.campus,at:Date.now()};
  if($('#trip-travel'))$('#trip-travel').value=minutes;updateCommute();
  el.innerHTML=`<div class="highlight"><strong>${esc(mode)} route preview</strong><div>${(route.distance/1000).toFixed(1)} km · about ${minutes} minutes (routing estimate, not live traffic)</div><div class="mini muted">Departure time was recalculated automatically using this route's duration.</div><span class="auto-applied">✓ Applied automatically</span></div>`;
  el.dataset.routeMinutes=String(minutes);
 }catch(err){if(seq===routeSeq)el.textContent='Automatic route unavailable: '+err.message+'. The app is still using your editable fallback journey estimate.';}finally{routeRequestBusy=false;}
}

// A custom, accessible AM/PM switch avoids browser-dependent native time-picker highlighting.
const timePicker = (prefix,label,h=9,m=0,period='AM') => `<fieldset class="time-picker" data-clock="${prefix}"><legend>${label}</legend><div class="time-controls"><label class="time-number">Hour<input aria-label="${label} hour" type="number" name="${prefix}-hour" min="1" max="12" value="${h}" required></label><span class="time-colon">:</span><label class="time-number">Minute<input aria-label="${label} minute" type="number" name="${prefix}-minute" min="0" max="59" value="${String(m).padStart(2,'0')}" required></label><div class="ampm-toggle" role="group" aria-label="${label} AM or PM"><button type="button" class="period-button ${period==='AM'?'active':''}" data-period="AM" data-clock="${prefix}" aria-pressed="${period==='AM'}">AM</button><button type="button" class="period-button ${period==='PM'?'active':''}" data-period="PM" data-clock="${prefix}" aria-pressed="${period==='PM'}">PM</button></div></div><input type="hidden" name="${prefix}" value="${to24Hour(h,m,period)}"></fieldset>`;
function to24Hour(hour,minute,period){const h=Number(hour)%12+(period==='PM'?12:0);return `${String(h).padStart(2,'0')}:${String(Number(minute)).padStart(2,'0')}`;}
const classForm=`<div class="field"><label for="subject-name">Subject name *</label><input id="subject-name" name="name" maxlength="80" required placeholder="e.g. Data Structures"></div><div class="formgrid"><div class="field"><label for="class-day">Day of week</label><select name="day" id="class-day">${days.map((day,i)=>`<option value="${i}">${day}</option>`).join('')}</select></div><div class="field"><label for="class-room">Room</label><input id="class-room" name="room" maxlength="40" placeholder="Room 401"></div></div><div class="time-grid">${timePicker('time','Class starts',9,0,'AM')}${timePicker('end','Class ends',10,30,'AM')}</div><div class="field"><label for="class-campus">Campus</label><select id="class-campus" name="campus">${Object.keys(campusOptions).map(c=>`<option>${esc(c)}</option>`).join('')}</select></div>`;
function updateHiddenTime(clock){const fs=document.querySelector(`[data-clock="${clock}"].time-picker`);if(!fs)return;const hour=Number(fs.querySelector(`[name="${clock}-hour"]`).value),minute=Number(fs.querySelector(`[name="${clock}-minute"]`).value);const period=fs.querySelector('.period-button.active')?.dataset.period||'AM';if(hour>=1&&hour<=12&&minute>=0&&minute<=59)fs.querySelector(`[name="${clock}"]`).value=to24Hour(hour,minute,period);}
$('#modal-fields').addEventListener('click',event=>{const btn=event.target.closest('.period-button');if(!btn)return;const fs=btn.closest('.time-picker');fs.querySelectorAll('.period-button').forEach(b=>{const active=b===btn;b.classList.toggle('active',active);b.setAttribute('aria-pressed',String(active));});updateHiddenTime(btn.dataset.clock);});
$('#modal-fields').addEventListener('input',event=>{const fs=event.target.closest('.time-picker');if(fs)updateHiddenTime(fs.dataset.clock);});
function openClassModal(){
 $('#modal-title').textContent='Add class';$('#modal-fields').innerHTML=classForm;
 $('#modal-fields [name="campus"]').value=state.settings.campus;
 $('#dialog').showModal();
}
$('#modal-form').addEventListener('submit',async event=>{
 event.preventDefault();const fields=Object.fromEntries(new FormData(event.target).entries());
 if(fields.end<=fields.time){toast('Class end time must be after the start time.');return;}
 state.classes.push({id:uid(),name:fields.name,day:Number(fields.day),room:fields.room,time:fields.time,end:fields.end,campus:fields.campus});
 $('#dialog').close();render();
 try{await saveToCloud('class_added');toast('Class saved online ✓');}catch(err){toast('Cloud save failed: '+(err.message||err));}
});
$('#close-modal').onclick=$('#cancel-modal').onclick=()=>$('#dialog').close();
$('#quick-add').onclick=openClassModal;
document.querySelectorAll('#nav button').forEach(button=>button.addEventListener('click',()=>navigate(button.dataset.page)));
$('#content').addEventListener('click',event=>{const button=event.target.closest('[data-theme-choice]');if(!button)return;const form=button.closest('form');if(!form)return;form.querySelector('input[name=theme]').value=button.dataset.themeChoice;form.querySelectorAll('[data-theme-choice]').forEach(b=>{const active=b===button;b.classList.toggle('selected',active);b.setAttribute('aria-checked',String(active));});applyTheme(button.dataset.themeChoice);});
$('#content').addEventListener('submit',async event=>{
 if(event.target.id!=='settings-form')return;
 event.preventDefault();const v=Object.fromEntries(new FormData(event.target).entries());
 const settings={...state.settings,name:v.name.trim()||'Tamaraw',campus:v.campus,mode:v.mode,travel:Number(v.travel),prep:Number(v.prep),buffer:Number(v.buffer),theme:themeNames[v.theme]?v.theme:'forest'};
 if(!Number.isFinite(settings.travel)||settings.travel<1||settings.travel>480||settings.prep<0||settings.prep>240||settings.buffer<0||settings.buffer>120){toast('Please enter valid settings.');return;}
 const changed=Object.keys(settings).some(k=>settings[k]!==state.settings[k]);state.settings=settings;applyTheme(settings.theme);navigate('settings');
 if(!changed){toast('No settings changed');return;}
 try{await saveToCloud('settings_saved');toast('Settings saved online ✓');}catch(err){toast('Save failed: '+(err.message||err));}
});
$('#content').addEventListener('click',async event=>{
 const button=event.target.closest('button[data-action]');if(!button)return;
 const action=button.dataset.action;
 if(action==='add-class'){openClassModal();return;}
 if(action==='go-commute'){navigate('commute');return;}
 if(action==='go-schedule'){navigate('schedule');return;}
 if(action==='tutorial'){showTutorial();return;}
 if(action==='del-class'){
  if(!confirm('Remove this class?'))return;
  state.classes=state.classes.filter(c=>c.id!==button.dataset.id);render();
  try{await saveToCloud('class_deleted');toast('Class removed online ✓');}catch(err){toast('Remove failed: '+(err.message||err));}return;
 }
 if(action==='save-commute'){
  const val=id=>Number($('#'+id)?.value);
  const revised={travel:val('trip-travel'),buffer:val('trip-buffer'),prep:val('trip-prep'),mode:$('#trip-mode').value};
  if(!Number.isFinite(revised.travel)||revised.travel<1||revised.travel>480||!Number.isFinite(revised.buffer)||revised.buffer<0||revised.buffer>120||!Number.isFinite(revised.prep)||revised.prep<0||revised.prep>240){toast('Please enter valid travel times.');return;}
  const changed=Object.entries(revised).some(([k,v])=>v!==state.settings[k]);
  Object.assign(state.settings,revised);updateCommute();
  if(!changed){toast('No commute settings changed');return;}
  try{await saveToCloud('commute_saved');toast('Commute saved online ✓');}catch(err){toast('Save failed: '+(err.message||err));}return;
 }
 if(action==='location'){
  const output=$('#gps-output');if(!navigator.geolocation){output.textContent='Geolocation is unavailable in this browser.';return;}
  stopGps();output.textContent='Requesting GPS permission…';
  gpsWatchId=navigator.geolocation.watchPosition(position=>{
   gpsPosition={lat:position.coords.latitude,lng:position.coords.longitude};
   if(currentPage==='commute'){$('#gps-output').innerHTML='<span class="gps-live-dot" aria-hidden="true"></span>Tracking live · accuracy approximately '+Math.round(position.coords.accuracy)+' m';updateGpsMarker();scheduleAutoRoute();}
  },error=>{if(currentPage==='commute')$('#gps-output').textContent='GPS unavailable: '+error.message;},{enableHighAccuracy:true,maximumAge:5000,timeout:20000});
  await logActivity('gps_checked');return;
 }
 if(action==='stop-location'){stopGps();return;}
 if(action==='show-map'){await findLiveRoute(false);await logActivity('maps_opened');return;}
 if(action==='select-jeepney'){selectJeepneyRoute(Number(button.dataset.index));return;}
 if(action==='use-route-eta'){const minutes=Number($('#route-info')?.dataset.routeMinutes);if(Number.isFinite(minutes)&&minutes>0){$('#trip-travel').value=minutes;updateCommute();toast('Route estimate applied. Save commute settings to keep it.');}return;}
 if(action==='refresh-cloud'){
  try{await refreshCloud();toast('Cloud data refreshed ✓');}catch(err){toast('Refresh failed: '+(err.message||err));}return;
 }
 if(action==='export'){
  const blob=new Blob([JSON.stringify({classes:state.classes,settings:state.settings,exportedAt:new Date().toISOString()},null,2)],{type:'application/json'});
  const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='tamaraw-time-schedule.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),4000);return;
 }
 if(action==='reset'){
  if(!confirm('Clear your saved classes and commute preferences? Study activity logs remain stored for the research team.'))return;
  const old=snapshot();state.classes=[];state.settings=structuredClone(defaults.settings);applyTheme(state.settings.theme);
  try{await saveToCloud();navigate('settings');toast('Schedule reset online ✓');}
  catch(err){state.classes=old.classes;state.settings=old.settings;render();toast('Reset failed: '+(err.message||err));}
 }
});
$('#tutorial-next').addEventListener('click',()=>{if(tutorialIndex===tutorialSteps.length-1){finishTutorial();navigate('schedule');}else{tutorialIndex++;drawTutorial();}});
$('#tutorial-prev').addEventListener('click',()=>{if(tutorialIndex>0){tutorialIndex--;drawTutorial();}});
$('#tutorial-close').addEventListener('click',finishTutorial);
$('#tutorial-skip').addEventListener('click',finishTutorial);
$('#tutorial-dialog').addEventListener('cancel',()=>{state.onboarding.finished=true;saveToCloud();});
function authMode(mode){
 const signup=mode==='signup';$('#auth-form').dataset.mode=mode;
 $('#auth-submit').textContent=signup?'Create account':'Sign in';
 $('#auth-heading').textContent=signup?'Create your Tamaraw Time account':'Welcome back, Tamaraw!';
 $('#auth-mode-toggle').textContent=signup?'Already have an account? Sign in':'New here? Create an account';
 $('#auth-consent').hidden=!signup;$('#study-consent').required=signup;
 $('#auth-password').autocomplete=signup?'new-password':'current-password';$('#auth-message').textContent='';
}
function showAuth(message=''){
 loadedUser=null;CloudStore.setUser(null);$('#app-layout').hidden=true;$('#auth-screen').hidden=false;$('#account-email').textContent='';
 if($('#tutorial-dialog').open)$('#tutorial-dialog').close();
 $('#auth-message').textContent=message;
 if(!CloudStore.configured){$('#auth-submit').disabled=true;$('#auth-message').textContent='Online database not connected. Ask the project owner to configure cloud-config.js and install schema.sql in Supabase.';}
}
async function enterApp(user){
 if(!user||!CloudStore.configured||loadedUser===user.id)return;
 const ticket=++authCounter;CloudStore.setUser(user);$('#auth-message').textContent='Loading your saved schedule…';
 try{
  const data=await CloudStore.load();if(ticket!==authCounter)return;
  const p=data.payload||{};
  state={classes:Array.isArray(p.classes)?p.classes:[],tasks:Array.isArray(p.tasks)?p.tasks:[],settings:{...defaults.settings,...(p.settings||{})},onboarding:{finished:!!p?.onboarding?.finished}};
  applyTheme(state.settings.theme);activeRouteEstimate=null;
  loadedUser=user.id;stopGps();gpsPosition=null;mapOriginText='';shownMapSignature='';
  $('#account-email').textContent=user.email||'Student account';$('#auth-screen').hidden=true;$('#app-layout').hidden=false;
  navigate('home');if(!state.onboarding.finished)setTimeout(showTutorial,120);
 }catch(err){showAuth('Could not load cloud data: '+(err.message||err)+'. Check your Supabase setup.');}
}
async function refreshCloud(){
 if(!CloudStore.getUser())return;
 await writeQueue.catch(()=>{});const data=await CloudStore.load();const p=data.payload||{};
 state={classes:Array.isArray(p.classes)?p.classes:[],tasks:Array.isArray(p.tasks)?p.tasks:[],settings:{...defaults.settings,...(p.settings||{})},onboarding:{finished:!!p?.onboarding?.finished}};
  applyTheme(state.settings.theme);activeRouteEstimate=null;
 navigate(currentPage);
}
$('#auth-mode-toggle').addEventListener('click',()=>authMode($('#auth-form').dataset.mode==='signup'?'login':'signup'));
$('#auth-form').addEventListener('submit',async event=>{
 event.preventDefault();if(!CloudStore.configured)return;
 const button=$('#auth-submit'),signup=event.target.dataset.mode==='signup';
 const email=$('#auth-email').value.trim(),password=$('#auth-password').value;
 if(signup&&!$('#study-consent').checked){$('#auth-message').textContent='Please read the research activity notice.';return;}
 button.disabled=true;$('#auth-message').textContent=signup?'Creating your account…':'Signing in…';
 try{
  const res=signup?await CloudStore.db.auth.signUp({email,password,options:{emailRedirectTo:location.origin+location.pathname}}):await CloudStore.db.auth.signInWithPassword({email,password});
  if(res.error)throw res.error;
  if(signup&&!res.data.session)$('#auth-message').textContent='Account created. Please verify your email, then sign in.';
  else if(res.data.user)await enterApp(res.data.user);
 }catch(err){$('#auth-message').textContent=err.message||'Could not sign in.';}finally{button.disabled=false;}
});
$('#signout-button').addEventListener('click',async()=>{
 await writeQueue.catch(()=>{});const {error}=await CloudStore.db.auth.signOut();
 if(error){toast('Sign out failed: '+error.message);return;}
 stopGps();++authCounter;showAuth('You are signed out. Your classes are saved online.');
});
async function boot(){
 formatClock();setInterval(formatClock,1000);authMode('login');
 if(!CloudStore.configured){showAuth();return;}
 CloudStore.db.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'){++authCounter;showAuth('Signed out.');}
  else if(event==='SIGNED_IN'&&session?.user)setTimeout(()=>enterApp(session.user),0);
 });
 const {data,error}=await CloudStore.db.auth.getSession();
 if(error){showAuth(error.message);return;}
 if(data.session?.user)await enterApp(data.session.user);else showAuth();
}
boot();
