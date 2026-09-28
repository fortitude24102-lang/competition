param(
 [ValidateSet('bullet','legacy')][string]$Demo='bullet',
 [string]$RiscvGcc='C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/par/ddr_demo_ti60/embedded_sw/soc',
 [ValidatePattern('^0x[0-9a-fA-F]{8}$')][string]$NetworkLocalIp='0xc0a80103',
 [ValidatePattern('^0x[0-9a-fA-F]{8}$')][string]$NetworkPeerIp='0xc0a80102'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $bsp="$Soc/bsp/efinix/EfxSapphireSoc"
 if(!(Test-Path "$bsp/linker/default.ld")) { throw "Official Sapphire BSP required: $Soc" }
 $out="generated/verification/bullet-demo/firmware-$Demo"
 New-Item -ItemType Directory -Force $out | Out-Null
 $sourceLine=Get-Content sw/efinix_gpu/Makefile | Where-Object {$_ -match '^SOURCES = '}
 $sources=@(($sourceLine -replace '^SOURCES = ','') -split '\s+' | ForEach-Object {"sw/efinix_gpu/$_"})
 $enabled=if($Demo -eq 'bullet'){1}else{0}
 & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections `
  "-DBULLET_DEMO_DEFAULT=$enabled" "-DNETWORK_LOCAL_IP=$NetworkLocalIp" "-DNETWORK_PEER_IP=$NetworkPeerIp" `
  -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet `
  -isystem "$bsp/include" -isystem "$Soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles `
  "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "-Wl,-Map,$out/gpu_demo.map" `
  "$Soc/software/standalone/common/start.S" @sources -o "$out/gpu_demo.elf"
 if($LASTEXITCODE -ne 0) {throw 'Firmware link failed'}
 $toolDir=Split-Path $RiscvGcc
 foreach($format in @(@('binary','bin'),@('ihex','hex'))) {
  & "$toolDir/riscv-none-elf-objcopy.exe" -O $format[0] "$out/gpu_demo.elf" "$out/gpu_demo.$($format[1])"
  if($LASTEXITCODE -ne 0) {throw 'Firmware conversion failed'}
 }
 & "$toolDir/riscv-none-elf-size.exe" "$out/gpu_demo.elf"
 if($LASTEXITCODE -ne 0) {throw 'Firmware size check failed'}
 Write-Output "PASS $Demo RV32 firmware build only; not board executed; release/ untouched"
} finally {Pop-Location}
