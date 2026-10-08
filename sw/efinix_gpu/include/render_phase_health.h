#ifndef RENDER_PHASE_HEALTH_H
#define RENDER_PHASE_HEALTH_H
#include <stdint.h>
/* Keep the complete hardware counter, including wrap/reset detection. */
static inline int render_phase_health_ok(uint64_t before,uint64_t after,uint32_t error) {
 return before==after && error==0;
}
#endif
