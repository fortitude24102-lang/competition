param()
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$wslRoot = '/mnt/' + $drive + $projectRoot.Substring(2).Replace('\', '/')
# Reuse environment exports from the main regression, excluding software builders.
$environment = (Get-Content (Join-Path $PSScriptRoot 'test-chisel.sh') -Raw)
$environment = $environment.Substring($environment.IndexOf('export JAVA_HOME='))
$environment = $environment.Substring(0, $environment.IndexOf('bash "$project_root/scripts/build-rv32i-tests.sh"'))
$command = "set -euo pipefail`n" + $environment + "`ncd '$wslRoot/chisel'`nexec bash /mnt/d/Chisel-environment/sbt/bin/sbt clean 'testOnly gpu.PixelPipeExtSpec'`n"
$command.Replace("`r`n", "`n") | & wsl.exe -d Ubuntu -- bash -s
if ($LASTEXITCODE -ne 0) { throw "Pixel Chisel blackbox regression failed: $LASTEXITCODE" }
Write-Host '[PASS] Pixel Chisel blackbox regression'

