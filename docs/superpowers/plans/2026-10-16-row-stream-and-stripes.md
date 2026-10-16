# Row stream and stripe composition implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Execute inline, as requested by the user.

**Goal:** Implement direction2 then3 while preserving exact game pixels, CPU baseline and rollback.

**Architecture:** First continuous cache prefetch with bounded row FIFO, reusing DenseBlit AXI writer. Then an AXI local stripe window reuses the original BitBlt engine to compose and write back full-width strips.

**Tech Stack:** Chisel/SystemVerilog, Sapphire C, existing Efinity/WSL test tools; no imported IP dependencies.

**Spec:** docs/superpowers/specs/2026-10-16-row-stream-and-stripes-design.md

## Global Constraints

- Default generator/release unchanged; candidate switches explicit, CPU rendering/game logic/network retained.
- Only JTAG RAM, never Flash. No remote push.
- Original Alpha rounding/Key transparency/order/boundary validation and fail-closed no-replay semantics preserved.
- One module per generated .v file; use existing split generation.

## Review Focus

- A prefetched row must not cause lost/duplicated first/last halfwords or zero-strobe beats.
- Late read/write error must drain every promised transaction and never reuse poisoned partial data.
- Local AXI valid/data must remain stable under backpressure; local aliases never leak onto DDR.
- Overlapping sprites must retain original order in every stripe; cross-boundary clips must use original source stride.
- Unsupported old BIT must reject stripe mode, not accidentally draw into an unmapped DDR alias.

### Task 1: Cached Key stream

**Files:** new CachedKeyStream.scala/Spec; DenseBlitEngine.scala; RenderEngine.scala; Efinix2dGpuTop.scala; GenerateEfinix2dGpu.scala; existing relevant tests.

**Interfaces:** command/eligible, AxiReadRequest/Data/done/error for texture cache, AxiWriteRequest/Data/done/error to existing writer, completion and wordPixelsDone. New final constructor bool `enableKeyPrefetch=false` propagated from `--key-prefetch`.

- [x] Write tests for8×8 whole-source one read, halfword target Key strobes, delayedB while next rows prefetch, completion/tag/backpressure, read/B error drains. Watch missing feature fail.
- [x] Implement bounded16-word FIFO and row aligner; integrate only eligible cached commands before any issue; retain all fallback paths.
- [x] Run new and CopyStream/TextureCacheBlit/WordKeyDma/RenderEngine regressions; cycle comparison with old path and no unsolicited resource/throughput claims. Commit independently.

### Task 2: Local stripe memory

**Files:** new StripeScratchpad.scala/Spec; Top/Regs/Generator capability/flag; synthesis source lists as required.

**Interfaces:** render-side AXI slave/DDR master; alias0x02e00000,bytes15360; STATUS bit16, `--stripe-scratchpad` flag.

- [x] RED tests: local WSTRB and burst reads, local/external owner changes/backpressure, invalid end/size/burst responses, errors; no local AR/AW appears outside.
- [x] Implement synchronous banked byte-enable memory with one read and one write stream, strict owner retention until retirement; wire before DDR QoS without touching Scanout/Asset.
- [x] GREEN tests plus full GPU suite, generated split RTL and resource/timing check. Preserve old candidate unchanged.

### Task 3: Sapphire strip planner and full renderer

**Files:** new gpu_stripes.[ch]/test; v3_demo.c candidate path; build/test scripts.

**Interfaces:** validated original gpu_instance scene/stats, stable per-stripe cropped descriptors, existing original list banks/render_span, existing HUD/PRESENT. Explicit `-StripeRender` requires hardware bit16 and frame lists.

- [x] RED C tests: stable bin order, y72/8line/last4line, source stride/offset, halfwordX, capacity/canary, invalid source/all-before-write; full-pixel original-vs-striped oracle with overlapping Alpha+Key.
- [x] Implement bounded two-pass Y binning into reserved DDR, load/draw/writeback eachstrip using originalengine/templates, no PRESENT before complete retirement; no fallback after partialissue.
- [x] Run C/protocol/pixel and fullRTL integrations. Build ELF with officialRAM/stack limits. On board only if bitresource/timing and connection pass; compare actual transactions/FPS/health and restore healthy MENU. Review, README/evidence/localcommit, no push.

Outcome: fullGPU91/91, C28/28, protocol27/27; strict native1040+130Alpha3600@60.10 and5secposthold. Stripe pixels correct but slower, remains experimental/off. See docs/efinix_2d_gpu/row_stream_and_stripes_20261016.md for both successes and rejected results; this implementation completion is not whole-project/endurance acceptance.
