param(
 [string]$ServerPath='',
 [string]$Manifest='sw/efinix_gpu/assets/bullet/manifest.csv',
 [ValidateRange(1,65535)][int]$Port=8080,
 [string]$PcAddress='192.168.1.2'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent

function Full-Path([string]$path) {
 if([IO.Path]::IsPathRooted($path)) { return [IO.Path]::GetFullPath($path) }
 return [IO.Path]::GetFullPath((Join-Path $root $path))
}

if(!$ServerPath) {
 foreach($candidate in @('generated/verification/v2-network-software/asset_server.exe','release/v2/asset_server.exe')) {
  if(Test-Path -LiteralPath (Full-Path $candidate) -PathType Leaf) { $ServerPath=$candidate; break }
 }
}
$server=Full-Path $ServerPath
$manifestPath=Full-Path $Manifest
if(!(Test-Path -LiteralPath $server -PathType Leaf)) { throw "asset server not found: $server" }
if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "asset manifest not found: $manifestPath" }

$manifestRoot=Split-Path $manifestPath -Parent
foreach($line in [IO.File]::ReadAllLines($manifestPath)) {
 $line=$line.Trim()
 if(!$line -or $line.StartsWith('#')) { continue }
 $fields=$line.Split(',')
 [uint32]$id=0
 if($fields.Count -ne 2 -or ![uint32]::TryParse($fields[0].Trim(),[ref]$id) -or !$fields[1].Trim()) {
  throw "invalid manifest row: $line"
 }
 $resource=[IO.Path]::GetFullPath((Join-Path $manifestRoot $fields[1].Trim()))
 if(!(Test-Path -LiteralPath $resource -PathType Leaf)) { throw "manifest resource not found: $resource" }
}

[Net.IPAddress]$parsed=$null
if(![Net.IPAddress]::TryParse($PcAddress,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
 throw "invalid IPv4 address: $PcAddress"
}
$local=Get-NetIPAddress -AddressFamily IPv4 -IPAddress $PcAddress -ErrorAction SilentlyContinue |
 Where-Object AddressState -eq 'Preferred' | Select-Object -First 1
if(!$local) { throw "IPv4 address is not assigned locally: $PcAddress" }

$endpoints=@(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
if($endpoints) {
 $owners=@($endpoints.OwningProcess | Sort-Object -Unique)
 if($owners.Count -ne 1) { throw "UDP $Port is already owned by multiple processes: $($owners -join ',')" }
 $owner=Get-Process -Id $owners[0] -ErrorAction Stop
 $ownerPath=if($owner.Path){[IO.Path]::GetFullPath($owner.Path)}else{'<unavailable>'}
 if($ownerPath.Equals($server,[StringComparison]::OrdinalIgnoreCase)) {
  Write-Output "ASST server already running: PID=$($owner.Id) path=$ownerPath UDP=$Port"
  return
 }
 throw "UDP $Port is already owned by PID=$($owner.Id) path=$ownerPath"
}

Write-Output "ASST foreground server: path=$server manifest=$manifestPath PC=$PcAddress UDP=$Port"
Write-Output 'Keep this terminal open during board use. For firewall guidance see docs/efinix_2d_gpu/bullet_demo_usage.md.'
& $server $manifestPath $Port
if($LASTEXITCODE -ne 0) { throw "asset server exited with code $LASTEXITCODE" }
