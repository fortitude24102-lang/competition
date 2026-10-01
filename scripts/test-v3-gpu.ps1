param(
  [string[]]$Suite = @(),
  [string]$LogPath = '',
  [switch]$Generate
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
foreach ($name in $Suite) {
  if ($name -notmatch '^gpu\.[A-Za-z0-9_]+$') { throw "Invalid GPU suite: $name" }
}
if (-not $LogPath) { $LogPath = Join-Path $projectRoot 'generated/verification/v3/copy/gpu-tests.log' }
$LogPath = [IO.Path]::GetFullPath($LogPath)
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
$wslRoot = '/mnt/' + $projectRoot.Substring(0, 1).ToLowerInvariant() + $projectRoot.Substring(2).Replace('\', '/')
$environment = Get-Content (Join-Path $PSScriptRoot 'test-chisel.sh') -Raw
$environment = $environment.Substring($environment.IndexOf('export JAVA_HOME='))
$environment = $environment.Substring(0, $environment.IndexOf('bash "$project_root/scripts/build-rv32i-tests.sh"'))
$compileFilter = 'set Compile / unmanagedSources := (Compile / unmanagedSources).value.filter(_.getPath.contains("/gpu/"))'
$testFilter = 'set Test / unmanagedSources := (Test / unmanagedSources).value.filter(f => f.getPath.contains("/gpu/") || f.getPath.contains("/testutil/"))'
$test = if ($Suite.Count) { 'testOnly ' + ($Suite -join ' ') } else { 'test' }
$generateCommand = if ($Generate) { " 'runMain gpu.GenerateEfinix2dGpu --target-dir ../generated/verification/v3/copy/rtl --split-verilog'" } else { '' }
$command = "set -euo pipefail`n" + $environment + "`ncd '$wslRoot/chisel'`nexec bash /mnt/d/Chisel-environment/sbt/bin/sbt '$compileFilter' '$testFilter' '$test'$generateCommand`n"
$command.Replace("`r`n", "`n") | & wsl.exe -d Ubuntu -- bash -s *> $LogPath
$result = $LASTEXITCODE
Get-Content $LogPath | Select-Object -Last 24
if ($result -ne 0) { throw "V3 GPU checks failed ($result); log: $LogPath" }
if (-not (Select-String -LiteralPath $LogPath -SimpleMatch 'All tests passed.')) {
  throw "No successful test run recorded; log: $LogPath"
}
Write-Host "[PASS] GPU RTL simulation only; log: $LogPath"
Write-Host '[NOT RUN] Board timing/FPS and full SoC tests; historical SoC exceptions remain separate.'
