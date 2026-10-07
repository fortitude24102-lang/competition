param(
 [Parameter(Mandatory=$true)][string]$Out,
 [string]$Url='http://127.0.0.1:8765',
 [double]$Seconds=1800,
 [double]$Interval=0.2,
 [string]$Python='C:/efinity/efinity/python311/bin/python.exe'
)
# Observe only. Never sends control POSTs, changes services or touches a board.
$ErrorActionPreference='Stop'
$captureRepo=Split-Path $PSScriptRoot -Parent
$capturePriorPythonHome=$env:PYTHONHOME
Push-Location $captureRepo
try {
 if(($Python -replace '\\','/') -like '*/efinity/python311/bin/python.exe') {
  $env:PYTHONHOME=Split-Path (Split-Path $Python)
 }
 & $Python sw/efinix_gpu/tools/control_gateway/capture.py --url $Url --out $Out --seconds $Seconds --interval $Interval
 $captureExit=$LASTEXITCODE
} finally {
 $env:PYTHONHOME=$capturePriorPythonHome
 Pop-Location
}
exit $captureExit
