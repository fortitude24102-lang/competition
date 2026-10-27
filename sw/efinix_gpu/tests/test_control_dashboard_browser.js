'use strict';
// Optional actual-browser check. Playwright is provided by the verification environment, not the gateway.
const assert = require('node:assert/strict');
const {spawn,spawnSync} = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const net = require('node:net');
const dgram = require('node:dgram');
const {chromium} = require('playwright');
const root=path.resolve(__dirname,'../../..');
const python=process.env.GATEWAY_TEST_PYTHON || 'python';
async function freePort(udp=false) {
  if(udp) {const socket=dgram.createSocket('udp4'); await new Promise(r=>socket.bind(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));return port;}
  const server=net.createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));return port;
}
async function until(fn,ms=2000) {
  const end=Date.now()+ms;
  while(Date.now()<end) {const v=await fn();if(v)return v;await new Promise(r=>setTimeout(r,20));}
  throw new Error('condition did not become true');
}
async function main() {
  const httpPort=await freePort(),udpPort=await freePort(true),fakePort=await freePort(true);
  const tool=path.join(root,'sw/efinix_gpu/tools/control_gateway');
  const children=[];let browser;
  function launch(file,args) {
    const command=process.env.GATEWAY_TEST_LAUNCHER ? 'powershell' : python;
    let commandArgs=[path.join(tool,file),...args];
    if(process.env.GATEWAY_TEST_LAUNCHER) {
      commandArgs=['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'scripts/run-control-gateway.ps1'),'-Python',python,
        '-BoardPort',String(fakePort),'-UdpPort',String(udpPort),'-HttpPort',String(httpPort),
        file==='fake_board.py'?'-FakeBoardOnly':'-Simulated'];
    }
    const child=spawn(command,commandArgs,{cwd:root,windowsHide:true,
      env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'},stdio:['ignore','pipe','pipe']});
    child.stdout.on('data',data=>process.stdout.write(data));child.stderr.on('data',data=>process.stderr.write(data));children.push(child);return child;
  }
  try {
    launch('fake_board.py',['--port',String(fakePort),'--gateway-port',String(udpPort),'--game-menu','--performance']);
    launch('gateway.py',['--board','127.0.0.1','--board-port',String(fakePort),'--udp-bind','127.0.0.1',
      '--udp-port',String(udpPort),'--http-port',String(httpPort),'--simulated']);
    const url='http://127.0.0.1:'+httpPort;
    await until(async()=>{try{return (await fetch(url+'/api/status')).ok;}catch{return false;}});
    browser=await chromium.launch({headless:true,executablePath:process.env.GATEWAY_TEST_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      args:['--disable-background-timer-throttling']});
    const page=await browser.newPage({viewport:{width:1280,height:1000}});
    const controls=[];page.on('request',request=>{
      if(request.method()==='POST' && request.url().endsWith('/api/control'))controls.push(request.postDataJSON());
    });
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.goto(url);await page.waitForFunction(()=>document.querySelector('#banner').textContent.includes('SIMULATED'));
    assert.equal(await page.locator('h1').innerText(),'AetherGX-2D渲染加速异构平台');
    assert.deepEqual(await page.locator('#modules .module > h2').allTextContents(),['游戏档位选择','CPU / GPU 同屏对比','性能测试']);
    await page.waitForFunction(()=>document.querySelector('#overview-ddr').textContent!=='—');
    assert.equal(await page.locator('#overview-ddr').textContent(),'112.74');
    assert.equal(await page.locator('#overview-risc').textContent(),'4.83%');
    assert.match(await page.locator('#reference-context').textContent(),/不是当前实时数据/);
    // Clicking a level acquires zero-key control itself; no Acquire button required.
    await page.locator('#level-1').click();
    await until(async()=>(await(await fetch(url+'/api/status')).json()).acknowledged).catch(async error=>{
      console.error('Browser control diagnostic',await page.locator('#control-status').textContent(),
        await page.evaluate(()=>({focus:document.hasFocus(),hidden:document.hidden})),
        await(await fetch(url+'/api/status')).json(),errors);throw error;
    });
    await until(async()=>(await(await fetch(url+'/api/status')).json()).game?.state==='applied');
    await page.waitForFunction(()=>document.querySelector('#current-difficulty').textContent.includes('难度 1'));
    const rBegin=controls.length;
    await page.keyboard.down('KeyR');
    await until(()=>controls.slice(rBegin).some(c=>c.keys&64));
    const rAction=controls.findLast(c=>c.keys&64).action_sequence;
    await new Promise(r=>setTimeout(r,250));
    await page.keyboard.down('KeyR'); /* Native repeat:true while still held. */
    await new Promise(r=>setTimeout(r,250));
    assert.ok(controls.slice(rBegin).every(c=>c.action_sequence===rAction),'held R must trigger only once');
    await page.keyboard.up('KeyR');
    await page.keyboard.down('ArrowLeft');await page.keyboard.down('KeyA');await page.keyboard.up('ArrowLeft');
    assert.equal(await page.locator('#keys').textContent(),'0x01');
    // Actual DOM blur listener must zero the visible key state as well as release the gateway.
    await page.evaluate(()=>window.dispatchEvent(new Event('blur')));
    await until(async()=>!(await(await fetch(url+'/api/status')).json()).owned);
    assert.equal(await page.locator('#keys').textContent(),'0x00');
    await page.keyboard.up('KeyA');
    await page.locator('#acquire').click();await until(async()=>(await(await fetch(url+'/api/status')).json()).acknowledged);
    const conflict=await page.evaluate(async()=>{
      const {token}=await(await fetch('/api/bootstrap')).json();
      return (await fetch('/api/control',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({token,client:'b'.repeat(32),keys:1,action_sequence:0,release:false})})).status;
    });
    assert.equal(conflict,409);
    for(let level=2;level<=6;level++) {
      await page.locator('#reselect').click();
      await page.waitForFunction(()=>!document.querySelector('#difficulty-options').hidden && !document.querySelector('#level-1').disabled);
      await page.locator('#level-'+level).click();
      await page.waitForFunction(l=>document.querySelector('#current-difficulty').textContent.includes('难度 '+l),level);
      const expected=[64,128,256,512,786,1024][level-1];
      assert.ok((await page.locator('#current-difficulty').textContent()).includes(expected+' Sprite'));
      await until(async()=>(await(await fetch(url+'/api/status')).json()).game?.state==='applied');
    }
    await page.keyboard.down('ArrowRight');
    assert.equal(await page.locator('#keys').textContent(),'0x02');
    await page.locator('#reselect').click();
    await page.waitForFunction(()=>!document.querySelector('#level-1').disabled);
    await page.locator('#level-1').click();
    await page.waitForFunction(()=>document.querySelector('#current-difficulty').textContent.includes('难度 1'));
    await until(async()=>(await(await fetch(url+'/api/status')).json()).game?.state==='applied');
    await page.keyboard.down('ArrowRight'); /* Repeat of a pre-menu physical press. */
    await new Promise(r=>setTimeout(r,100));
    assert.equal(controls.at(-1).keys,0,'old held direction is not retransmitted after START');
    assert.equal(await page.locator('#keys').textContent(),'0x00','old held direction cannot resume after START');
    await page.keyboard.up('ArrowRight');await page.keyboard.down('ArrowRight');
    assert.equal(await page.locator('#keys').textContent(),'0x02','a new physical press still works');
    await page.keyboard.up('ArrowRight');
    await page.locator('#reselect').click();
    await page.waitForFunction(()=>!document.querySelector('#difficulty-options').hidden && !document.querySelector('#level-1').disabled);
    await page.keyboard.press('ArrowLeft');assert.equal(await page.locator('#keys').textContent(),'0x00');
    await page.locator('#performance-start').click();
    await until(async()=>(await(await fetch(url+'/api/status')).json()).game?.opcode==='performance' &&
      (await(await fetch(url+'/api/status')).json()).game?.state==='applied');
    await page.waitForFunction(()=>document.querySelector('#performance-result').textContent.includes('活动 64'));
    await page.keyboard.down('ArrowRight');assert.equal(await page.locator('#keys').textContent(),'0x02');
    await page.keyboard.up('ArrowRight');await page.keyboard.press('KeyC');
    assert.equal(await page.locator('#keys').textContent(),'0x00');
    await page.locator('#reselect').click();
    await page.waitForFunction(()=>!document.querySelector('#performance-start').disabled);
    assert.equal((await(await fetch(url+'/api/status')).json()).performance,null,'MENU discards challenge score');
    const expectedBuild=(await(await fetch(url+'/api/status')).json()).telemetry.raw.firmware_build_id;
    await until(async()=>(await page.locator('#metric-firmware_build_id').textContent())===String(expectedBuild));
    assert.ok(await page.locator('#gpu-card').isHidden(),'invalid GPU result must not occupy a permanent Unavailable card');
    assert.ok(await page.locator('#cpu-card').isHidden(),'CPU card appears only after a valid comparison');
    assert.ok(await page.locator('#metric-render_read_bytes').locator('..').isHidden(),'unmeasured traffic is not a fabricated zero');
    await page.waitForFunction(()=>document.querySelector('#work-gain').textContent==='16.6%');
    await page.locator('details:has(> #comparison) > summary').click();
    assert.equal(await page.locator('#pixel-gain').textContent(),'30.4%');
    assert.equal(await page.locator('#copy-bandwidth').textContent(),'311.68 MB/s');
    assert.ok((await page.locator('#comparison-game').innerText()).includes('69.2%'));
    assert.ok((await page.locator('#comparison-game').innerText()).includes('57.7%'));
    assert.ok((await page.locator('#comparison-copy').innerText()).includes('77.92 MPixel/s'));
    assert.ok((await page.locator('#comparison').innerText()).includes('尚未测得完整RISC-V总占用率与整机DDR物理利用率'));
    assert.ok(await page.locator('#kernel-panel').isVisible());
    assert.ok((await page.locator('#comparison-kernel').innerText()).includes('17.166 ms'));
    assert.ok((await page.locator('#comparison-kernel').innerText()).includes('9.34%'));
    await page.locator('#kernel-target').selectOption('512');
    assert.ok((await page.locator('#comparison-kernel').innerText()).includes('9.284 ms'));
    assert.ok((await page.locator('#comparison-kernel').innerText()).includes('4.83%'));
    assert.ok(!(await page.locator('main').innerText()).includes('Unavailable'),'no permanently unavailable metric placeholders');
    await page.locator('.diagnostics > summary').click();
    const downloadPromise=page.waitForEvent('download');await page.locator('#export').click();
    const download=await downloadPromise;await download.saveAs(path.join(root,'generated/verification/v3/gateway/browser-raw.csv'));
    assert.ok(fs.readFileSync(path.join(root,'generated/verification/v3/gateway/browser-raw.csv'),'utf8').includes('render_read_bytes'),
      'hiding an invalid display field must not delete it from the raw export');
    await page.screenshot({path:path.join(root,'generated/verification/v3/gateway/dashboard.png'),fullPage:true});
    await page.setViewportSize({width:390,height:844});
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile page must not horizontally overflow');
    await page.screenshot({path:path.join(root,'generated/verification/v3/gateway/dashboard-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    await page.close();await until(async()=>!(await(await fetch(url+'/api/status')).json()).owned);
    // Real DOM + a controlled SSE boundary, not a simulated FPS benchmark.
    const preview=await browser.newPage({viewport:{width:1280,height:900}});
    preview.on('pageerror',e=>errors.push(e.message));
    await preview.addInitScript(()=>{window.EventSource=class {constructor(){window.testStream=this;}};});
    await preview.goto(url);
    await preview.waitForFunction(()=>window.testStream);
    await preview.locator('.diagnostics > summary').click();
    const snapshot=await(await fetch(url+'/api/status')).json();
    snapshot.stale=false;snapshot.age_ms=0;
    Object.assign(snapshot.telemetry.raw,{gpu_full_frame_fps_x100:6010,visible_sprites:504,requested_sprites:512,
      pre_present_us:9618,gpu_busy_us:7000,render_read_bytes:12345,status_flags:0x714801});
    Object.assign(snapshot.telemetry.display,{gpu_full_frame_fps_x100:6010,pre_present_us:9618,gpu_busy_us:7000,
      render_read_bytes:null,status_flags:0x714801});
    snapshot.telemetry.words[3]=512;snapshot.telemetry.words[5]=6010;snapshot.telemetry.words[21]=0x714801;
    await preview.evaluate(v=>window.testStream.onmessage({data:JSON.stringify(v)}),snapshot);
    await until(async()=>await preview.locator('#gpu-card').isVisible());
    assert.equal(await preview.locator('#gpu-fps').textContent(),'60.10');
    assert.equal(await preview.locator('#overview-fps').textContent(),'60.10');
    assert.equal(await preview.locator('#overview-sprites').textContent(),'504 / 512');
    assert.ok(await preview.locator('#metric-render_read_bytes').locator('..').isHidden());
    await until(async()=>await preview.locator('#gpu-card').isHidden());
    assert.ok(await preview.locator('#live-empty').isVisible(),'stale live metrics are removed');
    assert.equal(await preview.locator('#overview-fps').textContent(),'—');
    assert.equal(await preview.locator('#overview-sprites').textContent(),'—');
    assert.ok((await preview.locator('#mode').textContent()).includes('没有新鲜'),'stale mode is not shown as a current state');
    assert.equal(await preview.locator('#work-gain').textContent(),'16.6%','SSE loss must not erase historical results');
    assert.deepEqual(errors,[]);
    await preview.close();
    console.log('PASS browser: simulated label, ACK, aliases, blur zero/release, ownership conflict, invalid FPS, raw CSV, page close');
  } finally {
    if(browser)await browser.close();
    for(const child of children){
      if(child.exitCode===null && process.env.GATEWAY_TEST_LAUNCHER) {
        // Only terminate the process trees launched and recorded by this test.
        spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
      } else if(child.exitCode===null) child.kill();
      await new Promise(resolve=>{if(child.exitCode!==null)return resolve();child.once('exit',resolve);});
    }
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
