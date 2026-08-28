#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export JAVA_HOME=/mnt/d/Chisel-environment/wsl/java17-root/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export COURSIER_CACHE=/mnt/d/Chisel-environment/cache/coursier
export CHISEL_FIRTOOL_CACHE=/mnt/d/Chisel-environment/wsl/firtool-cache
export SBT_OPTS="-Dsbt.boot.directory=/mnt/d/Chisel-environment/cache/sbt/boot-wsl -Dsbt.global.base=/mnt/d/Chisel-environment/cache/sbt/global-wsl -Dsbt.ivy.home=/mnt/d/Chisel-environment/cache/ivy-wsl"

cd "$project_root/chisel"
bash /mnt/d/Chisel-environment/sbt/bin/sbt "runMain Generate soc --target-dir ../generated"
