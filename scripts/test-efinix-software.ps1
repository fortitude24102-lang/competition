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
    Write-Output 'PASS: host sanitizer tests and official Sapphire RV32 compile probe'
} finally { Pop-Location }

