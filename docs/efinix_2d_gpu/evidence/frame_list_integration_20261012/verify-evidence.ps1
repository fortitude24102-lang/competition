param([string]$Directory=$PSScriptRoot)
$ErrorActionPreference='Stop'
foreach($entry in Import-Csv "$Directory/sha256.csv") {
 if($entry.file -notmatch '^[a-zA-Z0-9_.-]+$') {throw 'Invalid evidence filename'}
 if((Get-FileHash -LiteralPath "$Directory/$($entry.file)" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {throw "Evidence hash mismatch: $($entry.file)"}
}
$names=@('256-old-r1','256-new-r1','256-old-r2','512-old-r1','512-new-r1','512-old-r2','512-qualified-old-r1','512-new-r2','512-qualified-production-r1')
$stats=@{}
foreach($name in $names) {
 $log=[IO.File]::ReadAllText("$Directory/board$name.log")
 if($log -match 'V3_FAIL|V3_PROBE_HEALTH_FAIL' -or $log -notmatch 'V3_PROBE_STOP,result=0' -or $log -notmatch 'V3_COPY_AHEAD,enabled=1') {throw "Incomplete/unhealthy cohort $name"}
 $matches=[regex]::Matches($log,'(?m)^V3_PROBE,target=([^\r\n]+)')
 if($matches.Count -ne 1) {throw "Expected one summary: $name"}
 $fields=@{}
 foreach($field in ('target='+$matches[0].Groups[1].Value).Split(',')) {$pair=$field.Split('=');$fields[$pair[0]]=[int]$pair[1]}
 if($fields.frames -ne 600 -or $fields.target -ne [int]$name.Substring(0,3) -or $fields.under -or $fields.errors -or $fields.visible_min -lt [int]($fields.target*.9) -or !$fields.alpha_min) {throw "Invalid workload/health: $name"}
 if($name -like '*-new-*' -and $log -notmatch 'V3_FRAME_LIST,present=1,enabled=1') {throw 'Missing actual batch path'}
 $stats[$name]=$fields
}
if($stats['512-new-r1'].fps_x10 -le $stats['512-qualified-production-r1'].fps_x10 -or $stats['512-new-r2'].fps_x10 -le $stats['512-qualified-production-r1'].fps_x10) {throw 'No repeatable gain over qualified baseline'}
if([IO.File]::ReadAllText("$Directory/gpu-full.log") -notmatch 'Tests: succeeded 82, failed 0') {throw 'GPU full regression evidence missing'}
if([IO.File]::ReadAllText("$Directory/board-oracle-r1.log") -notmatch 'FRAME_LIST_BOARD_STOP,result=0,publish=PASS,copy_key_alpha=PASS,tagwrap=PASS') {throw 'Pixel/publication oracle missing'}
if([IO.File]::ReadAllText("$Directory/menu-board-r1.log") -notmatch 'PASS real four-tier START/MENU ACK') {throw 'Menu qualification missing'}
if([IO.File]::ReadAllText("$Directory/control256-board.log") -notmatch 'PASS actual HTTP -> UDP -> FPGA -> Sapphire input') {throw 'Real control qualification missing'}
'PASS archive hashes,82GPU tests,pixel oracle,9healthy600-frame cohorts,net gain,menu and actual input. NOT stable512@60 or endurance.'
