param(
 [string]$HostGcc='D:/aaa/mingw64/bin/gcc.exe',
 [string]$Python='C:/efinity/efinity/python311/bin/python.exe',
 [string]$IcarusHome='D:/FPGA/iverilog',
 [string]$RiscvGcc='C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Out=''
)
# Offline only: no board connection, service restart, FPGA build or release write.
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$priorPythonHome=$env:PYTHONHOME
try {
 if(!$Out) {$Out='generated/verification/gameplay-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')}
 if(Test-Path -LiteralPath $Out) {throw 'Refusing to overwrite previous verification output'}
 New-Item -ItemType Directory -Path $Out | Out-Null
 $Out=(Resolve-Path -LiteralPath $Out).Path
 if(($Python -replace '\\','/') -like '*/efinity/python311/bin/python.exe') {
  $env:PYTHONHOME=Split-Path (Split-Path $Python)
 }
 function Run([string]$Name,[string]$Program,[string[]]$Arguments) {
  $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try {
   & $Program @Arguments 2>&1 | ForEach-Object {
    if($_ -is [System.Management.Automation.ErrorRecord]) {$_.Exception.Message} else {"$_"}
   } | Tee-Object (Join-Path $Out "$Name.log")
   $code=$LASTEXITCODE
  } finally {$ErrorActionPreference=$previous}
  if($code -ne 0) {throw "$Name failed ($code); see $Out"}
 }
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror',
  '-D__USE_MINGW_ANSI_STDIO=1','-ffunction-sections','-fdata-sections','-Wl,--gc-sections','-Isw/efinix_gpu/include')
 # 13 Windows-compatible main integration suites + campaign + lifecycle.
 # The unchanged HUD/app-only tests require Linux section garbage collection;
 # keep them in test-v3-integration.ps1 rather than masking unresolved symbols.
 $cases=@(
  @{name='net_control';modules=@('net_control','asset_protocol');extra=@('-DNC_TEST_BACKEND')},
  @{name='input_state';modules=@('input_state')},
  @{name='r7_frozen';modules=@('bullet_demo')},
  @{name='interactive_game';modules=@('bullet_demo','interactive_game')},
  @{name='input_replay';modules=@('bullet_demo','interactive_game','replay_input')},
  @{name='interactive_pixels';modules=@('bullet_demo','interactive_game','replay_input','golden_renderer','rgb565')},
  @{name='v3_runtime';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input','input_state')},
  @{name='game_menu';modules=@('game_menu','gpu');extra=@('-DGPU_TEST_BACKEND')},
  @{name='v3_frame_stats';modules=@()},
  @{name='render_phase_health';modules=@()},
  @{name='v3_capacity';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input');extra=@('-DBULLET_OBJECT_CAPACITY=1024')},
  @{name='submit_validation';modules=@();extra=@('-finstrument-functions','-DGPU_SUBMIT_REVALIDATE=0')},
  @{name='submit_shadow';modules=@('gpu','bullet_demo');extra=@('-DGPU_TEST_BACKEND','-DGPU_SUBMIT_SHADOW=1')},
  @{name='enemy_campaign';modules=@('bullet_demo','interactive_game','replay_input')},
  @{name='v3_ab_lifecycle';modules=@('net_control','asset_protocol','input_state','v3_runtime','bullet_demo','interactive_game','replay_input');extra=@('-DNC_TEST_BACKEND')}
 )
 foreach($case in $cases) {
  $name="test_$($case.name)"
  $sources=@("sw/efinix_gpu/tests/$name.c")+@($case.modules | ForEach-Object {"sw/efinix_gpu/src/$_.c"})
  $exe=Join-Path $Out "$name.exe"
  Run "build-$name" $HostGcc ($flags+@($case.extra)+$sources+@('-o',$exe))
  $arguments=@();if($case.name -eq 'interactive_pixels') {$arguments=@($Out)}
  Run $name $exe $arguments
 }
 $pixel='board/efinix_ti60/rtl/pixel'
 $rtl=@("$pixel/gpu_pixel_copy.v","$pixel/gpu_pixel_fill.v","$pixel/gpu_pixel_color_key.v",
  "$pixel/gpu_pixel_alpha_blend.v","$pixel/gpu_pixel_pipe.v")
 $simulation=Join-Path $Out 'interactive.vvp'
 Run 'build-pixel-replay' "$IcarusHome/bin/iverilog.exe" (@('-g2012',"-I$pixel",'-s','tb_interactive_pixels','-o',$simulation)+$rtl+@('tb/verilog/tb_interactive_pixels.sv'))
 Run 'rtl-pixels' "$IcarusHome/bin/vvp.exe" @($simulation,"+PIXELS=$($Out.Replace('\','/'))/pixels.txt")
 Run 'preview-live' $Python @('tools/bullet_preview.py',"$Out/interactive_live.rgb565","$Out/live.png")
 Run 'preview-victory' $Python @('tools/bullet_preview.py',"$Out/victory.rgb565","$Out/victory.png")
 $modules=@('net_control','input_state','bullet_demo','interactive_game','replay_input','v3_runtime')
 foreach($module in $modules) {
  Run "rv32-$module" $RiscvGcc @('-std=c11','-Os','-march=rv32imac','-mabi=ilp32',
   '-Wall','-Wextra','-Werror','-Wstack-usage=2048','-fstack-usage','-Isw/efinix_gpu/include',
   '-c',"sw/efinix_gpu/src/$module.c",'-o',"$Out/$module.rv32.o")
 }
 Run 'rv32-size' (Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-size.exe') @($modules | ForEach-Object {"$Out/$_.rv32.o"})
 $root=(Get-Location).Path
 $sources=@($modules | ForEach-Object {"sw/efinix_gpu/src/$_.c"})+
  @(Get-ChildItem sw/efinix_gpu/include -Filter *.h | ForEach-Object FullName)+
  @($cases | ForEach-Object {"sw/efinix_gpu/tests/test_$($_.name).c"})+
  $rtl+@('tb/verilog/tb_interactive_pixels.sv','scripts/test-gameplay-upgrade.ps1')
 $hashes=@($sources | Sort-Object -Unique | ForEach-Object {
  $hash=Get-FileHash -LiteralPath $_ -Algorithm SHA256
  @{path=$hash.Path.Substring($root.Length+1).Replace('\','/');sha256=$hash.Hash.ToLowerInvariant()}
 })
 @{qualification='offline_software_and_unchanged_pixel_rtl';c_suites=$cases.Count;
  rv32_objects=$modules.Count;board_test=$false;linked_firmware=$false;sources=$hashes
 } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$Out/receipt.json" -Encoding UTF8
 Write-Output "PASS gameplay upgrade: $($cases.Count) C suites, live+WIN pixel RTL, 6 RV32 objects: $Out"
 Write-Output 'No board FPS/endurance claim. Full firmware link is a separate test-efinix-software.ps1 -FirmwareOnly -Interactive step.'
} finally {$env:PYTHONHOME=$priorPythonHome;Pop-Location}
