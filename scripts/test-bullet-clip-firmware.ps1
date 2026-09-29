param(
 [string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='D:/efinity_builds/competition_day1_20260906/sapphire/soc'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
$normalBuilt=$false
try {
 $out='generated/verification/bullet-demo/clip-entry'
 New-Item -ItemType Directory -Force $out | Out-Null
 foreach($case in @('normal','profile')) {
  $options=@{FirmwareOnly=$true;Demo='bullet';RiscvGcc=$RiscvGcc;Soc=$Soc;
   NetworkLocalIp='0xc0a80103';NetworkPeerIp='0xc0a80102'}
  if($case -eq 'profile') { $options.Profile=$true }
  & ./scripts/test-efinix-software.ps1 @options
  if($LASTEXITCODE -ne 0) { throw "$case firmware build failed" }
  foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "generated/verification/efinix-software/gpu_demo.$ext" -Destination "$out/$case.$ext" -Force
  }
  if($case -eq 'normal') { $normalBuilt=$true }
 }
 $tools=Split-Path $RiscvGcc
 $nm=Join-Path $tools 'riscv-none-elf-nm.exe'
 $objdump=Join-Path $tools 'riscv-none-elf-objdump.exe'
 $normalSymbols=(& $nm --defined-only "$out/normal.elf") -join "`n"
 $profileSymbols=(& $nm --defined-only "$out/profile.elf") -join "`n"
 $normalDisassembly=(& $objdump -d "$out/normal.elf") -join "`n"
 if($LASTEXITCODE -ne 0) { throw 'cannot inspect normal firmware' }
 $main=[regex]::Match($normalDisassembly,'(?ms)^[0-9a-f]+ <main>:\r?\n(?<body>.*?)(?=^[0-9a-f]+ <[^>]+>:\r?$|\z)')
 if(!$main.Success -or $main.Groups['body'].Value -notmatch '<bullet_clip_background_for_hud>') {
  throw 'normal firmware main does not reach bullet_clip_background_for_hud'
 }
 if($normalSymbols -notmatch '(?m)\sbullet_clip_background_for_hud$') { throw 'normal firmware dropped clip function' }
 if($profileSymbols -match '(?m)\sbullet_clip_background_for_hud$') { throw 'Profile firmware retained clip function' }
 Write-Output 'PASS clip entry: ordinary main reaches HUD background clip; Profile retains full background path'
} finally {
 try {
  if($normalBuilt) { foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "$out/normal.$ext" -Destination "generated/verification/efinix-software/gpu_demo.$ext" -Force
  } }
 } finally { Pop-Location }
}
