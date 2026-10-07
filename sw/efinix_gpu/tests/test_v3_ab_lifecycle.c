/* Accelerated software lifecycle, not wall-clock/FPGA/FPS qualification.
 * Production modules consume real wire packets via a test-only APB RX model. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "v3_runtime.h"

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x); exit(1); } } while (0)
typedef struct { uint8_t data[32]; uint32_t age; } rx_record;
static struct { rx_record fifo[4], snapshot; unsigned head,count,valid; } hw;
static v3_runtime runtime;
static replay_recording saved_record;
static bullet_state expected,saved_live;
static bullet_stream actual_stream,expected_stream;
static nc_device device;
static nc_input network;
static game_input input;
static uint32_t now_ms,session,sequence,action;
static unsigned live_steps,replay_steps,comparisons;

static uint32_t crc(const uint8_t *p,unsigned n) {
 uint32_t value=UINT32_MAX;
 while(n--) {
  value^=*p++;
  for(unsigned bit=0;bit<8;bit++) value=(value>>1)^((value&1u)?UINT32_C(0xedb88320):0);
 }
 return ~value;
}
static void be(uint8_t *p,uint32_t v) {
 for(unsigned i=0;i<4;i++) p[i]=(uint8_t)(v>>(24-8*i));
}
static void enqueue(unsigned type,uint32_t sid,uint32_t seq,uint16_t keys,uint32_t event,uint32_t age) {
 CHECK(hw.count<4);
 rx_record *r=&hw.fifo[(hw.head+hw.count)%4];
 memset(r,0,sizeof *r);be(r->data,UINT32_C(0x41474331));
 r->data[4]=1;r->data[5]=(uint8_t)type;r->data[7]=32;
 be(r->data+8,sid);be(r->data+12,seq);be(r->data+16,keys);be(r->data+20,event);
 be(r->data+28,crc(r->data,28));r->age=age;++hw.count;
}
uint32_t nc_io_read(uintptr_t address) {
 CHECK(address>=GPU_APB_BASE && address<GPU_APB_BASE+0x400u && !(address&3u));
 unsigned reg=(unsigned)(address-GPU_APB_BASE);
 if(reg==0x300u) return UINT32_C(0x4d475431);
 if(reg==0x304u) return (hw.count?1u:0u)|(hw.valid?2u:0u); /* TX deliberately busy */
 if(reg==0x310u) {CHECK(hw.valid);return hw.snapshot.age;}
 CHECK(reg>=0x320u && reg<=0x33cu && hw.valid);
 const uint8_t *p=hw.snapshot.data+reg-0x320u;
 return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
void nc_io_write(uintptr_t address,uint32_t value) {
 CHECK(value==1);
 if(address==GPU_APB_BASE+0x308u) {
  CHECK(hw.count && !hw.valid);hw.snapshot=hw.fifo[hw.head];hw.valid=1;
 } else {
  CHECK(address==GPU_APB_BASE+0x30cu && hw.valid);
  hw.head=(hw.head+1)%4;--hw.count;hw.valid=0;
 }
}
void nc_io_fence(void) { }
static void poll(void) {
 CHECK(nc_poll(&device,now_ms,&network)>=0);
 input_update(&input,&network);CHECK(!hw.count && !hw.valid);
}
static void keys(uint16_t held,int new_action) {
 now_ms+=17;
 if(new_action) ++action;
 enqueue(2,session,++sequence,held,action,0);poll();
 CHECK(network.connected && network.session==session && network.keys==held);
}
static void equal_state(const bullet_state *a,const bullet_state *b) {
 CHECK(a->seed==b->seed && a->tick==b->tick && a->count==b->count);
 CHECK(a->player_x==b->player_x && a->player_y==b->player_y);
 CHECK(a->round_tick==b->round_tick && a->score==b->score && a->grazes==b->grazes);
 CHECK(a->invulnerable==b->invulnerable && a->game_over_ticks==b->game_over_ticks && a->hp==b->hp);
 for(unsigned i=0;i<a->count;i++) {
  const bullet_object *x=&a->objects[i],*y=&b->objects[i];
  CHECK(x->x==y->x && x->y==y->y && x->vx==y->vx && x->vy==y->vy);
  CHECK(x->age==y->age && x->kind==y->kind && x->shape==y->shape && x->grazed==y->grazed);
 }
}
static void equal_commands(void) {
 CHECK(!game_build(&runtime.game,GPU_FRAMEBUFFER_A,1,1,BULLET_MAX_COMMANDS,&actual_stream));
 CHECK(!game_build(&expected,GPU_FRAMEBUFFER_A,1,1,BULLET_MAX_COMMANDS,&expected_stream));
 CHECK(actual_stream.count==expected_stream.count && actual_stream.visible==expected_stream.visible);
 CHECK(actual_stream.scene_pixels==expected_stream.scene_pixels);
 CHECK(actual_stream.alpha_commands==expected_stream.alpha_commands && actual_stream.alpha_pixels==expected_stream.alpha_pixels);
 CHECK(actual_stream.count<=BULLET_MAX_COMMANDS && actual_stream.alpha_commands<=BULLET_MAX_TRAILS+4u);
 CHECK(actual_stream.alpha_commands>0); /* Alpha remains enabled. */
 for(unsigned i=0;i<actual_stream.count;i++) {
  const gpu_command *a=&actual_stream.commands[i],*b=&expected_stream.commands[i];
  CHECK(a->src_addr==b->src_addr && a->dst_addr==b->dst_addr && a->src_stride==b->src_stride && a->dst_stride==b->dst_stride);
  CHECK(a->width_pixels==b->width_pixels && a->height_pixels==b->height_pixels);
  CHECK(a->color==b->color && a->color_key==b->color_key && a->flags==b->flags && a->tag==b->tag && a->op==b->op && a->alpha==b->alpha);
 }
}
static void compare_round(void) {
 CHECK(runtime.mode==V3_MODE_LIVE && runtime.recording.sealed);
 saved_live=runtime.game;saved_record=runtime.recording;
 keys(V3_KEY_COMPARE,1);CHECK(input.pressed==V3_KEY_COMPARE);
 CHECK(v3_runtime_advance(&runtime,&input,16667)==0 && runtime.mode==V3_MODE_CPU);
 CHECK(v3_runtime_set_epoch(&runtime,runtime.epoch+1)==GPU_DRIVER_ARGUMENT);
 for(unsigned backend=0;backend<2;backend++) {
  replay_cursor reference;
  CHECK(!replay_begin(&saved_record,runtime.epoch,&expected,&reference));
  for(unsigned i=0;i<REPLAY_INPUT_TICKS;i++) {
   /* Valid human action/heartbeat continues, but neither backend consumes it. */
   keys(V3_KEY_RESTART|V3_KEY_COMPARE|V3_KEY_LEFT,backend==0 && i==0);
   game_input recorded;
   CHECK(replay_next(&saved_record,&reference,&recorded)==1);
   CHECK(game_update(&expected,&recorded)>=0);
   CHECK(v3_runtime_advance(&runtime,&input,999999)==1);++replay_steps;
   equal_state(&runtime.game,&expected);equal_commands();
   uint32_t flags=v3_runtime_status(&runtime,1,1,1,1,1);
   CHECK(flags&V3_STATUS_COMPARE_REPLAY);
   CHECK(!!(flags&V3_VALID_GPU_TIMING)==!!backend);
   CHECK(!!(flags&V3_STATUS_CPU_STALE)==!!backend);
   CHECK(runtime.recording.crc32==saved_record.crc32 && runtime.recording.count==600);
   CHECK(!memcmp(runtime.recording.keys,saved_record.keys,sizeof saved_record.keys));
   equal_state(&runtime.recording.initial,&saved_record.initial);
   CHECK(!v3_runtime_frame_done(&runtime));
  }
  CHECK(runtime.mode==(backend?V3_MODE_LIVE:V3_MODE_GPU));
 }
 equal_state(&runtime.game,&saved_live);
 CHECK(!runtime.recording.count && !runtime.clock.accumulator_x60 && !runtime.compare_pending);
 /* Held R/C was already observed during replay: LIVE must not retrigger it. */
 keys(V3_KEY_RESTART|V3_KEY_COMPARE|V3_KEY_LEFT,0);CHECK(!input.pressed);
 expected=saved_live;CHECK(game_update(&expected,&input)>=0);
 CHECK(v3_runtime_advance(&runtime,&input,16667)==1);++live_steps;
 equal_state(&runtime.game,&expected);CHECK(!runtime.compare_pending);
 uint32_t next_epoch=runtime.epoch+1;
 replay_cursor sentinel={.index=7,.previous=3,.active=1};
 expected=runtime.game;
 CHECK(replay_begin(&saved_record,next_epoch,&expected,&sentinel)==GPU_DRIVER_ARGUMENT);
 equal_state(&expected,&runtime.game);CHECK(sentinel.index==7 && sentinel.previous==3 && sentinel.active==1);
 CHECK(!v3_runtime_set_epoch(&runtime,next_epoch));
 CHECK(runtime.recording.resource_epoch==next_epoch && !runtime.recording.count);
 equal_state(&runtime.game,&expected);++comparisons;
}
static void lease_and_session(void) {
 keys(V3_KEY_RIGHT|V3_KEY_FIRE,0);CHECK(input.held==(V3_KEY_RIGHT|V3_KEY_FIRE));
 now_ms+=250;poll();CHECK(network.connected && network.age_ms==250 && input.held);
 ++now_ms;poll();CHECK(!network.connected && !input.held && input.released==(V3_KEY_RIGHT|V3_KEY_FIRE));
 uint32_t retired=session;
 enqueue(1,retired,1,0,0,0);enqueue(2,retired,++sequence,V3_KEY_LEFT,action,0);poll();
 CHECK(!network.connected && !input.held);
 ++session;sequence=1;action=0;
 enqueue(1,session,sequence,0,0,0);poll();CHECK(network.connected && !input.held);
 enqueue(2,retired,UINT32_C(0x7fffffff),V3_KEY_RESTART,99,0);poll();
 CHECK(network.session==session && !input.pressed && !input.held);
 keys(V3_KEY_UP|V3_KEY_DOWN|V3_KEY_FIRE,0);CHECK(input.held==V3_KEY_FIRE);
 keys(0,0);CHECK(!input.held);
}
int main(void) {
 const unsigned tiers[]={64,256,512};
 for(unsigned tier=0;tier<3;tier++) {
  memset(&hw,0,sizeof hw);input=(game_input){0};
  now_ms=UINT32_MAX-100u;session=tier+10;sequence=UINT32_MAX-2u;action=0;
  CHECK(!nc_init(&device,0));CHECK(!v3_runtime_init(&runtime,tiers[tier],7,UINT32_C(0x30001)));
  enqueue(1,session,sequence,0,0,0);poll();CHECK(network.connected);
  unsigned before_live=live_steps,before_replay=replay_steps;
  for(unsigned i=0;i<36000;i++) {
   static const uint16_t directions[]={V3_KEY_RIGHT,V3_KEY_UP,V3_KEY_LEFT,V3_KEY_DOWN};
   uint16_t held=directions[(i/100)%4]|V3_KEY_FIRE;
   if(i%90<30) held|=V3_KEY_SLOW;
   if(i==123 || i==124) held=V3_KEY_RESTART;
   keys(held,i==123);
   if(i==124) CHECK(!(input.pressed&V3_KEY_RESTART));
   CHECK(v3_runtime_advance(&runtime,&input,16667)==1);++live_steps;
   CHECK(runtime.game.count==tiers[tier] && runtime.recording.count<=600);
   CHECK(runtime.game.player_x>=8 && runtime.game.player_x<=952 && runtime.game.player_y>=80 && runtime.game.player_y<=532);
   if(i==123) CHECK(runtime.game.tick==0);
   if(i==124) CHECK(runtime.game.tick==1);
   if((i+1)%6000==0) {compare_round();lease_and_session();}
  }
  printf("PASS tier=%u live_updates=%u replay_updates=%u compares=6 (accelerated software only)\n",
   tiers[tier],live_steps-before_live,replay_steps-before_replay);
 }
 CHECK(live_steps==108018 && replay_steps==21600 && comparisons==18);
 puts("PASS A/B lifecycle: wire RX/input/runtime; leases/sessions/wrap, 18x600 CPU+GPU semantic replay, live restore/held actions, epoch isolation");
 puts("108000 scheduled LIVE updates = 30min logical quantity at 60Hz; NOT elapsed endurance, pixels, board FPS, latency, or linked RAM qualification");
 return 0;
}
