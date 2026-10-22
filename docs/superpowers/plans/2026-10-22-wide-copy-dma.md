# Native 128-bit Copy DMA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce background Copy cost without changing the normal firmware, pixels, game workload or CPU algorithm.

**Architecture:** A two-bank native 128-bit backend bypasses the 32-bit Sapphire user port. A fixed two-master DDR mux independently owns read/write directions, preserving the official SoC's eight-bit IDs. The new fabric and DMA use common DDR reset; GPU-only reset requests a safe drain.

**Tech Stack:** Existing Chisel/ScalaTest/StableChiselSim, PowerShell, Efinity. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-22-wide-copy-dma-design.md` (approved for execution 2026-10-22).

## Global Constraints

- Existing isolated worktree and official SoC/DDR source remain unchanged. One emitted HDL module per file.
- Default `enableWideCopyDma=false`, CLI `--wide-copy-dma`; flag off preserves direct DDR wiring.
- Native DMA cannot be combined with the narrow-only StripeScratchpad; reject at elaboration (independent review fix, no change to the stripe-disabled candidate).
- Copy only, >=4096 bytes, continuous RGB565, aligned16, length multiple16, disjoint validated DDR intervals. Ineligible commands fall back before new transactions.
- SIZE4, INCR, <=64 beats, source and destination 4KiB split; two 1KiB banks, <=2 native reads/writes outstanding, complete bank before AW.
- No owner switch with outstanding responses/address promises/unfinished W. Legacy credits16, native turn<=2; emergency protects display and cancels uncommitted native switch.
- GPU-only reset drains without losing bank contents or old SoC transactions; common DDR reset clears fabric.
- Register ABI/BIN unchanged; wide handshakes counted at16 bytes/8 pixels, busy/stalls use time union.
- Whole board XLR<54720, RAM<256, all16 final setup/hold positive, existing routed CDC checks pass before JTAG. No Flash, main push or release replacement.
- Optional Transform may be compiled out only if resource/timing requires it; retain source and use same-trim DMA-off control for A/B/A.
- Physical success is not performance success: same-BIN background/phase A/B/A, >=3600 normal1024 frames, unchanged challenge qualification. Retain old primary path on no net benefit.

## Review Focus

- GPU reset while an address is stalled or while a bank owes W/B: promise remains stable and new GPU cannot see stale completion (Tasks1/3).
- Emergency arrives while waiting to switch to native: legacy display must not wait on prohibited native issue (Task2).
- Simultaneous final response and new address, full16 credits, W before AW, different IDs/direction owners: never route/retire wrong owner (Task2).
- Bad read after AW or bad B with future R: accepted writes drain using intact data; no partial replay (Task1).
- Generated wide ports and board wiring disagree, or high address truncation: preparation fails or validated command rejects, never a downloadable half-enabled build (Task3).

### Task 1: Native Copy backend

**Files:** create `chisel/src/main/scala/gpu/Axi128.scala`, `WideCopyDma.scala`; test `chisel/src/test/scala/gpu/WideCopyDmaSpec.scala`.

**Interfaces:** `Axi128MasterPort` uses32-bit addresses,8-bit IDs,128-bit data/16-bit strobes and existing AXI attributes. `WideCopyRequest(srcAddr:UInt32,dstAddr:UInt32,bytes:UInt32,tag:UInt16)`. `WideCopyDma.io`: request Flipped Decoupled, completion Decoupled GpuCompletion, axi Axi128MasterPort, abort Input Bool, busy Output Bool. It is instantiated under common reset, not GPU reset. No optional functionality in this backend.

- [x] Write byte-accurate memory test with random channel stalls, delayed B, 4KiB offsets on both ends, bank reuse, stable VALID/data and no early completion. Assert SIZE4, INCR, <=64 beats and <=2 in flight, exact bytes+guards. Add finite protocol faults (R/B response, IDs, early/missing RLAST marker at expected count), abort at each channel promise and next request recovery.
- [x] Run `scripts/test-v3-gpu.ps1 -Suite gpu.WideCopyDmaSpec -LogPath <fresh>`; Expected RED missing new class. Record output.
- [x] Implement fixed two-bank SyncReadMem backend, independent read and write progress, stable pending addresses, bank held until B, error/abort drain; no general DMA library.
- [x] Same suite Expected PASS, all stated data/protocol assertions pass. Commit task and ledger actual command/result.

### Task 2: Fixed two-master DDR arbitration

**Files:** create `chisel/src/main/scala/gpu/WideDdrMux.scala`; test `chisel/src/test/scala/gpu/WideDdrMuxSpec.scala`.

**Interfaces:** consumes Axi128 types; produces `WideDdrMux.io.legacy/native` Flipped Axi128MasterPort, `ddr` Axi128MasterPort, `emergency` Input Bool. Common reset only. No hidden ID tagging.

- [x] Write tests for same-ID masters, many mixed legacy IDs, read/write independent owners,16-credit saturation and simultaneous retire/accept, >=4 old writes, stalled addresses, W before AW, emergency cancellation/fairness, common reset.
- [x] Run focused suite Expected RED missing WideDdrMux.
- [x] Implement direction owner/count, address-promise locks, write-address/data outstanding count, native turn quota2, drain-and-switch only when other eligible. Keep legacy admission alive in emergency unless native already promised.
- [x] Focused suite Expected PASS. Commit and ledger actual evidence.

### Task 3: Command, metrics, reset and board integration

**Files:** modify `RenderEngine.scala`, `Efinix2dGpuTop.scala`, `GpuPerfCounters.scala`, `GenerateEfinix2dGpu.scala`, `board/efinix_ti60/rtl/efinix_sapphire_adapter.v`, build scripts as needed. Test `WideCopyRenderSpec.scala`, `GpuPerfCountersSpec.scala`, board build preparation checks; reuse existing fixtures.

**Interfaces:** trailing `enableWideCopyDma:Boolean=false` on Render/Top. Render optional `fabricReset` Bool and `wideAxi` Axi128 master. Top optional common-reset input and legacy/ddr128 ports; mux under common reset, DMA under common reset with GPU reset as abort. No new clock domain or software opcode. Optional wide perf events merge into original counters without changing old IO when disabled. Board build derives a generated include from actual selected GPU interface and rejects mismatched manifest; existing default direct wiring unchanged.

- [ ] RED tests for Copy>=4096 using wide not narrow, legal unaligned/strided/small fallback, invalid/overflow/overlap rejection, exact pixels/guards, finalB ordering before following Fill/Alpha/Key/HUD/PRESENT, local reset recovery with legacy response survival; wide+narrow samecycle byte sums and clear. RED build test for half-enabled source selection.
- [ ] Implement command gating after validator, completion ownership, backend busy and handshake accounting; Top common-reset fabric and explicit scanout emergency; adapter wide ports under generated build define. Expected focused suites PASS, default existing consumers unchanged.
- [ ] Run complete GPU suite via `scripts/test-v3-gpu.ps1 -LogPath <fresh>` and affected board/HDL checks once; Expected PASS or named preexisting exception reported. Generate split RTL with full baseline flags plus `--wide-copy-dma`; verify filelist exactly one module/file and build flag consistency. Commit and ledger results.

### Task 4: Physical and board acceptance, evidence

**Files:** evidence report `docs/efinix_2d_gpu/evidence/wide_copy_dma_20261022/README.md`, README status only once results exist; preserve generated logs and private ledger.

- [ ] Run isolated/full-board map then compile in fresh `D:/efinity_builds/wide_copy_dma_20261022_rN` with candidate generated source. Expected resources within Global Constraints, final16 strictly-positive timing entries and routed net CDC all pass. If optional Transform is resource/timing cause, build same-trim control and candidate; if core gates still fail stop board integration and retain old primary.
- [ ] After pass, verify actual board USB and network availability read-only; only then full JTAG BIT followed by same diagnostic BIN. Expected byte checks/errors/underflows zero; collect old/new/old phase results. No overlapping serial/JTAG/control writers.
- [ ] If net benefit plausible, same normal1024 >=3600 and unchanged challenge; preserve all failures and identities. Expected no new errors/underflows; 30% background reduction is a target, not an assertion substituted for measurement.
- [ ] Record actual result, rollback decision, hashes, features, timing, counters, gains and limitations. One fresh whole-round code review, TDD fix Important/Critical in one pass, archive ledger/review evidence; local commits only. No repeated unchanged long suite just to commit.
