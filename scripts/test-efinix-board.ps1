[CmdletBinding()]
param([string]$EfinityHome='D:/efinity',[string]$OutputDirectory='D:/efinity_builds/efinix_2d_gpu_day5',[ValidateSet('interface','map','compile')][string]$Flow='compile',
 [string]$GpuRtlDirectory='',[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$board=Join-Path (Split-Path $PSScriptRoot -Parent) 'board/efinix_ti60'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
[xml]$project=Get-Content (Join-Path $board 'efinix_2d_gpu.xml')
$ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('e','http://www.efinixinc.com/enf_proj')
if($GpuRtlDirectory) {
 $gpu=(Resolve-Path -LiteralPath $GpuRtlDirectory).Path
 if(Test-Path -LiteralPath (Join-Path $OutputDirectory 'efinix_2d_gpu.xml')) {throw 'Candidate project output must be fresh; choose a new directory'}
 $sources=@(Get-Content -LiteralPath (Join-Path $gpu 'filelist.f') | Where-Object {$_ -match '\S'})
 if(!$sources.Count) {throw 'Candidate filelist is empty'}
 $design=$project.SelectSingleNode('//e:design_info',$ns)
 foreach($old in @($project.SelectNodes('//e:design_file',$ns) | Where-Object {$_.name -like '../../generated/efinix_gpu/*'})) { [void]$design.RemoveChild($old) }
 foreach($source in $sources) {
  $full=[IO.Path]::GetFullPath((Join-Path $gpu $source))
  if(!(Test-Path -LiteralPath $full -PathType Leaf)) {throw "Missing candidate source: $full"}
  $node=$project.CreateElement('efx','design_file',$ns.LookupNamespace('e'))
  $node.SetAttribute('name',$full.Replace('\','/'))
  $node.SetAttribute('version','default'); $node.SetAttribute('library','default')
  [void]$design.InsertBefore($node,$design.SelectSingleNode('e:top_vhdl_arch',$ns))
 }
}
foreach($file in $project.SelectNodes('//e:design_file|//e:sdc_file',$ns)) {
 $full=if([IO.Path]::IsPathRooted($file.name)) {$file.name} else {[IO.Path]::GetFullPath((Join-Path $board $file.name))}
 if(!(Test-Path -LiteralPath $full)){throw "Missing project input: $full"}
 $file.SetAttribute('name',$full.Replace('\','/'))
}
foreach($ip in $project.SelectNodes('//e:ip',$ns)) {
 $full=[IO.Path]::GetFullPath((Join-Path $board $ip.path))
 if(!(Test-Path -LiteralPath $full)){throw "Missing project IP settings: $full"}
 $ip.SetAttribute('path',$full.Replace('\','/'))
}
# The RTL generator is the single feature switch. Reject half-enabled sources
# before creating a downloadable candidate, and use Efinity's native macro.
$tops=@($project.SelectNodes('//e:design_file',$ns) | Where-Object {[IO.Path]::GetFileName($_.name) -match '^Efinix2dGpuTop\.(sv|v)$'})
if($tops.Count -ne 1){throw 'Expected exactly one selected Efinix2dGpuTop source'}
$topText=Get-Content -Raw -LiteralPath $tops[0].name
$widePins=@('io_fabricReset','io_legacyDdr_w_bits_data','io_wideDdr_w_bits_data')
$pinCount=@($widePins | Where-Object {$topText -match ('\b'+$_+'\b')}).Count
if($pinCount -ne 0 -and $pinCount -ne 3){throw 'Incomplete native DDR interface on selected GPU'}
$wideEnabled=$pinCount -eq 3
$manifestPath=Join-Path (Split-Path $tops[0].name) 'gpu-build.json'
if(Test-Path -LiteralPath $manifestPath) {
 $manifest=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
 if($manifest.wideCopyDma -isnot [bool] -or $manifest.wideCopyDma -ne $wideEnabled){throw 'GPU build manifest and native DDR ports disagree'}
} elseif($wideEnabled){throw 'Native DDR ports require generator build manifest'}
if(@($project.SelectNodes('//e:defmacro[@name="GPU_WIDE_COPY_DMA"]',$ns)).Count){throw 'Do not set native DMA macro separately from selected GPU RTL'}
if($wideEnabled) {
 $macro=$project.CreateElement('efx','defmacro',$ns.LookupNamespace('e'))
 $macro.SetAttribute('name','GPU_WIDE_COPY_DMA');$macro.SetAttribute('value','1')
 [void]$project.SelectSingleNode('//e:synthesis',$ns).AppendChild($macro)
}
$include=$project.SelectSingleNode('//e:param[@name="include"]',$ns)
$includePaths=$include.value.Split(';') | ForEach-Object {
 [IO.Path]::GetFullPath((Join-Path $board $_)).Replace('\','/')
}
$include.SetAttribute('value',($includePaths -join ';'))
$project.Save((Join-Path $OutputDirectory 'efinix_2d_gpu.xml'))
Copy-Item (Join-Path $board 'efinix_2d_gpu.peri.xml') $OutputDirectory -Force
Get-ChildItem (Join-Path $board 'vendor/sapphire_ddr3/par/ddr_demo_ti60/ip/soc') -Filter *.bin | Copy-Item -Destination $OutputDirectory -Force
if($PrepareOnly) {Write-Output "PROJECT_PREPARED: $OutputDirectory"; return}
Push-Location $OutputDirectory
try {
 & (Join-Path $EfinityHome 'bin/efx_run.bat') efinix_2d_gpu --prj -f $Flow 2>&1 | Tee-Object -FilePath "$Flow.log"
 if($LASTEXITCODE -ne 0){throw "Efinity $Flow failed ($LASTEXITCODE); see $OutputDirectory/$Flow.log"}
} finally {Pop-Location}
