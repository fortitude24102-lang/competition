# Wide Copy prefetch implementation plan

> **For agentic workers:** Use superpowers:executing-plans in this worktree. No new checkout or hardware deployment.

**Goal:** Hide synchronous bank-read latency behind an already committed Copy write address.

**Architecture:** Start filling the existing two-word queue while AW is pending. W remains disabled until AW is accepted; retain the full-bank prerequisite, bank ownership through B, common reset, and GPU abort draining.

**Tech Stack:** Existing Chisel, ScalaTest and Verilator. No new buffers or dependencies.

**Spec:** This short plan records the implementation decision under the user's continued autonomous optimization request. Compare verilog-axi's independent write address/data staging; no third-party RTL is copied. A general crossbar or early external W changes ownership/protocol scope and is deferred.

## Global constraints

Keep the accepted BIT/normal firmware and previous evidence immutable. Local cycle savings do not establish frame or board gains. Read-credit hardware remains a separate unmeasured candidate.

## Review focus

AW backpressure must not emit W. Prefetched words must not repeat after AW. A stalled W must remain stable. Fault/abort must drain every committed bank and permit a clean successor. Repeated one-beat and maximum bursts must leave no queued word behind.

## Task 1: Overlap bank reads with AW

Files: `chisel/src/main/scala/gpu/WideCopyDma.scala`, `chisel/src/test/scala/gpu/WideCopyDmaSpec.scala`.

- [x] Add a real DMA transaction test for one/64-beat bursts, AW stalls, exact words/last/strobes, first-W latency, final B fencing and reuse. Run against unchanged code and retain failure.
- [x] Initialize read/send indices at bank commitment, enable existing memory fetch during pending AW, and retain W's accepted-address gate. Run all WideCopyDmaSpec cases including faults/abort.
- [x] Run related mux/config/top tests; generate the same 18-feature RTL and inspect exact source/RTL differences. Obtain one read-only review.
- [ ] Record measured cycle scope and board dependency, verify protected files, commit only owned files. No Flash, push, or release.

## Verified implementation checkpoint

DMA5/5 and integration15/15 pass. First-W latency3→2 cycles with no AW wait,3→1 after8 stalled AW cycles, for both1/64 beats. Only WideCopyDma.scala changes among38 sources; among70 generated files, WideCopyDma.sv and its assertion file change, the latter only in source-location comments. Independent read-only review found no important defect. No new queue, register or RAM was introduced in the source.

Physical validation is a separate subsequent gate. The initial pre-build audit rejected prepared XML format metadata2025.2 against installed/archived2026.1.132. The original XML is retained, only that attribute is aligned to the verified installed compiler, then the complete238-input freeze passes before compilation. No device, seed, synthesis or routing comparison is relaxed; no physical or board speedup is claimed at this checkpoint.
