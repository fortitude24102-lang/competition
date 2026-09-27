# 100KBBH-inspired rendering candidate — A-work

## Scope

Software-only 960x540 RGB565 bullet showcase using the existing board-tested
Sapphire/GPU/DDR/HDMI design. Fixed-point ring, downward fan and spiral emitters,
six 8x8 keyed bullet shapes, a fixed 16x16 player marker, three small Alpha tiles and
three downward-facing 16x16 aircraft emitters, over an
original star/circuit arena background and a small ship marker. No character input, collision, score or complete game
yet. UART/network keyboard input remains a future independent task.

100KBBH is a reference, not an engine port. This implementation and procedural
art are independently authored; no Windows/OpenGL dependency or upstream code
is embedded. The original project license is MIT; any future actual source/art
reuse must retain relevant notices and check individual asset permissions.

Hardware and release/v2 remain identical to main a82f3dd. The A-work baseline
merge imports main's already-tested changes; the feature itself modifies no
RTL, Chisel, pins, clocks, GPU registers/opcodes or bitstream.

## Build / run later on the board

From repository root in PowerShell:

```powershell
./scripts/build-bullet-firmware.ps1 -Demo bullet
./scripts/build-bullet-firmware.ps1 -Demo legacy
```

Override -RiscvGcc and -Soc if the official toolchain/BSP lives elsewhere.
Defaults use C:/efinity/riscv and the user's local official co_debug Demo BSP.
Output goes to generated/verification/bullet-demo/firmware-bullet or
firmware-legacy, never over a board-tested release. ELF/BIN/HEX are candidates;
build success does not mean board validation.

The defaults retain the Sept26 network configuration:
board 192.168.1.3, PC 192.168.1.2, UDP 8080. Both are configurable with
-NetworkLocalIp and -NetworkPeerIp. No PC IP/firewall changes are automated.
Use an existing V2 asset_server.exe or the newly regression-built Windows
server, with:

```powershell
./release/v2/asset_server.exe ./sw/efinix_gpu/assets/bullet/manifest.csv 8080
```

For legacy firmware use assets/v2/manifest.csv instead. The new IDs 101/102
reuse the current GET/DATA protocol, packet CRC protection and asset DMA.
The renderer uses network destinations only after both full-file CRC checks
succeed. Local fallback uses background 0x02b00000 and atlas 0x02c00000,
disjoint from network DMA destinations 0x02900000/0x02a00000. Thus even an
abort timeout with accepted writes still draining cannot overwrite fallback.
Any partial-load failure regenerates both local resources and shows
NET FAIL FALLBACK; this is not network acceptance.

Use the V2 temporary JTAG bitstream/load procedure with the freshly selected
firmware, not a V1 bitstream. No board is currently available: physical download
and display/keys/network behavior are still unverified. Do not flash this
candidate as part of offline testing.

Makefile alternative: DEMO=bullet (default), or DEMO=legacy; supply your SOC and
TOOLCHAIN paths. Rebuild on mode switches; FORCE prevents stale mode binaries.
The older test-efinix-software.ps1 intentionally builds legacy to preserve its
baseline purpose; use the new native scripts on this machine without WSL.

## Measurement rules

- KEY1/KEY2 only select 32/64/128/256/512 target slots; they do not move the player.
- HUD BULLETS is the number actually clipped into the visible playfield, excluding
  player/emitters. Target slots are not a claimed simultaneous visible count.
- CPU and GPU each render 30 frames of the same saved state, then the next window
  advances. The sequence resets after 600 logical frames. It never depends on
  measured wall-clock frame duration. No quadratic per-frame replay rebuilding.
- Both use the same commands/assets and common CPU-rendered HUD. FPS includes
  HUD and PRESENT; RENDER MS is scene rendering only. Untested scores show --.
- UFL is cumulative hardware underflows; ERR is the current GPU hardware error.
- BULLET_GPU_300 collects GPU samples across alternating windows. Its
  windowed_60fps flag is NOT proof of 300 uninterrupted 60-FPS frames. Formal
  continuous-load/endurance acceptance still needs a board and dedicated run.
- 8x8 bullets touch 64 source pixels versus 5,120 for the old 64x80 sprites
  (80x fewer per full sprite). Background still copies all 518,400 pixels and
  HUD is still copied in full. In R2, visible text changes rebuild a 960x72
  raster at 0x02c10000 (138,240 bytes); each frame uses one common CPU COPY,
  rather than hundreds of glyph FILL commands. This is NOT a measured FPS gain;
  compare CPU/GPU within the new scene, not new FPS against old scene FPS.

## Offline verification

```powershell
./scripts/test-bullet-demo.ps1
./scripts/test-bullet-regression.ps1
```

The first runs state/asset/clipping/replay checks, independent scalar pixel
comparison at all five tiers, preserves the legacy CRC, and feeds every pixel
of one complete representative frame through unchanged production
gpu_pixel_pipe using D:/FPGA/iverilog. The second checks the existing software
suites and actual localhost UDP transfers for both manifests.

Windows host tests relocate only their simulated pointers, because Windows
reserves the board's low DDR address range for its heap. Actual firmware still
uses the original DDR addresses. These native MinGW runs are not sanitizer runs.

Historical R1/R2/R3 evidence is preserved. Current distinct-friendly/enemy
aircraft (R4) evidence and previews are in bullet_demo_r4_acceptance.md.
The player is a pointed narrow fighter; enemies have broad wings and two
side engines, not just the same sprite rotated and recolored.
RTL simulation verifies pixel math, ColorKey write suppression and elastic
backpressure; it does not simulate the complete RISC-V, APB/AXI DMA or physical
DDR/HDMI. No offline result is represented as a board FPS result.
