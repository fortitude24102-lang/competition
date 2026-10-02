#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v3/damage
mkdir -p "$out"
gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined \
 -Isw/efinix_gpu/include sw/efinix_gpu/tests/test_gpu_damage.c \
 sw/efinix_gpu/src/gpu_damage.c sw/efinix_gpu/src/bullet_demo.c \
 sw/efinix_gpu/src/golden_renderer.c sw/efinix_gpu/src/rgb565.c -o "$out/test_gpu_damage"
"$out/test_gpu_damage" sw/efinix_gpu/assets/bullet/background.rgb565 \
 sw/efinix_gpu/assets/bullet/atlas.rgb565
bash scripts/test-v2-perf.sh
flags=(-std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined
 -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet)
render=(sw/efinix_gpu/src/perf_demo.c sw/efinix_gpu/src/gpu_damage.c
 sw/efinix_gpu/src/hud.c sw/efinix_gpu/src/assets.c sw/efinix_gpu/src/sparse_pack.c
 sw/efinix_gpu/src/golden_renderer.c sw/efinix_gpu/src/rgb565.c)
for test in bullet_demo bullet_gameplay; do
 gcc "${flags[@]}" sw/efinix_gpu/tests/test_$test.c sw/efinix_gpu/src/bullet_demo.c -o "$out/test_$test"
 "$out/test_$test"
done
gcc "${flags[@]}" -DGPU_TEST_BACKEND sw/efinix_gpu/tests/test_bullet_pixels.c \
 sw/efinix_gpu/src/bullet_demo.c sw/efinix_gpu/src/bullet_assets.c sw/efinix_gpu/src/hud_cache.c \
 "${render[@]}" -o "$out/test_bullet_pixels"
"$out/test_bullet_pixels"
for test in hud_cache hud_gpu_cache; do
 extra=()
 if [[ $test == hud_gpu_cache ]]; then extra=(sw/efinix_gpu/src/hud_gpu_cache.c); fi
 gcc "${flags[@]}" -DGPU_TEST_BACKEND sw/efinix_gpu/tests/test_$test.c \
  sw/efinix_gpu/src/hud_cache.c "${extra[@]}" "${render[@]}" -o "$out/test_$test"
 "$out/test_$test"
done
gcc "${flags[@]}" -ffunction-sections -Wl,--gc-sections \
 sw/efinix_gpu/tests/test_damage_acceptance.c sw/efinix_gpu/src/benchmark.c -o "$out/test_damage_acceptance"
"$out/test_damage_acceptance"
printf '%s\n' 'DAMAGE_SUITE,PASS,C_suites=8,golden_frames=18000,UBSan'
