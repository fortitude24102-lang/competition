param([Parameter(Mandatory=$true)][string]$Bin,[Parameter(Mandatory=$true)][string]$Log,
 [string]$SerialPort='COM9',[ValidateRange(0,1)][int]$LogicCopy=0,
 [ValidateSet(0,256)][int]$SealWords=0,[int]$Seconds=90)
# Terminal candidate only: identical BIN, old/new scheduling selected before
# resume; original CopyAhead/list flags fixed on. JTAG RAM only, never Flash.
$ErrorActionPreference='Stop'
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
if($binPath -match '[{};\r\n]'){throw 'Unsafe OpenOCD path'}
$logPath=[IO.Path]::GetFullPath($Log)
if(Test-Path -LiteralPath $logPath){throw 'Refusing to overwrite raw capture'}
$serial=New-Object IO.Ports.SerialPort $SerialPort,115200,'None',8,'One'
try {
 $serial.Open();$serial.DiscardInBuffer()
 Push-Location 'D:/efinity_builds/competition_day1_20260906/sapphire/soc/bsp/efinix/EfxSapphireSoc/openocd'
 try {
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image {$binPath} 0x1000 bin; mww 0x02d10000 1; mww 0x02d10004 1; mww 0x02d10008 $LogicCopy; mww 0x02d1000c $SealWords; resume 0x1000; shutdown"
  if($LASTEXITCODE -ne 0){throw 'JTAG firmware load failed'}
 } finally {Pop-Location}
 $timer=[Diagnostics.Stopwatch]::StartNew();$tail=''
 while($timer.Elapsed.TotalSeconds -lt $Seconds) {
  $chunk=$serial.ReadExisting()
  if($chunk) {
   [IO.File]::AppendAllText($logPath,$chunk);Write-Output $chunk;$tail+=$chunk
   if($tail -match 'V3_FAIL|V3_PROBE_HEALTH_FAIL|V2 comparison stopped'){throw 'Board health failed'}
   if($tail -match 'V3_PROBE_STOP,result=0') {
    if($tail -notmatch "V3_LOGIC_COPY,enabled=$LogicCopy" -or $tail -notmatch 'V3_FRAME_LIST,present=1,enabled=1') {throw 'Candidate path identity mismatch'}
    if($SealWords -and $tail -notmatch "V3_SEAL_BUDGET,words=$SealWords") {throw 'Seal candidate identity mismatch'}
    return
   }
  }
  Start-Sleep -Milliseconds 20
 }
 throw 'Board capture timeout; partial log retained'
} finally {if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
