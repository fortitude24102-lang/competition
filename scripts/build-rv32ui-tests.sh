#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_root=${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}
tests_root=${RISCV_TESTS_HOME:-/mnt/d/Chisel-environment/riscv-tests}
build_dir=${RISCV_TESTS_BUILD:-/mnt/d/Chisel-environment/riscv-tests-build/rv32ui}
compiler_prefix="$toolchain_root/usr/bin/riscv64-unknown-elf-"
adapter_dir="$project_root/chisel/src/test/resources/rv32ui-env"
expected_commit=riscv-tests=2ebecad997fa58cd9e5724340ba75aa4b59bd1d0
expected_isa_digest=02edf74107518fa84c63c5a1547e3aa7272f558229b4814b90e6d653f292b7be

if ! grep -qx "$expected_commit" "$tests_root/.source-commit"; then
  echo "Unexpected or unverified riscv-tests source under $tests_root" >&2
  exit 1
fi

actual_isa_digest=$(cd "$tests_root" && find isa -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
if [[ "$actual_isa_digest" != "$expected_isa_digest" ]]; then
  echo "riscv-tests ISA source digest does not match the pinned snapshot" >&2
  exit 1
fi

tests=(
  add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
  lb lbu lh lhu lui lw or ori sb sh sll slli slt slti sltiu sltu
  sra srai srl srli sub sw xor xori
)

mkdir -p "$build_dir"
for test_name in "${tests[@]}"; do
  source_file="$tests_root/isa/rv32ui/$test_name.S"
  output_elf="$build_dir/$test_name.elf"
  "${compiler_prefix}gcc" \
    -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -nostartfiles -static \
    -Wl,--build-id=none -T "$adapter_dir/link.ld" \
    -I "$adapter_dir" -I "$tests_root/isa/macros/scalar" \
    -o "$output_elf" "$source_file"
  "${compiler_prefix}objcopy" -O binary "$output_elf" "$build_dir/$test_name.bin"
done

echo "Built ${#tests[@]} upstream rv32ui binaries in $build_dir"
