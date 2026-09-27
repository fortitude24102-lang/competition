# 100KBBH-inspired software rendering plan / ledger

Approved scope: 2026-09-27 conversation. Rendering-only, no player input,
collision/gameplay, hardware changes or performance claims without a board.
Base: origin/main a82f3dd; merged into A-work as 4da23d7. Main is read-only.

Architecture: independently authored fixed-point ring/fan/spiral simulation,
shared CPU/GPU commands, original RGB565 assets, existing network DMA protocol.
Keep the legacy renderer selectable at build time. Full background redraw first;
no dirty rectangles, shaders, new GPU opcodes or modified RTL.

## Tasks
- [x] 1: original assets, bounded deterministic simulation and clipped commands.
- [x] 2: optional network catalog, firmware integration, same-window replay and HUD.
- [x] 3: independent CPU oracle, real pixel-pipe simulation, preview and RV32 builds.
- [x] 4: whole-change review and evidence; authorized A-work commit/push recorded in Git history.

## Review focus
Negative/partial screen coordinates; object/command capacity; overlapping pixels;
partial network load followed by local regeneration; CPU/GPU replay identity.

## Decisions
- Main wins baseline merge conflicts, including already board-tested hardware.
  The feature delta must contain no changes under board/, chisel/, generated/efinix_gpu/.
- Current WSL is unavailable. Use native MinGW host tests and supplied Windows
  Icarus; sanitizer availability and firmware BSP will be reported honestly.
- 100KBBH is a design reference, not a binary/source port. No upstream code or
  art is copied. Assets are original procedural shapes, not original shaders.
- Keep full background COPY and existing common CPU HUD for comparable results.
  Small sprites reduce scene pixel work, not a demonstrated frame-rate increase.
- Windows heap occupies the board's low DDR addresses. Relocate host-test pointers
  only, via a forced test header; keep real firmware and RTL addresses unchanged.
- GPU_300 is explicitly windowed sampling, not uninterrupted stable-60 acceptance.
- Supplied native GCC lacks the WSL sanitizer environment. Run warning-clean
  native suites, independent oracle/RTL comparison and RV32 stack checks instead;
  do not label these sanitizer results.
- Final review: fresh read-only reviewer found an important unfinished-DMA
  fallback race, key-only visibility overcount and incomplete fallback testing.
  Fix pass: disjoint local DDR resources, cull key-only sprite rectangles,
  test failure of both resources through production preparation and late writes.
  Recovery/visibility regressions were observed RED with mutations before GREEN.
- Deferred board FPS, complete SoC memory/command execution and physical
  endurance are outside offline pixel simulation; explicitly documented.

## Final result
Green final run: state/asset tests, independent all-tier pixels, legacy perf
CRC, 599508 real RTL pixel operations, 12 original C suites, both UDP catalogs,
both RV32 configurations. Review fixes included fallback for both resource
failures and late DMA writes. Evidence/limitations: bullet_demo_acceptance.md.

## Validation contracts
Host: replay determinism, bounded objects, invalid inputs, clipped edges,
atomic stream-capacity failure, independent all-pixel RGB565 oracle, asset CRC.
RTL: replay emitted real scene pixel operations through unchanged gpu_pixel_pipe,
compare each result and write-enable, include backpressure and VCD evidence.
Firmware: compile/link bullet and legacy configurations with the official BSP;
do not overwrite any board-tested release artifacts.
