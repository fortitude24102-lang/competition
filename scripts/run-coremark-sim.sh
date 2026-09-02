#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-$project_root/sw/build/coremark_smoke.hex}
simulation_dir="$project_root/generated/coremark-sim"

if [[ ! -s "$image" ]]; then
  echo "CoreMark RAM image is missing or empty: $image" >&2
  exit 2
fi

export JAVA_HOME=/mnt/d/Chisel-environment/wsl/java17-root/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export COURSIER_CACHE=/mnt/d/Chisel-environment/cache/coursier
export CHISEL_FIRTOOL_CACHE=/mnt/d/Chisel-environment/wsl/firtool-cache
export SBT_OPTS="-Dsbt.boot.directory=/mnt/d/Chisel-environment/cache/sbt/boot-wsl -Dsbt.global.base=/mnt/d/Chisel-environment/cache/sbt/global-wsl -Dsbt.ivy.home=/mnt/d/Chisel-environment/cache/ivy-wsl"

rm -rf "$simulation_dir"
mkdir -p "$simulation_dir"

cd "$project_root/chisel"
bash /mnt/d/Chisel-environment/sbt/bin/sbt \
  "runMain Generate soc-image $image --target-dir ../generated/coremark-sim"

cd "$project_root"
echo "SIM_VERILATOR_VERSION=$(verilator --version)"
verilator --cc --exe --build --timing --Wno-fatal \
  --top-module SoCTop \
  -Mdir "$simulation_dir/obj_dir" \
  -o coremark_sim \
  -CFLAGS "-std=c++17 -O2" \
  "$simulation_dir"/*.sv \
  "$project_root/rtl/video/VideoAccelTop.v" \
  "$project_root/tb/coremark_sim.cpp"

"$simulation_dir/obj_dir/coremark_sim"
