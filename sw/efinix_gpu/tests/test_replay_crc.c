/* A wrong polynomial, byte order, sign extension or padding-based checksum
 * must disagree with this independent bitwise/canonical reference. */
#include "../src/replay_input.c"
#include <assert.h>
#include <stdio.h>
#include <time.h>
#include "replay_crc_reference.h"
static uint32_t random_word(uint32_t *state) {
 *state^=*state<<13;*state^=*state>>17;*state^=*state<<5;return *state;
}
static replay_recording recording,bad;
static bullet_state initial,restored;
#ifdef REPLAY_CRC_COST_CHECK
static volatile uint32_t sink;
#endif
int main(void) {
 const uint32_t words[]={0,UINT32_MAX,0x01234567,0x89abcdef,0xedb88320,0x80000001};
 for(unsigned i=0;i<6;i++) for(unsigned j=0;j<6;j++) {
  uint32_t crc=words[i];crc_word(&crc,words[j]);
  assert(crc==reference_word(words[i],words[j]));
 }
 uint32_t rng=7;
 for(unsigned i=0;i<10000;i++) {
  uint32_t before=random_word(&rng),word=random_word(&rng),crc=before;
  crc_word(&crc,word);assert(crc==reference_word(before,word));
 }
 for(unsigned count=32;count<=BULLET_MAX_OBJECTS;count*=2) {
  assert(!game_reset(&initial,count,7));
  initial.objects[0].x=-257;initial.objects[0].vx=-123;
  initial.objects[count-1].y=-1;initial.objects[count-1].vy=INT16_MIN;
  assert(!replay_init(&recording,&initial,3));
  for(unsigned i=0;i<REPLAY_INPUT_TICKS;i++) {
   game_input in={.held=(uint16_t)(i&V3_KEY_MASK)};
   assert(!replay_record(&recording,&in));
  }
  uint32_t expected=canonical_reference(&recording);
  assert(!replay_seal(&recording) && recording.crc32==expected);
  replay_cursor cursor;
  assert(!replay_begin(&recording,3,&restored,&cursor));
  assert(!memcmp(&initial,&restored,sizeof initial));
  bad=recording;bad.initial.objects[count-1].vy++;
  assert(replay_begin(&bad,3,&restored,&cursor)==GPU_DRIVER_ARGUMENT);
  bad=recording;bad.keys[599]^=V3_KEY_UP;
  assert(replay_begin(&bad,3,&restored,&cursor)==GPU_DRIVER_ARGUMENT);
  /* A skipped field, wrong canonical order or unbounded chunk breaks this
   * independent CRC oracle. No rolling CRC computed by the tested helper. */
  const unsigned budgets[]={1,7,256};
  for(unsigned b=0;b<3;b++) {
   replay_seal_cursor step={0};recording.sealed=0;recording.crc32=0;
   unsigned total=20u+9u*count+600u,calls=0;
   int done;
   do {
    unsigned before=step.offset;
    done=replay_seal_step(&recording,&step,budgets[b]);assert(done>=0);
    assert(step.offset>before && step.offset-before<=budgets[b]);++calls;
    assert(recording.sealed==(done==1));
   } while(!done);
   assert(step.offset==total && calls==(total+budgets[b]-1)/budgets[b]);
   assert(recording.crc32==expected && !replay_begin(&recording,3,&restored,&cursor));
  }
  replay_seal_cursor step={0};recording.sealed=0;
  assert(replay_seal_step(&recording,&step,0)<0 && !step.offset);
  assert(replay_seal_step(&recording,&step,257)<0 && !step.offset);
  recording.count=599;assert(replay_seal_step(&recording,&step,256)<0);recording.count=600;
  assert(!replay_seal_step(&recording,&step,256));
  bad=recording;bad.initial.player_x++;
  replay_seal_cursor bad_step=step;
  int bad_done;
  do {bad_done=replay_seal_step(&bad,&bad_step,256);assert(bad_done>=0);} while(!bad_done);
  assert(replay_begin(&bad,3,&restored,&cursor)==GPU_DRIVER_ARGUMENT);
 }
#ifdef REPLAY_CRC_COST_CHECK
 /* Opt-in benchmark, not a scheduler-sensitive ordinary regression gate.
  * Performance RED before implementation: the unmodified production
  * bitwise path has no 2x saving against the same independent algorithm.
  * This checks host algorithm cost only, never FPGA or game FPS. */
 uint32_t crc=UINT32_MAX;
 clock_t start=clock();
 for(unsigned i=0;i<300000;i++) crc=reference_word(crc,i*0x10203u);
 clock_t old_ticks=clock()-start;sink=crc;
 crc=UINT32_MAX;start=clock();
 for(unsigned i=0;i<300000;i++) crc_word(&crc,i*0x10203u);
 clock_t new_ticks=clock()-start;assert(crc==sink);sink=crc;
 printf("CRC host word cost: reference=%ld candidate=%ld ticks (not board FPS)\n",
  (long)old_ticks,(long)new_ticks);fflush(stdout);
#if REPLAY_CRC_NIBBLE
 assert(old_ticks>0 && new_ticks*2<old_ticks);
#endif
#endif
 puts("PASS replay CRC: word/canonical/sign/capacity/tamper equivalence");
 return 0;
}
