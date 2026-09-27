#include "lane_scene.h"
#include "asset_catalog.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    lane_game_state a,b;
    lane_scene scene;
    lane_game_init(&a,20260921u);
    lane_game_init(&b,20260921u);
    assert(a.phase==LANE_PLAYING && a.coins==50);
    assert(lane_game_plant(&a,0,0)==0);
    assert(lane_game_plant(&b,0,0)==0);
    assert(lane_game_plant(&a,0,0)<0);
    for(unsigned frame=0;frame<300;frame++) {
        lane_game_step(&a,0);
        lane_game_step(&b,0);
    }
    assert(lane_game_crc(&a)==lane_game_crc(&b));
    assert(a.spawned_in_wave>0);
    assert(lane_scene_build(&a,GPU_FRAMEBUFFER_A,&scene)==0);
    assert(scene.commands[0].op==GPU_OP_COPY);
    assert(scene.commands[0].src_addr==ASSET_SCENE_ADDR);
    assert(scene.commands[0].width_pixels==GPU_FRAME_WIDTH);
    assert(scene.commands[0].height_pixels==GPU_FRAME_HEIGHT);
    assert(scene.sprite_count>0);
    assert(lane_scene_build(&a,0,&scene)==GPU_DRIVER_ARGUMENT);
    puts("PASS lane game deterministic simulation and asset-backed scene");
}
