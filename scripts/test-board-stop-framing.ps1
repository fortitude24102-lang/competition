$ErrorActionPreference='Stop'
# Execute the actual capture-loop predicates without opening a port or running JTAG.
foreach($spec in @(
 @('measure-hud-glyphs-board.ps1','$StopPattern','COPY_BOARD_STOP,result=0,hardware=0'),
 @('capture-game-probe.ps1','V3_PROBE_STOP,result=0','V3_PROBE_STOP,result=0')
)) {
 $tokens=$null;$errors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $spec[0]),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'Capture script parse failure'}
 $conditions=@($ast.FindAll({param($node)
  $node -is [System.Management.Automation.Language.IfStatementAst] -and
  $node.Clauses[0].Item1.Extent.Text.Contains($spec[1])
 },$true) | ForEach-Object {$_.Clauses[0].Item1.Extent.Text})
 if($conditions.Count -ne 1){throw 'Expected one capture stop predicate'}
 $predicate=[scriptblock]::Create($conditions[0])
 $StopPattern='COPY_BOARD_STOP'
 foreach($case in @(
  @('', $false),
  @($spec[2], $false),
  @(("boot`n"+$spec[2]), $false),
  @(($spec[2]+"`r"), $false),
  @(($spec[2]+"`n"), $true),
  @(($spec[2]+"`r`n"), $true),
  @(($spec[2]+"`nnext partial"), $true)
 )) {
  $tail=$case[0]
  if([bool](& $predicate) -ne $case[1]){throw "Capture stopped on an incomplete record: $($spec[0])"}
 }
 if($spec[0] -eq 'capture-game-probe.ps1') {
  $tail="V3_PROBE_STOP,result=01`n"
  if(& $predicate){throw 'Nonzero STOP prefix accepted'}
 }
}
'PASS capture predicates wait for newline-complete STOP and reject nonzero result prefixes'
