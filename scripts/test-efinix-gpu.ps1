param()
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$drive = $projectRoot.Substring(0, 1).ToLowerInvariant()
$wslRoot = '/mnt/' + $drive + $projectRoot.Substring(2).Replace('\', '/')
$environment = (Get-Content (Join-Path $PSScriptRoot 'test-chisel.sh') -Raw)
$environment = $environment.Substring($environment.IndexOf('export JAVA_HOME='))
$environment = $environment.Substring(0, $environment.IndexOf('bash "$project_root/scripts/build-rv32i-tests.sh"'))
$compileFilter = 'set Compile / unmanagedSources := (Compile / unmanagedSources).value.filter(_.getPath.contains("/gpu/"))'
$testFilter = 'set Test / unmanagedSources := (Test / unmanagedSources).value.filter(f => f.getPath.contains("/gpu/") || f.getPath.contains("/testutil/"))'
$generate = 'runMain gpu.GenerateEfinix2dGpu --target-dir ../generated/efinix_gpu --split-verilog'
$command = "set -euo pipefail`n" + $environment + "`ncd '$wslRoot/chisel'`nexec bash /mnt/d/Chisel-environment/sbt/bin/sbt clean '$compileFilter' '$testFilter' test '$generate'`n"
$command.Replace("`r`n", "`n") | & wsl.exe -d Ubuntu -- bash -s
if ($LASTEXITCODE -ne 0) { throw "Efinix GPU regression failed: $LASTEXITCODE" }
& git -C $projectRoot diff --exit-code -- generated/efinix_gpu
if ($LASTEXITCODE -ne 0) { throw 'Generated GPU RTL differs from the staged or committed source; review and stage it.' }
Write-Host '[PASS] Efinix GPU regression'
