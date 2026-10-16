#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v3/rows-stripes-20261016
mkdir -p "$out"
gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -DGPU_TEST_BACKEND \
 -ffunction-sections -Wl,--gc-sections -Isw/efinix_gpu/include \
 sw/efinix_gpu/tests/test_gpu_stripes.c sw/efinix_gpu/src/gpu_stripes.c \
 sw/efinix_gpu/src/gpu_instances.c sw/efinix_gpu/src/golden_renderer.c sw/efinix_gpu/src/rgb565.c \
 -o "$out/test_gpu_stripes"
"$out/test_gpu_stripes"
