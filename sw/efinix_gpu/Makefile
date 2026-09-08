# Run from sw/efinix_gpu; BSP stays external and read-only.
SOC ?= D:/efinity_builds/competition_day1_20260906/sapphire/soc
TOOLCHAIN ?= D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-
CC = $(TOOLCHAIN)gcc
OBJCOPY = $(TOOLCHAIN)objcopy
BSP = $(SOC)/bsp/efinix/EfxSapphireSoc
OUT ?= ../../generated/verification/efinix-software
CFLAGS = -std=gnu11 -Os -Wall -Wextra -Werror -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -Iinclude -isystem $(BSP)/include -isystem $(SOC)/software/standalone/driver
SOURCES = src/main.c src/gpu.c src/benchmark.c src/golden_renderer.c src/rgb565.c
all: $(OUT)/gpu_demo.bin $(OUT)/gpu_demo.hex
$(OUT)/gpu_demo.elf: $(SOURCES) $(wildcard include/*.h)
	$(CC) $(CFLAGS) -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles -T$(BSP)/linker/default.ld -Wl,--gc-sections -Wl,-Map,$(OUT)/gpu_demo.map $(SOC)/software/standalone/common/start.S $(SOURCES) -o $@
$(OUT)/gpu_demo.bin: $(OUT)/gpu_demo.elf
	$(OBJCOPY) -O binary $< $@
$(OUT)/gpu_demo.hex: $(OUT)/gpu_demo.elf
	$(OBJCOPY) -O ihex $< $@
.PHONY: all
