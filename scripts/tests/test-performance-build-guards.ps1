$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script=Join-Path $root 'scripts/test-efinix-software.ps1'
$out=Join-Path $root 'generated/verification/v3/performance-challenge-20261013/implicit-network-guard'
$ErrorActionPreference='Continue'
$result=& powershell.exe -NoProfile -File $script -FirmwareOnly -Interactive -FrameList -PerformanceChallenge -OutDirectory $out 2>&1 | Out-String
$exit=$LASTEXITCODE
$ErrorActionPreference='Stop'
if(!$exit -or $result -notmatch 'explicit network addresses') {throw 'Performance build silently used legacy IP defaults'}
'PASS performance build requires explicit network addresses before compilation or output creation'
$ErrorActionPreference='Continue'
$shapeOut=Join-Path $root ('generated/verification/v3/late-frame-20261024/shape-guard-'+[guid]::NewGuid().ToString('N'))
$result=& powershell.exe -NoProfile -File $script -FirmwareOnly -Interactive -FrameList -ShapeLut -OutDirectory $shapeOut 2>&1 | Out-String
$exit=$LASTEXITCODE
$ErrorActionPreference='Stop'
if(!$exit -or $result -notmatch 'explicit network addresses' -or (Test-Path -LiteralPath $shapeOut)){throw "ShapeLut build guard failed: $result"}
'PASS ShapeLut build requires explicit network addresses before compilation or output creation'
