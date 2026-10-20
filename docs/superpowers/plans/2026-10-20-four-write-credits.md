# Four Write Credits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Inline execution; one fresh whole-diff reviewer at the end.

**Goal:** measure whether four small-blit write credits improve GPU throughput.

**Architecture:** parameterize the existing writer, owner FIFO and row counter together; default two, optional four. Do not add another DMA or change pixel storage.

**Tech Stack:** Chisel/ScalaTest, official Efinity/Sapphire, existing board diagnostics.

**Spec:** docs/superpowers/specs/2026-10-20-four-write-credits-design.md

## Global Constraints

No CPU raster/config, challenge thresholds, scene quantity, Alpha/Key or network changes. JTAG/RAM only; no Flash or remote writes. Preserve unrelated files. All final setup/hold domains positive before loading. Prefer existing tests and scripts; no dependencies.

## Review Focus

Four pending rows must not wrap to zero; a fifth AW must not overrun the owner FIFO; B errors at positions three/four or wrong BID must drain; split4KiB markers must retain request attribution; emergency must not withdraw offered AW or block promised W/B. Task1 pins these with real component tests.

### Task1: four-credit shared write pipeline

Files: AxiWritePipeline.scala, CachedKeyStream.scala, DdrQosArbiter.scala, DenseBlitEngine.scala, RenderEngine.scala, Efinix2dGpuTop.scala, GenerateEfinix2dGpu.scala. Extend KeyWritePipelineSpec.scala, KeyWriteArbiterSpec.scala, CachedKeyPipelineSpec.scala and SmallCopyPrefetchSpec.scala.

Interfaces: trailing `writeCredits:Int=2`, only2/4; CLI `--four-write-credits`. Top passes the same value to writer path and DDR arbitration. Existing decoupled ports unchanged.

- [x] Write tests for four credits, no fifth admission, every B error position/BID, split4KiB, pending-row retirement, owner/emergency drain and golden Copy/Key/Alpha recovery. Run `testOnly gpu.KeyWritePipelineSpec -- -z four`; expected missing parameter/credit behavior RED.
- [x] Implement queue depth and `log2Ceil(writeCredits+1)` row count, propagate build option and reject incompatible configurations. Default2 behavior unchanged.
- [x] Run writer, arbiter, cached-row and DDR QoS suites plus new four-credit full-Render test. Expected all pass; finite-delay four-credit completion faster than two in the same fixture, no byte/tag/error mismatch. Read logs, do not repeat unchanged long suites.
- [x] Commit tested code locally.

### Task2: physical gates, board decision, evidence

Files: new generated verification directory / Efinity build; README.md and new evidence report.
Consumes Task1 `--four-write-credits`; control BIT118491... and unchanged normal33aac.../probe1024 bd5489... BINs.

- [ ] Generate fresh RTL with previous stable flags plus four-credit flag; one module/file. Compile isolated Efinity build, check final16 timing rows, resource and routed network CDC. Expected all positive, no resource overflow; otherwise no new-BIT loading.
- [ ] Run same-BIN phase and1024 control/candidate/control probes; if viable run normal3600 challenge plus5s hold. Expected fresh identities/leases and under/error0; report negative frames too.
- [ ] Restore selected normal six-tier MENU, release owner and stop JTAG; choose four only if measured benefit. Record hashes/results/limits; update README without changing historical sealed evidence.
- [ ] Fresh whole-diff review once, address important findings by RED/GREEN, seal evidence and commit locally. No main push requested.
