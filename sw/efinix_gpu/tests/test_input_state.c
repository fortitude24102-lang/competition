#include <assert.h>
#include <stdio.h>
#include "input_state.h"

static void newly_pressed_action_does_not_repeat_other_held_action(void) {
    game_input state={0};
    nc_input input={.session=3,.sequence=1,.action_sequence=1,
                    .keys=V3_KEY_RESTART,.connected=1};
    input_update(&state,&input);
    assert(state.pressed==V3_KEY_RESTART);
    ++input.sequence; ++input.action_sequence;
    input.keys=V3_KEY_RESTART|V3_KEY_COMPARE;
    input_update(&state,&input);
    assert(state.pressed==V3_KEY_COMPARE);
    assert(state.held==(V3_KEY_RESTART|V3_KEY_COMPARE));
    input_update(&state,&input);
    assert(state.pressed==0);

    state=(game_input){0};
    input=(nc_input){.session=4,.sequence=1,.action_sequence=1,
                     .keys=V3_KEY_COMPARE,.connected=1};
    input_update(&state,&input);
    assert(state.pressed==V3_KEY_COMPARE);
    ++input.sequence; ++input.action_sequence;
    input.keys=V3_KEY_COMPARE|V3_KEY_RESTART;
    input_update(&state,&input);
    assert(state.pressed==V3_KEY_RESTART);

    /* No visible edge: a newer shared counter retains recovery from a lost
       release/re-press snapshot. Both-held ambiguity emits both actions. */
    ++input.sequence; ++input.action_sequence;
    input_update(&state,&input);
    assert(state.pressed==(V3_KEY_RESTART|V3_KEY_COMPARE));
}

int main(void) {
    newly_pressed_action_does_not_repeat_other_held_action();
    game_input a = {0}, b = {0};
    nc_input n = {.session=1, .sequence=UINT32_MAX-1u, .action_sequence=UINT32_MAX,
                  .keys=V3_KEY_LEFT|V3_KEY_RESTART, .connected=1};
    input_update(&a,&n);
    assert(a.held==(V3_KEY_LEFT|V3_KEY_RESTART));
    assert(a.pressed==(V3_KEY_LEFT|V3_KEY_RESTART));
    input_update(&a,&n);
    assert(a.pressed==0 && a.released==0);
    ++n.sequence;
    input_update(&a,&n);
    assert(a.pressed==0);
    ++n.sequence; n.action_sequence=0;
    input_update(&a,&n);
    assert(a.pressed==V3_KEY_RESTART);
    ++n.sequence; n.action_sequence=UINT32_MAX;
    input_update(&a,&n);
    assert(a.pressed==0);
    ++n.sequence; n.keys=V3_KEY_LEFT|V3_KEY_RIGHT|V3_KEY_UP|V3_KEY_DOWN|V3_KEY_FIRE;
    input_update(&a,&n);
    assert(a.held==V3_KEY_FIRE && a.pressed==V3_KEY_FIRE);
    assert(a.released==(V3_KEY_LEFT|V3_KEY_RESTART));
    input_update(&b,&n);
    assert(b.held==V3_KEY_FIRE);
    n.connected=0;
    input_update(&a,&n);
    assert(a.held==0 && a.released==V3_KEY_FIRE);
    assert(b.held==V3_KEY_FIRE);
    n.connected=1; n.session=2; n.keys=V3_KEY_COMPARE; n.action_sequence=0;
    input_update(&a,&n);
    assert(a.pressed==V3_KEY_COMPARE);
    n.age_ms=251;
    input_update(&a,&n);
    assert(a.held==0 && a.released==V3_KEY_COMPARE);
    input_update(&a,NULL);
    assert(a.held==0 && a.pressed==0 && a.released==0);
    input_update(NULL,&n);
    puts("PASS input_state: action cross-hold edges, same-key counter recovery, opposing keys, modular events, sessions, stale/disconnect, independent state");
    return 0;
}
