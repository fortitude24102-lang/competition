'use strict';
// Real local board only. No fake performance or additional endurance window.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require('playwright');
const out=process.argv[2];
if(!out || fs.existsSync(out))throw new Error('Fresh output directory required');
fs.mkdirSync(out,{recursive:true});
const url='http://127.0.0.1:8765';
const split=s=>s.telemetry?.raw.firmware_build_id===0x20261027 && (s.telemetry.raw.status_flags&0x102)===0x102;
let browser;
async function state(){const s=await(await fetch(url+'/api/status')).json();assert(!s.simulated);fs.appendFileSync(out+'/http.jsonl',JSON.stringify(s)+'\n');return s;}
async function until(test,seconds){const end=Date.now()+seconds*1000;while(Date.now()<end){const s=await state();if(test(s))return s;await new Promise(r=>setTimeout(r,100));}throw new Error('Board condition timeout');}
(async()=>{
 try {
  const initial=await until(s=>!s.stale && !s.owned && (!!(s.telemetry?.raw.status_flags&1024) || split(s)),5);
  browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',args:['--disable-background-timer-throttling']});
  const page=await browser.newPage({viewport:{width:1280,height:1100}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(url);await page.bringToFront();
  if(split(initial)) {
   await page.locator('#reselect').click({timeout:5000});
   await until(s=>!s.stale && s.game?.state==='applied' && !!(s.telemetry.raw.status_flags&1024),3);
  }
  await page.locator('#split-start').click({timeout:10000});
  await until(s=>!s.stale && split(s) && s.telemetry.raw.simulation_tick>=2,15);
  const cancel=Date.now();await page.locator('#reselect').click({timeout:3000});
  await until(s=>!s.stale && s.game?.opcode==='menu' && s.game.state==='applied' && !!(s.telemetry.raw.status_flags&1024),3);
  const cancelMs=Date.now()-cancel;assert(cancelMs<2500);
  console.log('PASS cancellation during slow CPU rendering,ms='+cancelMs);
  if(process.argv[3]==='--smoke') {
   assert.equal(await page.locator('#game #split-start').count(),1);
   assert.equal(await page.locator('#difficulty-options button').count(),6);
   const final=await state();assert(!final.stale && !!(final.telemetry.raw.status_flags&1024));
   assert(final.telemetry.raw.scanout_underflow_delta===0 && final.telemetry.raw.gpu_error_delta===0);
   assert.deepEqual(errors,[]);await page.locator('#split-start').scrollIntoViewIfNeeded();
   await page.screenshot({path:out+'/browser-final.png',fullPage:true});
    fs.writeFileSync(out+'/result.json',JSON.stringify({passed:true,scope:'separate menu entry and cancellation; timed run verified separately',cancel_ms:cancelMs,final},null,2));
   console.log('PASS separate exhibition in difficulty section,six original game buttons,MENU exit,health0');return;
  }
  await page.locator('#split-start').click({timeout:5000});
  await until(s=>!s.stale && split(s),10);
  let last=-1,lastTarget=0;
  const final=await until(s=>{
   assert(!s.stale,'Board telemetry became stale');assert(split(s),'Comparison exited unexpectedly');
   assert(s.owned && s.acknowledged,'Control lease/session lost');
   const r=s.telemetry.raw;assert(r.scanout_underflow_delta===0 && r.gpu_error_delta===0,'Board health failed');
   assert((r.status_flags&0x30000)===0,'Viewport FPS must not have native full-frame validity');
   if(r.requested_sprites!==lastTarget || r.simulation_tick>=last+1000){last=r.simulation_tick;lastTarget=r.requested_sprites;console.log('HDMI comparison target='+lastTarget+' elapsed_ms='+last);}
   return r.requested_sprites===512 && r.simulation_tick===15000;
  },90);
  await new Promise(r=>setTimeout(r,500));
  for(const target of [256,512])assert.match(await page.locator('#split-score-'+target).innerText(),/CPU [0-9.]+ \/ GPU [0-9.]+ FPS/);
  assert.match(await page.locator('#split-gpu').innerText(),/^60\./);
  assert.equal(await page.locator('#gpu-card').isVisible(),false);
  assert.equal(await page.locator('#split-live').isVisible(),false,'Completed window is retained, not live animation');
  assert.deepEqual(errors,[]);await page.locator('#split-start').scrollIntoViewIfNeeded();
  await page.screenshot({path:out+'/browser-final.png',fullPage:true});
  await page.locator('#reselect').click({timeout:3000});
  await until(s=>!s.stale && s.game?.state==='applied' && !!(s.telemetry.raw.status_flags&1024),3);
  for(let level=1;level<=6;level++) {
   await page.locator('#level-'+level).click({timeout:3000});
   await until(s=>!s.stale && s.game?.state==='applied' && s.telemetry.raw.requested_sprites===[64,128,256,512,786,1024][level-1] && s.telemetry.raw.simulation_tick>=65,5);
   const game=await state();assert(game.telemetry.raw.gpu_error_delta===0 && game.telemetry.raw.scanout_underflow_delta===0);
   assert(game.telemetry.raw.gpu_full_frame_fps_x100>=5900,'Original game GPU cadence regressed after comparison cache use');
   await page.locator('#reselect').click({timeout:3000});
   await until(s=>!s.stale && s.game?.state==='applied' && !!(s.telemetry.raw.status_flags&1024),3);
  }
  fs.writeFileSync(out+'/result.json',JSON.stringify({passed:true,cancel_ms:cancelMs,final,original_six_games_after_display:true},null,2));
  console.log('PASS real browser entry,MENU cancellation,2 tiers of15seconds,health0,all6originalgames after cache restoration,returned MENU');
 } finally {if(browser)await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
