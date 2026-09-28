param([string]$ServerPath='generated/verification/v2-network-software/asset_server.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$launcher=Join-Path $PSScriptRoot 'run-bullet-asset-server.ps1'
$server=[IO.Path]::GetFullPath((Join-Path $root $ServerPath))
$temp=Join-Path ([IO.Path]::GetTempPath()) ("bullet-server-launcher-"+[guid]::NewGuid().ToString('N'))
$processes=[Collections.Generic.List[Diagnostics.Process]]::new()

function Free-Port {
 $probe=[Net.Sockets.UdpClient]::new(0)
 try { return ([Net.IPEndPoint]$probe.Client.LocalEndPoint).Port } finally { $probe.Dispose() }
}
function Wait-Owner([int]$port) {
 $limit=[DateTime]::UtcNow.AddSeconds(5)
 do {
  $endpoint=Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if($endpoint) { return [int]$endpoint.OwningProcess }
  Start-Sleep -Milliseconds 50
 } while([DateTime]::UtcNow -lt $limit)
 throw "UDP $port did not become ready"
}
function Run-Launcher([string[]]$arguments) {
 $saved=$ErrorActionPreference
 try {
  $ErrorActionPreference='Continue'
  $output=& powershell -NoProfile -ExecutionPolicy Bypass -File $launcher @arguments 2>&1
  return @{Code=$LASTEXITCODE;Text=($output -join "`n")}
 } finally { $ErrorActionPreference=$saved }
}
function Assert-Fails([string[]]$arguments,[string]$needle) {
 $result=Run-Launcher $arguments
 if($result.Code -eq 0 -or $result.Text -notlike "*$needle*") {
  throw "expected launcher failure containing '$needle', got code=$($result.Code): $($result.Text)"
 }
}

try {
 if(!(Test-Path -LiteralPath $server -PathType Leaf)) { throw "missing test server: $server" }
 if(!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "missing launcher: $launcher" }
 [IO.Directory]::CreateDirectory($temp) | Out-Null
 $asset=Join-Path $temp 'asset.bin'; [IO.File]::WriteAllBytes($asset,[byte[]](1,2,3,4))
 $manifest=Join-Path $temp 'manifest.csv'; [IO.File]::WriteAllText($manifest,"7,asset.bin`n",[Text.Encoding]::ASCII)

 $port=Free-Port
 $stdout=Join-Path $temp 'server.out'; $stderr=Join-Path $temp 'server.err'
 $wrapper=Start-Process powershell -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,
   '-ServerPath',$server,'-Manifest',$manifest,'-Port',$port,'-PcAddress','127.0.0.1')
 $processes.Add($wrapper)
 $owner=Wait-Owner $port
 if($wrapper.HasExited) { throw "foreground wrapper exited early: $([IO.File]::ReadAllText($stderr))" }
 $ownerPath=(Get-Process -Id $owner).Path
 if([IO.Path]::GetFullPath($ownerPath) -ne $server) { throw "wrong UDP owner: $ownerPath" }

 $again=Run-Launcher @('-ServerPath',$server,'-Manifest',$manifest,'-Port',"$port",'-PcAddress','127.0.0.1')
 if($again.Code -ne 0 -or $again.Text -notlike '*already running*') { throw "duplicate detection failed: $($again.Text)" }
 if((Wait-Owner $port) -ne $owner) { throw 'duplicate invocation replaced the original server' }

 Stop-Process -Id $owner -Force
 if(!$wrapper.WaitForExit(5000)) { throw 'wrapper did not exit with its foreground server' }

 $foreignPort=Free-Port
 $holder="`$u=[Net.Sockets.UdpClient]::new($foreignPort);try{Start-Sleep -Seconds 60}finally{`$u.Dispose()}"
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($holder))
 $foreign=Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-EncodedCommand',$encoded)
 $processes.Add($foreign)
 Wait-Owner $foreignPort | Out-Null
 Assert-Fails @('-ServerPath',$server,'-Manifest',$manifest,'-Port',"$foreignPort",'-PcAddress','127.0.0.1') 'already owned'
 if($foreign.HasExited) { throw 'launcher terminated the foreign UDP owner' }

 Assert-Fails @('-ServerPath',$server,'-Manifest',(Join-Path $temp 'missing.csv'),'-Port',"$(Free-Port)",'-PcAddress','127.0.0.1') 'manifest'
 $badManifest=Join-Path $temp 'bad.csv'; [IO.File]::WriteAllText($badManifest,"8,missing.bin`n",[Text.Encoding]::ASCII)
 Assert-Fails @('-ServerPath',$server,'-Manifest',$badManifest,'-Port',"$(Free-Port)",'-PcAddress','127.0.0.1') 'resource'
 Assert-Fails @('-ServerPath',$server,'-Manifest',$manifest,'-Port',"$(Free-Port)",'-PcAddress','192.0.2.123') 'not assigned'
 Write-Output 'PASS bullet asset server launcher: foreground, duplicate, foreign owner, inputs'
} finally {
 foreach($process in $processes) {
  if(!$process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
 }
 if(Test-Path -LiteralPath $temp) {
  $resolved=[IO.Path]::GetFullPath($temp)
  if(!$resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) {
   throw "refusing to remove non-temporary path: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
