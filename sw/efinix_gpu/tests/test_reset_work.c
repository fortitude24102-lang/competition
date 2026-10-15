/* Catch duplicate discarded spawn work on the actual restart path. The old
 * two-pass reset below remains a state oracle, not a timed production path. */
#include <assert.h>
#include <stdio.h>
#include "../src/bullet_demo.c"
static unsigned spawns,waypoints;
void __attribute__((no_instrument_function)) __cyg_profile_func_enter(void *fn,void *caller) {
 (void)caller;if(fn==(void *)spawn)++spawns;
 if(fn==(void *)waypoint)++waypoints;
}
void __attribute__((no_instrument_function)) __cyg_profile_func_exit(void *fn,void *caller) {
 (void)fn;(void)caller;
}
static bullet_state actual,expected;
static void reference(unsigned count,uint32_t seed) {
 assert(!bullet_reset(&expected,count,seed));
 expected.interactive=1;
 for(unsigned i=0;i<BULLET_ENEMY_COUNT;i++)expected.enemy_hp[i]=BULLET_ENEMY_HP;
 for(unsigned i=0;i<count;i++)spawn(&expected,i,1);
}
int main(void) {
 const int initial_centers[3][2]={{480,280},{240,100},{720,220}};
 assert(!bullet_reset_player(&actual,512,7));
 for(unsigned i=0;i<3;i++) {
  int x,y;assert(!bullet_enemy_position(&actual,i,&x,&y));
  assert(x==initial_centers[i][0] && y==initial_centers[i][1]);
 }
 const unsigned counts[]={1,64,128,256,512};
 for(unsigned c=0;c<5;c++)for(unsigned seed=0;seed<3;seed++) {
  reference(counts[c],seed);
  memset(&actual,0xa5,sizeof actual);spawns=waypoints=0;
  assert(!bullet_reset_player(&actual,counts[c],seed));
  assert(!memcmp(&actual,&expected,sizeof actual));
  assert(spawns==counts[c]); /* Old code spawns every object twice. */
  assert(!waypoints); /* At round0 interpolation is exactly the fixed center. */
  actual.hp=0;actual.game_over_ticks=1;actual.tick=123;
  spawns=waypoints=0;
  assert(!bullet_step_player(&actual,480,480));
  expected.tick=124;
  assert(!memcmp(&actual,&expected,sizeof actual) && spawns==counts[c] && !waypoints);
 }
 assert(bullet_reset_player(NULL,512,7)==GPU_DRIVER_ARGUMENT);
 expected=actual;
 assert(bullet_reset_player(&actual,513,7)==GPU_DRIVER_ARGUMENT);
 assert(!memcmp(&actual,&expected,sizeof actual));
 puts("PASS reset work: one spawn/object, exact old state, death-restart tick and invalid-input immutability");
}
