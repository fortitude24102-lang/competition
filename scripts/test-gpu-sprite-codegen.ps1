param([string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $root ('generated/verification/v3/sprite-codegen-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
& $RiscvGcc -std=c11 -Os -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -fstack-usage "-I$root/sw/efinix_gpu/include" -c "$root/sw/efinix_gpu/src/gpu_instances.c" -o "$out/instances.o"
if($LASTEXITCODE -ne 0){throw 'GPU instance compilation failed'}
$usage=Get-Content -LiteralPath "$out/instances.su" -Raw
$sprite=[regex]::Match($usage,':sprite\t(\d+)\tstatic')
if(!$sprite.Success){throw 'Missing hot sprite stack report; inspect compiler inlining before changing this check'}
if([int]$sprite.Groups[1].Value -gt 32){throw "Per-object sprite stack exceeds 32 bytes ($($sprite.Groups[1].Value)); see $out/instances.su"}
Write-Output "GPU_SPRITE_CODEGEN,PASS,hot_stack_bytes=$($sprite.Groups[1].Value),evidence=$out"
