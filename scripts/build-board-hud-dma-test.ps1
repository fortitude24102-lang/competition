param(
 [ValidateSet('hud','key','texture','texture-profile')][string]$Test='hud',
 [string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='D:/efinity_builds/competition_day1_20260906/sapphire/soc'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out=switch($Test) {
  'hud' {'generated/verification/board-hud-dma'}
  'key' {'generated/verification/board-key-burst'}
  'texture' {'generated/verification/board-texture-cache'}
  'texture-profile' {'generated/verification/board-texture-cache-profile'}
 }
 New-Item -ItemType Directory -Force $out | Out-Null
 $bsp="$Soc/bsp/efinix/EfxSapphireSoc"
 $sourceLine=Get-Content sw/efinix_gpu/Makefile | Where-Object { $_ -match '^SOURCES = ' }
 $sources=@(($sourceLine -replace '^SOURCES = ','') -split '\s+' |
  Where-Object { $_ -ne 'src/main.c' } | ForEach-Object { "sw/efinix_gpu/$_" })
 $sources+=switch($Test) {
  'hud' {'sw/efinix_gpu/tests/test_board_hud_dma.c'}
  'key' {'sw/efinix_gpu/tests/test_board_key_burst.c'}
  'texture' {'sw/efinix_gpu/tests/test_board_texture_cache.c'}
  'texture-profile' {'sw/efinix_gpu/tests/test_board_texture_cache_profile.c'}
 }
 & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -DBULLET_DEMO_DEFAULT=1 -DNETWORK_LOCAL_IP=0xc0a80103 -DNETWORK_PEER_IP=0xc0a80102 -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet -isystem "$bsp/include" -isystem "$Soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "$Soc/software/standalone/common/start.S" @sources -o "$out/test.elf"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test link failed" }
 $objcopy=Join-Path (Split-Path $RiscvGcc) riscv-none-elf-objcopy.exe
 & $objcopy -O binary "$out/test.elf" "$out/test.bin"
 if($LASTEXITCODE -ne 0) { throw "Board $Test test objcopy failed" }
 Write-Output "Built $out/test.bin; load at 0x1000 via JTAG. Does not program hardware."
} finally { Pop-Location }
