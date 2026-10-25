param([Parameter(Mandatory=$true)][string]$ReferenceGpuRtlDirectory,
 [Parameter(Mandatory=$true)][string]$CandidateGpuRtlDirectory,
 [ValidateSet('wideCopyDma','alphaEarlyPrefetch')][string]$Feature='wideCopyDma')
$ErrorActionPreference='Stop'
$scripts=Split-Path $PSScriptRoot -Parent
$features=@('copyStream','instances','frameLists','keyPrefetch','stripeScratchpad',
 'copyBurstBuffer','scanoutWordPipeline','keyRowTrim','transformBlit','alphaPipeline',
 'axiDiagnostics','keyWritePipeline','extendedListArena','smallCopyPrefetch',
 'writeCredits','alphaRowPrefetch','wideCopyDma','alphaEarlyPrefetch')
foreach($directory in @($ReferenceGpuRtlDirectory,$CandidateGpuRtlDirectory)) {
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $directory 'gpu-build.json') | ConvertFrom-Json
 if($manifest.schemaVersion -ne 2){throw 'Generated manifest lacks complete configuration schema'}
 foreach($name in $features) {
  if($name -notin $manifest.features.PSObject.Properties.Name){throw "Missing generated feature: $name"}
 }
 if($manifest.sourceSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Missing generated source identity'}
 foreach($name in @('copyStream','instances','frameLists','keyPrefetch','scanoutWordPipeline',
  'transformBlit','alphaPipeline','axiDiagnostics','keyWritePipeline','extendedListArena',
  'smallCopyPrefetch','alphaRowPrefetch')) {
  if($manifest.features.$name -cne $true){throw "Full baseline option was not recorded as enabled: $name"}
 }
 foreach($name in @('stripeScratchpad','copyBurstBuffer','keyRowTrim')) {
  if($manifest.features.$name -cne $false){throw "Unexpected experimental option enabled: $name"}
 }
 if($manifest.features.writeCredits -ne 4){throw 'Fair baseline must retain four write credits'}
 if($Feature -eq 'wideCopyDma' -and $manifest.features.alphaEarlyPrefetch){throw 'Wide Copy comparison must keep early Alpha off'}
 if($Feature -eq 'alphaEarlyPrefetch' -and !$manifest.features.wideCopyDma){throw 'Early Alpha comparison must retain native Copy'}
}
$compare=Join-Path $scripts 'compare-gpu-build.ps1'
& $compare -ReferenceGpuRtlDirectory $ReferenceGpuRtlDirectory -CandidateGpuRtlDirectory $CandidateGpuRtlDirectory -AllowedFeatureDifference $Feature
$root=Join-Path (Split-Path $scripts -Parent) ('generated/verification/v3/gpu-build-match/manifest-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Reject([string]$Name,[scriptblock]$Change,[string[]]$Allowed=@($Feature)) {
 $copy=Join-Path $root $Name
 New-Item -ItemType Directory -Path $copy | Out-Null
 Copy-Item -LiteralPath (Join-Path $CandidateGpuRtlDirectory 'gpu-build.json') -Destination $copy
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $copy 'gpu-build.json') | ConvertFrom-Json
 # Resolve hashes against real generated modules without copying the whole design.
 Copy-Item -LiteralPath (Join-Path $CandidateGpuRtlDirectory 'filelist.f') -Destination $copy
 foreach($file in Get-Content -LiteralPath (Join-Path $CandidateGpuRtlDirectory 'filelist.f') | Where-Object {$_ -match '\S'}) {
  $destination=Join-Path $copy $file
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
  New-Item -ItemType HardLink -Path $destination -Target (Join-Path (Resolve-Path -LiteralPath $CandidateGpuRtlDirectory).Path $file) | Out-Null
 }
 & $Change $manifest $copy
 $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $copy 'gpu-build.json') -Encoding utf8
 $rejected=$false
 try { & $compare -ReferenceGpuRtlDirectory $ReferenceGpuRtlDirectory -CandidateGpuRtlDirectory $copy -AllowedFeatureDifference $Allowed | Out-Null } catch { $rejected=$true }
 if(!$rejected){throw "Unsafe comparison accepted: $Name"}
 Write-Output "PASS rejection $Name"
}
Reject 'omitted-scanout' {param($m,$p) $m.features.scanoutWordPipeline=$false}
Reject 'wrong-credits' {param($m,$p) $m.features.writeCredits=2}
Reject 'different-source' {param($m,$p) $m.sourceSha256='0'*64}
Reject 'missing-feature' {param($m,$p) $m.features.PSObject.Properties.Remove('alphaRowPrefetch')}
Reject 'missing-early-alpha' {param($m,$p) $m.features.PSObject.Properties.Remove('alphaEarlyPrefetch')}
Reject 'legacy-schema' {param($m,$p) $m.schemaVersion=1}
if($Feature -eq 'alphaEarlyPrefetch') {
 Reject 'early-without-row' {param($m,$p) $m.features.alphaRowPrefetch=$false} @('alphaEarlyPrefetch','alphaRowPrefetch')
}
Reject 'extra-feature' {param($m,$p) $m.features | Add-Member -NotePropertyName unexpected -NotePropertyValue $true}
if($Feature -eq 'wideCopyDma') {
 Reject 'same-wide-setting' {param($m,$p) $m.features.wideCopyDma=$false; $m.wideCopyDma=$false}
} else {
 Reject 'same-early-setting' {param($m,$p) $m.features.alphaEarlyPrefetch=$false}
}
Reject 'unknown-exception' {param($m,$p)} @('doesNotExist')
Reject 'empty-rtl-hashes' {param($m,$p) $m.rtlSha256=[pscustomobject]@{}}
Reject 'bad-rtl-hash' {param($m,$p) $first=@($m.rtlSha256.PSObject.Properties)[0];$m.rtlSha256.($first.Name)='0'*64}
Reject 'unrecorded-source' {param($m,$p) $first=@($m.rtlSha256.PSObject.Properties)[0];$m.rtlSha256.PSObject.Properties.Remove($first.Name)}
Reject 'different-handwritten-pixels' {param($m,$p)
 $file=Join-Path $p 'gpu_pixel_alpha_blend.v'
 $text=[IO.File]::ReadAllText($file)
 # Unlink the fixture first: its hard link must never change the real candidate.
 Remove-Item -LiteralPath $file
 [IO.File]::WriteAllText($file,$text+"`n// different handwritten source revision`n")
 $m.rtlSha256.'./gpu_pixel_alpha_blend.v'=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
$output=Join-Path $root 'rejected-board'
$rejected=$false
try {
 & (Join-Path $scripts 'test-efinix-board.ps1') -GpuRtlDirectory (Join-Path $root 'omitted-scanout') -ReferenceGpuRtlDirectory $ReferenceGpuRtlDirectory -AllowedFeatureDifference $Feature -OutputDirectory $output -PrepareOnly | Out-Null
} catch {$rejected=$true}
if(!$rejected -or (Test-Path -LiteralPath $output)){throw 'Board preparation bypassed reference comparison'}
Write-Output 'PASS board rejects mismatch before creating output'
Write-Output "GPU_BUILD_MATCH_TESTS,PASS,evidence=$root"
