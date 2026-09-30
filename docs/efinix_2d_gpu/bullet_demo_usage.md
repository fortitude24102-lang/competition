# 100KBBH-inspired rendering candidate — A-work

## Scope

Software-only 960x540 RGB565 bullet showcase using the existing board-tested
Sapphire/GPU/DDR/HDMI design. Fixed-point ring, downward fan and spiral emitters,
six 8x8 keyed bullet shapes, a 16x16 auto-pilot player, bounded Alpha glows and
three downward-facing 16x16 aircraft emitters, over an
original star/circuit arena background. R5 adds automatic movement, HP,
mask-based collision, graze scoring, protection and failure/restart mechanics.
R7 cycles four 60-tick attack waves: radial/spiral lanes turn a quarter circle,
the downward fan alternates right/left-biased lanes, recycled bullets accelerate from 1.5 to
2.25 pixels per update and rotate through the six shapes. Existing aircraft
halos brighten for the 16 ticks before each wave change; no extra commands or
Alpha pixels are added. The 600-tick CPU/GPU replay window still resets the
same deterministic game state. These are automatic showcase mechanics only;
physical buttons and one-way CPU-to-GPU presentation await lead approval.
This is an unattended survival demonstration, not yet a complete playable game.
UART/network keyboard input remains a future independent task.

100KBBH is a reference, not an engine port. This implementation and procedural
art are independently authored; no Windows/OpenGL dependency or upstream code
is embedded. The original project license is MIT; any future actual source/art
reuse must retain relevant notices and check individual asset permissions.

Hardware and release/v2 remain at the main a82f3dd baseline. Main's later
9f2eaba performance RTL is not imported by the scene-entry-only update.
The A-work baseline
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
Start the existing server through the checked foreground launcher:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-bullet-asset-server.ps1
```

Keep that terminal open until the board run ends. The launcher validates the
server, manifest resources, PC address and UDP owner, but never changes the
adapter or firewall and never terminates an unrelated port owner. If Windows
asks for network access, allow the selected `asset_server.exe` on the board's
current private/direct network before retrying.

For legacy firmware use assets/v2/manifest.csv instead. The new IDs 101/102
reuse the current GET/DATA protocol, packet CRC protection and asset DMA.
The renderer uses network destinations only after both full-file CRC checks
succeed. Local fallback uses background 0x02b00000 and atlas 0x02c00000,
disjoint from network DMA destinations 0x02900000/0x02a00000. Thus even an
abort timeout with accepted writes still draining cannot overwrite fallback.
Any partial-load failure regenerates both local resources and shows
NET FAIL FALLBACK; this is not network acceptance.

Use the V2 temporary JTAG bitstream/load procedure with the freshly selected
firmware, not a V1 bitstream. A build or host test is not board acceptance;
capture the UART resource byte counts, retries and result for each physical
run. Do not flash this candidate as part of testing.

Makefile alternative: DEMO=bullet (default), or DEMO=legacy; supply your SOC and
TOOLCHAIN paths. Rebuild on mode switches; FORCE prevents stale mode binaries.
The standard test-efinix-software.ps1 now defaults to this bullet scene;
use -Demo legacy explicitly for the older scene. -Profile keeps main's phase
diagnostic but uses the selected scene; it does not run the normal HUD loop.
Supply -Soc/-RiscvGcc when the BSP/toolchain is elsewhere; -FirmwareOnly avoids
the older WSL test path. Network IP defaults of this standard script are not
changed: supply the board/PC addresses explicitly. See scene_entry_handoff.md
for a complete command and offline entry validation. Nothing publishes or
flashes automatically.

## Measurement rules

- KEY1/KEY2 only select 32/64/128/256/512 target slots; they do not move the player.
- HUD BULLETS is the number actually clipped into the visible playfield, excluding
  player/emitters. Target slots are not a claimed simultaneous visible count.
- CPU and GPU each render 30 frames of the same saved state, then the next window
  advances. The sequence resets after 600 logical frames. It never depends on
  measured wall-clock frame duration. No quadratic per-frame replay rebuilding.
- Both use the same scene/assets and produce identical final HUD pixels. The
  ordinary GPU clips only the opaque HUD-covered background, updates changed
  text cells with its glyph atlas and copies the cached HUD using GPU Copy.
  CPU keeps the original full scene, CPU HUD raster and software HUD Copy.
  FPS includes
  HUD and PRESENT; RENDER MS is scene rendering only. Unmeasured FPS/render
  fields show --; HP/score/graze fields are computed game state, not FPS.
- UFL is cumulative hardware underflows; ERR is the current GPU hardware error.
- BULLET_GPU_300 collects GPU samples across alternating windows. Its
  windowed_60fps flag is NOT proof of 300 uninterrupted 60-FPS frames. Formal
  continuous-load/endurance acceptance still needs a board and dedicated run.
- 8x8 bullets touch 64 source pixels versus 5,120 for the old 64x80 sprites
  (80x fewer per full sprite). CPU/Profile retain the full background; ordinary
  GPU copies 960x468 rows. HUD is still copied in full from 0x02c10000 (138,240
  bytes), but only GPU-mode text changes use dirty glyph cells. The 39,312-byte
  white/green atlas at 0x02c40000 is initialized once from existing font tables,
  separate from the Sprite Cache. CPU retains its original complete rebuild.
  Compare CPU/GPU within the same scene, not new FPS against old scene FPS.

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

Historical R1..R5 evidence is preserved. Bounded Alpha/auto-pilot
survival (R5) mechanics and effects are in bullet_demo_r5_acceptance.md.
Current R6 fixes performance-HUD readability with a 5x7 font at integer 2x
scale, 4-pixel character/line gutters and unchanged 960x72 cache/playfield.
See bullet_demo_r6_acceptance.md for refreshed previews, logs and hashes.
The player is a pointed narrow fighter; enemies have broad wings and two
side engines, not just the same sprite rotated and recolored.
RTL simulation verifies pixel math, ColorKey write suppression and elastic
backpressure; it does not simulate the complete RISC-V, APB/AXI DMA or physical
DDR/HDMI. No offline result is represented as a board FPS result.
