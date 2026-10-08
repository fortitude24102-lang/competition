#ifndef INPUT_STATE_H
#define INPUT_STATE_H
#include "net_control.h"
typedef struct {
    uint16_t held, pressed, released;
    /* Caller-owned bookkeeping. Initialize the whole object to zero. */
    uint32_t session, sequence, action_sequence;
    uint8_t initialized, action_initialized,neutral;
} game_input;

/* Opposing directions cancel. Actions appear in pressed once for a new
   action_sequence even when the corresponding key remains held.
   NULL, disconnected, or age >250ms inputs release all held keys. */
void input_update(game_input *state, const nc_input *input);
#endif
