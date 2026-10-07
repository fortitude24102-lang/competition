param(
    [string]$RiscvGcc = 'D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe',
    [string]$Soc = 'D:/efinity_builds/competition_day1_20260906/sapphire/soc',
    [switch]$FirmwareOnly,
    [ValidateSet('bullet','legacy')][string]$Demo = 'bullet',
    [switch]$Profile,
    [switch]$Damage,
    [switch]$Interactive,
    [string]$OutDirectory,
    [ValidateRange(0,2048)][int]$StartCount=0,
    [ValidateSet(512,1024)][int]$ObjectCapacity=512,
    [switch]$ValidateOnce,
    [switch]$LegacyValidation,
    [switch]$ShadowSubmit,
    [switch]$FullSubmit,
    [ValidateRange(0,200000)][int]$ProbeFrames=0,
    [ValidatePattern('^0x[0-9a-fA-F]{8}$')][string]$NetworkLocalIp = '0xc0a80002',
    [ValidatePattern('^0x[0-9a-fA-F]{8}$')][string]$NetworkPeerIp = '0xc0a80003',
    [switch]$PublishRelease
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    if ($Profile -and $PublishRelease) { throw 'Profile firmware must not replace the production release.' }
    if ($Damage -and ($Profile -or $PublishRelease -or $Demo -ne 'bullet')) { throw 'Damage candidate is normal R7 firmware only; no release overwrite.' }
    if ($Interactive -and ($Profile -or $Damage -or $PublishRelease -or $Demo -ne 'bullet')) { throw 'Interactive candidate is separate from R7 profile/damage/release.' }
    if ($ValidateOnce -and $LegacyValidation) {throw 'Choose one submission path'}
    if ($ShadowSubmit -and $FullSubmit) {throw 'Choose one command-write path'}
    if ($OutDirectory -and $PublishRelease) {throw 'Separate candidate output cannot publish a release'}
    if (($StartCount -or $ProbeFrames -or $ObjectCapacity -ne 512 -or $ValidateOnce -or $LegacyValidation -or $ShadowSubmit -or $FullSubmit) -and (!$Interactive -or !$OutDirectory)) { throw 'Interactive measurement options require a separate OutDirectory.' }
    $out = if($Interactive) {'generated/verification/v3/integration'} else {'generated/verification/efinix-software'}
    if($OutDirectory) {
        $out=$OutDirectory
        if(Test-Path -LiteralPath $out) { throw 'Refusing to overwrite candidate output directory.' }
    }
    New-Item -ItemType Directory -Force $out | Out-Null
    # WSL host compiler avoids the incomplete MinGW installation on this PC.
    if (!$FirmwareOnly) {
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=undefined,address' -fno-omit-frame-pointer -Isw/efinix_gpu/include sw/efinix_gpu/tests/test_software.c sw/efinix_gpu/src/rgb565.c sw/efinix_gpu/src/golden_renderer.c -o "$out/test_software"
    if ($LASTEXITCODE -ne 0) { throw 'Host compilation failed' }
    & wsl "./$out/test_software" "$out/reference.rgb565"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed' }
    $common = @('-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-march=rv32im_zicsr', '-mabi=ilp32', '-ffreestanding', '-Isw/efinix_gpu/include', '-Iboard/efinix_ti60/vendor/sapphire_ddr3/par/ddr_demo_ti60/embedded_sw/include')
    foreach ($source in @('src/rgb565.c', 'src/golden_renderer.c', 'tests/sapphire_probe.c')) {
        $name = [IO.Path]::GetFileNameWithoutExtension($source)
        & $RiscvGcc @common -c "sw/efinix_gpu/$source" -o "$out/$name.o"
        if ($LASTEXITCODE -ne 0) { throw "RV32 compilation failed: $source" }
}
    foreach ($test in @('driver','copy','benchmark','texture_cache')) {
        $sources = @("sw/efinix_gpu/tests/test_$test.c", 'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
        if ($test -ne 'copy') { $sources += 'sw/efinix_gpu/src/gpu.c' }
        if ($test -eq 'benchmark') { $sources += 'sw/efinix_gpu/src/benchmark.c' }
        & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @sources -o "$out/test_$test"
        if ($LASTEXITCODE -ne 0) { throw "Host compile failed: $test" }
        & wsl "./$out/test_$test"
        if ($LASTEXITCODE -ne 0) { throw "Host tests failed: $test" }
    }
    $daySources = @('sw/efinix_gpu/tests/test_day9_13.c', 'sw/efinix_gpu/src/gpu.c',
        'sw/efinix_gpu/src/assets.c', 'sw/efinix_gpu/src/sparse_pack.c', 'sw/efinix_gpu/src/framebuffer.c',
        'sw/efinix_gpu/src/hud.c', 'sw/efinix_gpu/src/game.c',
        'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @daySources -o "$out/test_day9_13"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: day9_13' }
    & wsl "./$out/test_day9_13"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: day9_13' }
    $lateSources = @('sw/efinix_gpu/tests/test_days16_20.c', 'sw/efinix_gpu/src/gpu.c',
        'sw/efinix_gpu/src/assets.c', 'sw/efinix_gpu/src/sparse_pack.c', 'sw/efinix_gpu/src/benchmark.c',
        'sw/efinix_gpu/src/game.c', 'sw/efinix_gpu/src/hud.c',
        'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @lateSources -o "$out/test_days16_20"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: days16_20' }
    & wsl "./$out/test_days16_20"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: days16_20' }
    $sparseSources = @('sw/efinix_gpu/tests/test_sparse.c',
        'sw/efinix_gpu/src/sparse_pack.c', 'sw/efinix_gpu/src/assets.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -Isw/efinix_gpu/include @sparseSources -o "$out/test_sparse"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: sparse' }
    & wsl "./$out/test_sparse"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: sparse' }
    $finalSources = @('sw/efinix_gpu/tests/test_days21_23.c', 'sw/efinix_gpu/src/gpu.c',
        'sw/efinix_gpu/src/benchmark.c', 'sw/efinix_gpu/src/game.c',
        'sw/efinix_gpu/src/assets.c', 'sw/efinix_gpu/src/sparse_pack.c',
        'sw/efinix_gpu/src/hud.c', 'sw/efinix_gpu/src/golden_renderer.c',
        'sw/efinix_gpu/src/rgb565.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @finalSources -o "$out/test_days21_23"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: days21_23' }
    & wsl "./$out/test_days21_23"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: days21_23' }
    }
    $bsp = "$Soc/bsp/efinix/EfxSapphireSoc"
    if (!(Test-Path "$bsp/linker/default.ld")) { throw "Complete external Sapphire BSP missing: $Soc" }
    $sourceLine = Get-Content 'sw/efinix_gpu/Makefile' | Where-Object { $_ -match '^SOURCES = ' }
    $firmwareSources = @(($sourceLine -replace '^SOURCES = ', '') -split '\s+' | ForEach-Object { "sw/efinix_gpu/$_" })
    $sceneFlag = if ($Demo -eq 'bullet') { '-DBULLET_DEMO_DEFAULT=1' } else { '-DBULLET_DEMO_DEFAULT=0' }
    $profileFlag = @()
    if ($Profile) { $profileFlag += '-DV2_PROFILE' }
    if ($Damage) { $profileFlag += '-DV3_GPU_DAMAGE=1' }
    if ($Interactive) { $profileFlag += '-DV3_INTERACTIVE=1' }
    if ($StartCount) { $profileFlag += "-DV3_START_COUNT=$StartCount" }
    if ($ProbeFrames) { $profileFlag += "-DV3_PROBE_FRAMES=$ProbeFrames" }
    $profileFlag += "-DBULLET_OBJECT_CAPACITY=$ObjectCapacity"
    if($ValidateOnce) {$profileFlag += '-DGPU_SUBMIT_REVALIDATE=0'}
    if($ShadowSubmit) {$profileFlag += '-DGPU_SUBMIT_SHADOW=1'}
    if($FullSubmit) {$profileFlag += '-DGPU_SUBMIT_SHADOW=0'}
    if($LegacyValidation) {$profileFlag += '-DGPU_SUBMIT_REVALIDATE=1'}
    & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections "-DNETWORK_LOCAL_IP=$NetworkLocalIp" "-DNETWORK_PEER_IP=$NetworkPeerIp" $sceneFlag @profileFlag -Isw/efinix_gpu/include -Isw/efinix_gpu/assets/v2 -Isw/efinix_gpu/assets/bullet -isystem "$bsp/include" -isystem "$soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "-Wl,-Map,$out/gpu_demo.map" "$soc/software/standalone/common/start.S" @firmwareSources -o "$out/gpu_demo.elf"
    if ($LASTEXITCODE -ne 0) { throw 'Sapphire ELF link failed' }
    $objcopy = Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-objcopy.exe'
    foreach ($format in @(@('binary','bin'),@('ihex','hex'))) {
        & $objcopy -O $format[0] "$out/gpu_demo.elf" "$out/gpu_demo.$($format[1])"
        if ($LASTEXITCODE -ne 0) { throw "objcopy failed: $($format[0])" }
    }
    if ($PublishRelease) {
    $release = 'release'
    New-Item -ItemType Directory -Force $release | Out-Null
    foreach ($extension in @('elf','bin','hex')) {
        Copy-Item -LiteralPath "$out/gpu_demo.$extension" -Destination "$release/gpu_demo.$extension" -Force
    }
    $hashLines = foreach ($extension in @('elf','bin','hex')) {
        $file = "$release/gpu_demo.$extension"
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  gpu_demo.$extension"
    }
    [IO.File]::WriteAllLines((Join-Path $root 'release/software.sha256'), $hashLines)
    }
    if (!$FirmwareOnly) { Write-Output 'PASS: host sanitizer tests, production driver/model/benchmark/copy' }
    Write-Output "PASS: Sapphire ELF/BIN/Intel HEX; scene=$Demo profile=$Profile local=$NetworkLocalIp peer=$NetworkPeerIp (not board executed)"
} finally { Pop-Location }
