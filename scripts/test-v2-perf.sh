#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v2-perf
mkdir -p "$out"
cc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -fno-omit-frame-pointer \
 -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 \
 sw/efinix_gpu/tests/test_perf_demo.c sw/efinix_gpu/src/perf_demo.c \
 sw/efinix_gpu/src/hud.c sw/efinix_gpu/src/assets.c sw/efinix_gpu/src/sparse_pack.c \
 sw/efinix_gpu/src/golden_renderer.c sw/efinix_gpu/src/rgb565.c -o "$out/test_perf_demo"
"$out/test_perf_demo"
