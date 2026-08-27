#!/usr/bin/env bash
set -euo pipefail

toolchain_root=/mnt/d/Chisel-environment/riscv-toolchain
package_cache=/mnt/d/Chisel-environment/cache/riscv-debs

mkdir -p "$toolchain_root" "$package_cache"
cd "$package_cache"

apt-get download gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf

for package in ./*.deb; do
    dpkg-deb -x "$package" "$toolchain_root"
done

"$toolchain_root/usr/bin/riscv64-unknown-elf-gcc" --version
