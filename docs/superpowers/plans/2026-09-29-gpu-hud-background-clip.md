# GPU HUD Background Clip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the top 72 rows of redundant GPU background Copy work while preserving the CPU baseline, Profile workload, final frame bytes, and all gameplay content.

**Architecture:** Transform only command 0 after the normal bullet scene is built: advance source/destination by 72 strides and reduce height from 540 to 468. The ordinary GPU path applies the transform before rendering; CPU and Profile keep the original command. Existing opaque cached HUD Copy remains the final writer for rows 0–71.

**Tech Stack:** C11, existing bullet command builder and scalar renderer, PowerShell host regression, official Sapphire RV32 toolchain, current 100 MHz candidate bitstream.

**Spec:** `docs/superpowers/specs/2026-09-28-network-hud-background-design.md`

## Global Constraints

- Do not modify Chisel, Verilog, generated RTL, Efinity XML/constraints, GPU clock, resolution, opcodes, or `release/v2/`.
- CPU render path and Profile background remain full 960×540.
- Preserve 960×540 final pixels, Sprite count, Alpha, Color Key, game state, double buffering, and opaque 960×72 HUD.
- Reject malformed streams without modifying any byte of the input stream.
- Do not add dirty rectangles, dirty tiles, compression, DMA descriptors, or speculative abstractions.

## Review Focus

- `scene_pixels` smaller than one full frame must reject instead of underflowing; Task 1 has a literal boundary case.
- A source range whose 72-row advance or remaining 468 rows crosses DDR end must reject; Task 1 tests the last invalid aligned address.
- Framebuffer B must receive the same address adjustment as A; Task 1 tests both destinations.
- A Sprite crossing row 72 must retain every visible pixel below the HUD; Task 1 compares completed frames byte-for-byte.
- Network and fallback backgrounds must both produce identical completed full/clipped frames over multiple ticks; Task 1 covers both address modes and buffers.

---

### Task 1: Command transform and pixel-equivalence contract

**Files:**
- Modify: `sw/efinix_gpu/include/bullet_demo.h`
- Modify: `sw/efinix_gpu/src/bullet_demo.c`
- Modify: `sw/efinix_gpu/tests/test_bullet_demo.c`
- Modify: `sw/efinix_gpu/tests/test_bullet_pixels.c`

**Interfaces:**
- Consumes: a successful `bullet_build_frame` result whose command 0 is the full-frame background Copy.
- Produces: `int bullet_clip_background_for_hud(bullet_stream *stream, unsigned hud_height)`; success is 0, invalid input is `GPU_DRIVER_ARGUMENT` with byte-identical input.

- [ ] **Step 1: Write failing contract tests**

In `test_bullet_demo.c`, assert a 72-row clip advances source and destination by `72 * GPU_FRAME_STRIDE`, changes height to 468, preserves width/strides/count/visible/Alpha counters, and subtracts exactly `960 * 72` from `scene_pixels` for framebuffer A and B. Assert height 0 is a no-op. For null/empty streams, height 540, wrong op/width/height/stride/destination, source overflow, and too-small `scene_pixels`, save the complete stream before the call and assert `GPU_DRIVER_ARGUMENT` plus `memcmp` equality.

- [ ] **Step 2: Write failing completed-frame tests**

In `test_bullet_pixels.c`, for fallback/network assets, framebuffer A/B, ticks 0/90/180, and a bullet crossing row 72: render `full scene + cached HUD` to one buffer and `clipped scene + the same cached HUD` to the other, then compare all `GPU_FRAME_BYTES`. Use literal 72/468/138240/69120 expectations rather than computing the expected transform with the production helper.

- [ ] **Step 3: Run the focused test and verify RED**

Run: `powershell -NoProfile -File scripts/test-bullet-demo.ps1 -HostGcc D:/aaa/mingw64/bin/gcc.exe`

Expected: compile/link failure for missing `bullet_clip_background_for_hud`.

- [ ] **Step 4: Implement the minimal transform**

Declare the exact interface in `bullet_demo.h`. In `bullet_demo.c`, validate every contract and all arithmetic before writing command 0 or `scene_pixels`; then update only `src_addr`, `dst_addr`, `height_pixels`, and `scene_pixels`. Do not allocate, loop over pixels, or alter later commands.

- [ ] **Step 5: Run focused and native regression tests**

Run:

```powershell
powershell -NoProfile -File scripts/test-bullet-demo.ps1 -HostGcc D:/aaa/mingw64/bin/gcc.exe
powershell -NoProfile -File scripts/test-bullet-regression.ps1 -HostGcc D:/aaa/mingw64/bin/gcc.exe
```

Expected: all bullet pixel/RTL checks and the native regression pass.

- [ ] **Step 6: Commit**

```powershell
git add sw/efinix_gpu/include/bullet_demo.h sw/efinix_gpu/src/bullet_demo.c sw/efinix_gpu/tests/test_bullet_demo.c sw/efinix_gpu/tests/test_bullet_pixels.c
git commit -m "feat: clip GPU background below HUD"
```

### Task 2: Ordinary GPU-only firmware integration

**Files:**
- Create: `scripts/test-bullet-clip-firmware.ps1`
- Modify: `sw/efinix_gpu/src/main.c`

**Interfaces:**
- Consumes: Task 1 `bullet_clip_background_for_hud` and existing `HUD_CACHE_HEIGHT`.
- Produces: ordinary bullet firmware that invokes the clip only when `mode != 0`; CPU and Profile binaries retain the full background workload.

- [ ] **Step 1: Write a failing linked-firmware test**

Create `test-bullet-clip-firmware.ps1` that builds ordinary bullet and Profile bullet firmware with `test-efinix-software.ps1`, inspects defined/reachable symbols with the RV32 `nm`/`objdump`, and asserts the ordinary `main` reaches `bullet_clip_background_for_hud` while the Profile entry does not retain it. Preserve both output images under `generated/verification/bullet-demo/clip-entry/`.

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -File scripts/test-bullet-clip-firmware.ps1`

Expected: FAIL because the ordinary firmware does not reach the clip function.

- [ ] **Step 3: Wire the ordinary GPU path**

Immediately after successful `bullet_build_frame` in the normal infinite loop, call `bullet_clip_background_for_hud(&scene, HUD_CACHE_HEIGHT)` only when `mode` is GPU. Break on error before scene render, HUD render, or Present. Do not change `profile_run`, CPU rendering, metrics, or the HUD command.

- [ ] **Step 4: Run firmware and entry verification**

Run:

```powershell
powershell -NoProfile -File scripts/test-bullet-clip-firmware.ps1
powershell -NoProfile -File scripts/test-firmware-scene-entry.ps1
```

Expected: normal firmware reaches the clip; Profile does not; default/legacy and normal/Profile scene-entry matrix passes.

- [ ] **Step 5: Commit**

```powershell
git add scripts/test-bullet-clip-firmware.ps1 sw/efinix_gpu/src/main.c
git commit -m "perf: skip HUD-covered GPU background rows"
```

### Task 3: Board performance and final documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md`
- Create: `docs/efinix_2d_gpu/evidence/bullet-board-20260929/hud-background-clip.log`

**Interfaces:**
- Consumes: Tasks 1–2 firmware, the network launcher plan's zero-retry server, and the unchanged current candidate bitstream.
- Produces: comparable 64-object CPU/GPU windows, 300 GPU samples, and raw evidence for the new command geometry and hardware health.

- [ ] **Step 1: Build and temporarily load normal firmware**

Build with board `192.168.1.3`, PC `192.168.1.2`, keep the foreground server running, reload the current candidate bitstream before formal sampling, and load the new BIN at `0x1000`. Do not write Flash.

- [ ] **Step 2: Verify geometry and fixed controls**

Use Task 1 host output as the exact command-geometry evidence: ordinary GPU
command 0 starts at row 72 and has height 468, while an unmodified/Profile
stream remains 540 rows. On the board, use Profile byte counters and ordinary
render timing to confirm the corresponding workload change. Record CPU render
timing without changing it, asset retries/results, cache base, GPU clock,
logical resolution, actual visible Sprite count, Alpha count, hardware error,
and underflow delta.

- [ ] **Step 3: Measure performance once per accepted protocol**

At the 64-object tier, capture ten complete CPU/GPU windows and one 300-frame GPU summary after a fresh JTAG load. Compare GPU `render_us` against the 9.30 ms texture-cache baseline; report median/range, displayed FPS, P5, underflows, and errors without converting HDMI 60 Hz into game FPS.

- [ ] **Step 4: Apply the acceptance rule**

Accept only if final pixels remain correct, network assets are zero-retry, command geometry is 468 rows only in ordinary GPU mode, render time falls repeatably, and hardware errors/underflow increments are zero. Otherwise revert only the clip commits and retain the independent network launcher.

- [ ] **Step 5: Update documentation and commit**

State measured results and limitations in README and the bottleneck report; keep the known `SoftwareDriverSpec`/`PangoBringupSpec` exception visible.

```powershell
git add README.md docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md docs/efinix_2d_gpu/evidence/bullet-board-20260929/hud-background-clip.log
git commit -m "docs: record HUD background clip board results"
```
