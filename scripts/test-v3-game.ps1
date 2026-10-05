param(
 [string]$HostGcc='D:/aaa/mingw64/bin/gcc.exe',
 [string]$Python='C:/efinity/efinity/python311/bin/python.exe',
 [string]$IcarusHome='D:/FPGA/iverilog',
 [string]$RiscvGcc='C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe'
)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedPythonHome=$env:PYTHONHOME
try {
 $out='generated/verification/v3/game'
 New-Item -ItemType Directory -Force $out | Out-Null
 if($Python -like '*/python311/bin/python.exe') { $env:PYTHONHOME=Split-Path (Split-Path $Python) }
 function Check([string]$name) { if($LASTEXITCODE -ne 0) { throw "$name failed ($LASTEXITCODE)" } }
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-pedantic',
  '-D__USE_MINGW_ANSI_STDIO=1','-Isw/efinix_gpu/include')
 function Run-Test([string]$name,[string[]]$modules,[string[]]$extra=@()) {
  $sources=@("sw/efinix_gpu/tests/$name.c")+@($modules | ForEach-Object { "sw/efinix_gpu/src/$_.c" })
  & $HostGcc @flags @extra @sources -o "$out/$name.exe"
  Check "compile $name"
  & "./$out/$name.exe" | Tee-Object "$out/$name.log"
  Check $name
 }
 Run-Test 'test_net_control' @('net_control','asset_protocol') @('-DNC_TEST_BACKEND')
 Run-Test 'test_input_state' @('input_state')
 Run-Test 'test_r7_frozen' @('bullet_demo')
 Run-Test 'test_interactive_game' @('bullet_demo','interactive_game')
 Run-Test 'test_input_replay' @('bullet_demo','interactive_game','replay_input')
 Run-Test 'test_interactive_pixels' @('bullet_demo','interactive_game','replay_input','golden_renderer','rgb565')
 & $Python sw/efinix_gpu/tests/test_interactive_assets.py
 Check 'interactive asset manifest'
 & $HostGcc @flags sw/efinix_gpu/tools/asset_server/asset_server.c sw/efinix_gpu/src/asset_protocol.c sw/efinix_gpu/src/net_asset_server.c -lws2_32 -o "$out/asset_server.exe"
 Check 'compile unchanged asset server'
 $savedAssetDir=$env:ASSET_SERVER_TEST_DIRECTORY
 try {
  $env:ASSET_SERVER_TEST_DIRECTORY='sw/efinix_gpu/assets/interactive'
  & $Python sw/efinix_gpu/tests/test_asset_server_udp.py "$out/asset_server.exe"
  Check 'interactive resources via unchanged ASST server'
 } finally { $env:ASSET_SERVER_TEST_DIRECTORY=$savedAssetDir }
 $pixel='board/efinix_ti60/rtl/pixel'
 $rtl=@("$pixel/gpu_pixel_copy.v","$pixel/gpu_pixel_fill.v","$pixel/gpu_pixel_color_key.v",
  "$pixel/gpu_pixel_alpha_blend.v","$pixel/gpu_pixel_pipe.v")
 & "$IcarusHome/bin/iverilog.exe" -g2012 "-I$pixel" -s tb_interactive_pixels -o "$out/interactive.vvp" @rtl tb/verilog/tb_interactive_pixels.sv
 Check 'compile interactive RTL pixel replay'
 & "$IcarusHome/bin/vvp.exe" "$out/interactive.vvp" | Tee-Object "$out/rtl-pixels.log"
 Check 'interactive RTL pixel replay'
 & $Python tools/bullet_preview.py "$out/interactive_live.rgb565" "$out/preview.png"
 Check 'encode interactive preview'
 foreach($module in @('net_control','input_state','bullet_demo','interactive_game','replay_input')) {
  & $RiscvGcc -std=c11 -Os -march=rv32imac -mabi=ilp32 -Wall -Wextra -Werror -Wstack-usage=2048 -fstack-usage -Isw/efinix_gpu/include -c "sw/efinix_gpu/src/$module.c" -o "$out/$module.rv32.o"
  Check "compile RV32 production $module"
 }
 & (Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-size.exe') "$out/net_control.rv32.o" "$out/input_state.rv32.o" "$out/bullet_demo.rv32.o" "$out/interactive_game.rv32.o" "$out/replay_input.rv32.o" | Tee-Object "$out/rv32-size.log"
 Check 'RV32 object size'
 Write-Output 'PASS V3 B standalone: driver/input, frozen R7, interactive gameplay, 600-tick replay, assets, CPU/oracle pixels, unchanged pixel RTL, RV32 production objects'
 Write-Output 'Not tested: main/adapter integration, linked board BSS/stack, board input latency or sustained FPS.'
} finally {
 $env:PYTHONHOME=$savedPythonHome
 Pop-Location
}
