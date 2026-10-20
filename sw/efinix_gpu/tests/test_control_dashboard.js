'use strict';
// Behavioral tests run with Node's built-in assertions; no browser framework.
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const file = path.join(__dirname, '../tools/control_gateway/web/dashboard.js');
assert.ok(fs.existsSync(file), 'browser keyboard controller missing');
const {ControlPump, KeyboardState, SnapshotBuffer, TelemetryFreshness, formatValue, gameView,
  benchmarkMetrics,kernelMetrics,liveMetricRows,modeText} = require(file);

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
  assert.equal(typeof kernelMetrics,'function','measurement-firmware accounting is missing');
  const measured={target:512,alpha:64,frames:600,wall_us:10000000,work_us:7200000,max_work_us:12500,
    logic_us:300000,build_us:200000,render_call_us:6600000,present_us:2800000,
    pixels:300000000,rd:550000000,wr:570000000,cache:50000000,under:0,error:0,work_miss:0};
  const k=kernelMetrics(measured);
  assert.equal(k.fps,60);assert.equal(k.cpu_known_percent,5);assert.equal(k.cpu_known_ms.toFixed(3),'0.833');
  assert.equal(k.processed_mp_s,30);assert.equal(k.total_mb_s,112);
  assert.equal(k.render_processed_mp_s.toFixed(2),'45.45');assert.equal(k.render_mb_s.toFixed(2),'169.70');
  assert.equal(k.read_util_percent.toFixed(2),'13.75');assert.equal(k.write_util_percent.toFixed(2),'14.25');
  assert.equal(k.driver_ms,11);assert.equal(k.present_ms.toFixed(3),'4.667');
  for(const bad of [{...measured,wall_us:0},{...measured,logic_us:-1},
    {...measured,render_call_us:10000001},{...measured,error:1}]) assert.throws(()=>kernelMetrics(bad));
  assert.equal(typeof benchmarkMetrics,'function','archived comparison metrics are missing');
  const health={target:512,frames:3600,work_miss:0,late_present:0,under:0,errors:0};
  const fixture={conditions:{target_fps:60,axi_clock_hz:100000000,axi_data_bits:32},
    game:{before:{...health,work_mean_us:11527,work_max_us:15208,fps_x10:601},
      after:{...health,work_mean_us:9618,work_max_us:13191,fps_x10:601},return:{...health}},
    copy:{before:{width:960,height:468,us:7520,rd:898560,wr:898560},
      after:{width:960,height:468,us:5766,rd:898560,wr:898560}}};
  const b=benchmarkMetrics(fixture);
  assert.equal(b.game.before.budget_percent.toFixed(1),'69.2');
  assert.equal(b.game.after.budget_percent.toFixed(1),'57.7');
  assert.equal(b.work_reduction_percent.toFixed(1),'16.6');
  assert.equal(b.game.after.fps,60.1,'refresh capped FPS must not become an invented higher score');
  assert.equal(b.copy.before.mpixels_s.toFixed(2),'59.74');
  assert.equal(b.copy.after.mpixels_s.toFixed(2),'77.92');
  assert.equal(b.copy.after.total_mb_s.toFixed(2),'311.68');
  assert.equal(b.copy.before.read_util_percent.toFixed(1),'29.9');
  assert.equal(b.copy.after.read_util_percent.toFixed(1),'39.0');
  assert.equal(b.copy.after.write_util_percent.toFixed(1),'39.0');
  assert.equal(b.pixel_gain_percent.toFixed(1),'30.4');
  assert.equal(b.riscv_utilization,undefined,'frame work and GPU wait must not invent CPU utilization');
  assert.equal(b.ddr_physical_utilization,undefined,'AXI payload is not DDR chip total utilization');
  for(const mutate of [d=>{d.copy.after.us=0;},d=>{d.copy.after.width=8;},
    d=>{d.copy.after.rd=0;},d=>{d.game.after.work_mean_us=null;},d=>{d.game.after.frames=3599;},
    d=>{d.game.return.errors=1;},d=>{d.game.before.target=64;}]) {
    const bad=JSON.parse(JSON.stringify(fixture));mutate(bad);
    assert.throws(()=>benchmarkMetrics(bad),'invalid/mismatched windows cannot silently produce a comparison');
  }
  const display={firmware_build_id:539365397,gpu_full_frame_fps_x100:null,
    command_build_us:null,render_read_bytes:null,gpu_error_delta:0};
  assert.deepEqual(liveMetricRows({telemetry:{display}},false),[
    ['firmware_build_id',539365397],['gpu_error_delta',0]]);
  assert.deepEqual(liveMetricRows({telemetry:{display}},true),[],'disconnected data is not a live metric');
  assert.deepEqual(liveMetricRows({},false),[]);
  const menuWords=Array(27).fill(0);menuWords[21]=0x0d00;
  assert.equal(typeof modeText,'function','menu/debug capability labels need an unambiguous live mode');
  menuWords[21]=0x0da1;
  assert.equal(modeText({telemetry:{words:menuWords}}),'难度选择菜单 · CPU旧对照已过期');
  menuWords[21]=0x0d00;
  let gv=gameView({stale:false,age_ms:0,telemetry:{words:menuWords},game:null});
  assert.deepEqual(gv,{supported:true,phase:'menu',level:null,maxLevel:4,canStart:true,canMenu:true,pending:false,canPerformance:false});
  menuWords[21]=0x1d00;
  assert.equal(gameView({stale:false,age_ms:0,telemetry:{words:menuWords}}).canPerformance,true);
  menuWords[21]=0x3801;
  assert.equal(gameView({stale:false,age_ms:0,telemetry:{words:menuWords}}).phase,'performance');
  menuWords[21]=0x0d00;
  for(const [level,count] of [[1,64],[2,128],[3,256],[4,512],[5,786],[6,1024]]) {
    const words=menuWords.slice();words[21]=0x4801;words[3]=count;
    assert.equal(gameView({stale:false,age_ms:0,telemetry:{words}}).level,level);
  }
  assert.equal(gameView({stale:false,age_ms:0,telemetry:{words:menuWords}}).maxLevel,4);
  menuWords[21]=0x4d00;
  assert.equal(gameView({stale:false,age_ms:0,telemetry:{words:menuWords}}).maxLevel,6);
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
  assert.equal(formatValue(null,'gpu_full_frame_fps_x100'),'—');
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
