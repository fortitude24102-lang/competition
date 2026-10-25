param([string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $root ('generated/verification/v3/coordinate-codegen-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
& $RiscvGcc -std=c11 -Os -march=rv32im_zicsr -mabi=ilp32 -ffreestanding "-I$root/sw/efinix_gpu/include" -c "$root/sw/efinix_gpu/src/gpu_instances.c" -o "$out/instances.o"
if($LASTEXITCODE -ne 0){throw 'GPU instance compilation failed'}
$objdump=Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-objdump.exe'
$assembly=(& $objdump -d "$out/instances.o") -join "`n"
if($LASTEXITCODE -ne 0){throw 'GPU instance disassembly failed'}
[IO.File]::WriteAllText("$out/instances.asm",$assembly)
if($assembly -notmatch '<gpu_instances_build_into>:'){throw 'Missing production GPU builder'}
# Inspect every block, including an outlined helper's negative-coordinate branch.
if($assembly -match '\bdivu?\s'){throw "GPU instance module still executes division; see $out/instances.asm"}
Write-Output "GPU_COORDINATE_CODEGEN,PASS,evidence=$out"
