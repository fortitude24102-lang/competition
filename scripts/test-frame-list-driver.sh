#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v3/frame-list-integration
mkdir -p "$out"
gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -DGPU_TEST_BACKEND \
 -ffunction-sections -fdata-sections -Wl,--gc-sections -Isw/efinix_gpu/include \
 sw/efinix_gpu/tests/test_gpu_frame_list_driver.c sw/efinix_gpu/src/gpu.c \
 sw/efinix_gpu/src/gpu_instances.c sw/efinix_gpu/src/gpu_frame_list.c sw/efinix_gpu/src/bullet_demo.c \
 -o "$out/test_frame_list_driver"
"$out/test_frame_list_driver"
