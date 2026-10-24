# Fair wide Copy configuration implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Test native Copy with the existing Scanout optimization restored and prevent another incomplete A/B configuration comparison.

**Architecture:** Keep all production datapaths unchanged. Extend the generator's existing JSON manifest with all effective Top parameters, source content identity and emitted RTL hashes; compare a freshly generated control and candidate before preparing the board project. The only permitted feature difference in this experiment is `wideCopyDma`.

**Tech Stack:** Existing Scala/Chisel, PowerShell, Verilator, Efinity; no new dependencies.

**Spec:** `docs/efinix_2d_gpu/performance_retrospective_20261023.md`, P0 and acceptance/stop conditions. User requested continued optimization on 2026-10-24 after reviewing this route.

## Global constraints

- Reuse the existing `codex/efinix-2d-gpu` worktree; preserve all pre-existing dirty files.
- Keep CPU drawing, BINs, workload, 100 MHz clocks, Alpha/Key, network and qualification unchanged.
- Complete configuration: instances, frame-lists, key-prefetch, scanout-word-pipeline, transform-blit, alpha-pipeline, axi-diagnostics, key-write-pipeline, extended-list-arena, small-copy-prefetch, four-write-credits, alpha-row-prefetch, split-verilog. Candidate additionally enables wide-copy-dma.
- XLR <54720, RAM <256, all 16 final setup/hold entries positive and actual routed network CDC checks pass before JTAG.
- Fresh output directories; retain old candidates/evidence. No Flash, remote push or release replacement.
- Same-BIN old/new/old, fixed stages then ordinary1024 >=3600 frames. Search for higher activity only if ordinary game has repeatable net gain and passes qualification.

## Review focus

- Missing or extra feature keys, different write credits or source identity must fail comparison.
- A permitted wide difference must really differ; unrelated or unknown exceptions must fail.
- Manifest must match the selected emitted modules and filelist, including actual Scanout implementation.
- Historical one-field manifests remain usable for historical preparation, but cannot qualify a fair comparison.
- Preserve measurements, failures and rollback state; distinguish offline evidence from new board results.

### Task 1: Complete manifest and fail-closed comparison

**Files:** `chisel/src/main/scala/gpu/GenerateEfinix2dGpu.scala`, `scripts/compare-gpu-build.ps1`, `scripts/test-efinix-board.ps1`, `scripts/tests/test-gpu-build-match.ps1`.

- [x] Add a runnable check for the real generated manifests, requiring all 17 effective Top parameters and content identity; run against archived manifests and record expected RED.
- [x] Record effective parameters and SHA256 identities using existing runtime libraries. Add comparison requiring the same source and complete feature set, with exactly the explicitly named differing features; validate emitted hashes/filelist.
- [x] Add optional reference selection to the existing board preparation path; compare before preparing a candidate.
- [x] Generate control/candidate into fresh directories. Run real-manifest tests and negative cases for omitted Scanout, credits, source, missing/extra key, missing permitted difference and changed RTL. Re-run existing board selection checks.

### Task 2: Offline validation and physical candidate

**Files:** fresh `generated/verification/v3/wide-copy-fair-20261024/`, fresh `D:/efinity_builds/wide_copy_fair_20261024_r1/`.

- [x] Compare regenerated control RTL to the actual old Alpha-row-prefetch project. If any executable RTL differs, build a fresh same-source control BIT rather than silently reuse the historical one. Run actual generated Scanout throughput check (960 correct pixels in 960 cycles) and directed Scanout/Top/wide ordering/reset suites.
- [x] Prepare with reference comparison, then compile once. Inspect complete resources, 16 final timing entries and routed CDC before any board use.

### Task 3: Board A/B/A or explicit offline stopping point

**Files:** new evidence report `docs/efinix_2d_gpu/evidence/wide_copy_fair_20261024/README.md` and raw logs under this experiment's directory.

- [x] Check actual board/services availability. If available and physical gates pass, collect same-BIN fixed stages and ordinary1024 old/new/old without simultaneous serial/JTAG/control writers.
- [x] Evaluate whole-frame work, late/over-budget frames, underflow/errors and pixel/CRC equality; keep old primary without repeatable net gain. Restore normal MENU and release control.
- [x] Fresh independent review of the changed build safeguards; fix material findings with RED/GREEN checks, record actual evidence and any unavailable hardware steps. Do not claim unrun results.
