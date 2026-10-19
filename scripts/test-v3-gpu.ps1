param(
  [string[]]$Suite = @(),
  [string]$LogPath = '',
  [switch]$Generate,
  [switch]$KeyPrefetch,
  [switch]$CopyBurstBuffer,
  [switch]$ScanoutWordPipeline,
  [switch]$KeyRowTrim,
  [switch]$TransformBlit,
  [switch]$AlphaPipeline,
  [switch]$AxiDiagnostics,
  [switch]$StripeScratchpad,
  [switch]$SoftwareOnly
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
if ($SoftwareOnly -and ($Generate -or $Suite.Count)) { throw 'SoftwareOnly cannot select/generate RTL.' }
if (($KeyPrefetch -or $StripeScratchpad -or $CopyBurstBuffer -or $ScanoutWordPipeline -or $KeyRowTrim -or $TransformBlit -or $AlphaPipeline -or $AxiDiagnostics) -and !$Generate) { throw 'Candidate hardware switches require Generate' }
if ($KeyRowTrim -and !$KeyPrefetch) { throw 'KeyRowTrim requires KeyPrefetch' }
if (Test-Path (Join-Path $projectRoot 'scripts/test-v3-damage.sh')) {
 $softwareLog=$LogPath+'.software.log'
 $savedPreference=$ErrorActionPreference
 try {
  $ErrorActionPreference='Continue'
  & wsl.exe -d Ubuntu -- bash "$wslRoot/scripts/test-v3-damage.sh" *> $softwareLog
  $softwareResult=$LASTEXITCODE
 } finally { $ErrorActionPreference=$savedPreference }
 Get-Content $softwareLog | Select-Object -Last 8
 if($softwareResult -ne 0 -or !(Select-String -LiteralPath $softwareLog -SimpleMatch 'DAMAGE_SUITE,PASS')) { throw "Damage software checks failed: $softwareLog" }
 if($SoftwareOnly) { Write-Host '[PASS] Damage software only; board/RTL NOT RUN.'; return }
}
$environment = Get-Content (Join-Path $PSScriptRoot 'test-chisel.sh') -Raw
$environment = $environment.Substring($environment.IndexOf('export JAVA_HOME='))
$environment = $environment.Substring(0, $environment.IndexOf('bash "$project_root/scripts/build-rv32i-tests.sh"'))
$compileFilter = 'set Compile / unmanagedSources := (Compile / unmanagedSources).value.filter(_.getPath.contains("/gpu/"))'
$testFilter = 'set Test / unmanagedSources := (Test / unmanagedSources).value.filter(f => f.getPath.contains("/gpu/") || f.getPath.contains("/testutil/"))'
$test = if ($Suite.Count) { 'testOnly ' + ($Suite -join ' ') } else { 'test' }
$candidateFlags = if ($KeyPrefetch -or $StripeScratchpad -or $CopyBurstBuffer -or $ScanoutWordPipeline -or $KeyRowTrim -or $TransformBlit -or $AlphaPipeline -or $AxiDiagnostics) { ' --instances --frame-lists' } else { '' }
if ($KeyPrefetch) { $candidateFlags += ' --key-prefetch' }
if ($StripeScratchpad) { $candidateFlags += ' --stripe-scratchpad' }
if ($CopyBurstBuffer) { $candidateFlags += ' --copy-burst-buffer' }
if ($ScanoutWordPipeline) { $candidateFlags += ' --scanout-word-pipeline' }
if ($KeyRowTrim) { $candidateFlags += ' --key-row-trim' }
if ($TransformBlit) { $candidateFlags += ' --transform-blit' }
if ($AlphaPipeline) { $candidateFlags += ' --alpha-pipeline' }
if ($AxiDiagnostics) { $candidateFlags += ' --axi-diagnostics' }
if ($CopyBurstBuffer -and $StripeScratchpad) { throw 'Measure Copy staging without the experimental stripe path' }
if ($ScanoutWordPipeline -and ($CopyBurstBuffer -or $StripeScratchpad)) { throw 'Measure Scanout word replacement independently' }
$rtlOutput = if ($AlphaPipeline) { if($TransformBlit) { 'alpha-gray-20261019/rtl-both' } else { 'alpha-gray-20261019/rtl-alpha' } } elseif ($KeyRowTrim -and $TransformBlit) { 'dual-track-20261018/rtl-both' } elseif ($KeyRowTrim) { 'dual-track-20261018/rtl-key-trim' } elseif ($TransformBlit) { 'alpha-gray-20261019/rtl-gray' } elseif ($ScanoutWordPipeline) { 'scanout-word-pipeline-20261016/rtl' } elseif ($CopyBurstBuffer) { 'copy-burst-buffer-20261016/rtl' } elseif ($StripeScratchpad) { 'rows-stripes-20261016/rtl' } elseif ($KeyPrefetch) { 'rows-stripes-20261016/rtl-key' } else { 'copy/rtl' }
if ($AxiDiagnostics) { $rtlOutput = 'axi-diagnostics-20261019/rtl-'+[Guid]::NewGuid().ToString('N') }
$generateCommand = if ($Generate) { " 'runMain gpu.GenerateEfinix2dGpu --target-dir ../generated/verification/v3/$rtlOutput --split-verilog$candidateFlags'" } else { '' }
$command = "set -euo pipefail`n" + $environment + "`ncd '$wslRoot/chisel'`nexec bash /mnt/d/Chisel-environment/sbt/bin/sbt '$compileFilter' '$testFilter' '$test'$generateCommand`n"
# Windows PowerShell 5 turns native stderr (including WSL proxy warnings) into
# ErrorRecords. Capture those warnings without mistaking them for test failure.
$savedPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  $command.Replace("`r`n", "`n") | & wsl.exe -d Ubuntu -- bash -s *> $LogPath
  $result = $LASTEXITCODE
} finally { $ErrorActionPreference = $savedPreference }
Get-Content $LogPath | Select-Object -Last 24
if ($result -ne 0) { throw "V3 GPU checks failed ($result); log: $LogPath" }
if (-not (Select-String -LiteralPath $LogPath -SimpleMatch 'All tests passed.')) {
  throw "No successful test run recorded; log: $LogPath"
}
Write-Host "[PASS] GPU RTL simulation only; log: $LogPath"
Write-Host '[NOT RUN] Board timing/FPS and full SoC tests; historical SoC exceptions remain separate.'
