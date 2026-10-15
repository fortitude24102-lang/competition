# Run the actual collector's identity guard, without serial/JTAG access.
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) 'capture-game-probe.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors){throw 'Collector parse failed'}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ProbeIdentity'},$true)
if(!$function){throw 'Missing collector identity guard'}
. ([scriptblock]::Create($function.Extent.Text))
$base="V3_FRAME_LIST,present=1,enabled=1`r`nV3_LOGIC_COPY,enabled=1`r`n"
Assert-ProbeIdentity $base 1 0 # Pre-seal candidate explicitly allowed.
Assert-ProbeIdentity ($base+"V3_SEAL_BUDGET,words=0`r`n") 1 0
Assert-ProbeIdentity ($base+"V3_SEAL_BUDGET,words=256`r`n") 1 256
Assert-ProbeIdentity ($base+"V3_HUD_LIST,enabled=1`r`n") 1 0 1
Assert-ProbeIdentity ($base+"V3_HUD_LIST,enabled=0`r`n") 1 0 0
Assert-ProbeIdentity ($base+"V3_HUD_LIST,enabled=0`r`n") 1 0 0 $true
Assert-ProbeIdentity ($base+"V3_HUD_DIRECT,enabled=1`r`n") 1 0 0 $false 1 $true
Assert-ProbeIdentity ($base+"V3_HUD_DIRECT,enabled=0`r`n") 1 0 0 $false 0 $true
$cases=@(
 @{raw=$base+"V3_SEAL_BUDGET,words=256`r`n";logic=1;seal=0},
 @{raw=$base+"V3_SEAL_BUDGET,words=0`r`n";logic=1;seal=256},
 @{raw=$base;logic=1;seal=256},
 @{raw=$base;logic=0;seal=0},
 @{raw=$base+$base;logic=1;seal=0},
 @{raw=$base+"V3_HUD_LIST,enabled=1`r`n";logic=1;seal=0;hud=0},
 @{raw=$base+"V3_HUD_LIST,enabled=0`r`n";logic=1;seal=0;hud=1},
 @{raw=$base;logic=1;seal=0;hud=1},
 @{raw=$base+"V3_HUD_LIST,enabled=1`r`nV3_HUD_LIST,enabled=1`r`n";logic=1;seal=0;hud=1},
 @{raw=$base;logic=1;seal=0;hud=0;require=$true},
 @{raw=$base;logic=1;seal=0;direct=0;requireDirect=$true},
 @{raw=$base+"V3_HUD_DIRECT,enabled=1`r`n";logic=1;seal=0;direct=0;requireDirect=$true},
 @{raw=$base+"V3_HUD_DIRECT,enabled=0`r`n";logic=1;seal=0;direct=1;requireDirect=$true},
 @{raw=$base+"V3_HUD_DIRECT,enabled=1`r`nV3_HUD_DIRECT,enabled=1`r`n";logic=1;seal=0;direct=1;requireDirect=$true})
foreach($case in $cases) {
 $rejected=$false
 try {Assert-ProbeIdentity $case.raw $case.logic $case.seal ([int]$case.hud) ([bool]$case.require) ([int]$case.direct) ([bool]$case.requireDirect)}catch {$rejected=$true}
 if(!$rejected){throw 'Contradictory/missing/ambiguous cohort identity accepted'}
}
'PASS real collector identity guard: old/new/missing/duplicate, including seal and HUD explicit off contradictions'
