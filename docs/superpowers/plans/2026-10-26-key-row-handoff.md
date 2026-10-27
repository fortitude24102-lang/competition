# Cached sprite row handoff implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove avoidable row-boundary bubbles from the existing cached Key/small-Copy write path while preserving ordered pixels, AXI obligations and final-B retirement.

**Architecture:** Permit the final W of one accepted row to coincide with acceptance of the next row request. Add equivalent final-output/start handoff to the RGB565 aligner, then let CachedKeyStream select the next row address/count on that cycle. Preserve conservative complete-row credit, bounded outstanding writes, zero-strobe beats, 4KiB splits, stable stalled channels and error drain. No wider datapath, new RAM, public register ABI, feature flag or external implementation is introduced. The elastic/early-ready idea is informed by alexforencich/verilog-axi; implementation is independent.

**Tech stack:** Existing Chisel7.7/Scala2.13, StableChiselSim/Verilator, Efinity2026.1, current18-feature GPU configuration and controller board wrapper.

**Spec:** This plan is the candidate specification within the continuing hardware-limit goal. Source baseline771827f; accepted BITa98148a5 and normal87ef4b1d remain fallback.

## Constraints and review focus

- Request/start register initialization must win over simultaneous old-row retirement updates.
- No handoff at an intermediate burst boundary, on final image row, without complete next-row data or write-response credit, or on the cycle an error response is observed.
- New row address and halfword phase must use the advanced destination, including stride18 and 4KiB crossings.
- Outstanding AW/W/B must drain on errors, zero-strobe words remain, completion waits for every accepted row's final B.
- Ready/valid lookahead must not introduce a combinational loop or unstable offered payload.
- Keep CPU renderer/software and physical five-way/web controls unchanged. No Flash, release overwrite or preexisting user-file changes.

## Execution

- [x] Freeze three baseline Scala sources and add writer, aligner and combined-row handoff tests; observe expected baseline failures.
- [x] Implement minimal coordinated handoff; pass targeted tests, stalled/error cases and existing writer/aligner/Key/Copy/Alpha regressions. Record real cycle gain.
- [x] Generate fresh RTL with all18 features unchanged, inspect source/RTL deltas and obtain fresh review.
- [x] Freeze complete physical inputs before compiling; require XLR<54720, appropriate RAM/DSP,16 strictly positive timing relationships, applied local-input exception and routed1488+2+2 mailbox CDC coverage.
- [x] Only after physical qualification, compare identical firmware/workload on old/new BITs in controlled ordinary cohorts and targeted Key/Copy/Alpha phases. Adopt only measured gains with zero health/deadline failures.
- [x] Restore qualified normal six-tier MENU on accepted hardware even after failure, archive exact evidence and commit only justified changes. Do not claim the hardware limit reached from this single candidate.

Completion2026-10-27:7new+79related tests passed. XLR54234,RAM186,DSP38,16positive timing relationships. User replaced further long qualification with final720-frame A/B/A/B:8703/8656/8702/8657us,allhealth/deadline0;C9C5 adopted, optimization stopped. Evidence:docs/efinix_2d_gpu/evidence/key_row_handoff_20261027.
Ruling: Preserve original physical wrapperexit1. Separate qualification audited exactly root sw_version2025.2.288.3.8 to2026.1.132;169raw files and all other canonical settings match. Input freeze was not rewritten.
