#include <assert.h>
#include <stdio.h>
#include "local_keys.h"
static v3_runtime runtime;
static game_input input;
static local_keys keys;
static void poll(unsigned raw,unsigned ms) {
 assert(local_keys_update(&keys,GPU_STATUS_LOCAL_KEYS_PRESENT|((uint32_t)raw<<27),ms,&runtime,&input)==1);
}
int main(void) {
 assert(!v3_runtime_menu_init(&runtime,7,3));
 poll(0,0);poll(16,1);poll(16,22);
 assert(runtime.phase==V3_PHASE_MENU); /* Boot idle glitch cannot arm a held key. */
 keys=(local_keys){0};input=(game_input){0};
 assert(!v3_runtime_menu_init(&runtime,7,3));
 assert(!local_keys_update(&keys,0,0,&runtime,&input));
 poll(16,0);poll(16,21);assert(runtime.phase==V3_PHASE_MENU); /* Held at boot cannot start. */
 poll(0,22);poll(0,43);
 poll(8,44);poll(8,50);assert(keys.selected==1); /* Right contact bounces. */
 poll(0,51);poll(8,52);poll(8,73);assert(keys.selected==2);
 poll(8,200);assert(keys.selected==2); /* No navigation repeat while held. */
 poll(0,201);poll(0,222);poll(2,223);poll(2,244);assert(keys.selected==4);
 poll(0,245);poll(0,266);poll(16,267);poll(16,288);
 assert(runtime.phase==V3_PHASE_PLAY && runtime.level==4 && runtime.game.count==512);
 assert(runtime.await_neutral);assert(v3_runtime_advance(&runtime,&input,16667)>=0 && runtime.await_neutral);
 poll(0,289);poll(0,310);assert(v3_runtime_advance(&runtime,&input,16667)>=0 && !runtime.await_neutral);
 poll(21,311);poll(21,332);assert(input.held==(V3_KEY_UP|V3_KEY_LEFT|V3_KEY_FIRE));
 poll(21,350);assert(!input.pressed && input.held==(V3_KEY_UP|V3_KEY_LEFT|V3_KEY_FIRE));
 poll(15,351);poll(15,372);assert(!input.held && !input.neutral); /* Cancelled directions are not physical neutral. */
 assert(!v3_runtime_game_command(&runtime,V3_GAME_MENU,0,1,1));
 poll(16,373);poll(16,394);assert(runtime.phase==V3_PHASE_MENU); /* New menu requires release. */
 poll(0,395);poll(0,416);poll(16,417);poll(16,438);assert(runtime.phase==V3_PHASE_PLAY);
 runtime.phase=V3_PHASE_PERFORMANCE;game_input saved=input;
 assert(!local_keys_update(&keys,GPU_STATUS_LOCAL_KEYS_PRESENT,500,&runtime,&input));
 assert(input.held==saved.held && input.sequence==saved.sequence); /* Preserve challenge owner/lease. */
 assert(!keys.was_menu && !keys.armed);
 runtime.phase=V3_PHASE_MENU;
 poll(16,501);poll(16,522);assert(runtime.phase==V3_PHASE_MENU);
 poll(0,523);poll(0,544);poll(16,545);poll(16,566);
 assert(runtime.phase==V3_PHASE_PLAY); /* Challenge exit also requires a fresh release. */
 keys=(local_keys){0};input=(game_input){0};
 assert(!v3_runtime_menu_init(&runtime,7,3));poll(0,600);poll(0,621);
 poll(2,622);poll(2,643);assert(keys.selected==3);
 poll(0,644);poll(0,665);poll(2,666);poll(2,687);
 assert(keys.selected==(BULLET_MAX_OBJECTS>=1024?5:3));
 poll(8,688);poll(8,709);assert(keys.selected==(BULLET_MAX_OBJECTS>=1024?6:4));
 poll(2,710);poll(2,731);assert(keys.selected==(BULLET_MAX_OBJECTS>=1024?6:4));
 runtime.split_enabled=1;
 poll(0,732);poll(0,753);poll(2,754);poll(2,775);
 assert(keys.selected==(BULLET_MAX_OBJECTS>=1024?7:5));
 poll(0,776);poll(0,797);poll(16,798);poll(16,819);
 assert(runtime.phase==V3_PHASE_SPLIT_COMPARE);
 assert(!v3_runtime_game_command(&runtime,V3_GAME_MENU,0,1,2));
 assert(!v3_runtime_game_command(&runtime,V3_GAME_START,3,1,3));
 assert(v3_runtime_start_comparison(&runtime)==1 && runtime.phase==V3_PHASE_PLAY && runtime.game.count==256);
 puts("PASS local keys: debounce, neutral latch, menu selection/start, movement/fire and performance isolation");
}
