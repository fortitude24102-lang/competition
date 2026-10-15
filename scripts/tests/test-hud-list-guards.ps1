# Real negative build invocations must reject before creating any output or
# touching the external compiler, release, UART or JTAG.
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$builder=Join-Path $root 'scripts/test-efinix-software.ps1'
$cases=@(
 @{args=@('-HudList','-FirmwareOnly');message='HudList requires separate FrameList'},
 @{args=@('-HudList','-FirmwareOnly','-Interactive','-FrameList','-OutDirectory','generated/verification/v3/hud-list-invalid-output');message='HudList requires explicit network addresses'},
 @{args=@('-HudList','-FirmwareOnly','-Interactive','-FrameList','-PublishRelease');message='Interactive candidate is separate'},
 @{args=@('-HudDirect','-FirmwareOnly');message='HudDirect requires separate FrameList'},
 @{args=@('-HudDirect','-FirmwareOnly','-Interactive','-FrameList','-OutDirectory','generated/verification/v3/hud-list-invalid-output');message='HudDirect requires explicit network addresses'},
 @{args=@('-HudDirect','-HudList','-FirmwareOnly','-Interactive','-FrameList','-OutDirectory','generated/verification/v3/hud-list-invalid-output','-NetworkLocalIp','0xc0a80103','-NetworkPeerIp','0xc0a80102');message='Choose one HUD candidate'})
Push-Location $root
try {
 $unexpected=Join-Path $root 'generated/verification/v3/hud-list-invalid-output'
 if(Test-Path -LiteralPath $unexpected){throw 'Guard test output must start absent'}
 foreach($case in $cases) {
  $savedPreference=$ErrorActionPreference
  try {
   $ErrorActionPreference='Continue' # PS5 wraps the expected native stderr.
   $result=& powershell.exe -NoProfile -File $builder @($case.args) 2>&1
   $exitCode=$LASTEXITCODE
  } finally {$ErrorActionPreference=$savedPreference}
  if($exitCode -eq 0 -or (($result -join "`n") -notlike "*$($case.message)*")) {
   throw "Unexpected build guard result: $result"
  }
 }
 if(Test-Path -LiteralPath $unexpected){throw 'Rejected build created output'}
 'PASS HUD list/direct guards: explicit opt-in, mutually exclusive, FrameList, network addresses, no release or rejected output'
} finally {Pop-Location}
