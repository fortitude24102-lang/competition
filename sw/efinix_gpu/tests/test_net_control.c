#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "net_control.h"

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x); exit(1); } } while (0)
typedef struct { uint8_t bytes[32]; uint32_t age; } rx_record;
static struct {
    rx_record rx[16], snapshot;
    unsigned head, count, valid, releases, writes, reads, commits, tx_ready;
    uint32_t id, tx_length, tx_mask, tx_error;
    uint8_t shadow[128], sent[128];
    unsigned sent_length, inject;
} hw;

static uint32_t crc(const uint8_t *p, unsigned n) {
    uint32_t c=UINT32_MAX;
    while(n--) {
        c^=*p++;
        for(unsigned b=0;b<8;b++) c=(c>>1)^((c&1u)?UINT32_C(0xedb88320):0);
    }
    return ~c;
}
static void be(uint8_t *p,uint32_t v) {
    p[0]=(uint8_t)(v>>24); p[1]=(uint8_t)(v>>16); p[2]=(uint8_t)(v>>8); p[3]=(uint8_t)v;
}
static uint32_t read_be(const uint8_t *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static void enqueue(unsigned type,uint32_t session,uint32_t sequence,uint32_t keys,uint32_t action,uint32_t age) {
    CHECK(hw.count<16);
    rx_record *r=&hw.rx[(hw.head+hw.count)%16];
    memset(r,0,sizeof(*r));
    be(r->bytes,UINT32_C(0x41474331)); r->bytes[4]=1; r->bytes[5]=(uint8_t)type; r->bytes[7]=32;
    be(r->bytes+8,session); be(r->bytes+12,sequence);
    be(r->bytes+16,keys); be(r->bytes+20,action); be(r->bytes+28,crc(r->bytes,28));
    r->age=age; ++hw.count;
}
static void reset(void) { memset(&hw,0,sizeof(hw)); hw.id=UINT32_C(0x4d475431); hw.tx_ready=1; }
uint32_t nc_io_read(uintptr_t address) {
    CHECK(address>=GPU_APB_BASE && address<GPU_APB_BASE+0x400u && !(address&3u));
    unsigned r=(unsigned)(address-GPU_APB_BASE); ++hw.reads;
    if(r==0x300u) return hw.id;
    if(r==0x304u) return (hw.count?1u:0u)|(hw.valid?2u:0u)|(hw.tx_ready?4u:0u)|(hw.tx_error?8u:0u);
    if(r==0x310u) { CHECK(hw.valid); return hw.snapshot.age; }
    if(r==0x314u || r==0x31cu) return 0;
    CHECK(r>=0x320u && r<=0x33cu && hw.valid);
    unsigned i=r-0x320u;
    /* An arrival during reads must not overwrite the snapshot. */
    if(hw.inject) { hw.inject=0; enqueue(2,7,3,2,0,0); }
    return hw.snapshot.bytes[i]|((uint32_t)hw.snapshot.bytes[i+1]<<8)|
           ((uint32_t)hw.snapshot.bytes[i+2]<<16)|((uint32_t)hw.snapshot.bytes[i+3]<<24);
}
void nc_io_write(uintptr_t address,uint32_t v) {
    CHECK(address>=GPU_APB_BASE && address<GPU_APB_BASE+0x400u && !(address&3u));
    unsigned r=(unsigned)(address-GPU_APB_BASE); ++hw.writes;
    if(r==0x308u) { CHECK(v==1 && hw.count && !hw.valid); hw.snapshot=hw.rx[hw.head]; hw.valid=1; return; }
    if(r==0x30cu) { CHECK(v==1 && hw.valid); hw.head=(hw.head+1)%16; --hw.count; hw.valid=0; ++hw.releases; return; }
    CHECK(hw.tx_ready); /* No writes of any TX word while busy. */
    if(r==0x3c0u) { CHECK(v==32 || v==128); hw.tx_length=v; return; }
    if(r==0x318u) {
        uint32_t needed=hw.tx_length==32?0xffu:UINT32_MAX;
        CHECK(v==1 && hw.tx_length && hw.tx_mask==needed);
        memcpy(hw.sent,hw.shadow,hw.tx_length); hw.sent_length=hw.tx_length;
        hw.tx_mask=0; hw.tx_ready=0; hw.tx_error=0; ++hw.commits; return;
    }
    CHECK(r>=0x340u && r<=0x3bcu);
    unsigned i=r-0x340u;
    hw.tx_mask|=UINT32_C(1)<<(i/4);
    for(unsigned b=0;b<4;b++) hw.shadow[i+b]=(uint8_t)(v>>(8*b));
}
void nc_io_fence(void) { }

static void initialization(void) {
    nc_device d; nc_input in;
    reset(); hw.id=0;
    CHECK(nc_init(&d,0)<0);
    CHECK(nc_poll(&d,0,&in)<0 && !in.connected && !in.keys);
    CHECK(nc_init(NULL,0)<0 && nc_init(&d,GPU_APB_BASE+1)<0);
    reset(); enqueue(1,8,1,0,0,0); enqueue(2,8,2,16,0,0);
    CHECK(nc_init(&d,0)==0 && hw.count==0 && hw.releases==2);
    CHECK(nc_poll(&d,10,&in)==0 && !in.connected && !in.keys);
    enqueue(2,8,3,16,0,0);
    CHECK(nc_poll(&d,10,&in)>0 && !in.connected);
}
static void reception_and_lease(void) {
    nc_device d; nc_input in; reset(); CHECK(!nc_init(&d,0));
    enqueue(1,7,1,0,0,0); CHECK(nc_poll(&d,100,&in)>0 && in.connected && !in.keys);
    CHECK(nc_try_publish(&d,NULL,100)>0 && hw.sent_length==32);
    CHECK(read_be(hw.sent)==UINT32_C(0x41474331) && hw.sent[5]==3);
    CHECK(read_be(hw.sent+8)==7 && read_be(hw.sent+12)==1 && read_be(hw.sent+16)==1);
    CHECK(read_be(hw.sent+28)==crc(hw.sent,28));
    enqueue(2,7,2,1,9,50); hw.inject=1;
    CHECK(nc_poll(&d,200,&in)>0 && in.keys==2 && in.sequence==3); /* coherent first and second records */
    enqueue(1,8,1,0,0,0); enqueue(2,8,2,4,0,0);
    CHECK(nc_poll(&d,210,&in)>0 && in.session==7 && in.keys==2);
    enqueue(2,7,3,16,0,0); enqueue(2,7,2,16,0,0);
    CHECK(nc_poll(&d,300,&in)>0 && in.keys==2);
    enqueue(2,7,4,16,0,150); /* Received before the seq3 state at time200. */
    CHECK(nc_poll(&d,300,&in)>0 && in.keys==2 && in.sequence==3);
    enqueue(1,7,1,0,0,0); CHECK(nc_poll(&d,400,&in)>0 && in.keys==2);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,400)>0 && hw.sent[5]==3);
    CHECK(nc_poll(&d,450,&in)==0 && in.connected && in.age_ms==250);
    CHECK(nc_poll(&d,451,&in)>0 && !in.connected && !in.keys);
    enqueue(2,7,4,16,0,0); enqueue(1,7,1,0,0,0);
    CHECK(nc_poll(&d,452,&in)>0 && !in.connected);
    enqueue(1,9,1,0,0,251); CHECK(nc_poll(&d,460,&in)>0 && !in.connected);
    enqueue(1,9,1,0,0,245); enqueue(2,9,2,16,0,240);
    CHECK(nc_poll(&d,500,&in)>0 && in.keys==16 && in.age_ms==240);
    CHECK(nc_poll(&d,511,&in)>0 && !in.connected); /* arrival age, not poll age */
}
/* Literal fixtures are copied from A's tb/vectors/v3_control_packets.json.
   They verify independent cross-language CRC, field order and endian encoding. */
static unsigned from_hex(uint8_t *p,const char *hex) {
    CHECK(!(strlen(hex)&1u));
    unsigned length=(unsigned)strlen(hex)/2;
    for(unsigned i=0;i<length;i++) {
        unsigned value=0; CHECK(sscanf(hex+2*i,"%2x",&value)==1); p[i]=(uint8_t)value;
    }
    return length;
}
static void golden_vectors(void) {
    nc_device d; nc_input in; uint8_t expected[128]; reset(); CHECK(!nc_init(&d,0));
    hw.rx[0].age=0;
    CHECK(from_hex(hw.rx[0].bytes,"414743310101002012345678010203040000000000000000000000003e0b1a63")==32);
    hw.count=1;
    CHECK(nc_poll(&d,0,&in)>0 && in.session==UINT32_C(0x12345678) && in.sequence==UINT32_C(0x01020304));
    CHECK(nc_try_publish(&d,NULL,0)>0);
    from_hex(expected,"41474331010300201234567801020304000000010000000000000000c4e6ddc9");
    CHECK(hw.sent_length==32 && !memcmp(hw.sent,expected,32));
    CHECK(from_hex(hw.rx[hw.head].bytes,"41474331010200201234567801020305000000ffa1b2c3d400000000e633fa88")==32);
    hw.rx[hw.head].age=0; hw.count=1;
    CHECK(nc_poll(&d,1,&in)>0 && in.keys==255 && in.action_sequence==UINT32_C(0xa1b2c3d4));
    nc_telemetry t={.firmware_build_id=UINT32_C(0x20261001),.resource_epoch=7,.simulation_tick=600,
        .requested_sprites=512,.visible_sprites=499,.gpu_full_frame_fps_x100=6010,.cpu_full_frame_fps_x100=1325,
        .pre_present_us=15000,.gpu_busy_us=9000,.command_build_us=3101,.submit_blocked_us=10,.background_copy_us=7600,
        .render_read_bytes=1024,.render_write_bytes=2048,.texture_cache_bytes=4096,
        .asset_retry_delta=2,.control_drop_delta=3,.input_age_ms=20,.status_flags=UINT32_C(0x007f0051),
        .p95_work_us=16000,.present_wait_us=1667,.alpha_commands=64,.alpha_pixels=8192,.key_commands=512};
    d.snapshot_id=UINT32_MAX-2u; hw.tx_ready=1;
    CHECK(nc_try_publish(&d,&t,1)>0);
    CHECK(from_hex(expected,"414754310180008012345678fffffffe20261001000000070000025800000200000001f30000177a0000052d00003a980000232800000c1d0000000a00001db0000004000000080000001000000000000000000000000000000000020000000300000014007f005100003e80000006830000004000002000000002007e06afbd")==128);
    CHECK(!memcmp(hw.sent,expected,128));
    t=(nc_telemetry){0}; hw.tx_ready=1; d.snapshot_id=UINT32_MAX;
    CHECK(nc_try_publish(&d,&t,252)>0 && read_be(hw.sent+8)==0 && read_be(hw.sent+12)==0);
    memset(expected,0,128);
    from_hex(expected,"41475431018000800000000000000000");
    be(expected+124,UINT32_C(0xf8647dd5));
    CHECK(!memcmp(hw.sent,expected,128));
}
static void validation_and_budget(void) {
    nc_device d; nc_input in; reset(); CHECK(!nc_init(&d,0));
    /* Each malformed field with a recomputed CRC isolates validation. */
    const unsigned offsets[]={0,4,5,6,7,16,20,24,28};
    for(unsigned i=0;i<sizeof(offsets)/sizeof(offsets[0]);i++) {
        enqueue(1,7,1,0,0,0); uint8_t *p=hw.rx[hw.head].bytes;
        p[offsets[i]]^=0x10;
        if(offsets[i]!=28) be(p+28,crc(p,28));
        CHECK(nc_poll(&d,1,&in)>0 && !in.connected);
    }
    enqueue(1,0,1,0,0,0); CHECK(nc_poll(&d,2,&in)>0 && !in.connected);
    enqueue(1,7,UINT32_MAX-1u,0,0,0); CHECK(nc_poll(&d,2,&in)>0 && in.connected);
    enqueue(2,7,UINT32_MAX,1,0,0); enqueue(2,7,0,2,0,0);
    enqueue(2,7,UINT32_C(0x80000000),4,0,0); enqueue(2,7,UINT32_MAX,8,0,0);
    enqueue(2,7,1,16,0,0);
    unsigned released=hw.releases;
    CHECK(nc_poll(&d,3,&in)>0 && hw.releases-released==4 && hw.count==1 && in.keys==2 && in.sequence==0);
    CHECK(nc_poll(&d,3,&in)>0 && in.keys==16);
    enqueue(2,7,2,0x100,0,0); CHECK(nc_poll(&d,4,&in)>0 && in.keys==16);
    enqueue(3,7,2,1,0,0); CHECK(nc_poll(&d,4,&in)>0 && in.keys==16);
    CHECK(nc_poll(&d,4,NULL)<0);
}
static void telemetry_latest_atomic_and_rate(void) {
    nc_device d; nc_input in;
    nc_telemetry t={.firmware_build_id=0x01020304,.resource_epoch=2,.simulation_tick=3,
        .requested_sprites=4,.visible_sprites=5,.gpu_full_frame_fps_x100=6,
        .cpu_full_frame_fps_x100=7,.pre_present_us=8,.gpu_busy_us=9,
        .command_build_us=10,.submit_blocked_us=11,.background_copy_us=12,
        .render_read_bytes=13,.render_write_bytes=14,.texture_cache_bytes=15,
        .scanout_underflow_delta=16,.gpu_error_delta=17,.missed_vblank_delta=18,
        .asset_retry_delta=19,.control_drop_delta=20,.input_age_ms=21,
        .status_flags=V3_VALID_GPU_TIMING,.p95_work_us=23,.present_wait_us=24,
        .alpha_commands=25,.alpha_pixels=26,.key_commands=27};
    reset(); CHECK(!nc_init(&d,0));
    enqueue(1,7,1,0,0,0); CHECK(nc_poll(&d,0,&in)>0);
    CHECK(nc_try_publish(&d,&t,0)>0 && hw.commits==1 && hw.sent_length==32); /* ACK wins */
    unsigned writes=hw.writes;
    t.simulation_tick=30; CHECK(!nc_try_publish(&d,&t,1) && hw.writes==writes);
    t.simulation_tick=31; CHECK(!nc_try_publish(&d,&t,2) && hw.writes==writes);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,2)>0 && hw.sent_length==128 && hw.commits==2);
    CHECK(read_be(hw.sent)==UINT32_C(0x41475431) && hw.sent[4]==1 && hw.sent[5]==0x80 && hw.sent[7]==128);
    CHECK(read_be(hw.sent+8)==7 && read_be(hw.sent+12)==1);
    for(unsigned i=0;i<27;i++) {
        uint32_t expected=i+1;
        if(i==0) expected=0x01020304;
        if(i==2) expected=31;
        if(i==21) expected=V3_VALID_GPU_TIMING;
        CHECK(read_be(hw.sent+16+4*i)==expected);
    }
    CHECK(read_be(hw.sent+124)==crc(hw.sent,124));
    uint8_t old[128]; memcpy(old,hw.sent,128);
    t.simulation_tick=32; CHECK(!nc_try_publish(&d,&t,50) && !memcmp(old,hw.sent,128));
    hw.tx_ready=1; writes=hw.writes;
    CHECK(!nc_try_publish(&d,NULL,201) && hw.writes==writes);
    CHECK(nc_try_publish(&d,NULL,202)>0 && read_be(hw.sent+24)==32);
    hw.tx_ready=1; d.publish_interval_ms=1;
    CHECK(!nc_try_publish(&d,&t,301));
    CHECK(nc_try_publish(&d,NULL,302)>0); /* min 100ms, max 10Hz */
    hw.tx_ready=1; CHECK(nc_try_publish(&d,&t,UINT32_MAX)>0);
    hw.tx_ready=1; CHECK(!nc_try_publish(&d,&t,98));
    CHECK(nc_try_publish(&d,NULL,99)>0); /* time wrap */
    CHECK(nc_try_publish(NULL,&t,1)<0);
}
static void game_packet(uint32_t seq,uint32_t op,uint32_t level,uint32_t id,uint32_t age) {
    enqueue(4,7,seq,op,level,age);
    uint8_t *p=hw.rx[(hw.head+hw.count-1)%16].bytes;
    be(p+24,id); be(p+28,crc(p,28));
}
static void test_game_exactly_once(void) {
    nc_device d; nc_input in; nc_game_command cmd;
    reset(); CHECK(!nc_init(&d,0));
    enqueue(1,7,1,0,0,0); enqueue(2,7,2,16,42,0);
    CHECK(nc_poll(&d,1,&in)>0);
    /* Independent shared wire fixture, no driver serializer on the RX side. */
    from_hex(hw.rx[hw.head].bytes,"4147433101040020000000070000000900000001000000040000000b236caf84");
    hw.rx[hw.head].age=0; hw.count=1;
    CHECK(nc_poll(&d,2,&in)>0 && !in.keys && in.action_sequence==42 && in.sequence==9);
    CHECK(nc_take_game(&d,&cmd)==1 && cmd.session==7 && cmd.sequence==9);
    CHECK(cmd.opcode==1 && cmd.level==4 && cmd.request_id==11);
    CHECK(nc_try_publish(&d,NULL,2)>0 && hw.sent[5]==3); /* HELLO first */
    hw.tx_ready=1; CHECK(!nc_try_publish(&d,NULL,2)); /* not executed yet */
    d.snapshot_id=99;
    nc_telemetry old={.requested_sprites=64}; hw.tx_ready=0;
    CHECK(!nc_try_publish(&d,&old,3));
    CHECK(nc_complete_game(&d,&cmd,0)==0 && !d.telemetry_pending && d.snapshot_id==99);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,3)>0 && hw.sent[5]==5);
    CHECK(read_be(hw.sent+12)==9 && read_be(hw.sent+16)==11);
    CHECK(read_be(hw.sent+20)==0 && read_be(hw.sent+24)==99 && read_be(hw.sent+28)==crc(hw.sent,28));
    game_packet(10,1,4,11,0); CHECK(nc_poll(&d,4,&in)>0);
    CHECK(nc_take_game(&d,&cmd)==0);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,4)>0 && read_be(hw.sent+12)==10);
    unsigned rejected=d.rejected_packets;
    game_packet(11,1,3,11,0); game_packet(12,1,4,10,0);
    CHECK(nc_poll(&d,5,&in)>0 && d.rejected_packets==rejected+2 && in.sequence==10);
    game_packet(13,2,0,12,0); CHECK(nc_poll(&d,6,&in)>0 && nc_take_game(&d,&cmd)==1);
    game_packet(14,1,1,13,0); CHECK(nc_poll(&d,7,&in)>0 && nc_take_game(&d,&cmd)==1 && cmd.request_id==12);
    CHECK(nc_complete_game(&d,&cmd,1)==0);
    hw.tx_ready=1; nc_telemetry menu={.status_flags=0x0d00};
    CHECK(nc_try_publish(&d,&menu,8)>0 && hw.sent[5]==5 && read_be(hw.sent+20)==1);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,9)>0 && hw.sent[5]==128 && read_be(hw.sent+12)==100);
}
static void test_game_session_expiry(void) {
    nc_device d; nc_input in; nc_game_command cmd;
    reset(); CHECK(!nc_init(&d,0)); enqueue(1,7,1,0,0,0); nc_poll(&d,0,&in);
    game_packet(2,1,1,1,251); nc_poll(&d,1,&in); CHECK(!nc_take_game(&d,&cmd));
    game_packet(2,1,1,1,0); nc_poll(&d,2,&in); CHECK(nc_take_game(&d,&cmd)==1);
    nc_poll(&d,253,&in); CHECK(!nc_take_game(&d,&cmd));
    CHECK(nc_complete_game(&d,&cmd,0)<0 && !d.input.connected);
    enqueue(1,8,1,0,0,0); nc_poll(&d,254,&in);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,254)>0 && hw.sent[5]==3 && read_be(hw.sent+8)==8);
    hw.tx_ready=1; CHECK(!nc_try_publish(&d,NULL,254));
    reset(); CHECK(!nc_init(&d,0)); enqueue(1,7,UINT32_MAX-2u,0,0,0); nc_poll(&d,0,&in);
    game_packet(UINT32_MAX-1u,1,1,UINT32_MAX,0); nc_poll(&d,1,&in);
    CHECK(nc_take_game(&d,&cmd)==1 && nc_complete_game(&d,&cmd,0)==0);
    game_packet(0,2,0,1,0); nc_poll(&d,2,&in);
    CHECK(nc_take_game(&d,&cmd)==1 && cmd.request_id==1 && nc_complete_game(&d,&cmd,0)==0);
    CHECK(nc_take_game(NULL,&cmd)<0 && nc_take_game(&d,NULL)<0);
}
static void telemetry_cannot_cross_handshake(void) {
    nc_device d; nc_input in;
    reset(); CHECK(!nc_init(&d,0));
    nc_telemetry observer={.status_flags=V3_STATUS_GAME_MENU_CAPABLE};
    hw.tx_ready=0; CHECK(!nc_try_publish(&d,&observer,0));
    enqueue(1,7,1,0,0,0); CHECK(nc_poll(&d,1,&in)>0);
    hw.tx_ready=1; CHECK(nc_try_publish(&d,NULL,1)>0 && hw.sent[5]==3);
    hw.tx_ready=1;
    /* A queued disconnected snapshot must not acquire the newly ACKed session
       header: the gateway would interpret its flags as a lost board lease. */
    CHECK(!nc_try_publish(&d,NULL,201) && hw.commits==1);
    nc_telemetry active={.status_flags=V3_STATUS_CONTROL_CONNECTED|V3_STATUS_GAME_MENU_CAPABLE};
    CHECK(nc_try_publish(&d,&active,202)>0 && hw.sent[5]==128);
    CHECK(read_be(hw.sent+8)==7 && (read_be(hw.sent+100)&V3_STATUS_CONTROL_CONNECTED));
}
int main(void) {
    initialization(); reception_and_lease(); validation_and_budget(); telemetry_latest_atomic_and_rate(); golden_vectors();
    test_game_exactly_once(); test_game_session_expiry();
    telemetry_cannot_cross_handshake();
    puts("PASS net_control: validation, handshake/session, lease/age, modular seq, max4RX, ACK priority, atomic latest128B, rate/busy");
    return 0;
}
