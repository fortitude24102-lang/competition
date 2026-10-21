# Alpha Row Prefetch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Inline; one fresh whole-round reviewer after implementation/measurement.

**Goal:** hide Alpha row-end B latency with next-row reads and existing storage.

**Architecture:** retain single-write engine; prefetch only eligible non-overlapping small Alpha, flush abandoned lookahead on error. Default-off build flag, unchanged software.

**Tech Stack:** Chisel/ScalaTest, existing official Efinity/Sapphire and board tools.

**Spec:** docs/superpowers/specs/2026-10-21-alpha-row-prefetch-design.md

## Global Constraints

No CPU rendering/config, firmware workload, challenge thresholds, clocks, network, Alpha/Key math or dependencies changed. JTAG/RAM only; no Flash/main/release mutation. Preserve unrelated files and all old sealed evidence. Test/measure once per changed implementation, not repeated unchanged full CPU/SoC suites. All16 final setup/hold relationships strictly positive plus existing routed CDC/resource gates before candidate board loading.

## Review Focus

Late B error with next-row R stalled must drain; abandoned aligner/FIFO data must not poison following Alpha; shared halfword/4KiB edge must preserve adjacent pixels; in-place/wide Alpha must fall back; last row/next AW/completion must not run before required write retirement. Task1 pins each condition.

### Task1: Alpha lookahead and regression

Modify DenseBlitEngine.scala, RenderEngine.scala, Efinix2dGpuTop.scala, GenerateEfinix2dGpu.scala; extend existing AlphaPipelineSpec.scala byte-memory fixture (no duplicate bus model).
Interfaces: trailing enableAlphaRowPrefetch:Boolean=false; --alpha-row-prefetch requires --alpha-pipeline. Existing ports/ABI and writer depth unchanged.

- [ ] Add tests for12x12/pitch1920 cached row0/2 with delayed B: golden bytes and same ordered traces, next-row read before B, finite-delay faster. Add odd/noncache/4KiB and read/B/BID faults with stalled future R plus subsequent Alpha. Add wide/in-place fallback check.
- [ ] Run `testOnly gpu.AlphaPipelineSpec -- -z "row prefetch"`; expected missing build option/overlap behavior RED. Read failure.
- [ ] Implement eligible row advance, lookahead/error state, suppression of future unaccepted AW and complete read/write drain/abandoned buffer flush. Default branch unchanged.
- [ ] Run `testOnly gpu.AlphaPipelineSpec gpu.KeyWritePipelineSpec` and selected SmallCopy cached transition; expected all pass, no pixel/tag/error mismatch, observed prefetch and lower finite-delay cycles. Commit tested code locally.

### Task2: physical and board decision

Generated RTL/builds fresh; README.md and new evidence report. Consumes Task1 flag atop stable four-credit options, unchanged normal/probe/AXI BINs.

- [ ] Generate one-module/file RTL and isolated Efinity compile; expected final16 timing allpositive, routed CDC/resource gates pass. On failure do not load candidate.
- [ ] With board available, same-BIN phase and1024 A/B/A, golden checks and normal3600 challenge/5s hold if viable. Expected identity/health gates, record negative FPS results too.
- [ ] Restore selected normalMENU/release owner/stop JTAG; retain only measured gain, document exact hashes and limitations. One fresh review, no repeated reviewer, then seal/local commit; no push.
