param([string]$RiscvGcc='D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $root ('generated/verification/v3/logic-coordinate-codegen-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
& $RiscvGcc -std=gnu11 -Os -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -DV3_SHAPE_LUT=1 -DBULLET_OBJECT_CAPACITY=1024 "-I$root/sw/efinix_gpu/include" -c "$root/sw/efinix_gpu/src/bullet_demo.c" -o "$out/bullet.o"
if($LASTEXITCODE -ne 0){throw 'Game logic compilation failed'}
$objdump=Join-Path (Split-Path $RiscvGcc) 'riscv-none-elf-objdump.exe'
$step=(& $objdump -dr --disassemble=step "$out/bullet.o") -join "`n"
if($LASTEXITCODE -ne 0){throw 'Game logic disassembly failed'}
[IO.File]::WriteAllText("$out/step.asm",$step)
if($step -notmatch '<step>:'){throw 'Missing real game step'}
if($step -match 'R_RISCV_CALL[^\r\n]*pixel_coordinate'){throw "Per-object game logic still calls the division helper; see $out/step.asm"}
if(([regex]::Matches($step,'\bsrai\s+[^\r\n]+,0x8')).Count -lt 4){throw 'Game logic lost one of the four Q8 shift sites'}
Write-Output "LOGIC_COORDINATE_CODEGEN,PASS,evidence=$out"
