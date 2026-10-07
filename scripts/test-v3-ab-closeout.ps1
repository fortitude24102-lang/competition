param(
 [string]$HostGcc='D:/aaa/mingw64/bin/gcc.exe',
 [string]$Python='C:/efinity/efinity/python311/bin/python.exe',
 [string]$Node='C:/Program Files/nodejs/node.exe',
 [string]$RiscvGcc='C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe',
 [string]$Out=''
)
# Software/loopback only: never opens COM/JTAG or changes board/release files.
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$priorPythonHome=$env:PYTHONHOME
$priorBytecode=$env:PYTHONDONTWRITEBYTECODE
$priorAssetServer=$env:V3_ASSET_SERVER
try {
 if(!$Out) {$Out='generated/verification/v3/ab-closeout-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')}
 if(Test-Path -LiteralPath $Out) {throw 'Refusing to overwrite an existing closeout directory'}
 New-Item -ItemType Directory -Path $Out | Out-Null
 $Out=(Resolve-Path -LiteralPath $Out).Path
 if(($Python -replace '\\','/') -like '*/efinity/python311/bin/python.exe') {
  $env:PYTHONHOME=Split-Path (Split-Path $Python)
 }
 $env:PYTHONDONTWRITEBYTECODE='1'
 function Run([string]$Name,[string]$Program,[string[]]$Arguments) {
  $priorPreference=$ErrorActionPreference
  # unittest normally uses stderr; PS5 must not mistake it for a failed test.
  $ErrorActionPreference='Continue'
  try {
   & $Program @Arguments 2>&1 | ForEach-Object {
    if($_ -is [System.Management.Automation.ErrorRecord]) {$_.Exception.Message} else {"$_"}
   } | Tee-Object (Join-Path $Out "$Name.log")
   $nativeCode=$LASTEXITCODE
  } finally {$ErrorActionPreference=$priorPreference}
  if($nativeCode -ne 0) {throw "$Name failed ($nativeCode); see $Out"}
 }
 $flags=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-pedantic',
  '-D__USE_MINGW_ANSI_STDIO=1','-ffunction-sections','-fdata-sections','-Wl,--gc-sections','-Isw/efinix_gpu/include')
 $cases=@(
  @{name='net_control';modules=@('net_control','asset_protocol');extra=@('-DNC_TEST_BACKEND')},
  @{name='input_state';modules=@('input_state')},
  @{name='r7_frozen';modules=@('bullet_demo')},
  @{name='interactive_game';modules=@('bullet_demo','interactive_game')},
  @{name='input_replay';modules=@('bullet_demo','interactive_game','replay_input')},
  @{name='v3_runtime';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input','input_state')},
  @{name='v3_ab_lifecycle';modules=@('net_control','asset_protocol','input_state','v3_runtime','bullet_demo','interactive_game','replay_input');extra=@('-DNC_TEST_BACKEND')},
  @{name='v3_capacity';modules=@('v3_runtime','bullet_demo','interactive_game','replay_input');extra=@('-DBULLET_OBJECT_CAPACITY=1024')}
 )
 foreach($case in $cases) {
  $name="test_$($case.name)"
  $sources=@("sw/efinix_gpu/tests/$name.c")+@($case.modules | ForEach-Object {"sw/efinix_gpu/src/$_.c"})
  $program=Join-Path $Out "$name.exe"
  Run "build-$name" $HostGcc ($flags+@($case.extra)+$sources+@('-o',$program))
  Run $name $program @()
 }
 Run 'dashboard' $Node @('sw/efinix_gpu/tests/test_control_dashboard.js')
 foreach($test in @('control_gateway','control_capture','control_evidence','interactive_assets')) {
  Run $test $Python @("sw/efinix_gpu/tests/test_$test.py")
 }
 $server=Join-Path $Out 'asset_server.exe'
 Run 'build-asset-server' $HostGcc ($flags+@('sw/efinix_gpu/tools/asset_server/asset_server.c',
  'sw/efinix_gpu/src/asset_protocol.c','sw/efinix_gpu/src/net_asset_server.c','-lws2_32','-o',$server))
 $env:V3_ASSET_SERVER=$server
 Run 'ab-coexistence' $Python @('sw/efinix_gpu/tests/test_v3_ab_coexistence.py')
 Run 'closeout-entry' $Python @('sw/efinix_gpu/tests/test_v3_closeout_entry.py')
 $modules=@('net_control','input_state','bullet_demo','interactive_game','replay_input','v3_runtime')
 foreach($module in $modules) {
  Run "rv32-$module" $RiscvGcc @('-std=c11','-Os','-march=rv32imac','-mabi=ilp32',
   '-Wall','-Wextra','-Werror','-Wstack-usage=2048','-fstack-usage','-Isw/efinix_gpu/include',
   '-c',"sw/efinix_gpu/src/$module.c",'-o',(Join-Path $Out "$module.rv32.o"))
 }
 Run 'rv32-size' (Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-size.exe') @($modules | ForEach-Object {Join-Path $Out "$_.rv32.o"})
 foreach($script in @('capture-v3-telemetry.ps1','test-v3-board-control.ps1','test-v3-ab-closeout.ps1')) {
  $tokens=$null;$parseErrors=$null
  [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $script),[ref]$tokens,[ref]$parseErrors) | Out-Null
  if($parseErrors.Count) {throw ($parseErrors | Out-String)}
 }
 # Bind the receipt to actual consumed sources, not to a promised branch name.
 $sources=@($modules | ForEach-Object {"sw/efinix_gpu/src/$_.c"})+
  @(Get-ChildItem sw/efinix_gpu/include -Filter *.h | ForEach-Object FullName)+
  @($cases | ForEach-Object {"sw/efinix_gpu/tests/test_$($_.name).c"})+
  @(Get-ChildItem sw/efinix_gpu/tools/control_gateway -Recurse -File | Where-Object {$_.Extension -in @('.py','.js','.html','.css')} | ForEach-Object FullName)+
  @(Get-ChildItem sw/efinix_gpu/tests -File | Where-Object {$_.Name -match '^test_(control_|v3_ab_|interactive_assets)'} | ForEach-Object FullName)+
  @('sw/efinix_gpu/src/asset_protocol.c','sw/efinix_gpu/src/net_asset_server.c',
   'sw/efinix_gpu/tools/asset_server/asset_server.c','scripts/capture-v3-telemetry.ps1',
   'scripts/test-v3-board-control.ps1','scripts/test-v3-ab-closeout.ps1',
   'sw/efinix_gpu/tests/test_v3_closeout_entry.py')
 $root=(Get-Location).Path
 $hashes=@($sources | Sort-Object -Unique | ForEach-Object {
  $hash=Get-FileHash -LiteralPath $_ -Algorithm SHA256
  @{path=$hash.Path.Substring($root.Length+1).Replace('\','/');sha256=$hash.Hash.ToLowerInvariant()}
 })
 $receipt=@{qualification='offline_software_and_simulated_loopback_only';created_utc=[DateTime]::UtcNow.ToString('o');
  c_suites=8;scheduled_live_updates=108000;additional_live_restore_updates=18;replay_updates=21600;
  comparison_rounds=18;rv32_objects=6;board_endurance=$false;board_latency=$false;
  linked_firmware=$false;rtl_rerun=$false;host_gcc=$HostGcc;python=$Python;node=$Node;riscv_gcc=$RiscvGcc;sources=$hashes}
 $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Out 'receipt.json') -Encoding UTF8
 Write-Output "PASS V3 A/B offline closeout: $Out"
 Write-Output '8 strict C suites; dashboard; capture/evidence/gateway; real PC service coexistence with SIMULATED peer; 6 RV32 objects. NOT board endurance/FPS/P95 or full firmware link.'
} finally {
 $env:PYTHONHOME=$priorPythonHome;$env:PYTHONDONTWRITEBYTECODE=$priorBytecode;$env:V3_ASSET_SERVER=$priorAssetServer
 Pop-Location
}
