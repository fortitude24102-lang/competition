# GPU HUD Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate GPU-mode CPU full HUD raster rebuilds without changing the CPU baseline or pixels.

**Architecture:** Generate the existing font's two-color, opaque RGB565 cell atlas once in DDR. Share the actual HUD raster/text cache with the unchanged CPU path; GPU updates changed cells through existing Copy and waits before committing metadata. Keep the final full HUD Copy to the back buffer.

**Tech Stack:** C11, existing Copy/Fill/command queue, WSL GCC sanitizer tests, official RV32 toolchain and unchanged candidate bitstream.

**Spec:** `docs/superpowers/specs/2026-09-30-gpu-hud-glyphs.md`

## Global Constraints

- CPU `hud_update_cache` and `perf_render_cpu` remain unchanged.
- Preserve R7, RGB565 960×540, opaque 960×72 HUD, double buffering, 100 MHz, existing Sprite Cache and RTL.
- Atlas: 0x02c40000, 39 glyphs, 14×18 cells, white/green, 39312 bytes, disjoint DDR.
- No new dependencies, Flash writes, release replacement or automatic push.
- Dedicated DMA is conditional on measured command overhead, not a deliverable before measurement.

## Review Focus

- Shortening text / mode transitions must erase stale glyphs (Task 1 pixel sequence).
- Single-character changes must not trigger a full HUD Fill (Task 1 literal 504-byte cell check).
- Timeout after partial writes must invalidate metadata and recover on retry (Task 1 fault test).
- Maximum fields / green line / spacing must remain byte-identical (Task 1 boundary oracle).
- Ordinary GPU must use the new updater, CPU must still use the original updater, Profile/legacy remain unchanged (Task 2 linked entry and board hook).

### Task 1: Atlas and GPU-only cache updater

**Files:** Modify `include/hud.h`, append atlas initializer to `src/hud.c`; create `src/hud_gpu_cache.c` and `tests/test_hud_gpu_cache.c` under `sw/efinix_gpu/`; modify Makefile and test-bullet-demo.ps1; create `scripts/test-hud-glyphs.ps1`.

**Interfaces:** Produces `void hud_init_glyph_atlas(void)` and `int hud_update_gpu_cache(gpu_device *, const hud_comparison *, hud_raster_cache *, hud_command_stream *, uint32_t)`; consumes existing font tables, formatted text and `perf_render_gpu`.

- [ ] Write the raster test first: existing full redraw oracle versus GPU commands; 6→7 copies exactly 504 bytes and uses one Copy; unchanged text uses zero commands; long→short and mode/network/maximum fields match; injected timeout invalidates and retry restores full raster; invalid arguments have no writes.
- [ ] Run `powershell -NoProfile -File scripts/test-hud-glyphs.ps1`; expected RED for missing new symbols.
- [ ] Generate cells directly from existing static font tables at startup; implement changed-cell batch with final-tag wait and post-success text commit.
- [ ] Run the test; expected all cases PASS, canaries intact. Run existing CPU HUD test and C suite to preserve baseline.
- [ ] Commit tested Task 1 files.

### Task 2: Integration and measured acceptance

**Files:** Modify `src/main.c`, `tests/test_board_hud_dma.c`, build-board-hud-dma-test.ps1 and bullet_demo_usage.md; create test-hud-glyph-entry.ps1, measure-hud-glyphs-board.ps1, test_board_hud_glyphs.c and test_board_hud_glyph_sweep.c; update README and create dated evidence/report under `docs/efinix_2d_gpu/`.

**Interfaces:** Consumes Task 1 atlas/updater; ordinary GPU calls new updater, CPU calls unchanged updater. Keep existing final HUD Copy and frame timing definitions.

- [ ] Add linked-image test for reachable new updater in ordinary main, absent from Profile/legacy. Build and observe RED before routing change.
- [ ] Initialize atlas before performance sampling and platform sync. Route only ordinary bullet GPU frames to new updater; retain CPU and Profile/legacy behavior.
- [ ] Run host pixel tests, linked entry checks, existing software suite and board hook build; expected PASS. CPU golden code unchanged.
- [ ] Read board availability. If accessible, JTAG-load unchanged BIT and candidate BIN; measure GPU HUD update and ordinary ten 30-frame windows / 300 GPU samples, network result, errors and underflows. If unavailable, record the blocker without inventing board results.
- [ ] Record results, compare against historical R7 and HUD baselines with their different sampling boundaries; decide whether descriptor/glyph hardware is justified. Commit; do not push without user request.
