# GPU Texture Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a software-managed 4 KiB GPU texture cache that removes repeated DDR3 foreground reads for Color Key and Alpha while preserving pixels, CPU baseline behavior, fallback rendering, and display safety.

**Architecture:** `TextureCache` preloads one programmable, immutable DDR region into a 1024×32-bit `SyncReadMem`. `DenseBlitEngine` selects the cache for whole-command Color Key/Alpha source hits and otherwise uses its unchanged DDR reader; APB registers and a blocking C driver let Sapphire load or invalidate the cache only while the GPU is idle.

**Tech Stack:** Scala 2.13, Chisel 7, chisel-sim/ScalaTest, generated SystemVerilog, bare-metal RV32 C, Efinity 2026.1, Ti60F225 DDR3/HDMI board.

**Spec:** `docs/superpowers/specs/2026-09-28-texture-cache-design.md`

## Global Constraints

- Keep the CPU rendering path, scene state sequence, resource bytes, GPU command ABI, 100 MHz GPU clock, 400 MHz SDRAM clock, resolution, Alpha, and Sprite counts unchanged.
- Cache only Color Key/Alpha foreground data; Copy, Fill, Sparse, Present, framebuffers, backgrounds, HUD, Alpha background reads, and all target writes stay on existing paths.
- Use a 4096-byte, software-managed preload buffer; no replacement policy, write-back, snooping, or speculative refill.
- Any cache miss, invalid state, or unsupported source rectangle uses the original DDR path and produces identical pixels.
- Do not combine HUD occlusion, Sprite bounding-box cropping, clock changes, or multiple-outstanding AXI work with this candidate.
- Each generated `.sv` file contains one module and the Efinity XML order matches `generated/efinix_gpu/filelist.f`.
- Run each targeted simulation until green, then exactly one full GPU regression/generation run; do not repeat the long suite without a new failure that requires it.
- Board work uses temporary JTAG loads only, never writes Flash, and never replaces `release/v2/` before acceptance.

## Review Focus

- Misaligned, zero, oversized, overflowing, or out-of-DDR load regions must be rejected without changing valid cache contents; pin this in Task 1 `TextureCacheSpec` and Task 2 `GpuFrontEndSpec`.
- Delayed, split, backpressured, or errored preload AXI responses must finish or fail without deadlock or partial validity; pin this in Task 1 `TextureCacheSpec`.
- Halfword source phase, independent stride, last-word padding, and a rectangle crossing the cache end must select the same pixels or fall back as a whole command; pin this in Task 2 `TextureCacheBlitSpec`.
- Invalidate/reload while the cache or GPU is busy must be rejected, while an idle reload must atomically replace the old image; pin this in Tasks 1–3.
- Alpha foreground may hit the cache, but Alpha background reads and target writes must remain on DDR and retain response/error handling; pin this in Task 2 `TextureCacheBlitSpec`.

---

### Task 1: Standalone preload buffer and cached read stream

**Files:**
- Create: `chisel/src/main/scala/gpu/TextureCache.scala`
- Create: `chisel/src/test/scala/gpu/TextureCacheSpec.scala`

**Interfaces:**
- Produces: `TextureCacheLoad(base: UInt(32.W), bytes: UInt(13.W))`.
- Produces: `TextureCache.io.load: Flipped(Decoupled[TextureCacheLoad])`, `invalidate: Bool`, `readRequest: Flipped(Decoupled[AxiReadRequest])`, `readData: Decoupled[AxiReadBeat]`, `readDone`, `readError`, `axi: Axi4MasterPort`, `valid`, `busy`, `error`, `base`, `bytes`, `hitBytes`, and `perfClear`.
- Depends on: existing `AxiReadEngine`, `AxiReadRequest`, `AxiReadBeat`, and `Axi4MasterPort`.

- [ ] **Step 1: Write the failing standalone tests**

  Add tests named `preloads 3104 bytes and serves unaligned word streams`, `splits a maximum preload at 4 KiB and holds data under backpressure`, `keeps the old image invalid during reload`, and `rejects an errored AXI preload without partial validity`. Assert exact AR address/length, cached beat address/data/last, `busy/valid/error`, invalidate behavior, and `hitBytes` clear/count behavior.

- [ ] **Step 2: Run the targeted test and verify RED**

  Run in the WSL environment used by `scripts/test-efinix-gpu.ps1`:
  `sbt 'testOnly gpu.TextureCacheSpec'`

  Expected: compile failure because `TextureCache` and `TextureCacheLoad` do not exist.

- [ ] **Step 3: Implement the minimum cache module**

  Implement a 1024×32-bit `SyncReadMem`; use one `AxiReadEngine` for aligned preload beats, write each successful beat at `(beat.address-base)>>2`, and expose a sequential cached read stream with the same address/data/last contract as `AxiReadEngine`. Clear `valid` at load acceptance, set it only after `reader.done && !reader.error`, and never expose partial data as valid.

- [ ] **Step 4: Run `TextureCacheSpec` and verify GREEN**

  Run: `sbt 'testOnly gpu.TextureCacheSpec'`

  Expected: all new tests pass with no simulator assertion, AXI protocol error, or warning from the DUT.

- [ ] **Step 5: Commit Task 1**

  ```text
  git add chisel/src/main/scala/gpu/TextureCache.scala chisel/src/test/scala/gpu/TextureCacheSpec.scala
  git commit -m "feat: add GPU texture preload cache"
  ```

### Task 2: APB control plane and dense blit integration

**Files:**
- Modify: `chisel/src/main/scala/gpu/GpuMemoryMap.scala`
- Modify: `chisel/src/main/scala/gpu/GpuApbRegs.scala`
- Modify: `chisel/src/main/scala/gpu/DenseBlitEngine.scala`
- Modify: `chisel/src/main/scala/gpu/RenderEngine.scala`
- Modify: `chisel/src/main/scala/gpu/Efinix2dGpuTop.scala`
- Modify: `chisel/src/test/scala/gpu/GpuFrontEndSpec.scala`
- Create: `chisel/src/test/scala/gpu/TextureCacheBlitSpec.scala`

**Interfaces:**
- Consumes: Task 1 `TextureCache` and `TextureCacheLoad`.
- Produces: registers `0x0090..0x00a4`, cache load/invalidate pulses, cache status, and snapshotted 64-bit cache byte count.
- Produces: whole-command `useTextureCache` selection for Color Key/Alpha; all other commands retain existing DDR behavior.

- [ ] **Step 1: Write failing APB contract tests**

  In `GpuFrontEndSpec`, assert version `0x00010100`, legal read/write offsets, base/bytes readback, mutually exclusive `LOAD/INVALIDATE`, rejection while `engineBusy/cacheBusy`, invalid range rejection, status bits, and snapshot/clear of `PERF_CACHE_BYTES`.

- [ ] **Step 2: Verify APB tests fail for missing registers**

  Run: `sbt 'testOnly gpu.GpuFrontEndSpec'`

  Expected: failures at version/register decoding and cache control expectations.

- [ ] **Step 3: Write failing end-to-end blit tests**

  `TextureCacheBlitSpec` must preload known atlas words, then run repeated aligned and halfword-phase Color Key plus Alpha commands. Assert cache hits issue no foreground DDR AR, pixels/WSTRB match the DDR oracle, Alpha still issues background AR and target AW/W/B, a one-byte-out-of-range rectangle falls back entirely, invalidate restores DDR reads, and preload AXI errors do not block a later command.

- [ ] **Step 4: Verify integration tests fail on the old data path**

  Run: `sbt 'testOnly gpu.TextureCacheBlitSpec'`

  Expected: compile failure for missing integration IO or a functional failure because foreground AR requests still reach DDR.

- [ ] **Step 5: Implement the APB and data-path integration**

  Add the six register offsets and version bump. Instantiate `TextureCache` in `DenseBlitEngine`; compute the 64-bit whole-source end when accepting Color Key/Alpha; register the command-level hit; mux cached beats into the existing aligner/foreground FIFO; mux preload AR/R through the existing dense AXI port only while idle; hold `command.ready` low while loading. Thread control/status/performance signals through `RenderEngine` and `Efinix2dGpuTop` without changing `DdrQosArbiter` clients.

- [ ] **Step 6: Run both targeted suites and existing Key regression**

  Run: `sbt 'testOnly gpu.TextureCacheSpec gpu.TextureCacheBlitSpec gpu.WordKeyDmaSpec gpu.GpuFrontEndSpec'`

  Expected: all tests pass; existing halfword-phase Key cases remain green.

- [ ] **Step 7: Commit Task 2**

  ```text
  git add chisel/src/main/scala/gpu chisel/src/test/scala/gpu
  git commit -m "feat: route sprite reads through texture cache"
  ```

### Task 3: Versioned C register ABI and blocking cache driver

**Files:**
- Modify: `sw/efinix_gpu/include/gpu_regs.h`
- Modify: `sw/efinix_gpu/include/gpu.h`
- Modify: `sw/efinix_gpu/src/gpu.c`
- Create: `sw/efinix_gpu/tests/test_texture_cache.c`
- Modify: `scripts/test-efinix-software.ps1`

**Interfaces:**
- Produces: `gpu_texture_cache_load(gpu_device *, uint32_t base, uint32_t bytes, uint32_t poll_limit) -> int`.
- Produces: `gpu_texture_cache_invalidate(gpu_device *) -> int`.
- Consumes: Task 2 APB offsets/status/control/version.

- [ ] **Step 1: Write the failing host driver test**

  Model APB reads/writes with `GPU_TEST_BACKEND`. Assert exact write order for a valid load, two busy polls followed by valid, timeout, hardware error, invalid base/length/overflow, nonempty GPU rejection, invalidation, and no register writes on rejected arguments. Update the software test script to compile and run this test.

- [ ] **Step 2: Run the new host test and verify RED**

  Run the compile/run command through `scripts/test-efinix-software.ps1` or its new texture-cache test entry.

  Expected: compile failure for missing register macros and driver functions.

- [ ] **Step 3: Implement the minimum ABI and driver**

  Extend `gpu_register_layout` through `0x00a4`, update static offset/extent assertions and `GPU_VERSION_VALUE`, validate the exact design constraints, require `device->outstanding==0` plus hardware `EMPTY && !BUSY`, issue fences around control writes, and return existing driver error codes only.

- [ ] **Step 4: Run all host software checks**

  Run: `powershell -File scripts/test-efinix-software.ps1`

  Expected: the new texture-cache test and all existing host sanitizer/driver/model checks pass; firmware links with the new version.

- [ ] **Step 5: Commit Task 3**

  ```text
  git add sw/efinix_gpu/include sw/efinix_gpu/src/gpu.c sw/efinix_gpu/tests/test_texture_cache.c scripts/test-efinix-software.ps1
  git commit -m "feat: add texture cache driver contract"
  ```

### Task 4: RISC-V asset lifecycle and safe DDR fallback

**Files:**
- Modify: `sw/efinix_gpu/include/bullet_demo.h`
- Modify: `sw/efinix_gpu/src/bullet_assets.c`
- Modify: `sw/efinix_gpu/src/main.c`
- Modify: `sw/efinix_gpu/tests/test_bullet_pixels.c`
- Create: `sw/efinix_gpu/tests/test_board_texture_cache.c`
- Create: `sw/efinix_gpu/tests/test_board_texture_cache_profile.c`
- Modify: `scripts/build-board-hud-dma-test.ps1`

**Interfaces:**
- Produces: `bullet_prepare_texture_cache(gpu_device *, int network_result, uint32_t poll_limit) -> int`.
- Consumes: Task 3 cache driver and existing network/local atlas constants.

- [ ] **Step 1: Write failing asset-selection tests**

  Stub `gpu_texture_cache_load` in `test_bullet_pixels.c`. Assert network success selects `BULLET_ATLAS_ADDR`, network failure selects `BULLET_LOCAL_ATLAS`, both use `BULLET_ATLAS_BYTES`, and a cache failure is reported without changing asset bytes or CPU rendering output.

- [ ] **Step 2: Run the bullet test and verify RED**

  Run the existing bullet host test through `scripts/test-bullet-regression.ps1`.

  Expected: compile failure because `bullet_prepare_texture_cache` is absent.

- [ ] **Step 3: Connect the cache after CRC/fallback selection**

  Implement the helper and call it once after `bullet_prepare_assets` and `gpu_platform_sync`. Print one parseable `TEXTURE_CACHE` line; continue with DDR fallback if the helper fails. Do not change `perf_render_cpu`, command generation, game steps, HUD, or mode switching.

- [ ] **Step 4: Add reproducible board correctness and profile firmware**

  Add `texture` and `texture-profile` options to `build-board-hud-dma-test.ps1`. The correctness test must load a known atlas into Cache, mutate the DDR source, prove cached Key/Alpha still use the original data, invalidate, prove fallback observes the new DDR data, and finish with `TEXTURE_CACHE_BOARD_STOP,result=0`. The profile test must run the existing 32/64/128/256/512 tiers at ticks 0/90/180 and print the existing phase counters plus cache bytes/status without changing commands or scene state.

- [ ] **Step 5: Run software and firmware checks**

  Run:
  `powershell -File scripts/test-bullet-regression.ps1`
  `powershell -File scripts/test-efinix-software.ps1 -FirmwareOnly -Demo bullet -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102`
  `powershell -File scripts/build-board-hud-dma-test.ps1 -Test texture`
  `powershell -File scripts/build-board-hud-dma-test.ps1 -Test texture-profile`

  Expected: host pixel/gameplay regression passes and both RV32 binaries link; no board programming occurs.

- [ ] **Step 6: Commit Task 4**

  ```text
  git add sw/efinix_gpu scripts/build-board-hud-dma-test.ps1
  git commit -m "feat: preload bullet atlas into GPU cache"
  ```

### Task 5: Generated RTL, project integration, and one full offline acceptance

**Files:**
- Modify/Create: `generated/efinix_gpu/*.sv`
- Modify: `generated/efinix_gpu/filelist.f`
- Modify: `board/efinix_ti60/efinix_2d_gpu.xml`
- Modify: `scripts/test-task2-board-integration.ps1`

**Interfaces:**
- Consumes: completed Chisel hardware from Tasks 1–2.
- Produces: one-module-per-file SystemVerilog and a board project containing every generated dependency in filelist order.

- [ ] **Step 1: Generate split RTL and inspect the expected diff**

  Run `gpu.GenerateEfinix2dGpu --target-dir ../generated/efinix_gpu --split-verilog` in the existing Chisel environment. Confirm `TextureCache.sv` and inferred RAM helpers appear once and no unrelated SoC RTL changes.

- [ ] **Step 2: Update the Efinity source list and structural test**

  Add generated cache modules in dependency order before `DenseBlitEngine.sv`; keep XML/filelist order equal. Run: `powershell -File scripts/test-task2-board-integration.ps1`.

  Expected: PASS for source presence, dependency order, one-module files, top wiring, and constraints.

- [ ] **Step 3: Stage generated RTL, then run the one full GPU regression**

  Stage the intended generated files first, then run: `powershell -File scripts/test-efinix-gpu.ps1`.

  Expected: every GPU suite passes, generation succeeds, and the script reports no generated RTL drift. Record the exact test/suite totals once.

- [ ] **Step 4: Build one Efinity candidate**

  Run:
  `powershell -File scripts/test-efinix-board.ps1 -EfinityHome D:/efinity -OutputDirectory D:/efinity_builds/texture_cache_20260928 -Flow compile`

  Expected: map/interface/pnr/pgm pass; record core and SDRAM setup/hold, LUT/FF/RAM10/DSP, bitstream SHA-256, and compare RAM10 against 141.

- [ ] **Step 5: Commit Task 5**

  ```text
  git add generated/efinix_gpu board/efinix_ti60/efinix_2d_gpu.xml scripts/test-task2-board-integration.ps1
  git commit -m "build: integrate texture cache RTL"
  ```

### Task 6: Board proof, fixed-workload performance, and acceptance record

**Files:**
- Create: `docs/efinix_2d_gpu/texture_cache_20260928.md`
- Create: `docs/efinix_2d_gpu/evidence/texture-cache-20260928/` selected logs/reports only
- Modify: `docs/efinix_2d_gpu/gpu_performance_options.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 5 bitstream, Task 4 board-test and normal/profile firmware, the same resource server and 32/64/128/256/512 workloads used by the halfword candidate.
- Produces: reproducible correctness, traffic, timing, resource, and FPS evidence; no release artifact replacement.

- [ ] **Step 1: Run the short hardware correctness test**

  Temporarily JTAG-load the candidate bitstream and texture-cache board test. Require the expected pass records and `TEXTURE_CACHE_BOARD_STOP,result=0,hardware=0`; stop immediately on mismatch, timeout, underflow, or hardware error.

- [ ] **Step 2: Rebuild and run the unchanged five-tier probe**

  Use identical resource bytes, logic ticks, commands, tier counts, network addresses, QoS, and measurement boundaries. Record Cache valid/error, DDR read bytes, cache bytes, render grants, Key/Alpha/FULL times, visible/Alpha command counts, underflows, and errors. Compare all functional counts to the halfword candidate before comparing speed.

- [ ] **Step 3: Run the normal CPU/GPU comparison once**

  Preserve the basic CPU path. Record ten 30-frame CPU/GPU windows and one 300-GPU-sample report: GPU render time, full-window FPS range, P5, underflow/error totals, and 60 FPS verdict. Do not interpret the deliberate CPU/GPU mode switching as GPU jitter.

- [ ] **Step 4: Apply acceptance/rollback rules**

  Accept only if pixels/counts match, underflow/error increments are zero, timing margins are nonnegative, and 512 Key or FULL improvement is repeatable beyond noise. Otherwise revert the cache implementation commits while retaining the measurement report explaining the rejection.

- [ ] **Step 5: Document and commit evidence**

  Include exact commands, commit/bitstream/firmware SHA-256, resource deltas, timing, performance tables, limitations, and the preserved historical SoC test anomaly. Exclude `outflow/`, temporary binaries, and raw redundant traces.

  ```text
  git add README.md docs/efinix_2d_gpu
  git commit -m "docs: record texture cache board results"
  ```

## Final Verification

- [ ] `git diff --check` is clean outside intentionally raw measurement logs.
- [ ] Targeted Cache, APB, blit, driver, firmware, board-structure, and board correctness tests pass.
- [ ] One complete GPU regression/generation run passes after the final hardware edit.
- [ ] Efinity map/interface/pnr/pgm and all analyzed clock relationships pass.
- [ ] Normal screen retains CPU/GPU comparison, Ethernet resource loading, Alpha, Color Key, double buffering, and zero new display underflow.
- [ ] Only after the user requests integration, push the reviewed commits to `main` without force.
