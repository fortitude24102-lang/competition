#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
resource_dir="$project_root/chisel/src/test/resources/soc"

"${compiler_prefix}gcc" \
  -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib \
  -Wl,--build-id=none -T "$resource_dir/link.ld" \
  -o "$resource_dir/smoke.elf" "$resource_dir/smoke.S"
"${compiler_prefix}objcopy" -O binary \
  "$resource_dir/smoke.elf" "$resource_dir/smoke.bin"
od -An -v -tx4 -w4 "$resource_dir/smoke.bin" | sed 's/^ *//' > "$resource_dir/smoke.hex"

echo "Built $resource_dir/smoke.hex"
