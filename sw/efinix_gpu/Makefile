# Run from sw/efinix_gpu; BSP stays external and read-only.
SOC ?= D:/efinity_builds/competition_day1_20260906/sapphire/soc
TOOLCHAIN ?= D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-
CC = $(TOOLCHAIN)gcc
OBJCOPY = $(TOOLCHAIN)objcopy
BSP = $(SOC)/bsp/efinix/EfxSapphireSoc
OUT ?= ../../generated/verification/efinix-software
CFLAGS = -std=gnu11 -Os -Wall -Wextra -Werror -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -Iinclude -Iassets/v2 -isystem $(BSP)/include -isystem $(SOC)/software/standalone/driver
DEMO ?= bullet
ifeq ($(DEMO),bullet)
CFLAGS += -DBULLET_DEMO_DEFAULT=1
else ifeq ($(DEMO),legacy)
CFLAGS += -DBULLET_DEMO_DEFAULT=0
else
$(error DEMO must be bullet or legacy)
endif
CFLAGS += -Iassets/bullet
SOURCES = src/main.c src/gpu.c src/benchmark.c src/golden_renderer.c src/rgb565.c src/sparse_pack.c src/assets.c src/framebuffer.c src/hud.c src/game.c src/lane_game.c src/lane_scene.c src/asset_protocol.c src/asset_cache.c src/asset_dma.c src/net_asset_server.c src/network_assets.c src/perf_demo.c src/bullet_demo.c src/bullet_assets.c
all: $(OUT)/gpu_demo.bin $(OUT)/gpu_demo.hex
$(OUT)/gpu_demo.elf: $(SOURCES) $(wildcard include/*.h) $(wildcard assets/v2/*.h) $(wildcard assets/bullet/*.h) FORCE
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) -DUSE_GP -DNO_LIBC_INIT_ARRAY -nostartfiles -T$(BSP)/linker/default.ld -Tlinker.ld -Wl,--gc-sections -Wl,-Map,$(OUT)/gpu_demo.map $(SOC)/software/standalone/common/start.S $(SOURCES) -o $@
$(OUT)/gpu_demo.bin: $(OUT)/gpu_demo.elf
	$(OBJCOPY) -O binary $< $@
$(OUT)/gpu_demo.hex: $(OUT)/gpu_demo.elf
	$(OBJCOPY) -O ihex $< $@
.PHONY: all FORCE
FORCE:
