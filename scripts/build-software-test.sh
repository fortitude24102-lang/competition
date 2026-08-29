#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
output_dir="$project_root/sw/build"

mkdir -p "$output_dir"
"${compiler_prefix}gcc" \
  -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Os \
  -Wall -Wextra -Werror -fno-builtin -msmall-data-limit=0 \
  -I "$project_root/sw/bsp" -I "$project_root/sw/drivers" \
  -Wl,--build-id=none -Wl,-Map,"$output_dir/driver_test.map" \
  -T "$project_root/sw/link.ld" \
  -o "$output_dir/driver_test.elf" \
  "$project_root/sw/start.S" \
  "$project_root/sw/drivers/accel_driver.c" \
  "$project_root/sw/tests/driver_test.c"
"${compiler_prefix}objcopy" -O binary \
  "$output_dir/driver_test.elf" "$output_dir/driver_test.bin"
od -An -v -tx4 -w4 "$output_dir/driver_test.bin" | sed 's/^ *//' > "$output_dir/driver_test.hex"

test -s "$output_dir/driver_test.elf"
test -s "$output_dir/driver_test.bin"
test -s "$output_dir/driver_test.hex"
echo "Built $output_dir/driver_test.hex"
