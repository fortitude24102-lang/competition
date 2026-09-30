param(
 [string]$HostGcc='gcc',
 [string]$Python='C:/efinity/efinity/python311/bin/python.exe',
 [string]$IcarusHome='D:/FPGA/iverilog'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out='generated/verification/bullet-demo'
 New-Item -ItemType Directory -Force $out | Out-Null
 $savedPythonHome=$env:PYTHONHOME
 if($Python -like '*/python311/bin/python.exe') { $env:PYTHONHOME=Split-Path (Split-Path $Python) }
 function Check([string]$name) { if($LASTEXITCODE -ne 0) {throw "$name failed ($LASTEXITCODE)"} }
 & $Python tools/test_build_bullet_assets.py
 Check 'asset generator tests'
 & $Python tools/test_collect_bullet_evidence.py
 Check 'evidence receipt tests'
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-D__USE_MINGW_ANSI_STDIO=1',
  '-Isw/efinix_gpu/include','-Isw/efinix_gpu/assets/v2','-Isw/efinix_gpu/assets/bullet')
 function Run-Test([string]$name,[string[]]$sources,[string[]]$extra=@()) {
  & $HostGcc @flags @extra @sources -o "$out/$name.exe"
  Check "compile $name"
  & "./$out/$name.exe"
  Check $name
 }
 Run-Test 'test_bullet_demo' @('sw/efinix_gpu/tests/test_bullet_demo.c','sw/efinix_gpu/src/bullet_demo.c')
 Run-Test 'test_bullet_gameplay' @('sw/efinix_gpu/tests/test_bullet_gameplay.c','sw/efinix_gpu/src/bullet_demo.c') | Tee-Object "$out/final-gameplay-boundaries.log"
 $mapped=@('-DGPU_TEST_BACKEND','-Isw/efinix_gpu/tests/host_compat',
  '-include','sw/efinix_gpu/tests/host_compat/host_addresses.h')
 $render=@('sw/efinix_gpu/src/perf_demo.c','sw/efinix_gpu/src/hud.c',
  'sw/efinix_gpu/src/assets.c','sw/efinix_gpu/src/sparse_pack.c',
  'sw/efinix_gpu/src/golden_renderer.c','sw/efinix_gpu/src/rgb565.c')
 Run-Test 'test_hud_cache' (@('sw/efinix_gpu/tests/test_hud_cache.c','sw/efinix_gpu/src/hud_cache.c')+$render) $mapped
 Run-Test 'test_bullet_pixels' (@('sw/efinix_gpu/tests/test_bullet_pixels.c',
  'sw/efinix_gpu/src/bullet_demo.c','sw/efinix_gpu/src/bullet_assets.c','sw/efinix_gpu/src/hud_cache.c')+$render) $mapped
 Run-Test 'test_perf_demo' (@('sw/efinix_gpu/tests/test_perf_demo.c')+$render) $mapped
 $pixel='board/efinix_ti60/rtl/pixel'
 $rtl=@("$pixel/gpu_pixel_copy.v","$pixel/gpu_pixel_fill.v","$pixel/gpu_pixel_color_key.v",
  "$pixel/gpu_pixel_alpha_blend.v","$pixel/gpu_pixel_pipe.v")
 & "$IcarusHome/bin/iverilog.exe" -g2012 "-I$pixel" -s tb_bullet_pixels -o "$out/bullet.vvp" @rtl tb/verilog/tb_bullet_pixels.sv
 Check 'compile bullet RTL simulation'
 & "$IcarusHome/bin/vvp.exe" "$out/bullet.vvp"
 Check 'bullet RTL simulation'
 & $Python tools/bullet_preview.py "$out/frame.rgb565" "$out/preview.png"
 Check 'encode preview'
 foreach($tick in @('000','090','110','180')) {
  & $Python tools/bullet_preview.py "$out/frame512_$tick.rgb565" "$out/preview512_$tick.png"
  Check "encode 512 preview $tick"
 }
 foreach($scenario in @('shield','game_over')) {
  & $Python tools/bullet_preview.py "$out/$scenario.rgb565" "$out/$scenario.png"
  Check "encode scenario $scenario"
 }
 Write-Output 'PASS bullet demo: host state/assets/pixels, legacy perf, unchanged RTL pixel replay'
} finally {
 $env:PYTHONHOME=$savedPythonHome
 Pop-Location
}
