param(
 [ValidateSet('hud','key','texture','texture-profile','hud-glyphs','hud-glyph-sweep','render-phases','copy-stream','damage-cost','damage-sweep','damage-plan','damage-lower','instances')][string]$Test='hud',
 [string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='D:/efinity_builds/competition_day1_20260906/sapphire/soc',
 [switch]$InstanceExpandProbe,
 [switch]$ValidationCohort,
 [switch]$ValidateOnce,
 [switch]$LegacyValidation,
 [string]$OutDirectory
)
$ErrorActionPreference='Stop'
if($InstanceExpandProbe -and $Test -ne 'instances') { throw 'InstanceExpandProbe requires Test instances' }
if($ValidateOnce -and $LegacyValidation) {throw 'Choose one submission path'}
if(($ValidationCohort -or $ValidateOnce -or $LegacyValidation) -and ($Test -ne 'render-phases' -or !$OutDirectory)) {throw 'Validation comparison requires render-phases and fresh OutDirectory'}
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out=switch($Test) {
  'hud' {'generated/verification/board-hud-dma'}
  'key' {'generated/verification/board-key-burst'}
  'texture' {'generated/verification/board-texture-cache'}
  'texture-profile' {'generated/verification/board-texture-cache-profile'}
  'hud-glyphs' {'generated/verification/board-hud-glyphs'}
  'hud-glyph-sweep' {'generated/verification/board-hud-glyph-sweep'}
  'render-phases' {'generated/verification/board-render-phases'}
  'copy-stream' {'generated/verification/board-copy-stream'}
  'damage-cost' {'generated/verification/board-damage-cost'}
  'damage-sweep' {'generated/verification/board-damage-sweep'}
  'damage-plan' {'generated/verification/board-damage-plan'}
  'damage-lower' {'generated/verification/board-damage-lower'}
  'instances' {'generated/verification/v3/instances/board'}
 }
 if($InstanceExpandProbe) { $out+='-expand-probe' }
 if($OutDirectory) {
  $out=$OutDirectory
  if(Test-Path -LiteralPath $out) {throw 'Refusing to overwrite diagnostic output'}
 }
 New-Item -ItemType Directory -Force $out | Out-Null
 if($Test -eq 'render-phases') {
  & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -Isw/efinix_gpu/include sw/efinix_gpu/tests/test_submit_probe.c -o "$out/test_submit_probe"
  if($LASTEXITCODE -ne 0) { throw 'Diagnostic submit probe host compile failed' }
  & wsl "./$out/test_submit_probe"
  if($LASTEXITCODE -ne 0) { throw 'Diagnostic submit probe host checks failed' }
 }
 $bsp="$Soc/bsp/efinix/EfxSapphireSoc"
 $sourceLine=Get-Content sw/efinix_gpu/Makefile | Where-Object { $_ -match '^SOURCES = ' }
 $sources=@(($sourceLine -replace '^SOURCES = ','') -split '\s+' |
  Where-Object { $_ -ne 'src/main.c' -and !($Test -eq 'render-phases' -and $_ -eq 'src/gpu.c') } | ForEach-Object { "sw/efinix_gpu/$_" })
 $sources+=switch($Test) {
  'hud' {'sw/efinix_gpu/tests/test_board_hud_dma.c'}
  'key' {'sw/efinix_gpu/tests/test_board_key_burst.c'}
  'texture' {'sw/efinix_gpu/tests/test_board_texture_cache.c'}
  'texture-profile' {'sw/efinix_gpu/tests/test_board_texture_cache_profile.c'}
  'hud-glyphs' {'sw/efinix_gpu/tests/test_board_hud_glyphs.c'}
  'hud-glyph-sweep' {'sw/efinix_gpu/tests/test_board_hud_glyph_sweep.c'}
  'render-phases' {'sw/efinix_gpu/tests/test_board_render_phases.c'}
  'copy-stream' {'sw/efinix_gpu/tests/test_board_copy_stream.c'}
  'damage-cost' {'sw/efinix_gpu/tests/test_board_damage_cost.c'}
  'damage-sweep' {'sw/efinix_gpu/tests/test_board_damage_sweep.c'}
  'damage-plan' {'sw/efinix_gpu/tests/test_board_damage_plan.c'}
  'damage-lower' {'sw/efinix_gpu/tests/test_board_damage_lower.c'}
  'instances' {'sw/efinix_gpu/tests/test_board_instances.c';'sw/efinix_gpu/src/gpu_instances.c'}
 }
 [string[]]$probeFlags=@()
 if($InstanceExpandProbe) { $probeFlags=@('-DINSTANCE_EXPAND_PROBE=1') }
 if($ValidationCohort) {$probeFlags+='-DRENDER_VALIDATION_COHORT=1'}
 if($ValidateOnce) {$probeFlags+='-DGPU_SUBMIT_REVALIDATE=0'}
 if($LegacyValidation) {$probeFlags+='-DGPU_SUBMIT_REVALIDATE=1'}
 & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -DBULLET_DEMO_DEFAULT=1 -DNETWORK_LOCAL_IP=0xc0a80103 -DNETWORK_PEER_IP=0xc0a80102 -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet -isystem "$bsp/include" -isystem "$Soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "$Soc/software/standalone/common/start.S" @probeFlags @sources -o "$out/test.elf"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test link failed" }
 $objcopy=Join-Path (Split-Path $RiscvGcc) riscv-none-elf-objcopy.exe
 & $objcopy -O binary "$out/test.elf" "$out/test.bin"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test objcopy failed" }
 Write-Output "Built $out/test.bin; load at 0x1000 via JTAG. Does not program hardware."
} finally { Pop-Location }
