param([Parameter(Mandatory=$true)][string]$Bin,[Parameter(Mandatory=$true)][string]$Log,
 [string]$SerialPort='COM9',[ValidateRange(0,1)][int]$LogicCopy=0,
 [ValidateSet(0,256)][int]$SealWords=0,[int]$Seconds=90,[ValidateRange(0,1)][int]$HudList=0,
 [ValidateRange(0,1)][int]$HudDirect=0)
# Terminal candidate only: identical BIN, old/new scheduling selected before
# resume; original CopyAhead/list flags fixed on. JTAG RAM only, never Flash.
$ErrorActionPreference='Stop'
function Assert-ProbeIdentity([string]$Raw,[int]$LogicCopy,[int]$SealWords,[int]$HudList=0,[bool]$RequireHudIdentity=$false,[int]$HudDirect=0,[bool]$RequireDirectIdentity=$false) {
 $logic=[regex]::Matches($Raw,'(?m)^V3_LOGIC_COPY,enabled=(\d+)\r?$')
 $list=[regex]::Matches($Raw,'(?m)^V3_FRAME_LIST,present=1,enabled=1\r?$')
 $seal=[regex]::Matches($Raw,'(?m)^V3_SEAL_BUDGET,words=(\d+)\r?$')
 $hud=[regex]::Matches($Raw,'(?m)^V3_HUD_LIST,enabled=(\d+)\r?$')
 $direct=[regex]::Matches($Raw,'(?m)^V3_HUD_DIRECT,enabled=(\d+)\r?$')
 if($logic.Count -ne 1 -or $list.Count -ne 1 -or [int]$logic[0].Groups[1].Value -ne $LogicCopy) {throw 'Candidate path identity mismatch'}
 if($seal.Count -gt 1 -or (!$seal.Count -and $SealWords) -or
    ($seal.Count -eq 1 -and [int]$seal[0].Groups[1].Value -ne $SealWords)) {throw 'Seal candidate identity mismatch'}
 if($hud.Count -gt 1 -or (!$hud.Count -and ($HudList -or $RequireHudIdentity)) -or
    ($hud.Count -eq 1 -and [int]$hud[0].Groups[1].Value -ne $HudList)) {throw 'HUD candidate identity mismatch'}
 if($direct.Count -gt 1 -or (!$direct.Count -and ($HudDirect -or $RequireDirectIdentity)) -or
    ($direct.Count -eq 1 -and [int]$direct[0].Groups[1].Value -ne $HudDirect)) {throw 'Direct HUD candidate identity mismatch'}
}
$requireHudIdentity=$PSBoundParameters.ContainsKey('HudList')
$requireDirectIdentity=$PSBoundParameters.ContainsKey('HudDirect')
if($HudList -and $HudDirect){throw 'Choose one HUD candidate'}
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
if($binPath -match '[{};\r\n]'){throw 'Unsafe OpenOCD path'}
$logPath=[IO.Path]::GetFullPath($Log)
if(Test-Path -LiteralPath $logPath){throw 'Refusing to overwrite raw capture'}
$serial=New-Object IO.Ports.SerialPort $SerialPort,115200,'None',8,'One'
try {
 $serial.Open();$serial.DiscardInBuffer()
 Push-Location 'D:/efinity_builds/competition_day1_20260906/sapphire/soc/bsp/efinix/EfxSapphireSoc/openocd'
 try {
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image {$binPath} 0x1000 bin; mww 0x02d10000 1; mww 0x02d10004 1; mww 0x02d10008 $LogicCopy; mww 0x02d1000c $SealWords; mww 0x02d10010 $HudList; mww 0x02d10014 $HudDirect; resume 0x1000; shutdown"
  if($LASTEXITCODE -ne 0){throw 'JTAG firmware load failed'}
 } finally {Pop-Location}
 $timer=[Diagnostics.Stopwatch]::StartNew();$tail=''
 while($timer.Elapsed.TotalSeconds -lt $Seconds) {
  $chunk=$serial.ReadExisting()
  if($chunk) {
   [IO.File]::AppendAllText($logPath,$chunk);Write-Output $chunk;$tail+=$chunk
   if($tail -match 'V3_FAIL|V3_PROBE_HEALTH_FAIL|V2 comparison stopped'){throw 'Board health failed'}
   if($tail -match '(?m)^V3_PROBE_STOP,result=0\r?\n') {
    Assert-ProbeIdentity $tail $LogicCopy $SealWords $HudList $requireHudIdentity $HudDirect $requireDirectIdentity
    return
   }
  }
  Start-Sleep -Milliseconds 20
 }
 throw 'Board capture timeout; partial log retained'
} finally {if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
