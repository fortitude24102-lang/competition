#include "net_control.h"
#include "asset_protocol.h"

#ifdef NC_TEST_BACKEND
uint32_t nc_io_read(uintptr_t address);
void nc_io_write(uintptr_t address, uint32_t value);
void nc_io_fence(void);
#else
static uint32_t nc_io_read(uintptr_t a) { return *(volatile uint32_t *)a; }
static void nc_io_write(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a=v; }
static void nc_io_fence(void) {
#ifdef __riscv
    __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}
#endif

static uint32_t rd(const nc_device *d, unsigned offset) { return nc_io_read(d->base+offset); }
static void wr(const nc_device *d, unsigned offset, uint32_t v) { nc_io_write(d->base+offset,v); }
static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static void put32(uint8_t *p,uint32_t v) {
    p[0]=(uint8_t)(v>>24); p[1]=(uint8_t)(v>>16); p[2]=(uint8_t)(v>>8); p[3]=(uint8_t)v;
}
static int newer(uint32_t a,uint32_t b) { uint32_t delta=a-b; return delta && delta<UINT32_C(0x80000000); }

static int expire(nc_device *d,uint32_t now) {
    if(!d->input.connected) return 0;
    d->input.age_ms=now-d->received_ms;
    if(d->input.age_ms<=V3_INPUT_LEASE_MS) return 0;
    d->retired_session=d->input.session;
    d->input=(nc_input){.age_ms=UINT32_MAX};
    d->ack_pending=0;
    d->game_pending=d->game_done=d->game_ack_pending=0;
    return 1;
}

/* Stable snapshots are consumed once even when rejected. */
static int take(nc_device *d,uint8_t packet[32],uint32_t *age) {
    uint32_t status=rd(d,NC_REG_STATUS);
    if(!(status&(NC_STATUS_RX_AVAILABLE|NC_STATUS_RX_SNAPSHOT_VALID))) return 0;
    if(!(status&NC_STATUS_RX_SNAPSHOT_VALID)) {
        wr(d,NC_REG_RX_SNAPSHOT,1); nc_io_fence();
        if(!(rd(d,NC_REG_STATUS)&NC_STATUS_RX_SNAPSHOT_VALID)) return NC_ERROR_HARDWARE;
    }
    *age=rd(d,NC_REG_RX_AGE_MS);
    for(unsigned w=0;w<8;w++) {
        uint32_t v=rd(d,NC_REG_RX_WORD0+4*w);
        for(unsigned b=0;b<4;b++) packet[4*w+b]=(uint8_t)(v>>(8*b));
    }
    nc_io_fence(); wr(d,NC_REG_RX_RELEASE,1); nc_io_fence();
    return 1;
}

int nc_init(nc_device *d,uintptr_t base) {
    if(!d || (base&3u)) return NC_ERROR_ARGUMENT;
    *d=(nc_device){.base=base?base:GPU_APB_BASE,
                   .input={.age_ms=UINT32_MAX}, .publish_interval_ms=V3_TELEMETRY_DEFAULT_MS};
    if(rd(d,NC_REG_ID)!=NC_ID_VALUE) return NC_ERROR_UNAVAILABLE;
    /* On firmware restart, pre-existing HELLO/KEYS must not resume movement.
       The documented hardware FIFO holds four records. */
    for(unsigned i=0;i<V3_POLL_MAX_PACKETS;i++) {
        uint8_t packet[32]; uint32_t age;
        int result=take(d,packet,&age);
        if(result<0) return result;
        if(!result) break;
    }
    d->ready=1;
    return 0;
}

static int valid_packet(const uint8_t *p) {
    if(be32(p)!=V3_CONTROL_MAGIC || p[4]!=V3_PROTOCOL_VERSION ||
       p[6]!=0 || p[7]!=V3_CONTROL_BYTES || !be32(p+8) ||
       be32(p+28)!=asst_crc32(p,28)) return 0;
    if(p[5]==V3_PACKET_HELLO) return !(be32(p+16)|be32(p+20)|be32(p+24));
    if(p[5]==V3_PACKET_KEYS) return !(be32(p+16)&~(uint32_t)V3_KEY_MASK) && !be32(p+24);
    if(p[5]==V3_PACKET_GAME) {
        uint32_t op=be32(p+16),level=be32(p+20);
        return be32(p+24) && ((op==V3_GAME_START && level>=1 && level<=4) ||
                             (op==V3_GAME_MENU && level==0));
    }
    return 0;
}

static int accept(nc_device *d,const uint8_t *p,uint32_t age,uint32_t now) {
    if(age>V3_INPUT_LEASE_MS || !valid_packet(p)) return 0;
    uint32_t session=be32(p+8), sequence=be32(p+12);
    if(p[5]==V3_PACKET_HELLO) {
        if(d->input.connected) {
            /* Retransmit an identical HELLO ACK, preserving KEYS and lease.
               A HELLO never refreshes a held-key lease. */
            if(session!=d->input.session || sequence!=d->hello_sequence) return 0;
        } else {
            if(session==d->retired_session) return 0;
            d->input=(nc_input){.session=session,.sequence=sequence,.age_ms=age,.connected=1};
            d->received_ms=now-age;
            d->hello_sequence=sequence;
            d->game_pending=d->game_done=d->game_ack_pending=0;
        }
        d->ack_session=session; d->ack_sequence=sequence; d->ack_pending=1;
        return 1;
    }
    if(!d->input.connected || session!=d->input.session || !newer(sequence,d->input.sequence)) return 0;
    uint32_t arrival=now-age;
    /* Sequence freshness alone does not authorize a record captured before
       the current handshake/latest accepted state (e.g. a reset backlog). */
    if(arrival-d->received_ms>=UINT32_C(0x80000000)) return 0;
    if(p[5]==V3_PACKET_GAME) {
        uint32_t op=be32(p+16),level=be32(p+20),id=be32(p+24);
        if((d->game_pending || d->game_done) && id==d->game.request_id) {
            if(op!=d->game.opcode || level!=d->game.level) return 0;
            d->game.sequence=sequence;
            if(d->game_done) d->game_ack_pending=1;
        } else {
            if(d->game_pending || (d->game_done && !newer(id,d->game.request_id))) return 0;
            d->game=(nc_game_command){session,sequence,op,level,id};
            d->game_pending=1;d->game_done=d->game_ack_pending=0;
        }
        d->input.keys=0; /* Do not interpret level as an R/C action counter. */
    } else {
        d->input.action_sequence=be32(p+20);
        d->input.keys=(uint16_t)be32(p+16);
    }
    d->input.sequence=sequence;
    d->input.age_ms=age;
    d->received_ms=arrival;
    return 1;
}

int nc_poll(nc_device *d,uint32_t now,nc_input *in) {
    if(!in) return NC_ERROR_ARGUMENT;
    *in=(nc_input){.age_ms=UINT32_MAX};
    if(!d) return NC_ERROR_ARGUMENT;
    if(!d->ready) return NC_ERROR_UNAVAILABLE;
    int progress=expire(d,now);
    for(unsigned i=0;i<V3_POLL_MAX_PACKETS;i++) {
        uint8_t packet[32]; uint32_t age;
        int result=take(d,packet,&age);
        if(result<0) { *in=d->input; return result; }
        if(!result) break;
        progress=1;
        if(!accept(d,packet,age,now)) ++d->rejected_packets;
    }
    (void)expire(d,now);
    *in=d->input;
    return progress;
}

int nc_take_game(nc_device *d,nc_game_command *cmd) {
    if(!d || !cmd) return NC_ERROR_ARGUMENT;
    if(!d->ready) return NC_ERROR_UNAVAILABLE;
    if(!d->game_pending) return 0;
    *cmd=d->game;return 1;
}
void nc_discard_pending_telemetry(nc_device *d) {
    if(d) d->telemetry_pending=0;
}
int nc_complete_game(nc_device *d,const nc_game_command *cmd,uint32_t result) {
    if(!d || !cmd || result>2 || !d->ready || !d->input.connected || !d->game_pending ||
       cmd->session!=d->input.session || cmd->session!=d->game.session ||
       cmd->request_id!=d->game.request_id || cmd->opcode!=d->game.opcode || cmd->level!=d->game.level)
        return NC_ERROR_ARGUMENT;
    nc_discard_pending_telemetry(d);
    d->game_result=result;d->game_floor=d->snapshot_id;
    d->game_pending=0;d->game_done=d->game_ack_pending=1;
    return 0;
}
static void header(uint8_t *p,uint32_t magic,unsigned type,unsigned length,uint32_t session,uint32_t seq) {
    put32(p,magic); p[4]=V3_PROTOCOL_VERSION; p[5]=(uint8_t)type;
    p[6]=(uint8_t)(length>>8); p[7]=(uint8_t)length;
    put32(p+8,session); put32(p+12,seq);
}
static void telemetry_packet(uint8_t p[128],const nc_telemetry *t,uint32_t session,uint32_t seq) {
    const uint32_t fields[27]={
        t->firmware_build_id,t->resource_epoch,t->simulation_tick,
        t->requested_sprites,t->visible_sprites,t->gpu_full_frame_fps_x100,
        t->cpu_full_frame_fps_x100,t->pre_present_us,t->gpu_busy_us,
        t->command_build_us,t->submit_blocked_us,t->background_copy_us,
        t->render_read_bytes,t->render_write_bytes,t->texture_cache_bytes,
        t->scanout_underflow_delta,t->gpu_error_delta,t->missed_vblank_delta,
        t->asset_retry_delta,t->control_drop_delta,t->input_age_ms,
        t->status_flags&V3_STATUS_ALLOWED_MASK,t->p95_work_us,t->present_wait_us,
        t->alpha_commands,t->alpha_pixels,t->key_commands};
    header(p,V3_TELEMETRY_MAGIC,V3_PACKET_TELEMETRY,128,session,seq);
    for(unsigned i=0;i<27;i++) put32(p+16+4*i,fields[i]);
    put32(p+124,asst_crc32(p,124));
}

int nc_try_publish(nc_device *d,const nc_telemetry *t,uint32_t now) {
    if(!d) return NC_ERROR_ARGUMENT;
    if(!d->ready) return NC_ERROR_UNAVAILABLE;
    if(t) { d->pending_telemetry=*t; d->telemetry_pending=1; }
    (void)expire(d,now);
    if(!d->ack_pending && !d->game_ack_pending && !d->telemetry_pending) return 0;
    uint32_t interval=d->publish_interval_ms;
    if(interval<V3_TELEMETRY_MIN_MS) interval=V3_TELEMETRY_MIN_MS;
    if(!d->ack_pending && !d->game_ack_pending && d->published && now-d->last_publish_ms<interval) return 0;
    /* Single-owner shadow buffer: a busy transmitter receives no writes. */
    if(!(rd(d,NC_REG_STATUS)&NC_STATUS_TX_READY)) return 0;
    uint8_t packet[128]={0}; unsigned length;
    int is_ack=d->ack_pending,is_game_ack=!is_ack && d->game_ack_pending;
    if(is_ack) {
        length=32;
        header(packet,V3_CONTROL_MAGIC,V3_PACKET_ACK,32,d->ack_session,d->ack_sequence);
        put32(packet+16,1); put32(packet+28,asst_crc32(packet,28));
    } else if(is_game_ack) {
        length=32;
        header(packet,V3_CONTROL_MAGIC,V3_PACKET_GAME_ACK,32,d->game.session,d->game.sequence);
        put32(packet+16,d->game.request_id);put32(packet+20,d->game_result);
        put32(packet+24,d->game_floor);put32(packet+28,asst_crc32(packet,28));
    } else {
        length=128;
        telemetry_packet(packet,&d->pending_telemetry,d->input.connected?d->input.session:0,d->snapshot_id+1);
    }
    wr(d,NC_REG_TX_LENGTH,length);
    for(unsigned i=0;i<length;i+=4) {
        uint32_t word=packet[i]|((uint32_t)packet[i+1]<<8)|((uint32_t)packet[i+2]<<16)|((uint32_t)packet[i+3]<<24);
        wr(d,NC_REG_TX_WORD0+i,word);
    }
    nc_io_fence(); wr(d,NC_REG_TX_COMMIT,1); nc_io_fence();
    if(rd(d,NC_REG_STATUS)&NC_STATUS_TX_ERROR) return NC_ERROR_HARDWARE;
    if(is_ack) d->ack_pending=0;
    else if(is_game_ack) d->game_ack_pending=0;
    else {
        d->telemetry_pending=0; d->published=1;
        d->last_publish_ms=now; ++d->snapshot_id;
    }
    return 1;
}
