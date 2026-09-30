param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out='generated/verification/hud-glyphs'
 New-Item -ItemType Directory -Force $out | Out-Null
 $common=@('sw/efinix_gpu/src/hud.c','sw/efinix_gpu/src/hud_cache.c',
  'sw/efinix_gpu/src/perf_demo.c','sw/efinix_gpu/src/assets.c','sw/efinix_gpu/src/sparse_pack.c',
  'sw/efinix_gpu/src/golden_renderer.c','sw/efinix_gpu/src/rgb565.c')
 $gpuSources=@('sw/efinix_gpu/src/hud_gpu_cache.c')
 foreach($test in @('hud_gpu_cache','hud_cache')) {
  $sources=@("sw/efinix_gpu/tests/test_$test.c")+$common
  if($test -eq 'hud_gpu_cache') { $sources+=$gpuSources }
  & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 @sources -o "$out/test_$test"
  if($LASTEXITCODE -ne 0) { throw "compile $test failed" }
  & wsl "./$out/test_$test"
  if($LASTEXITCODE -ne 0) { throw "$test failed" }
 }
} finally { Pop-Location }
