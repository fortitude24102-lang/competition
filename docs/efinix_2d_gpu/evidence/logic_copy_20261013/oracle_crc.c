#include "replay_input.h"
#include "replay_crc_reference.h"
#include <assert.h>
#include <stdio.h>
static bullet_state state;
static replay_recording recording;
int main(void) {
 const unsigned counts[]={256,512};game_input in={0};
 for(unsigned i=0;i<2;i++) {
  assert(!game_reset(&state,counts[i],7));
  assert(!replay_init(&recording,&state,0x00030002u));
  for(unsigned tick=0;tick<600;tick++)assert(!replay_record(&recording,&in));
  printf("INDEPENDENT_CRC,count=%u,crc=%08x\n",counts[i],canonical_reference(&recording));
 }
}
