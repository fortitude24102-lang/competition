#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT

verilator --binary --timing --timescale 1ns/1ps --top-module tb_video_accel_top \
  --Mdir "$build_dir/obj_dir" -o video_accel_tb \
  "$project_root/rtl/video/VideoAccelTop.v" \
  "$project_root/tb/tb_video_accel_top.sv"
"$build_dir/obj_dir/video_accel_tb"
