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

## Follow-up R2 (2026-09-27)

Goal: improve presentation and remove per-frame HUD glyph command construction,
without changing hardware, gameplay, replay workloads or the legacy renderer.
Inline execution with test-first checks and one final independent review.

- [x] HUD: `hud_update_cache(metrics,cache,static_scratch)` and
  `hud_cached_command(dst,cache,out)` in src/hud_cache.c. Cache text, not raw
  padded metrics; DDR 0x02c10000..0x02c31c00, disjoint from pending network DMA.
  First compile observed RED (missing APIs), then pixel equality/A-B copy/text
  invalidation/canary test GREEN. CPU copies the HUD in both comparison modes.
- [x] Art: refine original RGB565 background/player/bullets in both Python asset
  generator and C fallback. Keep dimensions, bullet opacity mask and protocol.
  Existing complete asset byte-comparison must fail on generator-only changes,
  then pass with identical C regeneration. No new third-party license dependency.
- [x] Evidence: compare cached HUD against original all-pixel oracle; replay
  real cached COPY through unchanged pixel RTL. Generate 512-object frames
  0/90/180 with independent oracle checks. Archive actual parsed CRC/counts,
  not hardcoded historical metrics; reject mismatched host/RTL receipts.
- [x] Final: review, final render/regression runs, both RV32 builds, archive
  evidence and authorized push to A-work. Check hardware delta/main unchanged.

Review focus: cache visibility fence, text-only invalidation, memory separation,
all-pixel equivalence, asset fallback identity, receipt provenance, preview
visibility versus configured count. No added package/install requirement.

Final review: one important outline-threshold defect (no lattice pixels in
r=41..49). Outer-ring assertion RED, change both generators to r>=34 GREEN,
then fresh render/regression/bullet RV32/evidence. Cached HUD tests, 596296
unchanged RTL pixel operations, legacy CRC 8e341090, 12 existing suites and
both UDP catalogs green. Legacy RV32 branch unchanged by the outline fix;
its successful build remains valid. No deferred minors.

Review boundary rulings: physical coherence/SoC/HDMI/FPS stay unverified until
a board is available (cost: on-board acceptance remains necessary); controls,
collision and gameplay stay deferred (cost: this remains a rendering demo);
final artifacts are certified by actual parent test logs rather than the
read-only reviewer (cost: reviewer did not execute them); unrelated untracked
BSP/waves stay untouched (cost: not part of this deliverable). Authorized push
is to A-work only, never a merge or push into main.
