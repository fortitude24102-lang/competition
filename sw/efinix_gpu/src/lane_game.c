#include "lane_game.h"
#include <string.h>

#define FIELD_LEFT 64
#define FIELD_RIGHT 928
#define PLANT_COST 10u

static uint32_t next_random(lane_game_state *s) {
    s->rng = s->rng * UINT32_C(1664525) + UINT32_C(1013904223);
    return s->rng;
}

void lane_game_init(lane_game_state *s,uint32_t seed) {
    if (!s) return;
    memset(s,0,sizeof *s);
    s->coins=50;
    s->wave=1;
    s->rng=seed;
    s->phase=LANE_PLAYING;
}

int lane_game_plant(lane_game_state *s,uint8_t row,uint8_t col) {
    if (!s || s->phase!=LANE_PLAYING || row>=LANE_ROWS || col>=LANE_COLS ||
        s->coins<PLANT_COST) return -1;
    for (unsigned i=0;i<LANE_MAX_PLANTS;i++)
        if (s->plants[i].active && s->plants[i].row==row && s->plants[i].col==col)
            return -2;
    for (unsigned i=0;i<LANE_MAX_PLANTS;i++) if (!s->plants[i].active) {
        s->plants[i]=(lane_plant){.row=row,.col=col,.hp=100,.active=1};
        s->coins-=PLANT_COST;
        return 0;
    }
    return -3;
}

static void spawn_enemy(lane_game_state *s) {
    for (unsigned i=0;i<LANE_MAX_ENEMIES;i++) if (!s->enemies[i].active) {
        s->enemies[i]=(lane_enemy){.row=(uint8_t)(next_random(s)%LANE_ROWS),
            .active=1,.x16=900<<16,.hp=(uint16_t)(60+20*s->wave),
            .speed16=(uint16_t)(0x9000u+0x1000u*s->wave)};
        ++s->spawned_in_wave;
        return;
    }
}

static void plants_fire(lane_game_state *s) {
    for (unsigned p=0;p<LANE_MAX_PLANTS;p++) {
        lane_plant *plant=&s->plants[p];
        if (!plant->active) continue;
        if (plant->cooldown) { --plant->cooldown; continue; }
        int32_t plant_x=(int32_t)(FIELD_LEFT+plant->col*96u+48u)<<16;
        int target=0;
        for (unsigned e=0;e<LANE_MAX_ENEMIES;e++)
            if (s->enemies[e].active && s->enemies[e].row==plant->row &&
                s->enemies[e].x16>=plant_x) { target=1; break; }
        if (!target) continue;
        for (unsigned i=0;i<LANE_MAX_PROJECTILES;i++)
            if (!s->projectiles[i].active) {
                s->projectiles[i]=(lane_projectile){.row=plant->row,.active=1,
                    .x16=plant_x,.damage=20,.speed16=12u<<16};
                plant->cooldown=34;
                break;
            }
    }
}

static void move_projectiles(lane_game_state *s) {
    for (unsigned p=0;p<LANE_MAX_PROJECTILES;p++) {
        lane_projectile *shot=&s->projectiles[p];
        if (!shot->active) continue;
        shot->x16+=(int32_t)shot->speed16;
        if (shot->x16>=FIELD_RIGHT<<16) { shot->active=0; continue; }
        for (unsigned e=0;e<LANE_MAX_ENEMIES;e++) {
            lane_enemy *enemy=&s->enemies[e];
            if (!enemy->active || enemy->row!=shot->row ||
                shot->x16<enemy->x16 || shot->x16>enemy->x16+(48<<16)) continue;
            shot->active=0;
            if (enemy->hp<=shot->damage) {
                enemy->active=0;
                s->score+=10;
                s->coins+=5;
            } else enemy->hp-=shot->damage;
            break;
        }
    }
}

static void move_enemies(lane_game_state *s) {
    for (unsigned e=0;e<LANE_MAX_ENEMIES;e++) {
        lane_enemy *enemy=&s->enemies[e];
        if (!enemy->active) continue;
        lane_plant *blocking=0;
        for (unsigned p=0;p<LANE_MAX_PLANTS;p++) {
            lane_plant *plant=&s->plants[p];
            int32_t plant_x=(int32_t)(FIELD_LEFT+plant->col*96u+16u)<<16;
            if (plant->active && plant->row==enemy->row &&
                enemy->x16>=plant_x && enemy->x16<=plant_x+(40<<16)) {
                blocking=plant;
                break;
            }
        }
        if (blocking) {
            if (s->tick%12u==0) {
                if (blocking->hp<=10) blocking->active=0;
                else blocking->hp-=10;
            }
        } else enemy->x16-=enemy->speed16;
        if (enemy->x16<FIELD_LEFT<<16) s->phase=LANE_LOST;
    }
}

void lane_game_step(lane_game_state *s,uint32_t input) {
    if (!s || s->phase==LANE_WON || s->phase==LANE_LOST) return;
    uint32_t pressed=input & ~s->previous_input;
    s->previous_input=input;
    if (pressed&LANE_INPUT_PAUSE) {
        s->phase=s->phase==LANE_PAUSED ? LANE_PLAYING : LANE_PAUSED;
    }
    if (s->phase!=LANE_PLAYING) return;
    if (pressed&LANE_INPUT_NEXT_ROW) s->selected_row=(uint8_t)((s->selected_row+1u)%LANE_ROWS);
    if (pressed&LANE_INPUT_NEXT_COL) s->selected_col=(uint8_t)((s->selected_col+1u)%LANE_COLS);
    if (pressed&LANE_INPUT_PLANT) lane_game_plant(s,s->selected_row,s->selected_col);
    ++s->tick;
    if (s->tick%90u==0 && s->spawned_in_wave<4u+2u*s->wave) spawn_enemy(s);
    plants_fire(s);
    move_projectiles(s);
    move_enemies(s);
    if (s->phase==LANE_LOST) return;
    if (s->spawned_in_wave<4u+2u*s->wave) return;
    for (unsigned e=0;e<LANE_MAX_ENEMIES;e++) if (s->enemies[e].active) return;
    if (s->wave==3u) s->phase=LANE_WON;
    else { ++s->wave; s->spawned_in_wave=0; s->coins+=20; }
}

uint32_t lane_game_crc(const lane_game_state *s) {
    if (!s) return 0;
    uint32_t h=UINT32_C(2166136261);
#define MIX(value) do { h=(h^(uint32_t)(value))*UINT32_C(16777619); } while (0)
    MIX(s->tick); MIX(s->score); MIX(s->coins); MIX(s->wave);
    MIX(s->rng); MIX(s->spawned_in_wave); MIX(s->previous_input);
    MIX(s->selected_row); MIX(s->selected_col); MIX(s->phase);
    for (unsigned i=0;i<LANE_MAX_PLANTS;i++) {
        MIX(s->plants[i].row); MIX(s->plants[i].col); MIX(s->plants[i].hp);
        MIX(s->plants[i].active); MIX(s->plants[i].cooldown);
    }
    for (unsigned i=0;i<LANE_MAX_ENEMIES;i++) {
        MIX(s->enemies[i].row); MIX(s->enemies[i].active); MIX(s->enemies[i].x16);
        MIX(s->enemies[i].hp); MIX(s->enemies[i].speed16);
    }
    for (unsigned i=0;i<LANE_MAX_PROJECTILES;i++) {
        MIX(s->projectiles[i].row); MIX(s->projectiles[i].active);
        MIX(s->projectiles[i].x16); MIX(s->projectiles[i].damage);
        MIX(s->projectiles[i].speed16);
    }
#undef MIX
    return h;
}
