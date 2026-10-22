param(
 [ValidateSet('hud','key','key-trim','texture','texture-profile','hud-glyphs','hud-glyph-sweep','render-phases','qos-sweep','live-phases','copy-stream','damage-cost','damage-sweep','damage-plan','damage-lower','instances','replay-crc','frame-list','stripes','sprite-phases','axi-phases','dashboard-metrics','transform','zoom','alpha-pipeline','performance-trace')][string]$Test='hud',
 [string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='D:/efinity_builds/competition_day1_20260906/sapphire/soc',
 [switch]$InstanceExpandProbe,
 [switch]$ValidationCohort,
 [switch]$ValidateOnce,
 [switch]$LegacyValidation,
 [switch]$ShadowSubmit,
 [switch]$FullSubmit,
 [switch]$WideCopyAligned,
 [ValidateSet(256,512)][int]$LiveTarget=512,
 [switch]$LiveControl,
 [switch]$LiveSplit,
 [string]$OutDirectory
)
$ErrorActionPreference='Stop'
if($Test -eq 'axi-phases' -and !$OutDirectory) {throw 'AXI phase diagnostic requires fresh OutDirectory'}
if($WideCopyAligned -and ($Test -ne 'copy-stream' -or !$OutDirectory)){throw 'WideCopyAligned requires copy-stream and fresh OutDirectory'}
if($Test -eq 'performance-trace' -and !$OutDirectory) {throw 'Performance trace requires fresh OutDirectory'}
if($Test -eq 'live-phases' -and !$OutDirectory) {throw 'Live phase diagnostic requires fresh OutDirectory'}
if(($LiveControl -or $LiveSplit) -and $Test -ne 'live-phases') {throw 'Live options require live-phases'}
if($LiveControl -and $LiveSplit) {throw 'Split requires timing instrumentation'}
if($InstanceExpandProbe -and $Test -ne 'instances') { throw 'InstanceExpandProbe requires Test instances' }
if($ValidateOnce -and $LegacyValidation) {throw 'Choose one submission path'}
if(($ValidationCohort -or $ValidateOnce -or $LegacyValidation) -and ($Test -ne 'render-phases' -or !$OutDirectory)) {throw 'Validation comparison requires render-phases and fresh OutDirectory'}
if($ShadowSubmit -and ($Test -ne 'render-phases' -or !$OutDirectory)) {throw 'Shadow submit requires render-phases and fresh OutDirectory'}
if($FullSubmit -and ($Test -ne 'render-phases' -or !$OutDirectory)) {throw 'Full submit requires render-phases and fresh OutDirectory'}
if($ShadowSubmit -and $FullSubmit) {throw 'Choose one command-write path'}
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out=switch($Test) {
  'hud' {'generated/verification/board-hud-dma'}
  'key' {'generated/verification/board-key-burst'}
  'key-trim' {'generated/verification/v3/dual-track-20261018/board-key-trim-'+[Guid]::NewGuid().ToString('N')}
  'texture' {'generated/verification/board-texture-cache'}
  'texture-profile' {'generated/verification/board-texture-cache-profile'}
  'hud-glyphs' {'generated/verification/board-hud-glyphs'}
  'hud-glyph-sweep' {'generated/verification/board-hud-glyph-sweep'}
  'render-phases' {'generated/verification/board-render-phases'}
  'qos-sweep' {'generated/verification/v3/qos-sweep/board'}
  'live-phases' {'generated/verification/v3/live-phases/board'}
  'copy-stream' {'generated/verification/board-copy-stream'}
  'damage-cost' {'generated/verification/board-damage-cost'}
  'damage-sweep' {'generated/verification/board-damage-sweep'}
  'damage-plan' {'generated/verification/board-damage-plan'}
  'damage-lower' {'generated/verification/board-damage-lower'}
  'instances' {'generated/verification/v3/instances/board'}
  'replay-crc' {'generated/verification/v3/replay-crc/board'}
  'frame-list' {'generated/verification/v3/frame-list/board'}
  'stripes' {'generated/verification/v3/rows-stripes-20261016/board'}
  'sprite-phases' {'generated/verification/v3/sprite-phases-20261016/board'}
  'axi-phases' {'generated/verification/v3/axi-diagnostics-20261019/board'}
  'dashboard-metrics' {'generated/verification/v3/dashboard-comparison-20261017/board'}
  'transform' {'generated/verification/v3/dual-track-20261018/board-transform'}
  'alpha-pipeline' {'generated/verification/v3/alpha-gray-20261019/board-alpha-'+[Guid]::NewGuid().ToString('N')}
  'zoom' {'generated/verification/v3/dual-track-20261018/board-zoom-'+[Guid]::NewGuid().ToString('N')}
 }
 if($InstanceExpandProbe) { $out+='-expand-probe' }
 if($OutDirectory) {
  $out=$OutDirectory
  if(Test-Path -LiteralPath $out) {throw 'Refusing to overwrite diagnostic output'}
 }
 New-Item -ItemType Directory -Force $out | Out-Null
 if($Test -eq 'zoom') {
  & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -DZOOM_HOST_TEST -Isw/efinix_gpu/include sw/efinix_gpu/tests/test_board_zoom.c -o "$out/test_zoom_text"
  if($LASTEXITCODE -ne 0) { throw 'Zoom glyph host compile failed' }
  & wsl "./$out/test_zoom_text"
  if($LASTEXITCODE -ne 0) { throw 'Zoom glyph host checks failed' }
 }
 if($Test -in @('render-phases','qos-sweep')) {
  & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined -Isw/efinix_gpu/include sw/efinix_gpu/tests/test_submit_probe.c -o "$out/test_submit_probe"
  if($LASTEXITCODE -ne 0) { throw 'Diagnostic submit probe host compile failed' }
  & wsl "./$out/test_submit_probe"
  if($LASTEXITCODE -ne 0) { throw 'Diagnostic submit probe host checks failed' }
 }
 $bsp="$Soc/bsp/efinix/EfxSapphireSoc"
 $sourceLine=Get-Content sw/efinix_gpu/Makefile | Where-Object { $_ -match '^SOURCES = ' }
 $sources=@(($sourceLine -replace '^SOURCES = ','') -split '\s+' |
  Where-Object { $_ -ne 'src/main.c' -and !($Test -in @('render-phases','qos-sweep') -and $_ -eq 'src/gpu.c') } | ForEach-Object { "sw/efinix_gpu/$_" })
 if($Test -in @('live-phases','performance-trace')) {$sources=@($sources | Where-Object {$_ -ne 'sw/efinix_gpu/src/v3_demo.c'})}
 if($Test -eq 'replay-crc') {$sources=@($sources | Where-Object {$_ -ne 'sw/efinix_gpu/src/replay_input.c'})}
 if($Test -eq 'zoom') {$sources+='sw/efinix_gpu/src/zoom_control.c'}
 $sources+=switch($Test) {
  'hud' {'sw/efinix_gpu/tests/test_board_hud_dma.c'}
  'key' {'sw/efinix_gpu/tests/test_board_key_burst.c'}
  'key-trim' {'sw/efinix_gpu/tests/test_board_key_trim.c'}
  'texture' {'sw/efinix_gpu/tests/test_board_texture_cache.c'}
  'texture-profile' {'sw/efinix_gpu/tests/test_board_texture_cache_profile.c'}
  'hud-glyphs' {'sw/efinix_gpu/tests/test_board_hud_glyphs.c'}
  'hud-glyph-sweep' {'sw/efinix_gpu/tests/test_board_hud_glyph_sweep.c'}
  'render-phases' {'sw/efinix_gpu/tests/test_board_render_phases.c'}
  'qos-sweep' {'sw/efinix_gpu/tests/test_board_render_phases.c'}
  'live-phases' {'sw/efinix_gpu/tests/test_board_live_phases.c'}
  'copy-stream' {'sw/efinix_gpu/tests/test_board_copy_stream.c'}
  'damage-cost' {'sw/efinix_gpu/tests/test_board_damage_cost.c'}
  'damage-sweep' {'sw/efinix_gpu/tests/test_board_damage_sweep.c'}
  'damage-plan' {'sw/efinix_gpu/tests/test_board_damage_plan.c'}
  'damage-lower' {'sw/efinix_gpu/tests/test_board_damage_lower.c'}
  'instances' {'sw/efinix_gpu/tests/test_board_instances.c'}
  'replay-crc' {'sw/efinix_gpu/tests/test_board_replay_crc.c'}
  'frame-list' {'sw/efinix_gpu/tests/test_board_frame_list.c'}
  'stripes' {'sw/efinix_gpu/tests/test_board_stripes.c'}
  'sprite-phases' {'sw/efinix_gpu/tests/test_board_sprite_phases.c'}
  'axi-phases' {'sw/efinix_gpu/tests/test_board_sprite_phases.c'}
  'dashboard-metrics' {'sw/efinix_gpu/tests/test_board_dashboard_metrics.c'}
  'transform' {'sw/efinix_gpu/tests/test_board_transform.c'}
  'alpha-pipeline' {'sw/efinix_gpu/tests/test_board_alpha_pipeline.c'}
  'performance-trace' {'sw/efinix_gpu/tests/test_board_performance_trace.c'}
  'zoom' {'sw/efinix_gpu/tests/test_board_zoom.c'}
 }
 [string[]]$probeFlags=@()
 if($WideCopyAligned){$probeFlags+=@('-DCOPY_BOARD_SOURCE_BASE=0x02400ff0u','-DCOPY_BOARD_DEST_BASE=0x02600fe0u')}
 if($InstanceExpandProbe) { $probeFlags=@('-DINSTANCE_EXPAND_PROBE=1') }
 if($ValidationCohort) {$probeFlags+='-DRENDER_VALIDATION_COHORT=1'}
 if($Test -eq 'qos-sweep') {$probeFlags+=@('-DRENDER_VALIDATION_COHORT=1','-DRENDER_QOS_SWEEP=1')}
 if($ValidateOnce) {$probeFlags+='-DGPU_SUBMIT_REVALIDATE=0'}
 if($LegacyValidation) {$probeFlags+='-DGPU_SUBMIT_REVALIDATE=1'}
 if($ShadowSubmit) {$probeFlags+='-DGPU_SUBMIT_SHADOW=1'}
 if($FullSubmit) {$probeFlags+='-DGPU_SUBMIT_SHADOW=0'}
 if($Test -eq 'axi-phases') {$probeFlags+='-DGPU_AXI_DIAGNOSTICS=1'}
 if($Test -eq 'performance-trace') {
  $probeFlags+=@('-DV3_INTERACTIVE=1','-DV3_COPY_AHEAD=1','-DV3_LOGIC_COPY=1',
   '-DV3_FRAME_LIST=1','-DV3_PERFORMANCE_CHALLENGE=1','-DV3_HUD_DIRECT=1',
   '-DREPLAY_CRC_NIBBLE=1','-DV3_REPLAY_SEAL_BUDGET=1','-DBULLET_OBJECT_CAPACITY=1024')
 }
 if($Test -eq 'live-phases') {
  $probeFlags+="-DV3_START_COUNT=$LiveTarget"
  $probeFlags+=('-DLIVE_PHASE_TIMING='+[int](!$LiveControl))
  $probeFlags+=('-DLIVE_PHASE_SPLIT='+[int]($LiveSplit.IsPresent))
 }
 & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -DBULLET_DEMO_DEFAULT=1 -DNETWORK_LOCAL_IP=0xc0a80103 -DNETWORK_PEER_IP=0xc0a80102 -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet -isystem "$bsp/include" -isystem "$Soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "$Soc/software/standalone/common/start.S" @probeFlags @sources -o "$out/test.elf"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test link failed" }
 $objcopy=Join-Path (Split-Path $RiscvGcc) riscv-none-elf-objcopy.exe
 & $objcopy -O binary "$out/test.elf" "$out/test.bin"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test objcopy failed" }
 Write-Output "Built $out/test.bin; load at 0x1000 via JTAG. Does not program hardware."
} finally { Pop-Location }
