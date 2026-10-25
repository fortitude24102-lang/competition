param([Parameter(Mandatory=$true)][string]$ReferenceGpuRtlDirectory,
 [Parameter(Mandatory=$true)][string]$CandidateGpuRtlDirectory,
 [string[]]$AllowedFeatureDifference=@())
$ErrorActionPreference='Stop'
$featureNames=@('copyStream','instances','frameLists','keyPrefetch','stripeScratchpad',
 'copyBurstBuffer','scanoutWordPipeline','keyRowTrim','transformBlit','alphaPipeline',
 'axiDiagnostics','keyWritePipeline','extendedListArena','smallCopyPrefetch',
 'writeCredits','alphaRowPrefetch','wideCopyDma','alphaEarlyPrefetch')
if(@($AllowedFeatureDifference | Where-Object {$_ -notin $featureNames}).Count -or
 @($AllowedFeatureDifference | Select-Object -Unique).Count -ne $AllowedFeatureDifference.Count) {
 throw 'Unknown or duplicate permitted feature difference'
}
$manifests=@(foreach($directory in @($ReferenceGpuRtlDirectory,$CandidateGpuRtlDirectory)) {
 $root=(Resolve-Path -LiteralPath $directory).Path
 $m=Get-Content -Raw -LiteralPath (Join-Path $root 'gpu-build.json') | ConvertFrom-Json
 if($m.schemaVersion -ne 2 -or $m.sourceSha256 -notmatch '^[0-9a-f]{64}$') {
  throw "Complete generated configuration/source identity required: $root"
 }
 $keys=@($m.features.PSObject.Properties.Name)
 if($keys.Count -ne $featureNames.Count -or @(Compare-Object ($keys|Sort-Object) ($featureNames|Sort-Object)).Count) {
  throw "Incomplete or unknown effective GPU features: $root"
 }
 foreach($name in $featureNames) {
  if($name -eq 'writeCredits') {
   if(($m.features.$name -isnot [int] -and $m.features.$name -isnot [long]) -or $m.features.$name -notin 2,4) {
    throw 'Invalid write credit configuration'
   }
  } elseif($m.features.$name -isnot [bool]) {throw "Non-boolean feature: $name"}
 }
 if($m.wideCopyDma -isnot [bool] -or $m.wideCopyDma -ne $m.features.wideCopyDma) {
  throw 'Native interface flag disagrees with effective features'
 }
 if($m.features.alphaEarlyPrefetch -and (!$m.features.alphaRowPrefetch -or !$m.features.alphaPipeline)) {
  throw 'Early Alpha requires row prefetch and pixel pipeline'
 }
 $listed=@(Get-Content -LiteralPath (Join-Path $root 'filelist.f') | Where-Object {$_ -match '\S'} | ForEach-Object {$_.Trim()})
 $recorded=@($m.rtlSha256.PSObject.Properties.Name)
 if(!$listed.Count -or $listed.Count -ne @($listed|Select-Object -Unique).Count -or
    $recorded.Count -ne $listed.Count -or @(Compare-Object ($listed|Sort-Object) ($recorded|Sort-Object)).Count) {
  throw 'Emitted RTL hashes must cover exactly the selected filelist'
 }
 foreach($file in $listed) {
  $full=[IO.Path]::GetFullPath((Join-Path $root $file))
  if([IO.Path]::IsPathRooted($file) -or $file -notmatch '\.(sv|v|vh)$' -or
     !$full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
   throw "Unexpected emitted source path: $file"
  }
  $expected=$m.rtlSha256.$file
  if($expected -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
   throw "Selected RTL differs from generated manifest: $file"
  }
 }
 $m
})
if($manifests[0].sourceSha256 -cne $manifests[1].sourceSha256){throw 'GPU source identities differ'}
# PixelPipeExt imports these handwritten files in addition to the Scala source.
# Their self-consistent emitted hashes must also match ACROSS the two builds.
foreach($name in @('gpu_pixel_contract.vh','gpu_pixel_copy.v','gpu_pixel_fill.v',
 'gpu_pixel_color_key.v','gpu_pixel_alpha_blend.v','gpu_pixel_pipe.v')) {
 $hashes=@(foreach($m in $manifests) {
  $entry=@($m.rtlSha256.PSObject.Properties | Where-Object {($_.Name -replace '^\./','') -ceq $name})
  if($entry.Count -ne 1){throw "Missing handwritten pixel source: $name"}
  $entry[0].Value
 })
 if($hashes[0] -cne $hashes[1]){throw "Handwritten pixel sources differ: $name"}
}
$differences=@($featureNames | Where-Object {$manifests[0].features.$_ -ne $manifests[1].features.$_})
if($differences.Count -ne $AllowedFeatureDifference.Count -or
   ($differences.Count -and @(Compare-Object ($differences|Sort-Object) ($AllowedFeatureDifference|Sort-Object)).Count)) {
 throw "Unexpected GPU feature differences: $($differences -join ','); permitted: $($AllowedFeatureDifference -join ',')"
}
Write-Output "GPU_BUILD_MATCH,PASS,source=$($manifests[0].sourceSha256),differences=$($differences -join ',')"
