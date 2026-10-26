param(
 [Parameter(Mandatory=$true)][string]$Bin,
 [Parameter(Mandatory=$true)][string]$Log,
 [string]$StopPattern='GLYPH_BOARD_STOP',
 [int]$Seconds=180,
 [ValidatePattern('^COM[1-9][0-9]*$')][string]$SerialPort='COM13',
 [ValidateRange(-1,1)][int]$CopyAheadProbe=-1,
 [switch]$LoadBit,
 [ValidateRange(0,15)][int]$JtagSettleSeconds=3
)
$ErrorActionPreference='Stop'
$binPath=(Resolve-Path -LiteralPath $Bin).Path.Replace('\','/')
$logPath=[IO.Path]::GetFullPath($Log)
New-Item -ItemType Directory -Force (Split-Path $logPath) | Out-Null
if(Test-Path -LiteralPath $logPath) { throw "Refusing to overwrite measurement: $logPath" }
$serial=New-Object IO.Ports.SerialPort $SerialPort,115200,'None',8,'One'
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
  # Only the -CopyAhead terminal candidate consumes this reserved private-DDR
  # word. Set it before resume to compare old/new with one identical BIN.
  $probeSetup=if($CopyAheadProbe -ge 0){"mww 0x02d10000 $CopyAheadProbe; "}else{''}
  & D:/efinity/risc_v_gcc/openocd/bin/openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; reset halt; load_image $binPath 0x1000 bin; $($probeSetup)resume 0x1000; shutdown"
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
   if($tail -match 'GLYPH_BOARD_FAIL|V2 comparison stopped|HUD_DMA_FAIL|STRIPE_BOARD_FAIL|SPRITE_PHASE_FAIL|DASHBOARD_METRICS_FAIL|TRANSFORM_BOARD_FAIL|KEY_TRIM_BOARD_FAIL|ZOOM_STOP') { throw 'Board firmware reported failure' }
   if($tail.Substring(0,$tail.LastIndexOf("`n")+1) -match $StopPattern) { Write-Output "CAPTURE_COMPLETE: $logPath"; return }
   if($tail.Length -gt 8192) { $tail=$tail.Substring($tail.Length-4096) }
  }
  Start-Sleep -Milliseconds 20
 }
 throw "Measurement deadline reached without $StopPattern; partial log retained"
} finally { if($serial.IsOpen) { $serial.Close() }; $serial.Dispose() }
