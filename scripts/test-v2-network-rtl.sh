#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=generated/verification/v2-network-rtl
mkdir -p "$out"
verilator --binary --timing -j 4 -Wno-fatal --top-module tb_asset_udp_rx \
 --Mdir "$out/parser" -o run tb/verilog/tb_asset_udp_rx.sv \
 board/efinix_ti60/rtl/net/asset_udp_rx.v >"$out/parser-build.log" 2>&1
"$out/parser/run" | tee "$out/parser-result.log"
mapfile -t mac < <(find board/efinix_ti60/vendor/ge_udp/rtl/heijin_test/mac -name '*.v')
verilator --binary --timing -j 4 -Wno-fatal --top-module tb_asset_network \
 --Mdir "$out/mac" -o run tb/verilog/tb_asset_network.sv \
 board/efinix_ti60/rtl/net/*.v board/efinix_ti60/rtl/display/pixel_async_fifo.v \
 board/efinix_ti60/vendor/sapphire_ddr3/rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v \
 "${mac[@]}" >"$out/build.log" 2>&1
"$out/mac/run" | tee "$out/result.log"
