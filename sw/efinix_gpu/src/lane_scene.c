#include "lane_scene.h"
#include "asset_catalog.h"

static int add_sprite(lane_scene *out,uint32_t dst,uint32_t src,int x,int y) {
    if (x>=960 || x+64<=0 || y<0 || y+80>540) return 0;
    unsigned skip=x<0 ? (unsigned)-x : 0;
    unsigned visible=(unsigned)(x+64>960 ? 960-x : 64);
    if (skip>=visible) return 0;
    if (out->count==LANE_SCENE_MAX_COMMANDS) return GPU_DRIVER_FULL;
    out->commands[out->count++]=(gpu_command){
        .op=GPU_OP_COLOR_KEY,
        .src_addr=src+skip*2u,
        .dst_addr=dst+(uint32_t)y*GPU_FRAME_STRIDE+(uint32_t)(x+(int)skip)*2u,
        .src_stride=ASSET_SPRITE_WIDTH*2u,
        .dst_stride=GPU_FRAME_STRIDE,
        .width_pixels=(uint16_t)(visible-skip),
        .height_pixels=ASSET_SPRITE_HEIGHT,
        .color_key=ASSET_COLOR_KEY
    };
    ++out->sprite_count;
    return 0;
}

int lane_scene_build(const lane_game_state *s,uint32_t dst,lane_scene *out) {
    if (!s || !out || (dst!=GPU_FRAMEBUFFER_A && dst!=GPU_FRAMEBUFFER_B))
        return GPU_DRIVER_ARGUMENT;
    *out=(lane_scene){0};
    out->commands[out->count++]=(gpu_command){
        .op=GPU_OP_COPY,.src_addr=ASSET_SCENE_ADDR,.dst_addr=dst,
        .src_stride=GPU_FRAME_STRIDE,.dst_stride=GPU_FRAME_STRIDE,
        .width_pixels=GPU_FRAME_WIDTH,.height_pixels=GPU_FRAME_HEIGHT
    };
    for (unsigned i=0;i<LANE_MAX_PLANTS;i++) if (s->plants[i].active) {
        const lane_plant *plant=&s->plants[i];
        int result=add_sprite(out,dst,ASSET_FLOWER_ADDR,
                              80+(int)plant->col*96,68+(int)plant->row*96);
        if (result) return result;
    }
    for (unsigned i=0;i<LANE_MAX_ENEMIES;i++) if (s->enemies[i].active) {
        const lane_enemy *enemy=&s->enemies[i];
        uint32_t image=(s->tick/12u)&1u ? ASSET_ZOMBIE_WALK1_ADDR : ASSET_ZOMBIE_WALK2_ADDR;
        int result=add_sprite(out,dst,image,enemy->x16>>16,68+(int)enemy->row*96);
        if (result) return result;
    }
    for (unsigned i=0;i<LANE_MAX_PROJECTILES;i++) if (s->projectiles[i].active) {
        const lane_projectile *shot=&s->projectiles[i];
        int x=shot->x16>>16;
        if (x<0 || x>952) continue;
        if (out->count==LANE_SCENE_MAX_COMMANDS) return GPU_DRIVER_FULL;
        out->commands[out->count++]=(gpu_command){
            .op=GPU_OP_FILL,
            .dst_addr=dst+(uint32_t)(104+shot->row*96u)*GPU_FRAME_STRIDE+(uint32_t)x*2u,
            .dst_stride=GPU_FRAME_STRIDE,.width_pixels=8,.height_pixels=8,.color=0xffe0
        };
        ++out->sprite_count;
    }
    return 0;
}
