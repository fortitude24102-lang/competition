param(
 [Parameter(Mandatory=$true)][string]$Bin,
 [Parameter(Mandatory=$true)][string]$Log,
 [string]$StopPattern='GLYPH_BOARD_STOP',
 [int]$Seconds=180,
 [switch]$LoadBit,
 [ValidateRange(0,15)][int]$JtagSettleSeconds=3
)
$ErrorActionPreference='Stop'
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
$logPath=[IO.Path]::GetFullPath($Log)
New-Item -ItemType Directory -Force (Split-Path $logPath) | Out-Null
if(Test-Path -LiteralPath $logPath) { throw "Refusing to overwrite measurement: $logPath" }
$serial=New-Object IO.Ports.SerialPort 'COM13',115200,'None',8,'One'
$serial.ReadTimeout=100
try {
 $serial.Open()
 # Do not let buffered telemetry from the previous firmware satisfy StopPattern.
 $serial.DiscardInBuffer()
 if($LoadBit) {
  & D:/efinity/pgm/bin/ftdi_pgm.bat D:/efinity_builds/texture_cache_20260928/outflow/efinix_2d_gpu.bit -m jtag
  if($LASTEXITCODE -ne 0) { throw 'JTAG BIT load failed' }
  # Let the reset PHY negotiate before the firmware's short UDP retry window.
  # This changes the measurement setup, not production networking behavior.
  if($JtagSettleSeconds) { Start-Sleep -Seconds $JtagSettleSeconds }
 }
 Push-Location 'D:/efinity_builds/competition_day1_20260906/sapphire/soc/bsp/efinix/EfxSapphireSoc/openocd'
 try {
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image $binPath 0x1000 bin; resume 0x1000; shutdown"
  if($LASTEXITCODE -ne 0) { throw 'JTAG firmware load failed' }
 } finally { Pop-Location }
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $tail=''
 while($timer.Elapsed.TotalSeconds -lt $Seconds) {
  $chunk=$serial.ReadExisting()
  if($chunk) {
   [IO.File]::AppendAllText($logPath,$chunk)
   Write-Output $chunk
   $tail+=$chunk
   if($tail -match 'GLYPH_BOARD_FAIL|V2 comparison stopped|HUD_DMA_FAIL') { throw 'Board firmware reported failure' }
   if($tail -match $StopPattern) { Write-Output "CAPTURE_COMPLETE: $logPath"; return }
   if($tail.Length -gt 8192) { $tail=$tail.Substring($tail.Length-4096) }
  }
  Start-Sleep -Milliseconds 20
 }
 throw "Measurement deadline reached without $StopPattern; partial log retained"
} finally { if($serial.IsOpen) { $serial.Close() }; $serial.Dispose() }
