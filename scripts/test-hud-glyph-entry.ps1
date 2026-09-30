param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $out='generated/verification/hud-glyphs/entry'
 New-Item -ItemType Directory -Force $out | Out-Null
 $tool='D:/efinity/risc_v_gcc/toolchain/bin'
 foreach($case in @('normal','profile','legacy')) {
  $options=@{FirmwareOnly=$true;NetworkLocalIp='0xc0a80103';NetworkPeerIp='0xc0a80102'}
  if($case -eq 'profile') { $options.Profile=$true }
  if($case -eq 'legacy') { $options.Demo='legacy' }
  & ./scripts/test-efinix-software.ps1 @options
  foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "generated/verification/efinix-software/gpu_demo.$ext" -Destination "$out/$case.$ext" -Force
  }
  $symbols=(& "$tool/riscv-none-elf-nm.exe" --defined-only "$out/$case.elf") -join "`n"
  $disassembly=(& "$tool/riscv-none-elf-objdump.exe" -d "$out/$case.elf") -join "`n"
  if($LASTEXITCODE -ne 0) { throw "inspect $case failed" }
  $main=[regex]::Match($disassembly,'(?ms)^[0-9a-f]+ <main>:\r?\n(?<body>.*?)(?=^[0-9a-f]+ <[^>]+>:\r?$|\z)')
  if($case -eq 'normal') {
   foreach($function in @('hud_init_glyph_atlas','hud_update_gpu_cache','hud_update_cache')) {
    if(!$main.Success -or $main.Groups['body'].Value -notmatch "<$function>") { throw "normal main does not reach $function" }
   }
  } elseif($symbols -match '(?m)\s(hud_init_glyph_atlas|hud_update_gpu_cache)$') {
   throw "$case retained ordinary GPU glyph path"
  }
 }
 Write-Output 'PASS HUD glyph entry: ordinary main reaches glyph init/GPU updater/original CPU updater; Profile/legacy exclude new path'
} finally {
 if(Test-Path "$out/normal.elf") {
  foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "$out/normal.$ext" -Destination "generated/verification/efinix-software/gpu_demo.$ext" -Force
  }
 }
 Pop-Location
}
