/* Reuse the real APB RX/TX fixture, not a second simulated game controller. */
#define main net_control_fixture_suite
#include "test_net_control.c"
#undef main
#include "v3_demo.h"
#include "v3_runtime.h"
static v3_runtime runtime;
int main(void) {
 nc_device d;nc_input in;nc_game_command cmd;reset();CHECK(!nc_init(&d,0));
 CHECK(!v3_runtime_menu_init(&runtime,7,3));
 enqueue(1,7,1,0,0,0);nc_poll(&d,0,&in);nc_try_publish(&d,NULL,0);hw.tx_ready=1;
 game_packet(2,1,3,11,0);CHECK(nc_poll(&d,1,&in)>0 && nc_take_game(&d,&cmd)==1);
 unsigned generation=runtime.scene_generation;
 CHECK(!v3_apply_game_command(&runtime,&d,&cmd));
 CHECK(runtime.phase==V3_PHASE_PLAY && runtime.game.count==256 && runtime.scene_generation==generation+1);
 CHECK(nc_try_publish(&d,NULL,1)>0 && hw.sent[5]==5 && read_be(hw.sent+20)==0);
 game_packet(3,1,3,11,0);nc_poll(&d,2,&in);CHECK(!nc_take_game(&d,&cmd));
 CHECK(runtime.scene_generation==generation+1);
 game_packet(4,1,2,12,0);nc_poll(&d,3,&in);CHECK(nc_take_game(&d,&cmd)==1);
 CHECK(!v3_apply_game_command(&runtime,&d,&cmd));hw.tx_ready=1;nc_try_publish(&d,NULL,3);
 CHECK(read_be(hw.sent+20)==1 && runtime.game.count==256);
 game_packet(5,2,0,13,0);nc_poll(&d,4,&in);CHECK(nc_take_game(&d,&cmd)==1);
 CHECK(!v3_apply_game_command(&runtime,&d,&cmd) && runtime.phase==V3_PHASE_MENU);
 CHECK(!(v3_runtime_status(&runtime,1,1,1,0,0)&V3_VALID_GPU_TIMING));
 puts("PASS real 32B RX -> Sapphire runtime -> post-execution ACK; duplicate/no restart and menu return");
}
