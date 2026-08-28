#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
resource_dir="$project_root/chisel/src/test/resources/rv32i"

"${compiler_prefix}gcc" \
  -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib \
  -Wl,--build-id=none -T "$resource_dir/link.ld" \
  -o "$resource_dir/smoke.elf" "$resource_dir/smoke.S"
"${compiler_prefix}objcopy" -O binary \
  "$resource_dir/smoke.elf" "$resource_dir/smoke.bin"

echo "Built $resource_dir/smoke.bin"
