#include "replay_input.h"
#include <string.h>
#ifndef REPLAY_CRC_NIBBLE
#define REPLAY_CRC_NIBBLE 0
#endif
#if REPLAY_CRC_NIBBLE != 0 && REPLAY_CRC_NIBBLE != 1
#error "REPLAY_CRC_NIBBLE must be 0 or 1"
#endif
/* Canonical CRC covers logical fields, not compiler padding or pointer values.
 * Incremental words avoid allocating a serialized bullet_state on the stack. */
static void crc_word(uint32_t *crc,uint32_t v) {
#if REPLAY_CRC_NIBBLE
 /* Reflected 0xedb88320, four zero-bit steps for each table entry.
  * XOR the little-endian logical word once; eight nibbles consume it.
  * ponytail: 64B table, not a 1KiB table in the nearly-full CPU RAM. */
 static const uint32_t lut[16]={
  0x00000000u,0x1db71064u,0x3b6e20c8u,0x26d930acu,
  0x76dc4190u,0x6b6b51f4u,0x4db26158u,0x5005713cu,
  0xedb88320u,0xf00f9344u,0xd6d6a3e8u,0xcb61b38cu,
  0x9b64c2b0u,0x86d3d2d4u,0xa00ae278u,0xbdbdf21cu};
 *crc^=v;
 for(unsigned nibble=0;nibble<8;nibble++) *crc=(*crc>>4)^lut[*crc&15u];
#else
 for(unsigned byte=0;byte<4;byte++) {
  *crc^=(v>>(byte*8u))&255u;
  for(unsigned bit=0;bit<8;bit++) *crc=(*crc>>1)^((*crc&1u)?0xedb88320u:0u);
 }
#endif
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
 crc_word(&crc,s->interactive);crc_word(&crc,s->won);
 for(unsigned i=0;i<BULLET_ENEMY_COUNT;i++) crc_word(&crc,s->enemy_hp[i]);
 for(unsigned i=0;i<s->count;i++) {
  const bullet_object *b=&s->objects[i];
  crc_word(&crc,(uint32_t)b->x); crc_word(&crc,(uint32_t)b->y);
  crc_word(&crc,(uint32_t)b->vx); crc_word(&crc,(uint32_t)b->vy);
  crc_word(&crc,b->age); crc_word(&crc,b->kind); crc_word(&crc,b->shape); crc_word(&crc,b->grazed);
  crc_word(&crc,b->path);
 }
 for(unsigned i=0;i<r->count;i++) crc_word(&crc,r->keys[i]);
 return crc^UINT32_MAX;
}
static int initial_valid(const bullet_state *s) {
 if(!s || !s->count || s->count>BULLET_MAX_OBJECTS || s->hp>BULLET_START_HP || !bullet_campaign_valid(s) ||
    s->player_x<8 || s->player_x>952 || s->player_y<80 || s->player_y>532 ||
    s->invulnerable>BULLET_PROTECTION_TICKS ||
    (!s->hp && (!s->game_over_ticks || s->game_over_ticks>BULLET_RESTART_TICKS))) return 0;
 for(unsigned i=0;i<s->count;i++) if(s->objects[i].kind>3 || s->objects[i].shape>=BULLET_SHAPE_COUNT ||
  (s->interactive && s->objects[i].path>=BULLET_PATH_COUNT)) return 0;
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
/* Same canonical version2 serialization as checksum(), without a whole-state
 * buffer or a large table. Single-writer runtime freezes initial/keys at600. */
static uint32_t seal_word(const replay_recording *r,unsigned index) {
 const bullet_state *s=&r->initial;
 switch(index) {
  case 0:return REPLAY_INPUT_VERSION;case 1:return r->seed;
  case 2:return r->resource_epoch;case 3:return r->count;
  case 4:return s->count;case 5:return s->seed;case 6:return s->tick;
  case 7:return s->round_tick;case 8:return s->score;case 9:return s->grazes;
  case 10:return (uint32_t)s->player_x;case 11:return (uint32_t)s->player_y;
  case 12:return s->invulnerable;case 13:return s->game_over_ticks;case 14:return s->hp;
  case 15:return s->interactive;case 16:return s->won;
  case 17:return s->enemy_hp[0];case 18:return s->enemy_hp[1];case 19:return s->enemy_hp[2];
 }
 index-=20u;
 if(index>=s->count*9u)return r->keys[index-s->count*9u];
 const bullet_object *b=s->objects+index/9u;
 switch(index%9u) {
  case 0:return (uint32_t)b->x;case 1:return (uint32_t)b->y;
  case 2:return (uint32_t)b->vx;case 3:return (uint32_t)b->vy;
  case 4:return b->age;case 5:return b->kind;case 6:return b->shape;
  case 7:return b->grazed;default:return b->path;
 }
}
int replay_seal_step(replay_recording *r,replay_seal_cursor *c,unsigned words) {
 if(!r || !c || !words || words>256 || r->sealed || r->count!=REPLAY_INPUT_TICKS ||
    !r->initial.count || r->initial.count>BULLET_MAX_OBJECTS ||
    !r->resource_epoch || r->seed!=r->initial.seed)return GPU_DRIVER_ARGUMENT;
 unsigned total=20u+9u*r->initial.count+r->count;
 if(c->offset>=total)return GPU_DRIVER_ARGUMENT;
 if(!c->offset) {
  if(!initial_valid(&r->initial))return GPU_DRIVER_ARGUMENT;
  c->crc=UINT32_MAX;
 }
 unsigned end=total-c->offset<words?total:c->offset+words;
 while(c->offset<end)crc_word(&c->crc,seal_word(r,c->offset++));
 if(c->offset<total)return 0;
 if(!initial_valid(&r->initial))return GPU_DRIVER_ARGUMENT;
 r->crc32=c->crc^UINT32_MAX;r->sealed=1;return 1;
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
