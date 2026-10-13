#ifndef REPLAY_CRC_REFERENCE_H
#define REPLAY_CRC_REFERENCE_H
#include "replay_input.h"
/* Independent bitwise reference: no production CRC helper/table/padding. */
static uint32_t reference_word(uint32_t crc,uint32_t word) {
 for(unsigned byte=0;byte<4;byte++) {
  crc^=(word>>(byte*8u))&255u;
  for(unsigned bit=0;bit<8;bit++) crc=(crc>>1)^((crc&1u)?0xedb88320u:0u);
 }
 return crc;
}
static uint32_t canonical_reference(const replay_recording *r) {
 uint32_t crc=UINT32_MAX;
 const uint32_t header[]={REPLAY_INPUT_VERSION,r->seed,r->resource_epoch,r->count};
 const bullet_state *s=&r->initial;
 const uint32_t state[]={s->count,s->seed,s->tick,s->round_tick,s->score,s->grazes,
  (uint32_t)s->player_x,(uint32_t)s->player_y,s->invulnerable,s->game_over_ticks,s->hp,
  s->interactive,s->won,s->enemy_hp[0],s->enemy_hp[1],s->enemy_hp[2]};
 for(unsigned i=0;i<4;i++) crc=reference_word(crc,header[i]);
 for(unsigned i=0;i<sizeof state/sizeof state[0];i++) crc=reference_word(crc,state[i]);
 for(unsigned i=0;i<s->count;i++) {
  const bullet_object *b=&s->objects[i];
  const uint32_t object[]={(uint32_t)b->x,(uint32_t)b->y,(uint32_t)b->vx,(uint32_t)b->vy,
   b->age,b->kind,b->shape,b->grazed,b->path};
  for(unsigned j=0;j<sizeof object/sizeof object[0];j++) crc=reference_word(crc,object[j]);
 }
 for(unsigned i=0;i<r->count;i++) crc=reference_word(crc,r->keys[i]);
 return crc^UINT32_MAX;
}
#endif
