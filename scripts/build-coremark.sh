#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
output_dir="$project_root/sw/build"
iterations=${1:-1}
name=${2:-coremark_smoke}

if ! [[ "$iterations" =~ ^[1-9][0-9]*$ ]]; then
  echo "Iterations must be a positive integer" >&2
  exit 2
fi

mkdir -p "$output_dir"

"${compiler_prefix}gcc" \
  -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib \
  -Wall -Wextra -Werror -fno-builtin -msmall-data-limit=0 \
  -I "$project_root/third_party/coremark" \
  -I "$project_root/sw/coremark" \
  -I "$project_root/sw/bsp" \
  -DITERATIONS="$iterations" -DPERFORMANCE_RUN=1 -DTOTAL_DATA_SIZE=2000 \
  -Wl,--build-id=none -Wl,--no-warn-rwx-segments \
  -Wl,-Map,"$output_dir/$name.map" -T "$project_root/sw/link.ld" \
  -o "$output_dir/$name.elf" \
  "$project_root/sw/start.S" \
  "$project_root/sw/bsp/uart.c" \
  "$project_root/sw/coremark/core_portme.c" \
  "$project_root/third_party/coremark/core_list_join.c" \
  "$project_root/third_party/coremark/core_main.c" \
  "$project_root/third_party/coremark/core_matrix.c" \
  "$project_root/third_party/coremark/core_state.c" \
  "$project_root/third_party/coremark/core_util.c" \
  -lgcc

"${compiler_prefix}objcopy" -O binary \
  "$output_dir/$name.elf" "$output_dir/$name.bin"
od -An -v -tx4 -w4 "$output_dir/$name.bin" | sed 's/^ *//' > "$output_dir/$name.hex"

image_size=$(stat -c '%s' "$output_dir/$name.bin")
if ((image_size > 65536)); then
  echo "CoreMark image is $image_size bytes, exceeding the 64 KiB SoC RAM" >&2
  exit 1
fi

"${compiler_prefix}size" "$output_dir/$name.elf"
echo "Built $output_dir/$name.hex ($image_size bytes, $iterations iterations)"
