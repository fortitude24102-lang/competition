# Small Copy Prefetch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Inline execution, one fresh whole-diff reviewer at the end.

**Goal:** remove small strided GPU Copy read/retirement overhead with identical framebuffer output.

**Architecture:** extend existing CachedKeyStream and DDR mux; no new DMA/FIFO. Build-time default-off flag and known-BIT rollback.

**Tech Stack:** Chisel, existing ScalaTest simulator, official Efinity/Sapphire and C diagnostic.

**Spec:** docs/superpowers/specs/2026-10-20-small-copy-prefetch-design.md

## Global Constraints

No CPU raster/config, challenge thresholds, scene quantity, Alpha/Key or network changes. JTAG/RAM only; no Flash or remote writes. Preserve unrelated files. All final setup/hold domains positive before loading. Prefer existing tests and scripts; no dependencies.

## Review Focus

Copy must preserve magenta and edge strobes; contiguous Copy must not start two engines; malformed read drains without deadlock; second outstanding B cannot retire the next command; cache-vs-DDR read mux must not consume the other's beats. Task1 tests pin these.

### Task1: shared FIFO Copy path

Files: CachedKeyStream.scala, DenseBlitEngine.scala, RenderEngine.scala, Efinix2dGpuTop.scala, GenerateEfinix2dGpu.scala; test SmallCopyPrefetchSpec.scala.
Interfaces: trailing enableSmallCopyPrefetch:Boolean=false and --small-copy-prefetch. Reuse existing AxiReadRequest/AxiWriteRequest ports and completion; no public software interface changes.

- [ ] Write real RenderEngine tests for14x18 all pixels/guards, height32, magenta, halfword/stride1922/4KiB, fallback height33/source+2/odd/contiguous; AR count1 vs18 and finite delayed-B cycle reduction. Add malformed R/B and following Fill/Alpha/Key retirement.
- [ ] Run testOnly gpu.SmallCopyPrefetchSpec; observe missing constructor/behavior RED.
- [ ] Implement strict eligibility, Copy strobe, DDR reader mux, flag plumbing, exclusivity and error drain.
- [ ] Run new and affected Key/Copy/Alpha/arbiter suites; run software integration for test-only trace. Require no unexplained failures.
- [ ] Commit tested code/trace locally.

### Task2: EDA, board decision and evidence

Files: generated fresh RTL/build outputs; README.md and new evidence report (not old sealed bundles).
Consumes Task1 --small-copy-prefetch; uses unchanged normal production BIN SHA33aac5fa... and stable BITa476... for control.

- [ ] Generate fresh UUID RTL with stable flags plus new flag, enforce one module/file; isolated Efinity compile.
- [ ] Read all final setup/hold domains and resource totals. Stop new-BIT deployment on any failed gate.
- [ ] SameBIN A/B/A1024 probes and challenge+5s hold if timing passes, exact hashes/session/health. Preserve negative results without score inflation.
- [ ] Restore known normal six-tier MENU if no repeatable benefit; otherwise retain qualified candidate. Release collector and stop programmer.
- [ ] Fresh whole-diff review once; fix important issues with RED/GREEN, document measured limits/negative staging, locally commit evidence. No push requested.
