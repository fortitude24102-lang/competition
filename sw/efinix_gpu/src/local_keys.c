#include "local_keys.h"
int local_keys_update(local_keys *s,uint32_t status,uint32_t now,v3_runtime *r,game_input *input) {
 if(!s || !r || !input || !(status&GPU_STATUS_LOCAL_KEYS_PRESENT))return 0;
 if(r->phase==V3_PHASE_PERFORMANCE){s->was_menu=s->armed=0;return 0;}
 unsigned raw=(status>>GPU_STATUS_LOCAL_KEYS_SHIFT)&31u;
 if(!s->initialized){s->initialized=1;s->selected=1;s->pending=(uint8_t)raw;s->changed_ms=now;}
 if(raw!=s->pending){s->pending=(uint8_t)raw;s->changed_ms=now;}
 unsigned old=s->stable;
 if(now-s->changed_ms>=20u)s->stable=s->pending;
 unsigned held=s->stable,pressed=held&~old;
 if((held&3u)==3u){held&=~3u;pressed&=~3u;}
 if((held&12u)==12u){held&=~12u;pressed&=~12u;}
 int menu=r->menu_enabled && r->phase==V3_PHASE_MENU;
 if(menu && !s->was_menu)s->armed=0;
 if(!s->stable && !s->pending && now-s->changed_ms>=20u)s->armed=1;
 s->was_menu=(uint8_t)menu;
 unsigned levels=BULLET_MAX_OBJECTS>=1024?6u:4u;
 if(menu && s->armed) {
  if((pressed&1u) && s->selected>2)s->selected=(uint8_t)(s->selected>levels?levels:s->selected-2u);
  if(pressed&2u) {
   if(s->selected+2u<=levels)s->selected+=2;
   else if(r->split_enabled)s->selected=(uint8_t)(levels+1u);
  }
  if((pressed&4u) && !(s->selected&1u))--s->selected;
  if((pressed&8u) && (s->selected&1u) && s->selected<levels)++s->selected;
  if(pressed&16u) {
   int e=s->selected>levels?v3_runtime_start_comparison(r):
    v3_runtime_game_command(r,V3_GAME_START,s->selected,UINT32_C(0x4c4f434c),s->sequence);
   if(e)return e;
   s->armed=0;
  }
 }
 nc_input local={.session=UINT32_C(0x4c4f434c),.sequence=++s->sequence,.age_ms=0,
  .keys=(uint16_t)(((held&3u)<<2)|((held>>2)&3u)|(held&16u)),.connected=1,.keys_snapshot=1};
 input_update(input,&local);
 input->neutral=(uint8_t)(!s->stable && !s->pending);
 return 1;
}
