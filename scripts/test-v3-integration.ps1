param([string]$IcarusRoot='C:/iverilog',[switch]$SoftwareOnly,[switch]$RtlOnly)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
 $out='generated/verification/v3/integration'
 New-Item -ItemType Directory -Force $out,'generated/verification/v3/game' | Out-Null
 function Check([string]$name) {if($LASTEXITCODE -ne 0){throw "$name failed ($LASTEXITCODE)"}}
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-fsanitize=undefined',
  '-ffunction-sections','-fdata-sections','-Wl,--gc-sections','-Isw/efinix_gpu/include')
 $cases=@(
  @{name='net_control';modules=@('net_control','asset_protocol');extra=@('-DNC_TEST_BACKEND')},
  @{name='input_state';modules=@('input_state')},
  @{name='r7_frozen';modules=@('bullet_demo')},
  @{name='interactive_game';modules=@('bullet_demo','interactive_game')},
  @{name='input_replay';modules=@('bullet_demo','interactive_game','replay_input')},
  @{name='interactive_pixels';modules=@('bullet_demo','interactive_game','replay_input','golden_renderer','rgb565')},
  @{name='v3_runtime';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input','input_state')},
  @{name='v3_hud';modules=@('hud')}
  @{name='v3_frame_stats';modules=@()},
  @{name='v3_capacity';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input');extra=@('-DBULLET_OBJECT_CAPACITY=1024')},
  @{name='submit_validation';modules=@();extra=@('-finstrument-functions','-DGPU_SUBMIT_REVALIDATE=0')}
  @{name='submit_shadow';modules=@('gpu','bullet_demo');extra=@('-DGPU_TEST_BACKEND','-DGPU_SUBMIT_SHADOW=1')}
 )
 if(!$RtlOnly) { foreach($test in $cases) {
  $sources=@("sw/efinix_gpu/tests/test_$($test.name).c")+@($test.modules|ForEach-Object {"sw/efinix_gpu/src/$_.c"})
  & wsl gcc @flags @($test.extra) @sources -o "$out/test_$($test.name)"
  Check "compile $($test.name)"
  & wsl "./$out/test_$($test.name)" | Tee-Object "$out/test_$($test.name).log"
  Check $test.name
 }
 & python sw/efinix_gpu/tests/test_control_gateway.py
 Check 'real UDP/HTTP gateway contracts'
 }
 if(!$SoftwareOnly) {
  $net=@(Get-ChildItem board/efinix_ti60/rtl/net/*.v | ForEach-Object FullName)
  $mac=@(Get-ChildItem board/efinix_ti60/vendor/ge_udp/rtl/heijin_test/mac -Filter *.v -Recurse | ForEach-Object FullName)
  $ErrorActionPreference='Continue' # Read-only vendor warnings are native stderr in PS5.
  & "$IcarusRoot/bin/iverilog.exe" -g2012 -s tb_v3_network_subsystem -o "$out/subsystem.vvp" tb/verilog/tb_v3_network_subsystem.sv @net board/efinix_ti60/rtl/display/pixel_async_fifo.v board/efinix_ti60/vendor/sapphire_ddr3/rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v @mac 2> "$out/subsystem-build.log"
  $ErrorActionPreference='Stop'
  Check 'owner subsystem elaboration'
  & "$IcarusRoot/bin/vvp.exe" "$out/subsystem.vvp" | Tee-Object "$out/subsystem.log"
  Check 'actual owner APB/MAC glue'
 }
 Write-Output "PASS requested V3 integration checks: SoftwareOnly=$SoftwareOnly RtlOnly=$RtlOnly. Not board qualification."
} finally {Pop-Location}
