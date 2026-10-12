param([Parameter(Mandatory=$true)][string]$Bin,[Parameter(Mandatory=$true)][string]$Log,
 [ValidateRange(-1,1)][int]$FrameList=-1,[string]$Stop='V3_PROBE_STOP,result=0',[int]$Seconds=90)
# Qualification artifact, same setup for all cohorts. No Flash or BIT loading.
$ErrorActionPreference='Stop'
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
if($binPath -match '[{};\r\n]') {throw 'Unsafe OpenOCD path'}
$logPath=[IO.Path]::GetFullPath($Log)
if(Test-Path -LiteralPath $logPath) {throw 'Refusing to overwrite raw capture'}
$serial=New-Object IO.Ports.SerialPort 'COM9',115200,'None',8,'One'
try {
 $serial.Open();$serial.DiscardInBuffer()
 Push-Location 'D:/efinity_builds/competition_day1_20260906/sapphire/soc/bsp/efinix/EfxSapphireSoc/openocd'
 try {
  $setup=if($FrameList -ge 0){"mww 0x02d10000 1; mww 0x02d10004 $FrameList; "}else{''}
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image {$binPath} 0x1000 bin; $($setup)resume 0x1000; shutdown"
  if($LASTEXITCODE -ne 0) {throw 'JTAG firmware load failed'}
 } finally {Pop-Location}
 $timer=[Diagnostics.Stopwatch]::StartNew();$tail=''
 while($timer.Elapsed.TotalSeconds -lt $Seconds) {
  $chunk=$serial.ReadExisting()
  if($chunk) {
   [IO.File]::AppendAllText($logPath,$chunk);Write-Output $chunk;$tail+=$chunk
   if($tail -match 'V3_FAIL|V3_PROBE_HEALTH_FAIL|FRAME_LIST_BOARD_FAIL|V2 comparison stopped') {throw 'Board health/oracle failed'}
   if($tail -match $Stop) {return}
   if($tail.Length -gt 16384) {$tail=$tail.Substring($tail.Length-8192)}
  }
  Start-Sleep -Milliseconds 20
 }
 throw 'Board capture timeout; partial log retained'
} finally {if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
