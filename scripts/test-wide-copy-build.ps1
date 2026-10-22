$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path $projectRoot ('generated/verification/v3/wide-copy-20261022/build-check-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
function Check-Selection([string]$name,[bool]$ports,[Nullable[bool]]$manifest,[bool]$pass) {
 $source=Join-Path $testRoot $name
 New-Item -ItemType Directory -Path $source -Force | Out-Null
 $signature=if($ports){'input io_fabricReset,input [127:0] io_legacyDdr_w_bits_data,output [127:0] io_wideDdr_w_bits_data'}else{'input clock,input reset'}
 [IO.File]::WriteAllText((Join-Path $source 'Efinix2dGpuTop.sv'),"module Efinix2dGpuTop($signature); endmodule`n")
 [IO.File]::WriteAllText((Join-Path $source 'filelist.f'),"Efinix2dGpuTop.sv`n")
 if($null -ne $manifest){[IO.File]::WriteAllText((Join-Path $source 'gpu-build.json'),(@{wideCopyDma=[bool]$manifest}|ConvertTo-Json))}
 $output=Join-Path $testRoot ($name+'-board')
 $failed=$false
 try { & (Join-Path $PSScriptRoot 'test-efinix-board.ps1') -GpuRtlDirectory $source -OutputDirectory $output -PrepareOnly | Out-Null } catch {$failed=$true}
 if($pass -eq $failed){throw "Build selection ${name}: expected accepted=$pass, observed rejected=$failed"}
 if($pass) {
  [xml]$xml=Get-Content (Join-Path $output 'efinix_2d_gpu.xml')
  $adapter=@($xml.SelectNodes('//*[local-name()="design_file"]') | Where-Object {$_.name -match 'efinix_sapphire_adapter.v$'})
  if($adapter.Count -ne 1){throw 'Selected project must contain exactly one adapter'}
  # Inspect the EFFECTIVE selected project, not the preparation script's source.
  $enabled=@($xml.SelectNodes('//*[local-name()="defmacro"]') | Where-Object {$_.name -eq 'GPU_WIDE_COPY_DMA' -and $_.value -eq '1'}).Count -eq 1
  if($enabled -ne $ports){throw "Wrong effective board wiring for $name"}
 }
 Write-Output "PASS selection $name"
}
Check-Selection 'legacy' $false $null $true
Check-Selection 'wide' $true $true $true
Check-Selection 'wide-missing-manifest' $true $null $false
Check-Selection 'wide-disabled-manifest' $true $false $false
Check-Selection 'enabled-missing-ports' $false $true $false
Write-Output "WIDE_COPY_BUILD,PASS,evidence=$testRoot"
