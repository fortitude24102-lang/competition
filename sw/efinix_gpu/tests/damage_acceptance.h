#ifndef DAMAGE_ACCEPTANCE_H
#define DAMAGE_ACCEPTANCE_H
#include "benchmark.h"
/* Shared only by owner diagnostics and their host check; CPU/legacy summary
 * deliberately retains its established P5 policy. */
static inline int damage_run_qualified(const benchmark_run_summary *summary,
 unsigned frames,unsigned work_missed,unsigned cadence_missed) {
 return frames==300 && summary->stable_sprite_count!=0 &&
  !summary->total_underflows && !summary->total_errors && !work_missed && !cadence_missed;
}
#endif
