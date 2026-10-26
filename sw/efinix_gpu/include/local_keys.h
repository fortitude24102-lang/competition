#ifndef LOCAL_KEYS_H
#define LOCAL_KEYS_H
#include "v3_runtime.h"
typedef struct {
 uint32_t changed_ms,sequence;
 uint8_t pending,stable,selected,initialized,was_menu,armed;
} local_keys;
/* Consumes only the local STATUS capability; no synthetic UDP ownership/ACKs.
 * Return1 when the local device supplied input,0 for legacy/performance input. */
int local_keys_update(local_keys *,uint32_t status,uint32_t now_ms,v3_runtime *,game_input *);
#endif
