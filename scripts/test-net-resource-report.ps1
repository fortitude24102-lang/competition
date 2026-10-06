param([Parameter(Mandatory=$true)][string]$BuildDirectory,[switch]$ParserOnly,[switch]$RequireRouted,
 [string]$SdcFile='')
$ErrorActionPreference='Stop'
if(!$SdcFile) {$SdcFile=Join-Path $PSScriptRoot '../board/efinix_ti60/efinix_2d_gpu.sdc'}
$report=Get-Content (Join-Path $BuildDirectory 'outflow/efinix_2d_gpu.hier_util.rpt')
function Usage([string]$name) {
 $rows=@($report | Where-Object {($_ -split '\|')[1] -match ('\+'+[regex]::Escape($name)+'\s*$')})
 if($rows.Count -ne 1) {throw "Expected one $name resource row, got $($rows.Count)"}
 $cells=$rows[0] -split '\|'
 [pscustomobject]@{Xlr=[double](($cells[2].Trim() -split '\(')[0]);Ram=[int](($cells[3].Trim() -split '\(')[0])}
}
$parser=Usage 'u_parser'
if($parser.Xlr -gt 2000 -or $parser.Ram -lt 1) {throw "Parser resource gate: XLR=$($parser.Xlr) (max 2000), RAM=$($parser.Ram) (min 1)"}
if(!$ParserOnly) {
 foreach($name in @('u_request','u_tx')) { $usage=Usage $name; if($usage.Ram -ne 0) {throw "$name still occupies $($usage.Ram) RAM blocks"} }
 $board=Usage 'board_top'
 if($board.Xlr -ge 54720) {throw "Total XLR=$($board.Xlr), must be below 90% of 60800"}
 # Check actual synthesized FF names, including destination aliases introduced
 # by optimization. Source-code names alone cannot prove SDC coverage.
 $mapped=[IO.File]::ReadAllText((Join-Path $BuildDirectory 'outflow/efinix_2d_gpu.map.v'))
 $names=@([regex]::Matches($mapped,'(?m)^\s*EFX_FF\s+\\(\S+)\s+\(') | ForEach-Object {$_.Groups[1].Value})
 $pairs=[regex]::Matches($mapped,'(?m)^\s*EFX_FF\s+\\(\S+)\s+\(\.D\(\\(\S*/u_(?:tx|request)/wr_snapshot)\s+\[(\d+)\]\)')
 if($pairs.Count -ne 1488) {throw "Expected 1488 actual snapshot transfers, got $($pairs.Count)"}
 $sdc=[IO.File]::ReadAllText((Resolve-Path $SdcFile).Path)
 $mailbox=$sdc.Substring($sdc.IndexOf('# Single-outstanding network mailboxes:'))
 $constraints=[regex]::Matches($mailbox,'set_max_delay\s+8\.000\s+\\\s+-from\s+\[get_cells\s+\{([^}]+)\}\]\s+\\\s+-to\s+\[get_cells\s+\{([^}]+)\}\]')
 if($constraints.Count -ne 3) {throw 'Expected three explicit 8ns mailbox constraints'}
 function MatchesAny([string]$name,[string]$patterns) {
  foreach($pattern in ($patterns -split '\s+')) {
   if($name -match ('^'+[regex]::Escape($pattern).Replace('\*','.*')+'$')) {return $true}
  }
  return $false
 }
 foreach($constraint in $constraints) {
  foreach($side in 1,2) {
   $count=@($names | Where-Object {MatchesAny $_ $constraint.Groups[$side].Value}).Count
   $expected=if($constraint -eq $constraints[2]) {1488}else{2}
   if($count -ne $expected) {throw "Mailbox CDC collection ${side}: matched $count FFs, expected $expected"}
  }
 }
 foreach($pair in $pairs) {
  $source=$pair.Groups[2].Value+'['+$pair.Groups[3].Value+']~FF'
  if($names -notcontains $source -or !(MatchesAny $source $constraints[2].Groups[1].Value) -or
     !(MatchesAny $pair.Groups[1].Value $constraints[2].Groups[2].Value)) {throw 'Uncovered actual snapshot transfer'}
 }
 Write-Output 'PASS mapped mailbox CDC coverage: 1488 data pairs and two request/two acknowledge pairs; routed delay verification remains separate.'
 if($RequireRouted) {
  $applied=[IO.File]::ReadAllText((Join-Path $BuildDirectory 'outflow/net-mailbox-applied.sdc'))
  # Efinity 2026.1 write_sdc concatenates exception commands without newlines.
  $actual=[regex]::Matches($applied,'set_max_delay 8(?:\.0+)? -from \[get_cells \{([^}]+)\}\] -to \[get_cells \{([^}]+)\}\]')
  foreach($constraint in $constraints) {
   $sources=@($names | Where-Object {MatchesAny $_ $constraint.Groups[1].Value})
   $destinations=@($names | Where-Object {MatchesAny $_ $constraint.Groups[2].Value})
   $covered=@($actual | Where-Object {
    $from=$_.Groups[1].Value -split '\s+'; $to=$_.Groups[2].Value -split '\s+'
    !@($sources | Where-Object {$_ -notin $from}).Count -and !@($destinations | Where-Object {$_ -notin $to}).Count
   })
   if($covered.Count -ne 1) {throw 'Missing applied 8ns mailbox constraint'}
  }
  foreach($kind in 'data','request','ack') {
   $paths=[regex]::Matches([IO.File]::ReadAllText((Join-Path $BuildDirectory "outflow/net-mailbox-$kind.rpt")),
    '(?m)^\s*\d+\s*\|\s*([\d.]+)\s*\|\s*(\S+)\|Q\s*\|\s*(\S+)\|D\s*$')
   $expected=if($kind -eq 'data'){1488}else{2}
   if($paths.Count -ne $expected) {throw "Routed $kind paths: $($paths.Count), expected $expected"}
   $max=($paths | ForEach-Object {[double]$_.Groups[1].Value} | Measure-Object -Maximum).Maximum
   if($max -gt 8) {throw "Routed $kind delay exceeds 8ns: $max"}
   if($kind -eq 'data') {
    $routed=@{};foreach($path in $paths) {$routed[$path.Groups[3].Value]=$path.Groups[2].Value}
    foreach($pair in $pairs) {
     $source=$pair.Groups[2].Value+'['+$pair.Groups[3].Value+']~FF'
     if($routed[$pair.Groups[1].Value] -ne $source) {throw 'Missing or incorrect routed data pair'}
    }
   }
   Write-Output "PASS routed $kind CDC: $expected paths, maximum $max ns"
  }
  $timing=[IO.File]::ReadAllText((Join-Path $BuildDirectory 'outflow/efinix_2d_gpu.timing.rpt'))
  $rows=[regex]::Matches($timing,'(?m)^\S+\s+\S+\s+(-?[\d.]+)\s+(-?[\d.]+)\s+\(R-R\)\s*$')
  if($timing -notmatch 'status\s+: final' -or $rows.Count -ne 16) {throw 'Missing expected final setup/hold summary (16 relationships)'}
  if(@($rows | Where-Object {[double]$_.Groups[2].Value -lt 0}).Count) {throw 'Negative final setup/hold slack'}
  Write-Output 'PASS final setup/hold: all 16 clock relationships nonnegative'
 }
}
Write-Output "PASS network resource gate: parser XLR=$($parser.Xlr), RAM=$($parser.Ram), ParserOnly=$ParserOnly. Timing and board qualification are separate."
