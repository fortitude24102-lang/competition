# Machine-Mode CSR and Interrupt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add precise machine-mode synchronous traps, Zicsr instructions, MRET, and machine timer interrupts to the default generated RV32 core while preserving EBREAK as the Demo completion mechanism.

**Architecture:** A focused `CsrFile` owns machine architectural state. CSR operations execute in EX with the existing forwarding network; synchronous traps enter from MEM, and timer interrupts flush younger work only after the current MEM instruction is preserved for WB.

**Tech Stack:** Scala 2.13, Chisel 7.7, ScalaTest, CIRCT simulator, RV32I/Zicsr bare-metal assembly

**Spec:** `docs/superpowers/specs/2026-09-01-machine-mode-csr-design.md`

## Global Constraints

- Keep the five-stage single-issue pipeline and existing CoreBus interfaces.
- Default generated CPU enables machine mode; EBREAK remains a configurable debug halt.
- Support direct `mtvec` mode only and force IALIGN=32 addresses to four-byte alignment.
- Synchronous traps outrank timer interrupts; timer interrupts outrank younger redirects.
- Do not invoke Vivado during implementation.

---

### Task 1: Decode Zicsr and MRET

**Files:**
- Modify: `chisel/src/main/scala/cpu/Rv32Isa.scala`
- Modify: `chisel/src/main/scala/cpu/Decoder.scala`
- Modify: `chisel/src/test/scala/cpu/DecoderSpec.scala`

**Interfaces:**
- Produces: `CsrOp.None/Write/Set/Clear`, `DecodedControl.csrOp`, `csrImmediate`, and `mret`

- [ ] Write decoder assertions for all six CSR encodings, register-source use, immediate-source handling, and exact `0x30200073` MRET decoding.
- [ ] Run `sbt "testOnly cpu.DecoderSpec"` and verify RED because CSR fields do not exist.
- [ ] Add the minimal enum/control fields and SYSTEM decode; preserve illegal behavior for reserved funct3 values and other privileged encodings.
- [ ] Run `DecoderSpec` and verify GREEN.
- [ ] Commit with `feat(cpu): decode zicsr and mret instructions`.

### Task 2: Implement the machine CSR file

**Files:**
- Create: `chisel/src/main/scala/cpu/CsrFile.scala`
- Create: `chisel/src/test/scala/cpu/CsrFileSpec.scala`

**Interfaces:**
- Produces: combinational CSR read data/legality, registered CSR write port, trap-entry port, MRET port, `trapVector`, `returnPc`, and `timerInterruptPending`

- [ ] Write unit tests for reset values, writable masks, read-only/unknown legality, CSR write results, trap entry, MRET state restoration, MTIP reflection, and MTIE/MIE gating.
- [ ] Run `CsrFileSpec` and verify RED because `CsrFile` does not exist.
- [ ] Implement only the ten CSRs in the spec, direct `mtvec`, and the documented update priority `trap > mret > CSR write`.
- [ ] Run `CsrFileSpec` and verify GREEN.
- [ ] Commit with `feat(cpu): add machine mode csr file`.

### Task 3: Integrate precise synchronous trap redirects

**Files:**
- Modify: `chisel/src/main/scala/cpu/CoreBus.scala`
- Modify: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Modify: `chisel/src/main/scala/cpu/PipelineControl.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32CoreTrapSpec.scala`
- Create: `chisel/src/test/scala/cpu/Rv32CoreCsrSpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32CoreArithmeticSpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32CoreControlFlowSpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32CoreMemorySpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32ProgramSpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32UiSpec.scala`

**Interfaces:**
- Produces: `Rv32Core(enableMachineMode: Boolean = true, haltOnEbreak: Boolean = true)`, input `timerInterrupt`, and `TrapTrace.interrupt`

- [ ] Add a program test that sets `mtvec`, executes ECALL, reads `mcause/mepc` in a handler, advances `mepc`, executes MRET, resumes the interrupted program, and ends with EBREAK.
- [ ] Run `Rv32CoreCsrSpec` and verify RED before core integration.
- [ ] Carry CSR operation and precise `mtval` data through ID/EX and EX/MEM, execute legal CSR writes only when EX advances, and return old CSR values through normal writeback.
- [ ] Redirect synchronous machine traps to `mtvec`; preserve legacy permanent-halt assertions with `enableMachineMode=false`; keep configurable EBREAK halt.
- [ ] Run decoder, CSR, trap, arithmetic, control-flow, and memory suites and verify GREEN.
- [ ] Commit with `feat(cpu): enter and return from machine traps`.

### Task 4: Accept precise machine timer interrupts

**Files:**
- Modify: `chisel/src/main/scala/cpu/PipelineControl.scala`
- Modify: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Modify: `chisel/src/test/scala/cpu/PipelineControlSpec.scala`
- Modify: `chisel/src/test/scala/cpu/Rv32CoreCsrSpec.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`

**Interfaces:**
- Consumes: `MachineTimer.io.interrupt`
- Produces: `PipelineAction.Interrupt` and precise `mcause=0x80000007`

- [ ] Add priority and integration tests showing that an older MEM result retires, younger writes are suppressed, `mepc` points to the oldest flushed instruction, and synchronous exceptions win over a simultaneous timer interrupt.
- [ ] Run the focused tests and verify RED before adding `PipelineAction.Interrupt`.
- [ ] Implement the interrupt action, next-PC selection, CSR trap entry, frontend redirect, and SoCTop timer connection.
- [ ] Run focused CPU/SoC tests and verify GREEN.
- [ ] Commit with `feat(cpu): handle precise machine timer interrupts`.

### Task 5: Bare-metal trap smoke and generated RTL

**Files:**
- Create: `sw/bsp/csr.h`
- Create: `sw/tests/machine_trap.c`
- Modify: `scripts/build-software-test.sh`
- Create: `chisel/src/test/scala/soc/MachineTrapSoftwareSpec.scala`
- Modify: `docs/chisel_build.md`
- Regenerate: `generated/SoCTop.sv`, `generated/Rv32Core.sv`, and `generated/soc/*.sv`

**Interfaces:**
- Produces: minimal CSR read/write/set/clear helpers and a real-software ECALL/MRET smoke image

- [ ] Write the SoC software test first and verify it fails before `machine_trap.hex` exists.
- [ ] Add a freestanding trap handler that records ECALL state, advances `mepc`, returns with MRET, prints `P`, and finishes with EBREAK.
- [ ] Build the image and run the software test until GREEN.
- [ ] Run the full non-Vivado Chisel regression, regenerate RTL, run Verilator lint, and run `git diff --check`.
- [ ] Mark this plan complete and commit with `test(cpu): verify machine trap software flow`.
