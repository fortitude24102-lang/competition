#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v3/rows-stripes-20261016
mkdir -p "$out"
wraps=(v3_runtime_menu_init nc_init nc_poll nc_take_game nc_complete_game nc_try_publish
 nc_discard_pending_telemetry gpu_frame_list_init gpu_stripes_supported gpu_stripes_render
 hud_gpu_list_init hud_render_gpu_list gpu_set_qos gpu_read_perf_snapshot perf_render_gpu
 perf_render_cpu framebuffer_present game_menu_draw network_asset_fetch split_compare_init split_compare_step gpu_texture_cache_load)
args=();for f in "${wraps[@]}";do args+=("-Wl,--wrap=$f");done
gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -DGPU_TEST_BACKEND \
 -DV3_FRAME_LIST=1 -DV3_STRIPE_RENDER=1 -DV3_HUD_LIST=1 -ffunction-sections -Wl,--gc-sections \
 -Isw/efinix_gpu/include -Isw/efinix_gpu/tests/include -Isw/efinix_gpu/assets/v2 \
 sw/efinix_gpu/tests/test_stripe_hud_route.c \
 sw/efinix_gpu/src/{v3_demo,v3_runtime,bullet_demo,interactive_game,replay_input,input_state,local_keys,gpu_instances,perf_demo,golden_renderer,rgb565,hud,game_menu,hud_cache}.c \
 "${args[@]}" -o "$out/test_stripe_hud_route"
"$out/test_stripe_hud_route"
