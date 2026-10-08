(function (root) {
  'use strict';
  const FIELDS = ['firmware_build_id','resource_epoch','simulation_tick','requested_sprites','visible_sprites',
    'gpu_full_frame_fps_x100','cpu_full_frame_fps_x100','pre_present_us','gpu_busy_us','command_build_us',
    'submit_blocked_us','background_copy_us','render_read_bytes','render_write_bytes','texture_cache_bytes',
    'scanout_underflow_delta','gpu_error_delta','missed_vblank_delta','asset_retry_delta','control_drop_delta',
    'input_age_ms','status_flags','p95_work_us','present_wait_us','alpha_commands','alpha_pixels','key_commands'];
  const MAP = {ArrowLeft:1,KeyA:1,ArrowRight:2,KeyD:2,ArrowUp:4,KeyW:4,ArrowDown:8,KeyS:8,
    Space:16,KeyZ:16,ShiftLeft:32,ShiftRight:32,KeyR:64,KeyC:128};

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
    if(value===null || value===undefined) return 'Unavailable';
    if(name.endsWith('fps_x100')) return (value/100).toFixed(2);
    return String(value);
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
    const phase=supported?(flags&(1<<10)?'menu':'play'):'unknown';
    const counts=[64,128,256,512],index=counts.indexOf(view?.telemetry?.words[3]);
    const pending=['pending','await_snapshot'].includes(view?.game?.state);
    const ready=supported && !view.stale && (view.age_ms==null || view.age_ms<500) && !pending;
    return {supported,phase,level:phase==='play' && index>=0?index+1:null,
      canStart:ready && phase==='menu',canMenu:ready,pending};
  }

  async function boot() {
    const $=id=>document.getElementById(id);
    const banner=$('banner'), control=$('control-status'), keys=new KeyboardState(), samples=new SnapshotBuffer();
    const client=Array.from(crypto.getRandomValues(new Uint8Array(16)),v=>v.toString(16).padStart(2,'0')).join('');
    let token, simulated=false,choice=null,gameSending=false,requestId=0,restartUntil=0;
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
      keys.clear();
      $('keys').textContent='0x00';
      if(pump.active || pump.inflight) pump.clear();
      control.textContent='Control released; keys cleared'; $('acquire').disabled=false;
    }
    $('acquire').addEventListener('click',()=>{
      if(document.hidden || !document.hasFocus()) return;
      keys.clear(); pump.acquire(); $('acquire').disabled=true;
      control.textContent='Waiting for board ACK…';
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
    for(let level=1;level<=4;level++) $('level-'+level).addEventListener('click',()=>choose('start',level));
    $('reselect').addEventListener('click',()=>choose('menu',0));
    document.addEventListener('keydown',event=>{
      if(!pump.active || event.repeat || event.ctrlKey || event.metaKey || event.altKey || !MAP[event.code]) return;
      const gv=lastView?gameView(lastView):null;
      if(gv?.supported && (gv.phase!=='play' || gv.pending || choice || gameSending || performance.now()<restartUntil)) return;
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
      label.textContent=name; value.id='metric-'+name;value.textContent='Unavailable';row.append(label,value);table.append(row);
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
      const t=view.telemetry;
      if(t && samples.add(t,new Date().toISOString())) {
        history.push({...t.display});if(history.length>120)history.shift();draw();
      }
      if(t) {
        for(const name of FIELDS) $('metric-'+name).textContent=formatValue(t.display[name],name);
        $('gpu-fps').textContent=formatValue(t.display.gpu_full_frame_fps_x100,'gpu_full_frame_fps_x100');
        $('cpu-fps').textContent=formatValue(t.display.cpu_full_frame_fps_x100,'cpu_full_frame_fps_x100');
        $('sprites').textContent=t.raw.visible_sprites+' / '+t.raw.requested_sprites;
        $('mode').textContent=['GPU live','Comparison replay','Loading','Local fallback','Control ACK','CPU expired','Probes enabled','Invalid counters','Paused','Recovery']
          .filter((_,i)=>t.raw.status_flags & (1<<i)).join(' · ') || 'No active status flags';
      }
      $('packet-drops').textContent=String(view.dropped_packets);
      if(pump.active) control.textContent=view.acknowledged ? 'This tab controls the board' : 'Waiting for board ACK…';
    };
    events.onerror=()=>{streamFailed=true;freshness.disconnect(); clear();};
    setInterval(()=>{
      const ages=freshness.view(performance.now());
      const stale=!lastView || lastView.stale || ages.stale || streamFailed;
      const gv=gameView(lastView || {stale:true});
      $('difficulty-options').hidden=gv.phase==='play';
      $('current-difficulty').textContent=gv.level?'当前难度 '+gv.level+' · '+[64,128,256,512][gv.level-1]+' Sprite 请求档位':'';
      $('reselect').disabled=!gv.canMenu || stale || !!choice || gameSending;
      for(let level=1;level<=4;level++) $('level-'+level).disabled=!gv.canStart || stale || !!choice || gameSending;
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
          gv.pending?'等待板端执行确认与新快照…':gv.phase==='menu'?'请选择难度，游戏逻辑由 Sapphire 执行':'键盘控制飞机；死亡自动回到难度选择';
      }
      banner.className=stale?'warning':'healthy';
      banner.textContent=(simulated?'SIMULATED — not board measurements. ':'')+
        (stale?'Telemetry stale / unavailable':'Telemetry current')+
        (ages.snapshot_age_ms!==null?' · Snapshot age '+Math.round(ages.snapshot_age_ms)+' ms':'');
      $('gpu-age').textContent=ages.gpu_age_ms===null?'Unavailable':
        'Snapshot age '+Math.round(ages.gpu_age_ms)+' ms'+(stale?' · stale':'');
      $('cpu-age').textContent=!ages.cpu_valid?'Unavailable — no valid CPU result':
        (ages.cpu_stale?'Expired retained CPU result':'CPU result reported fresh')+
        (ages.cpu_observation_age_ms===null?' · Fresh observation time unknown':
          ' · Last fresh observation '+Math.round(ages.cpu_observation_age_ms)+' ms ago')+
        ' · CPU sample age not transmitted';
      $('chart').classList.toggle('stale',stale);
    },100);
  }

  const api={ControlPump,KeyboardState,SnapshotBuffer,TelemetryFreshness,formatValue,gameView};
  if(typeof module!=='undefined' && module.exports) module.exports=api;
  if(typeof document!=='undefined') document.addEventListener('DOMContentLoaded',boot);
  root.AetherGXDashboard=api;
})(typeof globalThis!=='undefined'?globalThis:this);
