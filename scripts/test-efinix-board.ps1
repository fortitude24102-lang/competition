param([string]$EfinityHome='D:/efinity',[string]$OutputDirectory='D:/efinity_builds/efinix_2d_gpu_day5',[ValidateSet('interface','map','compile')][string]$Flow='compile')
$ErrorActionPreference='Stop'
$board=Join-Path (Split-Path $PSScriptRoot -Parent) 'board/efinix_ti60'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
[xml]$project=Get-Content (Join-Path $board 'efinix_2d_gpu.xml')
$ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('e','http://www.efinixinc.com/enf_proj')
foreach($file in $project.SelectNodes('//e:design_file|//e:sdc_file',$ns)) {
 $full=[IO.Path]::GetFullPath((Join-Path $board $file.name))
 if(!(Test-Path -LiteralPath $full)){throw "Missing project input: $full"}
 $file.SetAttribute('name',$full.Replace('\','/'))
}
$include=$project.SelectSingleNode('//e:param[@name="include"]',$ns)
$includePaths=$include.value.Split(';') | ForEach-Object {
 [IO.Path]::GetFullPath((Join-Path $board $_)).Replace('\','/')
}
$include.SetAttribute('value',($includePaths -join ';'))
$project.Save((Join-Path $OutputDirectory 'efinix_2d_gpu.xml'))
Copy-Item (Join-Path $board 'efinix_2d_gpu.peri.xml') $OutputDirectory -Force
Get-ChildItem (Join-Path $board 'vendor/sapphire_ddr3/par/ddr_demo_ti60/ip/soc') -Filter *.bin | Copy-Item -Destination $OutputDirectory -Force
Push-Location $OutputDirectory
try {
 & (Join-Path $EfinityHome 'bin/efx_run.bat') efinix_2d_gpu --prj -f $Flow 2>&1 | Tee-Object -FilePath "$Flow.log"
 if($LASTEXITCODE -ne 0){throw "Efinity $Flow failed ($LASTEXITCODE); see $OutputDirectory/$Flow.log"}
} finally {Pop-Location}
