'use strict';
// Optional actual-browser check. Playwright is provided by the verification environment, not the gateway.
const assert = require('node:assert/strict');
const {spawn,spawnSync} = require('node:child_process');
const path = require('node:path');
const net = require('node:net');
const dgram = require('node:dgram');
const {chromium} = require('playwright');
const root=path.resolve(__dirname,'../../..');
const python=process.env.GATEWAY_TEST_PYTHON || 'C:/efinity/efinity/python311/bin/python.exe';
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
      env:{...process.env,PYTHONHOME:process.env.PYTHONHOME || 'C:/efinity/efinity/python311',PYTHONDONTWRITEBYTECODE:'1'},stdio:['ignore','pipe','pipe']});
    child.stdout.on('data',data=>process.stdout.write(data));child.stderr.on('data',data=>process.stderr.write(data));children.push(child);return child;
  }
  try {
    launch('fake_board.py',['--port',String(fakePort),'--gateway-port',String(udpPort)]);
    launch('gateway.py',['--board','127.0.0.1','--board-port',String(fakePort),'--udp-bind','127.0.0.1',
      '--udp-port',String(udpPort),'--http-port',String(httpPort),'--simulated']);
    const url='http://127.0.0.1:'+httpPort;
    await until(async()=>{try{return (await fetch(url+'/api/status')).ok;}catch{return false;}});
    browser=await chromium.launch({headless:true,executablePath:process.env.GATEWAY_TEST_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      args:['--disable-background-timer-throttling']});
    const page=await browser.newPage({viewport:{width:1280,height:1000}});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.goto(url);await page.waitForFunction(()=>document.querySelector('#banner').textContent.includes('SIMULATED'));
    await page.locator('#acquire').click();
    await until(async()=>(await(await fetch(url+'/api/status')).json()).acknowledged).catch(async error=>{
      console.error('Browser control diagnostic',await page.locator('#control-status').textContent(),
        await page.evaluate(()=>({focus:document.hasFocus(),hidden:document.hidden})),
        await(await fetch(url+'/api/status')).json(),errors);throw error;
    });
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
    await until(async()=>(await page.locator('#metric-firmware_build_id').textContent())!=='Unavailable');
    assert.equal(await page.locator('#gpu-fps').textContent(),'Unavailable');
    const downloadPromise=page.waitForEvent('download');await page.locator('#export').click();
    const download=await downloadPromise;await download.saveAs(path.join(root,'generated/verification/v3/gateway/browser-raw.csv'));
    await page.screenshot({path:path.join(root,'generated/verification/v3/gateway/dashboard.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    await page.close();await until(async()=>!(await(await fetch(url+'/api/status')).json()).owned);
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
