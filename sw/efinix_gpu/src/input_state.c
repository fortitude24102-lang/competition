#include "input_state.h"

static int newer(uint32_t a,uint32_t b) {
    uint32_t delta=a-b; return delta && delta<UINT32_C(0x80000000);
}
void input_update(game_input *s,const nc_input *in) {
    if(!s) return;
    s->pressed=0; s->released=0;
    if(!in || !in->connected || !in->session || in->age_ms>V3_INPUT_LEASE_MS) {
        s->released=s->held; s->held=0; s->initialized=0; s->action_initialized=0;
        return;
    }
    if(s->initialized && s->session==in->session && !newer(in->sequence,s->sequence)) return;
    if(!s->initialized || s->session!=in->session) s->action_initialized=0;
    uint16_t keys=in->keys&V3_KEY_MASK;
    if((keys&(V3_KEY_LEFT|V3_KEY_RIGHT))==(V3_KEY_LEFT|V3_KEY_RIGHT)) keys&=(uint16_t)~(V3_KEY_LEFT|V3_KEY_RIGHT);
    if((keys&(V3_KEY_UP|V3_KEY_DOWN))==(V3_KEY_UP|V3_KEY_DOWN)) keys&=(uint16_t)~(V3_KEY_UP|V3_KEY_DOWN);
    s->pressed=keys&(uint16_t)~s->held&(uint16_t)~V3_KEY_ACTION_MASK;
    s->released=s->held&(uint16_t)~keys;
    if(!s->action_initialized || newer(in->action_sequence,s->action_sequence)) {
        uint16_t rising_actions=keys&(uint16_t)~s->held&V3_KEY_ACTION_MASK;
        /* A newly visible action identifies which key advanced the shared
           counter; do not repeat the other held action. Without an edge,
           retain recovery from a lost release/re-press snapshot. */
        s->pressed|=rising_actions?rising_actions:keys&V3_KEY_ACTION_MASK;
        s->action_sequence=in->action_sequence;
        s->action_initialized=1;
    }
    s->held=keys; s->session=in->session; s->sequence=in->sequence; s->initialized=1;
}
