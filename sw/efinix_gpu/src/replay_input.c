#include "replay_input.h"
#include <string.h>
/* Canonical CRC covers logical fields, not compiler padding or pointer values.
 * Incremental words avoid allocating a serialized bullet_state on the stack. */
static void crc_word(uint32_t *crc,uint32_t v) {
 for(unsigned byte=0;byte<4;byte++) {
  *crc^=(v>>(byte*8u))&255u;
  for(unsigned bit=0;bit<8;bit++) *crc=(*crc>>1)^((*crc&1u)?0xedb88320u:0u);
 }
}
static uint32_t checksum(const replay_recording *r) {
 uint32_t crc=UINT32_MAX;
 crc_word(&crc,REPLAY_INPUT_VERSION); crc_word(&crc,r->seed);
 crc_word(&crc,r->resource_epoch); crc_word(&crc,r->count);
 const bullet_state *s=&r->initial;
 crc_word(&crc,s->count); crc_word(&crc,s->seed); crc_word(&crc,s->tick);
 crc_word(&crc,s->round_tick); crc_word(&crc,s->score); crc_word(&crc,s->grazes);
 crc_word(&crc,(uint32_t)s->player_x); crc_word(&crc,(uint32_t)s->player_y);
 crc_word(&crc,s->invulnerable); crc_word(&crc,s->game_over_ticks); crc_word(&crc,s->hp);
 for(unsigned i=0;i<s->count;i++) {
  const bullet_object *b=&s->objects[i];
  crc_word(&crc,(uint32_t)b->x); crc_word(&crc,(uint32_t)b->y);
  crc_word(&crc,(uint32_t)b->vx); crc_word(&crc,(uint32_t)b->vy);
  crc_word(&crc,b->age); crc_word(&crc,b->kind); crc_word(&crc,b->shape); crc_word(&crc,b->grazed);
 }
 for(unsigned i=0;i<r->count;i++) crc_word(&crc,r->keys[i]);
 return crc^UINT32_MAX;
}
static int initial_valid(const bullet_state *s) {
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || s->hp>BULLET_START_HP ||
    s->player_x<8 || s->player_x>952 || s->player_y<80 || s->player_y>532 ||
    s->invulnerable>BULLET_PROTECTION_TICKS ||
    (!s->hp && (!s->game_over_ticks || s->game_over_ticks>BULLET_RESTART_TICKS))) return 0;
 for(unsigned i=0;i<s->count;i++) if(s->objects[i].kind>3 || s->objects[i].shape>=BULLET_SHAPE_COUNT) return 0;
 return 1;
}
int replay_init(replay_recording *r,const bullet_state *initial,uint32_t epoch) {
 if(!r || !initial_valid(initial) || !epoch || initial==&r->initial) return GPU_DRIVER_ARGUMENT;
 memset(r,0,sizeof *r); r->initial=*initial; r->seed=initial->seed; r->resource_epoch=epoch;
 return 0;
}
int replay_record(replay_recording *r,const game_input *in) {
 if(!r || !in || r->sealed || ((in->held|in->pressed|in->released)&~V3_KEY_MASK)) return GPU_DRIVER_ARGUMENT;
 if(r->count>=REPLAY_INPUT_TICKS) return GPU_DRIVER_FULL;
 r->keys[r->count++]=(uint16_t)((in->held&~V3_KEY_ACTION_MASK)|(in->pressed&V3_KEY_ACTION_MASK));
 return 0;
}
int replay_seal(replay_recording *r) {
 if(!r || r->sealed || r->count!=REPLAY_INPUT_TICKS || !initial_valid(&r->initial) ||
    !r->resource_epoch || r->seed!=r->initial.seed) return GPU_DRIVER_ARGUMENT;
 r->crc32=checksum(r); r->sealed=1; return 0;
}
int replay_begin(const replay_recording *r,uint32_t epoch,bullet_state *s,replay_cursor *c) {
 if(!r || !s || !c || !r->sealed || r->count!=REPLAY_INPUT_TICKS ||
    r->resource_epoch!=epoch || !epoch || !initial_valid(&r->initial) ||
    r->seed!=r->initial.seed || r->crc32!=checksum(r)) return GPU_DRIVER_ARGUMENT;
 *s=r->initial; *c=(replay_cursor){.active=1}; return 0;
}
int replay_next(const replay_recording *r,replay_cursor *c,game_input *in) {
 if(!r || !c || !in || !r->sealed || r->count!=REPLAY_INPUT_TICKS || !c->active ||
    c->index>r->count) return GPU_DRIVER_ARGUMENT;
 if(c->index==r->count) { *in=(game_input){0}; return 0; }
 uint16_t keys=r->keys[c->index];
 if(keys&~V3_KEY_MASK) return GPU_DRIVER_ARGUMENT;
 *in=(game_input){.held=keys,
  .pressed=(uint16_t)(((keys&~c->previous)&~V3_KEY_ACTION_MASK)|(keys&V3_KEY_ACTION_MASK)),
  .released=(uint16_t)(c->previous&~keys)};
 c->previous=keys; ++c->index; return 1;
}
