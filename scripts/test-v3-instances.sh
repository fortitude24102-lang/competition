#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=generated/verification/v3/instances
mkdir -p "$out"
flags=(-std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined
 -DGPU_TEST_BACKEND -ffunction-sections -Wl,--gc-sections -Isw/efinix_gpu/include)
for test in gpu_instances gpu_instances_driver; do
 extra=()
 if [[ $test == gpu_instances_driver ]]; then extra=(sw/efinix_gpu/src/gpu.c); fi
 gcc "${flags[@]}" "sw/efinix_gpu/tests/test_$test.c" \
  sw/efinix_gpu/src/gpu_instances.c sw/efinix_gpu/src/bullet_demo.c "${extra[@]}" -o "$out/test_$test"
 "$out/test_$test"
done
