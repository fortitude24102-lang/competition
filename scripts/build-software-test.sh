#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
output_dir="$project_root/sw/build"

mkdir -p "$output_dir"

build_image() {
  local name=$1
  shift
  "${compiler_prefix}gcc" \
    -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Os \
    -Wall -Wextra -Werror -fno-builtin -msmall-data-limit=0 \
    -I "$project_root/sw/bsp" -I "$project_root/sw/drivers" \
    -Wl,--build-id=none -Wl,--no-warn-rwx-segments \
    -Wl,-Map,"$output_dir/$name.map" -T "$project_root/sw/link.ld" \
    "$@" -o "$output_dir/$name.elf" \
    "$project_root/sw/start.S" \
    "$project_root/sw/drivers/accel_driver.c" \
    "$project_root/sw/tests/driver_test.c"
  "${compiler_prefix}objcopy" -O binary \
    "$output_dir/$name.elf" "$output_dir/$name.bin"
  od -An -v -tx4 -w4 "$output_dir/$name.bin" | sed 's/^ *//' > "$output_dir/$name.hex"
  test -s "$output_dir/$name.elf"
  test -s "$output_dir/$name.bin"
  test -s "$output_dir/$name.hex"
}

build_image driver_test
build_image driver_test_fail -DFORCE_FAILURE
echo "Built C validation images in $output_dir"
