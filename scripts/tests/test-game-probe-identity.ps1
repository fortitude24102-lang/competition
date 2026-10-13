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
$cases=@(
 @{raw=$base+"V3_SEAL_BUDGET,words=256`r`n";logic=1;seal=0},
 @{raw=$base+"V3_SEAL_BUDGET,words=0`r`n";logic=1;seal=256},
 @{raw=$base;logic=1;seal=256},
 @{raw=$base;logic=0;seal=0},
 @{raw=$base+$base;logic=1;seal=0})
foreach($case in $cases) {
 $rejected=$false
 try {Assert-ProbeIdentity $case.raw $case.logic $case.seal}catch {$rejected=$true}
 if(!$rejected){throw 'Contradictory/missing/ambiguous cohort identity accepted'}
}
'PASS real collector identity guard: old/new/missing/duplicate, including explicit off contradiction'
