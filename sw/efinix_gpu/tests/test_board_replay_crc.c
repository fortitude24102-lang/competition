/* Isolated algorithm diagnostic, NOT game FPS. One BIN runs both algorithms.
 * DDR scratch is disjoint from assets/runtime; no framebuffer/GPU writes. */
#define REPLAY_CRC_NIBBLE 1
#include "../src/replay_input.c"
#include "replay_crc_reference.h"
#include "bsp.h"
#include "vexriscv.h"
static volatile uint32_t sink;
static uint32_t elapsed_us(uint64_t start) {
 return (uint32_t)((clint_getTime(BSP_CLINT)-start)/(BSP_CLINT_HZ/1000000u));
}
#define CHECK(c) do {if(!(c)) {bsp_printf("REPLAY_CRC_BOARD_FAIL,line=%d\r\n",__LINE__);return 1;}} while(0)
int main(void) {
 bsp_init();
 replay_recording *r=(replay_recording *)(uintptr_t)0x02e00000u;
 bullet_state *initial=(bullet_state *)(uintptr_t)0x02e10000u;
 bullet_state *restored=(bullet_state *)(uintptr_t)0x02e20000u;
 _Static_assert(sizeof(replay_recording)<65536u,"scratch record extent");
 _Static_assert(sizeof(bullet_state)<65536u,"scratch state extent");
 bsp_printf("REPLAY_CRC_BOARD_BEGIN,algorithm=nibble64,scratch=02e00000\r\n");
 for(unsigned count=256;count<=512;count*=2) {
  CHECK(!game_reset(initial,count,7));
  initial->objects[0].vx=-123;initial->objects[count-1].vy=INT16_MIN;
  CHECK(!replay_init(r,initial,3));
  for(unsigned i=0;i<600;i++) {
   game_input in={.held=(uint16_t)(i&V3_KEY_MASK)};CHECK(!replay_record(r,&in));
  }
  uint32_t expected=canonical_reference(r);CHECK(!replay_seal(r) && expected==r->crc32);
  for(unsigned repeat=0;repeat<3;repeat++) {
   uint64_t start=clint_getTime(BSP_CLINT);
   uint32_t reference=canonical_reference(r);uint32_t old_us=elapsed_us(start);sink=reference;
   r->sealed=0;start=clint_getTime(BSP_CLINT);
   int e=replay_seal(r);uint32_t seal_us=elapsed_us(start);CHECK(!e && r->crc32==reference);
   replay_cursor cursor;start=clint_getTime(BSP_CLINT);
   e=replay_begin(r,3,restored,&cursor);uint32_t begin_us=elapsed_us(start);
   CHECK(!e && !memcmp(initial,restored,sizeof *initial));
   /* Official lite BSP supports d/x but not u; unsupported u scans ahead
    * into the next specifier and may interpret an integer as a pointer. */
   bsp_printf("REPLAY_CRC_BOARD,count=%d,repeat=%d,crc=%x,reference_us=%d,seal_us=%d,begin_us=%d\r\n",
    count,repeat,r->crc32,old_us,seal_us,begin_us);
  }
  replay_cursor cursor;r->keys[599]^=V3_KEY_UP;
  CHECK(replay_begin(r,3,restored,&cursor)==GPU_DRIVER_ARGUMENT);
 }
 uint32_t crc=UINT32_MAX;uint64_t start=clint_getTime(BSP_CLINT);
 for(unsigned i=0;i<10000;i++) crc=reference_word(crc,i*0x10203u);
 uint32_t old_us=elapsed_us(start);sink=crc;
 crc=UINT32_MAX;start=clint_getTime(BSP_CLINT);
 for(unsigned i=0;i<10000;i++) crc_word(&crc,i*0x10203u);
 uint32_t new_us=elapsed_us(start);CHECK(crc==sink && old_us>new_us);
 bsp_printf("REPLAY_CRC_BOARD_WORDS,n=10000,reference_us=%d,nibble_us=%d\r\n",old_us,new_us);
 bsp_printf("REPLAY_CRC_BOARD_STOP,result=PASS,not_game_fps=1\r\n");
 for(;;) __asm__ volatile("wfi");
}
