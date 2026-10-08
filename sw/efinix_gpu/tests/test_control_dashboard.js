'use strict';
// Behavioral tests run with Node's built-in assertions; no browser framework.
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const file = path.join(__dirname, '../tools/control_gateway/web/dashboard.js');
assert.ok(fs.existsSync(file), 'browser keyboard controller missing');
const {ControlPump, KeyboardState, SnapshotBuffer, TelemetryFreshness, formatValue, gameView} = require(file);

class Clock {
  constructor() { this.now = 0; this.tasks = []; }
  set = (fn, delay) => {const task = {fn, at: this.now + delay}; this.tasks.push(task); return task;};
  clear = task => {this.tasks = this.tasks.filter(t => t !== task);};
  advance(ms) {
    const end = this.now + ms;
    while (true) {
      this.tasks.sort((a,b) => a.at - b.at);
      if (!this.tasks.length || this.tasks[0].at > end) break;
      const task = this.tasks.shift(); this.now = task.at; task.fn();
    }
    this.now = end;
  }
}

async function main() {
  const menuWords=Array(27).fill(0);menuWords[21]=0x0d00;
  let gv=gameView({stale:false,age_ms:0,telemetry:{words:menuWords},game:null});
  assert.deepEqual(gv,{supported:true,phase:'menu',level:null,canStart:true,canMenu:true,pending:false});
  for(const [level,count] of [[1,64],[2,128],[3,256],[4,512]]) {
    const words=menuWords.slice();words[21]=0x0801;words[3]=count;
    assert.equal(gameView({stale:false,age_ms:0,telemetry:{words}}).level,level);
  }
  assert.equal(gameView({stale:true,telemetry:{words:menuWords}}).canStart,false);
  assert.equal(gameView({stale:false,telemetry:{words:Array(27).fill(0)}}).supported,false);
  gv=gameView({stale:false,age_ms:0,telemetry:{words:menuWords},game:{state:'await_snapshot'}});
  assert.equal(gv.canStart,false);assert.equal(gv.pending,true);
  const freshness=new TelemetryFreshness();
  function view(sequence,flags,age=0) {
    const words=Array(27).fill(0);words[0]=20261007;words[21]=flags;
    return {stale:age>=500,age_ms:age,telemetry:{session:7,sequence,words}};
  }
  freshness.observe(view(1,(1<<16)|(1<<17)),1000);
  assert.equal(freshness.view(1000).gpu_age_ms,0);
  assert.equal(freshness.view(1000).cpu_observation_age_ms,0);
  // A repeated SSE heartbeat with an unchanged age must not revive old data.
  freshness.observe(view(1,(1<<16)|(1<<17)),1600);
  assert.equal(freshness.view(1600).stale,true);
  assert.equal(freshness.view(1600).gpu_age_ms,600);
  assert.equal(freshness.view(1600).cpu_observation_age_ms,600);
  freshness.observe(view(2,(1<<16)|(1<<17)|32,10),2000);
  assert.equal(freshness.view(2100).gpu_age_ms,110);
  assert.equal(freshness.view(2100).cpu_stale,true);
  assert.equal(freshness.view(2100).cpu_observation_age_ms,1100);
  freshness.observe(view(3,1<<21),2200);
  assert.equal(freshness.view(2200).gpu_age_ms,null);
  assert.equal(freshness.view(2200).cpu_valid,false);
  const unseen=new TelemetryFreshness();
  unseen.observe(view(1,(1<<17)|32),0);
  assert.equal(unseen.view(100).cpu_observation_age_ms,null,'retained CPU value does not invent an observation date');
  freshness.disconnect();
  assert.equal(freshness.view(2200).stale,true);
  const clock = new Clock(); const sent = []; const pending = [];
  const pump = new ControlPump({send: state => { sent.push({...state}); return new Promise(resolve => pending.push(resolve)); },
    now: () => clock.now, setTimer: clock.set, clearTimer: clock.clear});
  pump.acquire(); clock.advance(0);
  assert.equal(sent.length, 1);
  pump.update(1, 0); pump.update(2, 0); pump.update(4, 0);
  clock.advance(100);
  assert.equal(sent.length, 1, 'slow POST must not accumulate requests');
  pending.shift()({ok:true, status:200}); await new Promise(setImmediate);
  clock.advance(0);
  assert.equal(sent.length, 2); assert.equal(sent[1].keys, 4, 'only latest state survives');
  pump.clear(); clock.advance(100);
  assert.equal(sent.length, 2, 'clear respects single in-flight request');
  pending.shift()({ok:true, status:200}); await new Promise(setImmediate);
  clock.advance(0);
  assert.equal(sent[2].keys, 0); assert.equal(sent[2].release, true);
  pending.shift()({ok:true, status:200}); await new Promise(setImmediate);
  clock.advance(1000); assert.equal(sent.length, 3, 'blur/close stops heartbeats');

  const fast = []; const clk = new Clock();
  const rate = new ControlPump({send: async state => {fast.push({at:clk.now,...state}); return {ok:true,status:200};},
    now:()=>clk.now, setTimer:clk.set, clearTimer:clk.clear});
  rate.acquire(); clk.advance(0); await new Promise(setImmediate);
  rate.update(1,0); clk.advance(32); assert.equal(fast.length,1);
  clk.advance(1); await new Promise(setImmediate); assert.equal(fast.length,2);
  rate.update(2,0); clk.advance(33); await new Promise(setImmediate);
  assert.equal(fast[2].at - fast[1].at,33);
  rate.clear(); clk.advance(33); await new Promise(setImmediate);

  const keys = new KeyboardState();
  keys.press('ArrowLeft'); keys.press('KeyA'); keys.release('ArrowLeft');
  assert.equal(keys.mask,1, 'alias release must not clear a still-held alias');
  keys.press('KeyR'); assert.equal(keys.action,1);
  keys.press('KeyR'); assert.equal(keys.action,1, 'repeated keydown is not a new action');
  keys.release('KeyR'); keys.press('KeyR'); assert.equal(keys.action,2);
  keys.press('KeyC'); assert.equal(keys.action,3);
  keys.clear(); assert.equal(keys.mask,0);
  assert.equal(formatValue(null,'gpu_full_frame_fps_x100'),'Unavailable');
  assert.equal(formatValue(6010,'gpu_full_frame_fps_x100'),'60.10');
  const samples = new SnapshotBuffer(2);
  samples.add({sequence:1,words:Array(27).fill(7)}, 't1');
  const repeated=Array(27).fill(9); repeated[0]=repeated[1]=7;
  samples.add({sequence:1,words:repeated}, 't2');
  assert.equal(samples.rows.length,1, 'repeated SSE status must not duplicate raw snapshots');
  samples.add({sequence:2,words:Array(27).fill(8)}, 't3');
  samples.add({sequence:3,words:Array(27).fill(9)}, 't4');
  assert.equal(samples.rows.length,2);
  const csv = samples.csv(); assert.ok(csv.includes('firmware_build_id'));
  assert.ok(csv.includes('t3')); assert.ok(!csv.includes('t1'));
  console.log('PASS dashboard: latest-only POST, single in-flight, 33 ms rate, release, aliases, action edges, validity, bounded raw CSV');
}
main().catch(error => {console.error(error); process.exitCode=1;});
