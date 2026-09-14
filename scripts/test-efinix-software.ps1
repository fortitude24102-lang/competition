param(
    [string]$RiscvGcc = 'D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $out = 'generated/verification/efinix-software'
    New-Item -ItemType Directory -Force $out | Out-Null
    # WSL host compiler avoids the incomplete MinGW installation on this PC.
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
    foreach ($test in @('driver','copy','benchmark')) {
        $sources = @("sw/efinix_gpu/tests/test_$test.c", 'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
        if ($test -ne 'copy') { $sources += 'sw/efinix_gpu/src/gpu.c' }
        if ($test -eq 'benchmark') { $sources += 'sw/efinix_gpu/src/benchmark.c' }
        & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @sources -o "$out/test_$test"
        if ($LASTEXITCODE -ne 0) { throw "Host compile failed: $test" }
        & wsl "./$out/test_$test"
        if ($LASTEXITCODE -ne 0) { throw "Host tests failed: $test" }
    }
    $daySources = @('sw/efinix_gpu/tests/test_day9_13.c', 'sw/efinix_gpu/src/gpu.c',
        'sw/efinix_gpu/src/assets.c', 'sw/efinix_gpu/src/framebuffer.c',
        'sw/efinix_gpu/src/hud.c', 'sw/efinix_gpu/src/game.c',
        'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @daySources -o "$out/test_day9_13"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: day9_13' }
    & wsl "./$out/test_day9_13"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: day9_13' }
    $lateSources = @('sw/efinix_gpu/tests/test_days16_20.c', 'sw/efinix_gpu/src/gpu.c',
        'sw/efinix_gpu/src/assets.c', 'sw/efinix_gpu/src/benchmark.c',
        'sw/efinix_gpu/src/game.c', 'sw/efinix_gpu/src/hud.c',
        'sw/efinix_gpu/src/golden_renderer.c', 'sw/efinix_gpu/src/rgb565.c')
    & wsl gcc -std=c11 -O2 -Wall -Wextra -Werror '-fsanitize=address,undefined' -fno-omit-frame-pointer -DGPU_TEST_BACKEND -Isw/efinix_gpu/include @lateSources -o "$out/test_days16_20"
    if ($LASTEXITCODE -ne 0) { throw 'Host compile failed: days16_20' }
    & wsl "./$out/test_days16_20"
    if ($LASTEXITCODE -ne 0) { throw 'Host tests failed: days16_20' }
    $soc = 'D:/efinity_builds/competition_day1_20260906/sapphire/soc'
    $bsp = "$soc/bsp/efinix/EfxSapphireSoc"
    if (!(Test-Path "$bsp/linker/default.ld")) { throw "Complete external Sapphire BSP missing: $soc" }
    & $RiscvGcc -std=gnu11 -Os -Wall -Wextra -Werror '-Wstack-usage=2048' -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -Isw/efinix_gpu/include -isystem "$bsp/include" -isystem "$soc/software/standalone/driver" -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles "-T$bsp/linker/default.ld" '-Tsw/efinix_gpu/linker.ld' '-Wl,--gc-sections' "-Wl,-Map,$out/gpu_demo.map" "$soc/software/standalone/common/start.S" sw/efinix_gpu/src/main.c sw/efinix_gpu/src/gpu.c sw/efinix_gpu/src/benchmark.c sw/efinix_gpu/src/golden_renderer.c sw/efinix_gpu/src/rgb565.c sw/efinix_gpu/src/assets.c sw/efinix_gpu/src/framebuffer.c sw/efinix_gpu/src/hud.c sw/efinix_gpu/src/game.c -o "$out/gpu_demo.elf"
    if ($LASTEXITCODE -ne 0) { throw 'Sapphire ELF link failed' }
    $objcopy = Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-objcopy.exe'
    foreach ($format in @(@('binary','bin'),@('ihex','hex'))) {
        & $objcopy -O $format[0] "$out/gpu_demo.elf" "$out/gpu_demo.$($format[1])"
        if ($LASTEXITCODE -ne 0) { throw "objcopy failed: $($format[0])" }
    }
    Write-Output 'PASS: host sanitizer tests, production driver/model/benchmark/copy, Sapphire ELF/BIN/Intel HEX (not board executed)'
} finally { Pop-Location }
