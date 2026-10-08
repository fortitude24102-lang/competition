#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "hud.h"
int main(void) {
 char lines[HUD_COMPARISON_LINES][HUD_COMPARISON_COLUMNS];
 hud_comparison m={.bullet_demo=1,.gameplay=1,.cpu_valid=1,.gpu_active=1,.cpu_fps_x10=28};
 assert(hud_comparison_text(&m,lines)==0 && strstr(lines[3]," AUTO"));
 m.v3_mode=1;m.cpu_stale=1;m.logic_slow=1;
 assert(hud_comparison_text(&m,lines)==0);
 assert(strstr(lines[0],"STALE") && strstr(lines[2],"LIVE") && strstr(lines[3],"SLOW"));
 m.v3_mode=2;m.cpu_stale=0;m.logic_slow=0;m.gpu_active=0;
 assert(hud_comparison_text(&m,lines)==0 && strstr(lines[2],"REPLAY"));
 m.v3_mode=4;m.gameplay=0;m.gpu_valid=0;
 assert(!hud_comparison_text(&m,lines) && strstr(lines[2],"MENU") && strstr(lines[3],"SELECT LEVEL ON WEB"));
 for(unsigned i=0;i<HUD_COMPARISON_LINES;i++) assert(strlen(lines[i])<HUD_COMPARISON_COLUMNS);
 puts("PASS V3 HUD real/replay, stale CPU and logic slowdown labels; legacy AUTO unchanged");
}
