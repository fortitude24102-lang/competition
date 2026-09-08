#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
vendor="$project_root/board/efinix_ti60/vendor"
(cd "$vendor" && sha256sum --check --quiet manifest.sha256)
echo 'PASS vendor manifest'
rtl="$project_root/board/efinix_ti60/rtl/display"
encoder="$vendor/hdmi_tx/rtl/hdmi_src/dvi_tx"
for name in rgb565_to_rgb888 hdmi_tx_adapter; do
  sources=("$rtl/$name.v" "$project_root/tb/verilog/tb_$name.sv")
  if [[ "$name" == hdmi_tx_adapter ]]; then
    # Suppress only upstream width truncation and bit-chain UNOPTFLAT warnings.
    # The q_m chain is feed-forward by bit, not an actual combinational loop.
    printf '`verilator_config\nlint_off -rule WIDTH -file "%s"\nlint_off -rule UNOPTFLAT -file "%s"\n' \
      "$encoder/encode.v" "$encoder/encode.v" >"$build_dir/vendor.vlt"
    sources=("$build_dir/vendor.vlt" "${sources[@]}")
    sources+=("$encoder/dvi_encoder.v" "$encoder/encode.v")
  fi
  verilator --binary --timing --top-module "tb_$name" \
    --Mdir "$build_dir/$name" -o run "${sources[@]}" >"$build_dir/$name.log" 2>&1 || {
      cat "$build_dir/$name.log"; exit 1;
    }
  "$build_dir/$name/run"
done

pixel="$project_root/board/efinix_ti60/rtl/pixel"
# Production self-written Verilog keeps exactly one module in each source.
while IFS= read -r source; do
  count=$(grep -Ec '^[[:space:]]*module[[:space:]]' "$source" || true)
  [[ "$count" == 1 ]] || { echo "FAIL module structure: $source ($count modules)"; exit 1; }
done < <(find "$project_root/board/efinix_ti60/rtl" -name '*.v' -type f)
echo 'PASS self-written Verilog module structure'
verilator --binary --timing --top-module tb_gpu_pixel_pipe \
  -I"$pixel" --Mdir "$build_dir/pixel" -o run \
  "$pixel/gpu_pixel_copy.v" "$pixel/gpu_pixel_fill.v" "$pixel/gpu_pixel_pipe.v" \
  "$project_root/tb/verilog/tb_gpu_pixel_pipe.sv" >"$build_dir/pixel.log" 2>&1 || {
    cat "$build_dir/pixel.log"; exit 1;
  }
"$build_dir/pixel/run"
