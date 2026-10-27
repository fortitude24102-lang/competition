(function (root) {
  'use strict';
  const FIELDS = ['firmware_build_id','resource_epoch','simulation_tick','requested_sprites','visible_sprites',
    'gpu_full_frame_fps_x100','cpu_full_frame_fps_x100','pre_present_us','gpu_busy_us','command_build_us',
    'submit_blocked_us','background_copy_us','render_read_bytes','render_write_bytes','texture_cache_bytes',
    'scanout_underflow_delta','gpu_error_delta','missed_vblank_delta','asset_retry_delta','control_drop_delta',
    'input_age_ms','status_flags','p95_work_us','present_wait_us','alpha_commands','alpha_pixels','key_commands'];
  const MAP = {ArrowLeft:1,KeyA:1,ArrowRight:2,KeyD:2,ArrowUp:4,KeyW:4,ArrowDown:8,KeyS:8,
    Space:16,KeyZ:16,ShiftLeft:32,ShiftRight:32,KeyR:64,KeyC:128};
  const LEVEL_COUNTS=[64,128,256,512,786,1024];

  class KeyboardState {
    constructor() { this.down = new Set(); this.action = 0; }
    get mask() { let mask=0; for (const code of this.down) mask |= MAP[code] || 0; return mask; }
    press(code) {
      if (!MAP[code] || this.down.has(code)) return false;
      const was=this.mask; this.down.add(code);
      if ((MAP[code] & 192) && !(was & MAP[code])) this.action=(this.action+1)>>>0;
      return true;
    }
    release(code) { return this.down.delete(code); }
    clear() { this.down.clear(); }
  }

  class ControlPump {
    constructor({send, now=()=>performance.now(), setTimer=(fn,delay)=>setTimeout(fn,delay), clearTimer=id=>clearTimeout(id), onError=()=>{}}) {
      this.send=send; this.now=now; this.setTimer=setTimer; this.clearTimer=clearTimer; this.onError=onError;
      this.active=false; this.inflight=false; this.latest=null; this.timer=null; this.last=-Infinity;
      this.keys=0; this.action=0;
    }
    acquire() { this.active=true; this.keys=0; this.queue(false); }
    update(keys,action) { this.keys=keys; this.action=action; if(this.active) this.queue(false); }
    clear() { this.active=false; this.keys=0; this.queue(true); }
    queue(release) {
      this.latest={keys:this.keys,action_sequence:this.action,release};
      this.schedule();
    }
    schedule() {
      if(this.inflight || this.timer !== null || !this.latest) return;
      this.timer=this.setTimer(()=>{this.timer=null; this.flush();},Math.max(0,33-(this.now()-this.last)));
    }
    async flush() {
      if(this.inflight || !this.latest) return;
      const state=this.latest; this.latest=null; this.inflight=true; this.last=this.now();
      try {
        const response=await this.send(state);
        if(!response.ok) throw new Error(response.status===409 ? 'Another tab owns control. Release it before acquiring here.' : 'Input rejected ('+response.status+').');
      } catch(error) {
        this.active=false; this.keys=0;
        // One bounded zero release follows a failed active heartbeat. A failed release relies on the lease.
        this.latest=state.release ? null : {keys:0,action_sequence:this.action,release:true};
        this.onError(error);
      } finally {
        this.inflight=false;
        if(this.active && !this.latest) this.latest={keys:this.keys,action_sequence:this.action,release:false};
        this.schedule();
      }
    }
  }

  function formatValue(value,name) {
    if(value===null || value===undefined) return '—';
    if(name.endsWith('fps_x100')) return (value/100).toFixed(2);
    return String(value);
  }

  function liveMetricRows(view,stale) {
    if(stale) return [];
    const display=view?.telemetry?.display || {};
    return FIELDS.filter(name=>Number.isFinite(display[name])).map(name=>[name,display[name]]);
  }

  function benchmarkMetrics(data) {
    for(const name of ['before','after','return']) {
      const s=data.game[name];
      if(!s || s.target!==512 || s.frames!==3600 || ['work_miss','late_present','under','errors'].some(k=>s[k]!==0))
        throw new Error('Unqualified normal512 comparison');
    }
    const positive=value=>{
      if(typeof value!=='number' || !Number.isFinite(value) || value<=0) throw new Error('Invalid benchmark measurement');
      return value;
    };
    const budget=1e6/positive(data.conditions.target_fps);
    const peak=positive(data.conditions.axi_clock_hz)*positive(data.conditions.axi_data_bits)/8;
    const game={},copy={};
    for(const name of ['before','after']) {
      const g=data.game[name],c=data.copy[name];
      game[name]={work_ms:positive(g.work_mean_us)/1000,max_ms:positive(g.work_max_us)/1000,
        fps:positive(g.fps_x10)/10,budget_percent:g.work_mean_us/budget*100,
        headroom_ms:(budget-g.work_mean_us)/1000};
      const time=positive(c.us),pixels=positive(c.width)*positive(c.height);
      const read=positive(c.rd),write=positive(c.wr);
      copy[name]={time_ms:time/1000,mpixels_s:pixels/time,read_mb_s:read/time,write_mb_s:write/time,
        total_mb_s:(read+write)/time,read_util_percent:read/(time/1e6)/peak*100,
        write_util_percent:write/(time/1e6)/peak*100};
    }
    const a=data.copy.before,b=data.copy.after;
    if(a.width!==b.width || a.height!==b.height || a.rd!==b.rd || a.wr!==b.wr) throw new Error('Mismatched Copy workloads');
    return {game,copy,work_reduction_percent:(1-game.after.work_ms/game.before.work_ms)*100,
      pixel_gain_percent:(copy.after.mpixels_s/copy.before.mpixels_s-1)*100};
  }

  function kernelMetrics(s) {
    for(const key of ['frames','wall_us','work_us','max_work_us','render_call_us','pixels'])
      if(!Number.isFinite(s[key]) || s[key]<=0)throw new Error('Invalid measurement window');
    for(const key of ['logic_us','build_us','present_us','rd','wr','cache','work_miss'])
      if(!Number.isFinite(s[key]) || s[key]<0)throw new Error('Invalid measurement counter');
    if(s.under!==0 || s.error!==0 || s.logic_us+s.build_us+s.render_call_us+s.present_us>s.wall_us)
      throw new Error('Unhealthy or overlapping measurement');
    return {fps:s.frames*1e6/s.wall_us,work_mean_ms:s.work_us/s.frames/1000,max_work_ms:s.max_work_us/1000,
      cpu_known_ms:(s.logic_us+s.build_us)/s.frames/1000,cpu_known_percent:(s.logic_us+s.build_us)/s.wall_us*100,
      driver_ms:s.render_call_us/s.frames/1000,present_ms:s.present_us/s.frames/1000,
      processed_mp_s:s.pixels/s.wall_us,render_processed_mp_s:s.pixels/s.render_call_us,
      read_mb_s:s.rd/s.wall_us,write_mb_s:s.wr/s.wall_us,total_mb_s:(s.rd+s.wr)/s.wall_us,
      render_mb_s:(s.rd+s.wr)/s.render_call_us,
      read_util_percent:s.rd/s.wall_us/400*100,write_util_percent:s.wr/s.wall_us/400*100,work_miss:s.work_miss};
  }

  class SnapshotBuffer {
    constructor(limit=600) { this.limit=limit; this.rows=[]; this.last=null; }
    add(snapshot,received) {
      const identity=[snapshot.session,snapshot.sequence,snapshot.words[0],snapshot.words[1]].join(':');
      if(identity===this.last) return false;
      this.last=identity;
      this.rows.push({received,session:snapshot.session || 0,sequence:snapshot.sequence,words:snapshot.words.slice()});
      if(this.rows.length>this.limit) this.rows.shift();
      return true;
    }
    csv() {
      const header=['received_utc','session','snapshot_id',...FIELDS];
      return [header.join(','),...this.rows.map(row=>[row.received,row.session,row.sequence,...row.words].join(','))].join('\r\n')+'\r\n';
    }
  }

  class TelemetryFreshness {
    constructor() { this.identity=null;this.anchor=0;this.age=0;this.flags=0;this.cpuObserved=null;this.failed=false; }
    observe(view,now) {
      this.failed=false;
      const t=view.telemetry;
      if(!t) {this.identity=null;this.flags=0;return;}
      const identity=[t.session,t.sequence,t.words[0],t.words[1]].join(':');
      const age=Math.max(0,Number(view.age_ms)||0);
      const fresh=identity!==this.identity;
      this.age=fresh?age:Math.max(age,this.age+Math.max(0,now-this.anchor));
      this.identity=identity;this.anchor=now;this.flags=t.words[21];
      // Time of the last fresh telemetry observation, NOT the CPU sample time.
      if(fresh && (this.flags&(1<<17)) && !(this.flags&32)) this.cpuObserved=now-this.age;
    }
    disconnect() {this.failed=true;}
    view(now) {
      const age=this.identity===null?null:this.age+Math.max(0,now-this.anchor);
      return {stale:this.failed || age===null || age>=500,snapshot_age_ms:age,
        gpu_age_ms:(this.flags&(1<<16))?age:null,
        cpu_valid:!!(this.flags&(1<<17)),cpu_stale:!!(this.flags&32),
        cpu_observation_age_ms:this.cpuObserved===null?null:Math.max(0,now-this.cpuObserved)};
    }
  }

  function gameView(view) {
    const flags=view?.telemetry?.words[21]||0,supported=!!(flags&(1<<11));
    const split=view?.telemetry?.words[0]===0x20261027 && (flags&0x102)===0x102;
    const phase=supported?(flags&(1<<10)?'menu':split?'split':flags&(1<<13)?'performance':'play'):'unknown';
    const maxLevel=flags&(1<<14)?6:4,index=LEVEL_COUNTS.indexOf(view?.telemetry?.words[3]);
    const pending=['pending','await_snapshot'].includes(view?.game?.state);
    const ready=supported && !view.stale && (view.age_ms==null || view.age_ms<500) && !pending;
    return {supported,phase,level:phase==='play' && index>=0 && index<maxLevel?index+1:null,maxLevel,
      canStart:ready && phase==='menu',canMenu:ready,pending,canPerformance:ready && phase==='menu' && !!(flags&(1<<12))};
  }

  function splitMetrics(view,stale) {
    const w=view?.telemetry?.words;
    if(stale || view?.stale || view?.simulated || view?.age_ms>=500 || gameView(view).phase!=='split' ||
       (w[21]&0x30000) || ![256,512].includes(w[3]) || w[2]>15000 ||
       ![w[2],w[5],w[6]].every(v=>Number.isInteger(v) && v>=0)) return null;
    return {target:w[3],elapsed_ms:w[2],cpu:w[6]/100,gpu:w[5]/100};
  }
  class SplitResults {
    constructor(){this.rows=new Map();this.last=null;}
    observe(view,stale) {
      const m=splitMetrics(view,stale);if(!m){this.last=null;return;}
      const session=view.telemetry.session;
      if(!this.last || session!==this.last.session ||
         (m.target===256 && this.last.target===512) ||
         (m.target===this.last.target && m.elapsed_ms<this.last.elapsed_ms))this.rows.clear();
      this.last={...m,session};
      if(m.elapsed_ms===15000)this.rows.set(m.target,m);
    }
  }

  function modeText(view) {
    const flags=view?.telemetry?.words[21]||0,phase=gameView(view).phase;
    const label=phase==='menu'?'难度选择菜单':phase==='split'?'CPU / GPU 同屏对比':phase==='performance'?'性能挑战':
      flags&2?'CPU/GPU比较回放':flags&4?'资源加载':flags&1?'GPU互动游戏':'等待板端场景';
    return [label,...[[8,'本地备用素材'],[16,'控制已握手'],[32,'CPU旧对照已过期'],[512,'恢复状态']]
      .filter(([bit])=>flags&bit).map(([,text])=>text)].join(' · ');
  }

  async function boot() {
    const $=id=>document.getElementById(id);
    const banner=$('banner'), control=$('control-status'), keys=new KeyboardState(), samples=new SnapshotBuffer(), splitScores=new SplitResults();
    // Archived evidence loads independently: a disconnected board must not erase the comparison.
    fetch('/benchmarks.json',{cache:'no-store'}).then(response=>{
      if(!response.ok) throw new Error('历史实测文件未加载');
      return response.json();
    }).then(data=>{
      const final=data.final_release;
      if(final && final.rows.length===2 && final.rows.every(r=>r.window_ms===15000 && r.gpu_frames>0 && r.cpu_frames>0)) {
        $('release-date').textContent=final.recorded_on+' 最终版 · 已保存的实板成绩，非实时';
        for(const r of final.rows) {
          const tr=document.createElement('tr');
          for(const value of [r.target,(r.cpu_fps_x100/100).toFixed(2),(r.gpu_fps_x100/100).toFixed(2),r.cpu_frames+' / '+r.gpu_frames]) {
            const td=document.createElement('td');td.textContent=value;tr.append(td);
          }
          $('release-scores').append(tr);
        }
        $('release-identity').textContent='BIT '+final.bit_sha256+'\nBIN '+final.firmware_sha256+'\n证据 '+final.evidence;
      }
      const m=benchmarkMetrics(data);
      $('work-gain').textContent=m.work_reduction_percent.toFixed(1)+'%';
      $('pixel-gain').textContent=m.pixel_gain_percent.toFixed(1)+'%';
      $('copy-bandwidth').textContent=m.copy.after.total_mb_s.toFixed(2)+' MB/s';
      function row(target,label,before,after) {
        const tr=document.createElement('tr');
        for(const [tag,text] of [['th',label],['td',before],['td',after]]) {
          const cell=document.createElement(tag);cell.textContent=text;tr.append(cell);
        }
        $(target).append(tr);
      }
      for(const [label,key,digits,unit] of [
        ['整帧FPS（刷新率封顶）','fps',1,' FPS'],['平均帧工作时间（含GPU等待）','work_ms',3,' ms'],
        ['最大帧工作时间','max_ms',3,' ms'],['60FPS工作预算占用（非CPU占用率）','budget_percent',1,'%'],
        ['平均帧预算余量','headroom_ms',3,' ms']]) {
        row('comparison-game',label,m.game.before[key].toFixed(digits)+unit,m.game.after[key].toFixed(digits)+unit);
      }
      for(const [label,key,digits,unit] of [
        ['背景Copy耗时','time_ms',3,' ms'],['Copy像素吞吐','mpixels_s',2,' MPixel/s'],
        ['GPU有效读带宽','read_mb_s',2,' MB/s'],['GPU有效写带宽','write_mb_s',2,' MB/s'],
        ['有效读写合计','total_mb_s',2,' MB/s'],['读通道等效利用率','read_util_percent',1,'%'],
        ['写通道等效利用率','write_util_percent',1,'%']]) {
        row('comparison-copy',label,m.copy.before[key].toFixed(digits)+unit,m.copy.after[key].toFixed(digits)+unit);
      }
      $('comparison-source').textContent=data.recorded_on+' 历史实板 · 960×540 RGB565 · 100MHz · 两组各用同一BIN；非当前实时成绩';
      $('comparison-return').textContent='A/B/A回测：'+data.game.before.work_mean_us/1000+' → '+
        data.game.after.work_mean_us/1000+' → '+data.game.return.work_mean_us/1000+
        ' ms；每组3600帧，超预算/迟到/新增下溢/错误均0。包含死亡等待/重开，可见499–504，Alpha66–67。';
      $('comparison-identity').textContent='证据提交 '+data.source_commit+' · ZIP SHA256 '+data.evidence.sha256+
        '\n优化前BIT '+data.versions.before.bit_sha256+'\n优化后BIT '+data.versions.after.bit_sha256+
        '\n512探针BIN '+data.game.firmware_sha256+'\nCopy探针BIN '+data.copy.firmware_sha256+
        '\n仓库证据 '+data.evidence.archive;
      if(data.kernel) {
        const reference=['before','after','return'].map(name=>data.kernel[name].find(s=>s.target===512));
        if(reference.some(s=>!s || s.frames!==600 || s.alpha!==64) ||
           ['pixels','rd','wr','cache','state_crc','list_crc'].some(key=>reference.some(s=>s[key]!==reference[0][key])))
          throw new Error('Mismatched reference workload');
        const ref=reference.map(kernelMetrics)[1];
        $('overview-ddr').textContent=ref.total_mb_s.toFixed(2);
        $('overview-risc').textContent=ref.cpu_known_percent.toFixed(2)+'%';
        $('reference-context').textContent='已保存专项实测 · '+data.kernel.recorded_on+' · 512 全活动精灵 + 64 Alpha · 600 帧。DDR 与 RISC 数值来自该记录，不是当前实时数据。';
        function showKernel() {
          const target=Number($('kernel-target').value),records=['before','after','return'].map(name=>data.kernel[name].find(s=>s.target===target));
          if(records.some(s=>!s || s.frames!==600 || s.alpha!==Math.ceil(target/8)) ||
              ['pixels','rd','wr','cache','state_crc','list_crc'].some(key=>records.some(s=>s[key]!==records[0][key])))
            throw new Error('Mismatched diagnostic workload');
          const result=records.map(kernelMetrics);
          $('comparison-kernel').replaceChildren();
          for(const [label,key,digits,unit] of [
            ['专项场景整帧FPS（非游戏资格）','fps',2,' FPS'],['平均帧工作时间','work_mean_ms',3,' ms'],
            ['软核逻辑＋命令构建 / 帧','cpu_known_ms',3,' ms'],['软核已测工作占比（非总占用率）','cpu_known_percent',2,'%'],
            ['驱动提交＋GPU轮询 / 帧','driver_ms',3,' ms'],['PRESENT与同步等待 / 帧','present_ms',3,' ms'],
            ['处理像素吞吐（完整测量期）','processed_mp_s',2,' MPixel/s'],
            ['GPU渲染调用期处理吞吐','render_processed_mp_s',2,' MPixel/s'],
            ['GPU读写有效带宽（完整测量期）','total_mb_s',2,' MB/s'],
            ['GPU读写有效带宽（渲染调用期）','render_mb_s',2,' MB/s'],
            ['整期GPU侧AXI读通道等效利用率','read_util_percent',2,'%'],
            ['整期GPU侧AXI写通道等效利用率','write_util_percent',2,'%'],['超60Hz工作预算帧数','work_miss',0,' / 600']]) {
            row('comparison-kernel',label,result[0][key].toFixed(digits)+unit,result[1][key].toFixed(digits)+unit);
          }
          $('kernel-return').textContent='同一测量BIN · 每组30帧预热＋600个连续PRESENT间隔 · A/B/A帧工作均值 '+
            result.map(s=>s.work_mean_ms.toFixed(3)).join(' → ')+' ms；三组像素/读写/Cache字节、最终状态与列表CRC一致，新增下溢/错误均0。';
        }
        showKernel();$('kernel-target').addEventListener('change',showKernel);$('kernel-panel').hidden=false;
        $('kernel-source').textContent=data.kernel.recorded_on+' 新增实板测量 · 测量BIN SHA256 '+data.kernel.firmware_sha256;
      }
      $('comparison-values').hidden=false;
    }).catch(()=>{
      $('comparison-source').textContent='历史实测未加载或不一致，不显示旧值／猜测值；实时控制不受影响。';
      $('reference-context').textContent='专项实测未加载或不一致；当前实时控制不受影响。';
      $('overview-ddr').textContent='—';$('overview-risc').textContent='—';
    });
    const client=Array.from(crypto.getRandomValues(new Uint8Array(16)),v=>v.toString(16).padStart(2,'0')).join('');
    let token, simulated=false,choice=null,gameSending=false,requestId=0,restartUntil=0,splitRequest=null;
    try {
      const response=await fetch('/api/bootstrap',{cache:'no-store'});
      if(!response.ok) throw new Error('Gateway unavailable');
      const data=await response.json(); token=data.token; simulated=data.simulated;
    } catch(error) { banner.textContent=error.message; return; }
    const pump=new ControlPump({send:state=>fetch('/api/control',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({token,client,...state}),keepalive:state.release}),
      onError:error=>{keys.clear();control.textContent=error.message; $('acquire').disabled=false;}});
    function clear() {
      choice=null;
      splitRequest=null;
      keys.clear();
      $('keys').textContent='0x00';
      if(pump.active || pump.inflight) pump.clear();
      control.textContent='控制权已释放，按键已清除。'; $('acquire').disabled=false;
    }
    $('acquire').addEventListener('click',()=>{
      if(document.hidden || !document.hasFocus()) return;
      keys.clear(); pump.acquire(); $('acquire').disabled=true;
      control.textContent='等待开发板确认…';
    });
    $('release').addEventListener('click',clear);
    function choose(opcode,level) {
      if(document.hidden || !document.hasFocus() || gameSending || choice) return;
      keys.clear();$('keys').textContent='0x00';pump.update(0,keys.action);
      requestId=(requestId+1)>>>0;if(!requestId) requestId=1;
      choice={opcode,level,request_id:requestId,deadline:performance.now()+2000};
      if(!pump.active) {pump.acquire();$('acquire').disabled=true;}
      $('game-status').textContent='正在获取控制并等待开发板确认…';
    }
    for(let level=1;level<=LEVEL_COUNTS.length;level++) $('level-'+level).addEventListener('click',()=>choose('start',level));
    $('reselect').addEventListener('click',()=>choose('menu',0));
    $('split-menu').addEventListener('click',()=>choose('menu',0));
    $('performance-menu').addEventListener('click',()=>choose('menu',0));
    $('performance-start').addEventListener('click',()=>choose('performance',0));
    $('split-start').addEventListener('click',()=>{
      if(document.hidden || !document.hasFocus() || splitRequest || choice || gameSending) return;
      keys.clear();splitRequest={deadline:performance.now()+3000,sent:false};
      if(!pump.active){pump.acquire();$('acquire').disabled=true;}
    });
    document.addEventListener('keydown',event=>{
      if(!pump.active || event.repeat || event.ctrlKey || event.metaKey || event.altKey || !MAP[event.code]) return;
      const gv=lastView?gameView(lastView):null;
      if(gv?.supported && (!['play','performance'].includes(gv.phase) ||
          gv.phase==='performance' && event.code==='KeyC' || gv.pending || choice || gameSending || performance.now()<restartUntil)) return;
      event.preventDefault(); if(keys.press(event.code)) pump.update(keys.mask,keys.action);
      if(event.code==='KeyR' && gv?.supported) {
        keys.clear();restartUntil=performance.now()+100;
        setTimeout(()=>{if(pump.active)pump.update(0,keys.action);},100);
      }
      $('keys').textContent='0x'+keys.mask.toString(16).padStart(2,'0');
    });
    document.addEventListener('keyup',event=>{
      if(!MAP[event.code]) return;
      event.preventDefault(); if(keys.release(event.code)) pump.update(keys.mask,keys.action);
      $('keys').textContent='0x'+keys.mask.toString(16).padStart(2,'0');
    });
    window.addEventListener('blur',clear);
    document.addEventListener('visibilitychange',()=>{if(document.hidden) clear();});
    // Keep one POST in flight even on page close. If unload cancels it, the 250 ms gateway lease clears it.
    window.addEventListener('pagehide',clear);
    window.addEventListener('beforeunload',clear);
    $('export').addEventListener('click',()=>{
      const url=URL.createObjectURL(new Blob([samples.csv()],{type:'text/csv;charset=utf-8'}));
      const link=document.createElement('a');link.href=url;link.download='aethergx-v3-raw-telemetry.csv';link.click();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    });
    const table=$('metrics');
    for(const name of FIELDS) {
      const row=document.createElement('tr'); const label=document.createElement('th');const value=document.createElement('td');
      label.textContent=name; value.id='metric-'+name;row.hidden=true;row.append(label,value);table.append(row);
    }
    const history=[];let lastView=null;let streamFailed=false,lastPhase=null,lastGameState=null;
    const freshness=new TelemetryFreshness();
    function draw() {
      const canvas=$('chart'),ctx=canvas.getContext('2d'),w=canvas.width,h=canvas.height;
      ctx.clearRect(0,0,w,h);ctx.strokeStyle='#29415a';ctx.lineWidth=1;
      for(let y=30;y<h;y+=40){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke();}
      for(const [field,color] of [['gpu_full_frame_fps_x100','#52d8ba'],['cpu_full_frame_fps_x100','#e9b86b']]) {
        ctx.strokeStyle=color;ctx.lineWidth=2;ctx.beginPath();let started=false;
        for(let i=0;i<history.length;i++) {
          const value=history[i][field]; if(value==null){started=false;continue;}
          const x=i*(w/119),y=h-10-Math.min(value/100,70)*(h-30)/70;
          if(started)ctx.lineTo(x,y);else ctx.moveTo(x,y);started=true;
        }ctx.stroke();
      }
    }
    const events=new EventSource('/api/events');
    events.onmessage=event=>{
      const view=JSON.parse(event.data);lastView=view;streamFailed=false;
      const gv=gameView(view);
      if(gv.phase!==lastPhase || gv.pending || view.game?.state!==lastGameState) {
        keys.clear();$('keys').textContent='0x00';if(pump.active)pump.update(0,keys.action);
        lastPhase=gv.phase;lastGameState=view.game?.state;
      }
      freshness.observe(view,performance.now());
      splitScores.observe(view,freshness.view(performance.now()).stale);
      const t=view.telemetry;
      if(t && samples.add(t,new Date().toISOString())) {
        history.push({...t.display});if(history.length>120)history.shift();draw();
      }
      if(t) {
        $('sprites').textContent=t.raw.visible_sprites+' / '+t.raw.requested_sprites;
        $('mode').textContent=modeText(view);
      }
      $('packet-drops').textContent=String(view.dropped_packets);
      if(pump.active) control.textContent=view.acknowledged ? '当前页面已获取控制权' : '等待开发板确认…';
    };
    events.onerror=()=>{streamFailed=true;freshness.disconnect();splitScores.observe(null,true); clear();};
    setInterval(()=>{
      const ages=freshness.view(performance.now());
      const stale=!lastView || lastView.stale || ages.stale || streamFailed;
      if(stale)splitScores.observe(null,true);
      const metrics=liveMetricRows(lastView,stale),valid=new Map(metrics);
      if(stale)$('mode').textContent='当前没有新鲜板端状态';
      $('history-panel').hidden=!history.some(row=>row.gpu_full_frame_fps_x100!=null || row.cpu_full_frame_fps_x100!=null);
      for(const name of FIELDS) {
        const cell=$('metric-'+name);cell.parentElement.hidden=!valid.has(name);
        if(valid.has(name))cell.textContent=formatValue(valid.get(name),name);
      }
      $('live-empty').hidden=metrics.length!==0;
      const gpu=valid.get('gpu_full_frame_fps_x100'),cpu=valid.get('cpu_full_frame_fps_x100');
      $('gpu-card').hidden=gpu===undefined;
      $('cpu-card').hidden=cpu===undefined;
      $('sprites-card').hidden=stale || !lastView?.telemetry;
      $('gpu-fps').textContent=formatValue(gpu,'gpu_full_frame_fps_x100');
      $('cpu-fps').textContent=formatValue(cpu,'cpu_full_frame_fps_x100');
      const gv=gameView(lastView || {stale:true});
      const splitLive=splitMetrics(lastView,stale);
      const liveFps=splitLive && splitLive.elapsed_ms<15000?splitLive.gpu:gpu===undefined?null:gpu/100;
      $('overview-fps').textContent=liveFps===null?'—':liveFps.toFixed(2);
      $('overview-fps-note').textContent=liveFps===null?'等待游戏或同屏展示':
        (simulated?'模拟 · ':'实时 · ')+(splitLive?'480 × 270 视区':'960 × 540 整帧')+' · FPS';
      const scene=!stale && ['play','performance','split'].includes(gv.phase) && lastView?.telemetry?.raw;
      $('overview-sprites').textContent=scene?scene.visible_sprites+' / '+scene.requested_sprites:'—';
      $('overview-sprites-note').textContent=scene?(simulated?'模拟 · ':'实时 · ')+'可见 / 请求数量':'可见 / 请求数量';
      $('split-live').hidden=!splitLive || splitLive.elapsed_ms===15000;
      if(splitLive) {
        $('split-cpu').textContent=splitLive.cpu.toFixed(2);
        $('split-gpu').textContent=splitLive.gpu.toFixed(2);
        $('split-progress').value=splitLive.elapsed_ms;
      }
      for(const target of [256,512]) {
        const score=splitScores.rows.get(target);
        $('split-score-'+target).textContent=score?'CPU '+score.cpu.toFixed(2)+' / GPU '+score.gpu.toFixed(2)+' FPS':'尚未收到完整成绩';
      }
      const splitCapable=lastView?.telemetry?.words[0]===0x20261027;
      $('split-start').disabled=stale || !splitCapable || !gv.canStart || !!choice || gameSending || !!splitRequest;
      $('split-status').textContent=gv.phase==='split'?(stale?'同屏状态已过期，等待开发板…':
        '正在 HDMI 独立刷新 · '+lastView.telemetry.words[3]+' 档 · '+(lastView.telemetry.words[2]/1000).toFixed(1)+' / 15.0 秒'+
        (lastView.telemetry.words[3]===512 && lastView.telemetry.words[2]===15000?' · 已完成，成绩保留':'')):
        !splitCapable?'等待支持同屏对比的开发板':gv.phase==='menu'?'就绪：左 CPU，右 GPU；两档各 15 秒。':'请先点击“一键重选难度”返回菜单。';
      if(splitRequest && gv.phase==='split')splitRequest=null;
      if(splitRequest && performance.now()>=splitRequest.deadline){splitRequest=null;keys.clear();if(pump.active)pump.update(0,keys.action);}
      if(splitRequest && !splitRequest.sent && !stale && gv.canStart && lastView.acknowledged && pump.active){
        splitRequest.sent=true;keys.press('KeyC');pump.update(keys.mask,keys.action);
        setTimeout(()=>{keys.clear();if(pump.active)pump.update(0,keys.action);},150);
      }
      $('difficulty-options').hidden=['play','performance'].includes(gv.phase);
      $('performance-start').disabled=!gv.canPerformance || stale || !!choice || gameSending;
      const perf=lastView?.performance;
      $('performance-result').textContent=gv.phase!=='performance'?'独立全活动负载；普通游戏和CPU渲染不改变。':
        stale || !perf || perf.stale?'等待新鲜板端挑战数据，旧成绩不作当前结论':
        ['','预热','搜索','60秒复核','60秒复核通过','达到本次配置容量（非硬件极限）','失败／成绩失效'][perf.stage]+
        ' · 活动 '+perf.target+' · 窗口 '+perf.frames+' 帧 · 已复核最佳 '+perf.best;
      $('current-difficulty').textContent=gv.level?'当前难度 '+gv.level+' · '+LEVEL_COUNTS[gv.level-1]+' Sprite 请求档位':'';
      $('reselect').disabled=!gv.canMenu || stale || !!choice || gameSending;
      $('split-menu').disabled=$('reselect').disabled;
      $('performance-menu').disabled=$('reselect').disabled;
      for(let level=1;level<=LEVEL_COUNTS.length;level++) $('level-'+level).disabled=!gv.canStart || level>gv.maxLevel || stale || !!choice || gameSending;
      if(choice && performance.now()>=choice.deadline) {choice=null;$('game-status').textContent='请求超时，状态未知；等待真实板端状态。';}
      if(choice && !gameSending && !stale && lastView.acknowledged && pump.active && gv.supported) {
        const selected=choice;gameSending=true;
        fetch('/api/game',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token,client,
          opcode:selected.opcode,level:selected.level,request_id:selected.request_id})})
          .then(async response=>{if(!response.ok)throw new Error('操作未接受 ('+response.status+')');
            await response.json();$('game-status').textContent='命令已提交，等待执行确认与新场景快照…';})
          .catch(error=>{$('game-status').textContent=error.message;})
          .finally(()=>{if(choice===selected)choice=null;gameSending=false;});
      } else if(!choice && !gameSending) {
        const state=lastView?.game?.state;
        $('game-status').textContent=stale?'开发板状态过期，不能开始新局':!gv.supported?'当前固件不支持难度菜单（原键盘仍可用）':
          state==='unknown'?'请求结果未知；以下界面以真实板端快照为准':state==='rejected'?'板端拒绝操作，请按当前状态重试':
          gv.pending?'等待板端执行确认与新快照…':gv.phase==='menu'?'请选择难度，游戏逻辑由 Sapphire 执行':
          gv.phase==='performance'?'软核自动加压；方向键控制第一架飞机，R重新挑战，重选退出':'键盘控制飞机；死亡自动回到难度选择';
      }
      banner.className=stale?'warning':'healthy';
      banner.textContent=(simulated?'SIMULATED — 模拟连接，不是实板成绩。 ':'')+
        (stale?'未连接开发板或遥测已过期；上方历史对照仍可查阅':'实时遥测正常')+
        (ages.snapshot_age_ms!==null?' · 快照 '+Math.round(ages.snapshot_age_ms)+' ms 前':'');
      $('gpu-age').textContent=ages.gpu_age_ms===null?'':
        '快照 '+Math.round(ages.gpu_age_ms)+' ms 前'+(stale?' · 已过期':'');
      $('cpu-age').textContent=!ages.cpu_valid?'':
        (ages.cpu_stale?'Expired retained CPU result':'CPU result reported fresh')+
        (ages.cpu_observation_age_ms===null?' · Fresh observation time unknown':
          ' · Last fresh observation '+Math.round(ages.cpu_observation_age_ms)+' ms ago')+
        ' · CPU sample age not transmitted';
      $('chart').classList.toggle('stale',stale);
    },100);
  }

  const api={ControlPump,KeyboardState,SnapshotBuffer,TelemetryFreshness,formatValue,gameView,benchmarkMetrics,kernelMetrics,liveMetricRows,modeText,splitMetrics,SplitResults};
  if(typeof module!=='undefined' && module.exports) module.exports=api;
  if(typeof document!=='undefined') document.addEventListener('DOMContentLoaded',boot);
  root.AetherGXDashboard=api;
})(typeof globalThis!=='undefined'?globalThis:this);
