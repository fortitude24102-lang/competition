param()
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$candidate=Join-Path $repo 'generated/verification/v3/copy/rtl'
$output=Join-Path $repo ('generated/verification/v3/copy/project-test-'+[Guid]::NewGuid().ToString('N'))
$original=Join-Path $repo 'board/efinix_ti60/efinix_2d_gpu.xml'
$before=(Get-FileHash $original).Hash
# A partial replacement or stale generated source must fail this check.
foreach($option in @('GpuRtlDirectory','PrepareOnly')) {
 if(!(Get-Command "$PSScriptRoot/test-efinix-board.ps1").Parameters.ContainsKey($option)) {throw "Missing safe project preparation option: $option"}
}
& "$PSScriptRoot/test-efinix-board.ps1" -GpuRtlDirectory $candidate -OutputDirectory $output -PrepareOnly
[xml]$project=Get-Content (Join-Path $output 'efinix_2d_gpu.xml')
[void]$project.Schemas.Add('http://www.efinixinc.com/enf_proj','D:/efinity/bin/enf_proj.xsd')
$project.Validate({param($sender,$eventArgs) throw $eventArgs.Message})
$ns=New-Object Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('e','http://www.efinixinc.com/enf_proj')
$files=@($project.SelectNodes('//e:design_file',$ns) | ForEach-Object {$_.name})
$expected=@(Get-Content "$candidate/filelist.f" | Where-Object {$_ -match '\S'} | ForEach-Object {[IO.Path]::GetFullPath((Join-Path $candidate $_)).Replace('\','/')})
$actual=@($files | Where-Object { $_.StartsWith($candidate.Replace('\','/')+'/') })
if(@(Compare-Object ($expected | Sort-Object) ($actual | Sort-Object)).Count) {throw 'Candidate source list is incomplete or duplicated'}
if($files -match '/generated/efinix_gpu/') {throw 'Stale production GPU source remained'}
if(!($actual -match '/CopyStreamEngine.sv$')) {throw 'Copy stream module not integrated'}
if(!($files -match '/rtl/board_top.v$') -or !($files -match '/vendor/.*/ddr3_top.v$')) {throw 'Board/vendor sources lost'}
if((Get-FileHash $original).Hash -ne $before) {throw 'Original project was modified'}
$includes=$project.SelectSingleNode('//e:param[@name="include"]',$ns).value.Split(';')
if($includes.Count -ne 1 -or $includes[0] -ne (Join-Path $repo 'board/efinix_ti60/vendor/sapphire_ddr3/rtl').Replace('\','/')) {throw 'Vendor include must remain a single supported directory; GPU headers are source-relative'}
foreach($file in $files) {if(!(Test-Path -LiteralPath $file)) {throw "Missing source: $file"}}
Write-Output "PASS: full candidate list ($($actual.Count) entries), board/vendor retained, original untouched, no build or JTAG. $output"
