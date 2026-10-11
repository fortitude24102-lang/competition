/* Catch overlapping phases, omitted inter-frame cost and unsafe sample bounds. */
#include <assert.h>
#include <stdio.h>
#include "live_phase_stats.h"
int main(void) {
 live_phase_stats s={0};uint32_t p[LP_COUNT]={10,20,30,40,50,60,70,80};
 assert(live_phase_record(&s,p,400,600,500)==0);
 assert(s.frames==1 && s.total[LP_OTHER]==40 && s.work==400 && s.wall==600);
 assert(s.misses==0 && s.late==1 && s.worst[LP_SCENE]==50);
 p[LP_LOGIC]=220;
 assert(live_phase_record(&s,p,600,600,500)==0);
 assert(s.frames==2 && s.misses==1 && s.max_work==600 && s.worst[LP_LOGIC]==220);
 live_phase_stats old=s;
 assert(live_phase_record(&s,p,500,600,500)<0); /* 560 cannot fit in 500. */
 assert(!memcmp(&s,&old,sizeof s));
 assert(live_phase_record(&s,p,600,599,500)<0);
 assert(live_phase_record(&s,p,600,600,0)<0);
 s.frames=LP_SAMPLES;
 assert(live_phase_record(&s,p,600,600,500)<0);
 puts("PASS live phase accounting: exclusive sum/remainder, worst-frame attribution, deadline and bounds");
}
