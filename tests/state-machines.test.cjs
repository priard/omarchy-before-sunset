const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const dir = path.join(__dirname, '..');
const m = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(dir, 'LocationState.js'), 'utf8'), m);
const events = ['enable', 'disable', 'request', 'start', 'success', 'failure'];
let visited = new Set();
function explore(s, depth) {
  assert(['disabled','waiting','lookup','idle','exhausted'].includes(s.phase));
  assert(s.failures >= 0 && s.failures <= 4);
  if (!s.enabled) assert(['disabled','lookup'].includes(s.phase));
  if (s.phase === 'waiting') assert(s.delay > 0);
  const key = JSON.stringify(s) + depth;
  if (!depth || visited.has(key)) return;
  visited.add(key);
  for (const e of events) explore(m.transition(s, e), depth - 1);
}
explore(m.initial(), 10);
let s=m.transition(m.initial(),'enable');
s=m.transition(s,'start');
s=m.transition(s,'request');
assert(s.dirty); // change during lookup must survive until completion
s=m.transition(s,'success');
assert.equal(s.phase,'waiting');
for(let i=0;i<4;i++) { s=m.transition(s,'start'); s=m.transition(s,'failure'); }
assert.equal(s.phase,'exhausted');
s=m.transition(s,'request'); assert.equal(s.phase,'waiting');
s=m.transition(s,'start'); s=m.transition(s,'disable'); s=m.transition(s,'enable');
assert(s.dirty); // re-enable must not accept the pre-disable response
s=m.transition(s,'success'); assert.equal(s.phase,'waiting');
for(const pair of [[null,0],['40',0],[NaN,0],[91,0],[0,181],[Infinity,0]]) assert(!m.coordinates(...pair));
assert(m.coordinates(0,0)); assert(m.coordinates(-90,180));
const src=fs.readFileSync(path.join(dir,'Service.qml'),'utf8');
const compute=src.slice(src.indexOf('  function computeAutoSchedule()'),src.indexOf('  // What the theme follows,'));
let c=vm.createContext({Date,configAutoMode:'sun',hasLocation:false,autoSource:'',sensorUsable:false,Sun:{fixedSchedule(){throw Error('unrequested fixed fallback')},sunSchedule(){return null}},latitude:40,longitude:-74,twilight:'official',sunriseOffsetMinutes:0,sunsetOffsetMinutes:0});
vm.runInContext(compute,c);
assert.equal(c.computeAutoSchedule(),null); assert.equal(c.autoSource,'');
c.hasLocation=true; assert.equal(c.computeAutoSchedule(),null); // polar/no-event day holds theme
c.Sun.sunSchedule=()=>({mode:'day'}); assert.equal(c.computeAutoSchedule().mode,'day');
assert.equal(c.autoSource,'sun');
c.configAutoMode='fixed'; c.fixedDay='07:00'; c.fixedNight='19:00'; c.Sun.fixedSchedule=()=>({mode:'night'});
assert.equal(c.computeAutoSchedule().mode,'night');
const start=src.indexOf('onExited: function(exitCode)',src.indexOf('id: themeProcess'));
const callback=src.slice(start+'onExited: '.length,src.indexOf('\n    }\n  }',start)+6);
const calls=[]; const root={queuedTheme:'obsolete',pendingTheme:'in-flight',probeBackground(){},evaluate(){calls.push('evaluate')}};
const context=vm.createContext({root,themeNameFile:{reload(){}},Qt:{callLater(fn){calls.push(fn)}}});
const exited=vm.runInContext('('+callback+')',context);
exited(0); assert.equal(root.queuedTheme,''); assert(calls.includes(root.evaluate));
calls.length=0; root.queuedTheme='obsolete'; exited(1);
assert.equal(root.pendingTheme,''); assert(!calls.includes(root.evaluate)); // no immediate failure spin
console.log(`State transitions explored: ${visited.size}; location, schedule, and theme-queue regressions passed.`);
const solar=vm.createContext({Date,Math,isNaN,Number,String});
vm.runInContext(fs.readFileSync(path.join(dir,'Sun.js'),'utf8'),solar);
for(const date of ['2026-03-08T12:00:00','2026-11-01T12:00:00','2026-06-21T12:00:00','2026-12-21T12:00:00']) {
  const noon=new Date(date), up=solar.sunrise(noon,40.7,-74), down=solar.sunset(noon,40.7,-74);
  assert(up && down && up < down);
  assert.equal(solar.sunSchedule(new Date(+up-1),40.7,-74,{}).mode,'night');
  assert.equal(solar.sunSchedule(up,40.7,-74,{}).mode,'day');
  assert.equal(solar.sunSchedule(down,40.7,-74,{}).mode,'night');
  const schedule=solar.sunSchedule(noon,40.7,-74,{});
  assert(schedule.since <= +noon && schedule.next > +noon);
}
console.log('Solar boundary checks passed, including both 2026 daylight-saving transition dates.');
