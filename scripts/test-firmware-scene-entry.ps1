param(
 [string]$RiscvGcc='C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Soc='Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/par/ddr_demo_ti60/embedded_sw/soc'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
$defaultBuilt=$false
try {
 $out='generated/verification/scene-entry'
 New-Item -ItemType Directory -Force $out | Out-Null
 $tools=Split-Path $RiscvGcc
 # Assert the linked firmware's reachable scene, not the script's source text.
 foreach($case in @('default','legacy','profile-default','profile-legacy')) {
  $options=@{FirmwareOnly=$true;RiscvGcc=$RiscvGcc;Soc=$Soc}
  if($case -like '*legacy') { $options.Demo='legacy' }
  if($case -like 'profile-*') { $options.Profile=$true }
  & ./scripts/test-efinix-software.ps1 @options
  $elf='generated/verification/efinix-software/gpu_demo.elf'
  $symbols=(& "$tools/riscv-none-elf-nm.exe" --defined-only $elf) -join "`n"
  if($LASTEXITCODE -ne 0) { throw 'Cannot inspect linked firmware' }
  $binary=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $root 'generated/verification/efinix-software/gpu_demo.bin')))
  $scene=if($case -like '*legacy'){'perf_build_frame'}else{'bullet_build_frame'}
  $other=if($case -like '*legacy'){'bullet_build_frame'}else{'perf_build_frame'}
  if($symbols -notmatch "(?m)\b$scene`$") { throw "$case firmware selected the wrong scene: missing $scene" }
  if($symbols -match "(?m)\b$other`$") { throw "$case firmware retained unexpected scene $other" }
  $profile=$binary.Contains('PROFILE,%s,count=')
  if($profile -ne ($case -like 'profile-*')) { throw "$case firmware selected the wrong diagnostic entry" }
  foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "generated/verification/efinix-software/gpu_demo.$ext" -Destination "$out/$case.$ext"
  }
  if($case -eq 'default') { $defaultBuilt=$true }
  & "$tools/riscv-none-elf-size.exe" "$out/$case.elf"
  if($LASTEXITCODE -ne 0) { throw 'Cannot inspect firmware RAM budget' }
  Write-Output "PASS entry $case`: reachable scene=$scene, profile=$profile; not board executed"
 }
 # A diagnostic must never replace any release binary, even with missing BSP.
 $blocked=$false
 try { & ./scripts/test-efinix-software.ps1 -FirmwareOnly -Profile -PublishRelease -Soc 'missing-test-bsp' }
 catch { $blocked=$_.Exception.Message -like '*Profile firmware must not replace*' }
 if(!$blocked) { throw 'Diagnostic release protection failed' }
 Write-Output 'PASS firmware entry matrix and diagnostic release protection'
} finally {
 try {
  # Restore even if a later case fails. Do not use stale prior-run artifacts.
  if($defaultBuilt) { foreach($ext in @('elf','bin','hex','map')) {
   Copy-Item -LiteralPath "$out/default.$ext" -Destination "generated/verification/efinix-software/gpu_demo.$ext"
  } }
 } finally { Pop-Location }
}
