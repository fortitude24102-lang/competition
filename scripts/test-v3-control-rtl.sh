#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=generated/verification/v3/control-rtl
mkdir -p "$out"
mapfile -t mac < <(find board/efinix_ti60/vendor/ge_udp/rtl/heijin_test/mac -name '*.v')
for top in tb_net_async_mailbox tb_net_control tb_net_control_arbiter tb_net_control_mac; do
  verilator --binary --timing -j 4 -Wno-fatal --top-module "$top" \
    --Mdir "$out/$top" -o run "tb/verilog/$top.sv" \
    board/efinix_ti60/rtl/net/*.v board/efinix_ti60/rtl/display/pixel_async_fifo.v \
    board/efinix_ti60/vendor/sapphire_ddr3/rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v \
    "${mac[@]}" >"$out/$top-build.log" 2>&1
  "$out/$top/run" | tee "$out/$top-result.log"
done
# Original resource suite runs once per invocation; use --scoped for later
# edits confined to the new control modules after a successful legacy run.
if [[ "${1:-}" != --scoped ]]; then
  bash scripts/test-v2-network-rtl.sh | tee "$out/legacy-result.log"
fi
