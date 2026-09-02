# CoreMark Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run official CoreMark v1.0 on the current RV32I SoC and record a reproducible pre-optimization cycle baseline.

**Architecture:** Keep official benchmark sources immutable. A small bare-metal port reuses the existing timer and UART, while a Verilator C++ harness runs a RAM-preloaded simulation top substantially faster than Scala per-cycle driving.

**Tech Stack:** RV32I GCC, CoreMark v1.0, Chisel 7.7, SystemVerilog, Verilator 5

**Spec:** `docs/superpowers/specs/2026-09-02-coremark-baseline-design.md`

## Global Constraints

- Use official CoreMark revision `1f483d5b8316753a742cbf5590caf5bd0a4e4777` unchanged.
- Use performance seeds and the standard 2000-byte data set.
- Label the short RTL result non-reportable; official results require at least ten seconds.
- Do not modify CPU microarchitecture or invoke Vivado/PDS.

---

### Task 1: Pin and verify official sources

**Files:**
- Create: `third_party/coremark/*`
- Create: `scripts/verify-coremark-sources.ps1`

- [ ] Import the official license, five algorithm sources, `core_main.c`, `coremark.h`, and source MD5 file.
- [ ] Add a script that checks the pinned file hashes and fails if benchmark algorithms change.
- [ ] Run the integrity check and commit the official source import.

### Task 2: Build the RV32I CoreMark image

**Files:**
- Create: `sw/coremark/core_portme.h`
- Create: `sw/coremark/core_portme.c`
- Create: `scripts/build-coremark.ps1`
- Create: `scripts/build-coremark.sh`

- [ ] Add a build check that fails before the port exists.
- [ ] Implement performance seeds, fixed iterations, MMIO timer hooks, and the minimal UART formatter.
- [ ] Build `coremark_smoke.hex` and `coremark_board.hex` with identical RV32I optimization flags.
- [ ] Reject an ELF whose load image exceeds the 64 KiB RAM window.

### Task 3: Run and measure the RTL baseline

**Files:**
- Modify: `chisel/src/main/scala/Generate.scala`
- Create: `tb/coremark_sim.cpp`
- Create: `scripts/run-coremark-baseline.ps1`

- [ ] Add a simulation-only generator that preloads a selected RAM image.
- [ ] Add the Verilator harness and verify it fails on a zero or missing image.
- [ ] Run the CoreMark image to EBREAK and capture UART plus elapsed simulation cycles.
- [ ] Require standard performance CRCs and reject algorithm CRC errors.
- [ ] Write `generated/reports/coremark-baseline.txt` with cycles/iteration and estimated CoreMark/MHz.

### Task 4: Close the baseline stage

**Files:**
- Modify: `.gitignore`
- Modify: `docs/chisel_build.md`
- Modify: this plan

- [ ] Run source integrity, software build, CoreMark RTL baseline, focused CPU/SoC tests, RTL generation, Verilator lint, and `git diff --check`.
- [ ] Document the measured result and its non-reportable status.
- [ ] Mark every task complete and commit without generated ELF/BIN/HEX files.
