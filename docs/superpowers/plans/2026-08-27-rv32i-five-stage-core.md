# RV32I Five-Stage Chisel Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a timing-conscious RV32I/ILP32 five-stage single-issue CPU in Chisel.

**Architecture:** The core uses explicit IF/ID, ID/EX, EX/MEM, and MEM/WB registers with centralized stall/flush control, independent ready/valid instruction and data ports, EX/MEM and MEM/WB forwarding, and precise halt-on-trap behavior. AXI, caches, and SoC address decoding remain outside the core.

**Tech Stack:** Scala 2.13.18, Chisel 7.7.0, ScalaTest/ChiselSim, Verilator, GNU RISC-V bare-metal toolchain, Vivado milestone synthesis.

**Spec:** `docs/superpowers/specs/2026-08-27-rv32i-five-stage-core-design.md`

## Global Constraints

- Write CPU source in Chisel only; generated Verilog is an artifact and must not be edited.
- Implement RV32I with ILP32; compile bare-metal code with `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`.
- Keep all added toolchain files under `D:\Chisel-environment`.
- Treat `D:\loong\CPU-5\nscscc-solo-la-soc-master` as read-only; use only `references/loongarch-core-v2` for local reference.
- Use a five-stage single-issue pipeline and keep each stage to at most one major 32-bit operation.
- Do not form a combinational ready chain across the five internal stages.
- Keep instruction/data address decoding, AXI, caches, M extension, CSR, interrupts, MMU, compressed instructions, and dual issue out of this plan.
- Run Vivado only after the first complete pipeline and after full RV32I program tests; final SoC synthesis belongs to the later SoC integration plan.
- Every non-trivial implementation step begins with a failing focused test.

---

## File Map

- `scripts/setup-riscv-toolchain.sh`: extract Ubuntu's RISC-V bare-metal compiler packages under `D:\Chisel-environment`.
- `scripts/setup-riscv-toolchain.ps1`: invoke the WSL setup and verify the compiler.
- `chisel/src/main/scala/cpu/Rv32Isa.scala`: ISA enums, instruction fields, decoded control, trap causes.
- `chisel/src/main/scala/cpu/CoreBus.scala`: independent request/response and commit/trap bundles.
- `chisel/src/main/scala/cpu/Decoder.scala`: RV32I decode and immediate generation.
- `chisel/src/main/scala/cpu/RegFile.scala`: 32×32 dual-read/single-write register file.
- `chisel/src/main/scala/cpu/Execute.scala`: ALU, branch comparison, and branch target calculation.
- `chisel/src/main/scala/cpu/LoadStoreUnit.scala`: alignment, byte mask, store formatting, and load extraction.
- `chisel/src/main/scala/cpu/PipelineControl.scala`: forwarding selection, load-use detection, and control priority.
- `chisel/src/main/scala/cpu/Frontend.scala`: PC, one-outstanding fetch state, two-entry response queue, redirect discard.
- `chisel/src/main/scala/cpu/Rv32Core.scala`: stage registers and top-level pipeline integration.
- `chisel/src/test/scala/cpu/*Spec.scala`: focused component and pipeline tests.
- `chisel/src/test/scala/cpu/TestMemory.scala`: deterministic ready/valid test memory used only by tests.
- `chisel/src/test/resources/rv32i/`: generated program images and expected signatures.
- `chisel/src/main/scala/Generate.scala`: add `Rv32Core` RTL generation.

---

### Task 1: Install the RV32I Bare-Metal Toolchain Under `D:\Chisel-environment`

**Files:**
- Create: `scripts/setup-riscv-toolchain.sh`
- Create: `scripts/setup-riscv-toolchain.ps1`
- Modify: `scripts/chisel-env.ps1`

**Interfaces:**
- Produces: `/mnt/d/Chisel-environment/riscv-toolchain/usr/bin/riscv64-unknown-elf-{gcc,objcopy,objdump}`.
- Produces: Windows environment variable `RISCV_TOOLCHAIN_HOME=D:\Chisel-environment\riscv-toolchain`.

- [x] **Step 1: Write the compiler smoke command before installation**

Run:

```powershell
wsl.exe -d Ubuntu -- bash -lc 'test -x /mnt/d/Chisel-environment/riscv-toolchain/usr/bin/riscv64-unknown-elf-gcc'
```

Expected: non-zero exit because the compiler is not installed at the required location.

- [x] **Step 2: Add the minimal extraction script**

```bash
#!/usr/bin/env bash
set -euo pipefail
root=/mnt/d/Chisel-environment/riscv-toolchain
cache=/mnt/d/Chisel-environment/cache/riscv-debs
mkdir -p "$root" "$cache"
cd "$cache"
apt-get download gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
for package in ./*.deb; do dpkg-deb -x "$package" "$root"; done
"$root/usr/bin/riscv64-unknown-elf-gcc" --version
```

The PowerShell wrapper calls this file through Ubuntu, sets `RISCV_TOOLCHAIN_HOME` for the current user, and exits with the WSL status. Add `D:\Chisel-environment\riscv-toolchain\usr\bin` to the local `chisel-env.ps1` tool path list without removing existing entries.

- [x] **Step 3: Run setup and verify RV32I compilation**

Run:

```powershell
.\scripts\setup-riscv-toolchain.ps1
wsl.exe -d Ubuntu -- bash -lc 'p=/mnt/d/Chisel-environment/riscv-toolchain/usr/bin/riscv64-unknown-elf-; printf ".globl _start\n_start: addi x1,x0,1\nebreak\n" | ${p}gcc -x assembler -march=rv32i -mabi=ilp32 -nostdlib -Wl,-Ttext=0 -o /tmp/rv32i-smoke.elf - && ${p}objdump -d /tmp/rv32i-smoke.elf'
```

Expected: disassembly contains `addi` and `ebreak`.

- [x] **Step 4: Commit**

```powershell
git add scripts/setup-riscv-toolchain.sh scripts/setup-riscv-toolchain.ps1 scripts/chisel-env.ps1
git commit -m "build(riscv): add local bare-metal toolchain setup"
```

---

### Task 2: Define Stable ISA and Core Interfaces

**Files:**
- Create: `chisel/src/main/scala/cpu/Rv32Isa.scala`
- Create: `chisel/src/main/scala/cpu/CoreBus.scala`
- Test: `chisel/src/test/scala/cpu/Rv32IsaSpec.scala`

**Interfaces:**
- Produces: `AluOp`, `BranchOp`, `Op1Sel`, `Op2Sel`, `WbSel`, `MemWidth` Chisel enums.
- Produces: `DecodedControl`, `CoreBusReq`, `CoreBusResp`, `CoreBusIO`, `CommitTrace`, `TrapTrace` bundles.
- Produces: `TrapCause` UInt constants matching RISC-V cause numbers.

- [x] **Step 1: Write failing encoding and bundle-width tests**

```scala
class Rv32IsaSpec extends AnyFunSpec with ChiselSim {
  describe("RV32I definitions") {
    it("uses the architectural trap cause numbers") {
      TrapCause.IllegalInstruction.litValue shouldBe 2
      TrapCause.Breakpoint.litValue shouldBe 3
      TrapCause.LoadAddressMisaligned.litValue shouldBe 4
      TrapCause.StoreAddressMisaligned.litValue shouldBe 6
      TrapCause.EnvironmentCall.litValue shouldBe 11
    }
  }
}
```

Import `org.scalatest.matchers.should.Matchers` and mix in `Matchers` so `shouldBe` is available.

Run `powershell -ExecutionPolicy Bypass -File scripts/test-chisel.ps1` and expect compilation to fail because `cpu.Rv32Isa` does not exist.

- [x] **Step 2: Implement the exact public bundles and enums**

```scala
package cpu

import chisel3._
import chisel3.util._

object AluOp extends ChiselEnum { val Add, Sub, Sll, Slt, Sltu, Xor, Srl, Sra, Or, And, CopyB = Value }
object BranchOp extends ChiselEnum { val None, Eq, Ne, Lt, Ge, Ltu, Geu, Jal, Jalr = Value }
object Op1Sel extends ChiselEnum { val Rs1, Pc, Zero = Value }
object Op2Sel extends ChiselEnum { val Rs2, Imm = Value }
object WbSel extends ChiselEnum { val Alu, Mem, Pc4 = Value }
object MemWidth extends ChiselEnum { val Byte, Half, Word = Value }

object TrapCause {
  val InstructionAddressMisaligned = 0.U(4.W)
  val InstructionAccessFault = 1.U(4.W)
  val IllegalInstruction = 2.U(4.W)
  val Breakpoint = 3.U(4.W)
  val LoadAddressMisaligned = 4.U(4.W)
  val LoadAccessFault = 5.U(4.W)
  val StoreAddressMisaligned = 6.U(4.W)
  val StoreAccessFault = 7.U(4.W)
  val EnvironmentCall = 11.U(4.W)
}
```

`DecodedControl` contains `legal`, `rs1Used`, `rs2Used`, `aluOp`, `op1Sel`, `op2Sel`, `branchOp`, `memRead`, `memWrite`, `memWidth`, `memUnsigned`, `regWrite`, `wbSel`, `ecall`, and `ebreak`. `CoreBusReq` contains `addr`, `write`, `size`, `wdata`, and `wstrb`; `CoreBusResp` contains `rdata` and `error`.

- [x] **Step 3: Run all Chisel tests**

Run `powershell -ExecutionPolicy Bypass -File scripts/test-chisel.ps1`.

Expected: existing RegDemo tests and new definition tests pass.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu chisel/src/test/scala/cpu/Rv32IsaSpec.scala
git commit -m "feat(cpu): define RV32I core interfaces"
```

---

### Task 3: Implement RV32I Decode and Immediate Generation

**Files:**
- Create: `chisel/src/main/scala/cpu/Decoder.scala`
- Test: `chisel/src/test/scala/cpu/DecoderSpec.scala`

**Interfaces:**
- Consumes: enums and `DecodedControl` from Task 2.
- Produces: `Decoder.io.inst: UInt(32.W)`, `io.control: DecodedControl`, `io.immediate: UInt(32.W)`, `io.rs1/rs2/rd: UInt(5.W)`.

- [x] **Step 1: Write table-driven failing tests**

Use exact instruction words: `addi x1,x2,-1 = 0xfff10093`, `add x3,x1,x2 = 0x002081b3`, `lw x5,8(x6) = 0x00832283`, `sw x5,12(x6) = 0x00532623`, `beq x1,x2,8 = 0x00208463`, `jal x1,8 = 0x008000ef`, and `0xffffffff` illegal. Check register fields, sign-extended immediate, writeback selector, memory flags, and legality.

Run the single spec and expect failure because `Decoder` is absent.

- [x] **Step 2: Implement opcode/funct decode with safe defaults**

Default every instruction to `legal := false.B`, no register write, no memory request, and no branch. Decode RV32I opcode classes `LUI`, `AUIPC`, `JAL`, `JALR`, `BRANCH`, `LOAD`, `STORE`, `OP-IMM`, `OP`, `MISC-MEM`, and `SYSTEM`; reject reserved funct combinations. Generate I/S/B/U/J immediates directly from instruction fields and sign-extend to 32 bits.

- [x] **Step 3: Run decoder and full tests**

Run:

```powershell
wsl.exe -d Ubuntu -- bash -lc 'cd /mnt/d/ZYNQ/smallproject/chisel && sbt "testOnly cpu.DecoderSpec"'
powershell -ExecutionPolicy Bypass -File scripts/test-chisel.ps1
```

Expected: all tests pass.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/Decoder.scala chisel/src/test/scala/cpu/DecoderSpec.scala
git commit -m "feat(cpu): decode the RV32I base ISA"
```

---

### Task 4: Implement Register File and Execute Units

**Files:**
- Create: `chisel/src/main/scala/cpu/RegFile.scala`
- Create: `chisel/src/main/scala/cpu/Execute.scala`
- Test: `chisel/src/test/scala/cpu/RegFileSpec.scala`
- Test: `chisel/src/test/scala/cpu/ExecuteSpec.scala`

**Interfaces:**
- Produces: `RegFile` with `rs1/rs2`, `rd`, `writeEnable`, `writeData`, `rs1Data/rs2Data`.
- Produces: `Execute` with selected operands, `aluOp`, `branchOp`, `pc`, `immediate`, `aluResult`, `branchTaken`, `branchTarget`.

- [x] **Step 1: Write failing register and ALU tests**

Check that x0 remains zero after a write, same-cycle WB data is visible on matching read ports, ADD/SUB/SLL/SRL/SRA/SLT/SLTU results match 32-bit expectations, signed and unsigned branches differ at `0xffffffff` versus `1`, and JALR clears target bit zero.

- [x] **Step 2: Implement minimal combinational execute logic**

Use `RegInit(VecInit(Seq.fill(32)(0.U(32.W))))` for a simple FPGA-friendly first version, two combinational reads, and one synchronous write. Implement one ALU `switch`; compute branch comparison and `pc + immediate` in parallel with the ALU. Select JALR target as `(rs1 + immediate) & "hfffffffe".U`.

- [x] **Step 3: Run focused and full tests**

Run `sbt "testOnly cpu.RegFileSpec cpu.ExecuteSpec"` through WSL, then `scripts/test-chisel.ps1`.

Expected: all tests pass.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/RegFile.scala chisel/src/main/scala/cpu/Execute.scala chisel/src/test/scala/cpu/RegFileSpec.scala chisel/src/test/scala/cpu/ExecuteSpec.scala
git commit -m "feat(cpu): add register file and execute units"
```

---

### Task 5: Implement Load/Store Formatting

**Files:**
- Create: `chisel/src/main/scala/cpu/LoadStoreUnit.scala`
- Test: `chisel/src/test/scala/cpu/LoadStoreUnitSpec.scala`

**Interfaces:**
- Consumes: `MemWidth`, effective address, rs2 store data, and 32-bit response data.
- Produces: `misaligned`, `wstrb`, shifted `wdata`, and sign/zero-extended `loadData`.

- [x] **Step 1: Write failing byte/half/word tests**

Test all four byte offsets for LB/LBU/SB, both legal halfword offsets for LH/LHU/SH, word offset zero for LW/SW, and misalignment at halfword offsets 1/3 and word offsets 1/2/3.

- [x] **Step 2: Implement format logic**

Derive byte shift from `addr(1,0) << 3`. `SB` uses `1.U << addr(1,0)`, `SH` uses `3.U << addr(1,0)`, and `SW` uses `15.U`. Select the addressed byte/halfword before applying `Cat(Fill(...), data)` sign extension.

- [x] **Step 3: Run focused and full tests**

Run `sbt "testOnly cpu.LoadStoreUnitSpec"`, then the project test script.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/LoadStoreUnit.scala chisel/src/test/scala/cpu/LoadStoreUnitSpec.scala
git commit -m "feat(cpu): format RV32I load and store accesses"
```

---

### Task 6: Implement Pipeline Hazard and Forwarding Control

**Files:**
- Create: `chisel/src/main/scala/cpu/PipelineControl.scala`
- Test: `chisel/src/test/scala/cpu/PipelineControlSpec.scala`

**Interfaces:**
- Produces: two `ForwardSel` outputs (`Reg`, `ExMem`, `MemWb`), `loadUseStall`, and stage enable/flush decisions.
- Consumes: valid/write/load flags and rd indices for ID/EX, EX/MEM, MEM/WB plus ID rs usage/indices and global memory wait/redirect/trap signals.

- [x] **Step 1: Write failing priority tests**

Check EX/MEM forwarding wins over MEM/WB, rd zero never forwards, unused rs fields never stall, a dependent load stalls, and control priority is `reset > trap > redirect > memoryWait > loadUse > advance`.

- [x] **Step 2: Implement direct comparisons and centralized priority**

Use exact 5-bit equality comparisons gated by stage valid, register-write, and `rd =/= 0.U`. Do not build a generic pipeline controller; emit only the enables and flushes used by `Rv32Core`.

- [x] **Step 3: Run focused and full tests**

Run `sbt "testOnly cpu.PipelineControlSpec"`, then all tests.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/PipelineControl.scala chisel/src/test/scala/cpu/PipelineControlSpec.scala
git commit -m "feat(cpu): control forwarding stalls and flushes"
```

---

### Task 7: Implement the Frontend and Redirect Discard Rule

**Files:**
- Create: `chisel/src/main/scala/cpu/Frontend.scala`
- Test: `chisel/src/test/scala/cpu/FrontendSpec.scala`

**Interfaces:**
- Consumes: `CoreBusIO` instruction port, `redirectValid`, `redirectPc`, and downstream dequeue readiness.
- Produces: fetched `pc`, `inst`, and fetch error in program order.

- [x] **Step 1: Write failing backpressure and redirect tests**

Test sequential addresses 0/4/8, one outstanding request, queue backpressure, redirect with no pending response, and redirect after an old request handshake but before its response. The stale response must be accepted and dropped; the next visible instruction must use the redirected PC.

- [x] **Step 2: Implement PC, pending, dropResponse, and a depth-2 Queue**

Set a pending bit on request fire and clear it on response fire. Instantiate Chisel `Queue` with depth 2 and `hasFlush = true`. On redirect, drive its flush input and set `dropResponse` only when an old request is pending. Do not issue the redirected request until that response has been consumed.

- [x] **Step 3: Run focused and full tests**

Run `sbt "testOnly cpu.FrontendSpec"`, then all tests.

- [x] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/Frontend.scala chisel/src/test/scala/cpu/FrontendSpec.scala
git commit -m "feat(cpu): add buffered RV32I frontend"
```

---

### Task 8: Connect the Five-Stage Arithmetic Pipeline

**Files:**
- Create: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Create: `chisel/src/test/scala/cpu/TestMemory.scala`
- Test: `chisel/src/test/scala/cpu/Rv32CoreArithmeticSpec.scala`
- Modify: `chisel/src/main/scala/Generate.scala`

**Interfaces:**
- Produces: `class Rv32Core(resetVector: BigInt = 0) extends Module` with `imem`, `dmem`, `commit`, `trap`, and `halted` IO.
- Consumes: all component interfaces from Tasks 2-7.

- [x] **Step 1: Write a failing arithmetic program test**

Load a hand-encoded program containing dependent ADDI/ADD/SUB/shift/compare operations followed by several NOPs. Drive one-cycle instruction responses with `TestMemory`, stop after the expected number of commits, and check architectural register results including EX/MEM and MEM/WB forwarding cases. EBREAK is not used until precise trap behavior exists in Task 11.

- [x] **Step 2: Connect explicit stage registers**

Create focused IF/ID, ID/EX, EX/MEM, and MEM/WB bundles inside `Rv32Core.scala`, each with a `valid` register initialized false. Connect decode, register reads, forwarding, ALU, writeback, and commit. Keep dmem inactive in this task. Add `Rv32Core` as a generation choice in `Generate.scala`.

- [x] **Step 3: Run tests and generate RTL**

Run the arithmetic spec, all Chisel tests, then generate `Rv32Core.sv` under `generated/` using the existing environment.

Expected: arithmetic program reaches EBREAK only after all prior results commit in order.

- [x] **Step 4: Run the first Vivado checkpoint once**

Run out-of-context synthesis for `Rv32Core` and save the worst timing path and logic-level report under `generated/reports/`. Do not optimize for a target frequency yet; only verify no path crosses multiple pipeline stages and no ready chain spans the core.

- [x] **Step 5: Commit**

```powershell
git add chisel/src/main/scala/cpu/Rv32Core.scala chisel/src/main/scala/Generate.scala chisel/src/test/scala/cpu/TestMemory.scala chisel/src/test/scala/cpu/Rv32CoreArithmeticSpec.scala
git commit -m "feat(cpu): connect the five-stage arithmetic pipeline"
```

---

### Task 9: Add Branches, Jumps, and Pipeline Redirects

**Files:**
- Modify: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Test: `chisel/src/test/scala/cpu/Rv32CoreControlFlowSpec.scala`

**Interfaces:**
- Consumes: `Execute.branchTaken/branchTarget` and `Frontend.redirectValid/redirectPc`.
- Produces: correct JAL/JALR link writes and two-younger-stage flush behavior.

- [ ] **Step 1: Write failing taken/not-taken and wrong-path tests**

Use a loop with BEQ/BNE plus JAL and JALR. Place register writes on wrong paths and assert they never commit. Check JAL/JALR write `PC+4` and JALR target bit zero is cleared.

- [ ] **Step 2: Wire redirect and flush**

Resolve control flow in EX, redirect the frontend on JAL/JALR or a taken conditional branch, and clear IF/ID and ID/EX valid bits. Preserve all older EX/MEM and MEM/WB instructions.

- [ ] **Step 3: Run focused and full tests**

Run the control-flow spec, then all tests.

- [ ] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/Rv32Core.scala chisel/src/test/scala/cpu/Rv32CoreControlFlowSpec.scala
git commit -m "feat(cpu): execute RV32I branches and jumps"
```

---

### Task 10: Add Loads, Stores, and Variable Bus Latency

**Files:**
- Modify: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Modify: `chisel/src/test/scala/cpu/TestMemory.scala`
- Test: `chisel/src/test/scala/cpu/Rv32CoreMemorySpec.scala`

**Interfaces:**
- Consumes: LSU formatting and `dmem` request/response.
- Produces: one-outstanding load/store behavior, store response checking, and memory-wait pipeline hold.

- [ ] **Step 1: Write failing memory and backpressure tests**

Test LB/LBU/LH/LHU/LW and SB/SH/SW at legal offsets, a dependent load-use sequence, store-data forwarding, request-ready delays, response delays, and exactly one request for each stalled instruction.

- [ ] **Step 2: Implement pending transaction state**

Issue dmem only from a valid EX/MEM memory operation. Latch request completion, keep the memory instruction stable until response fire, and block younger stages without changing older committed state. Format load data before MEM/WB. Require a response for stores and suppress repeated requests while pending.

- [ ] **Step 3: Run focused and full tests**

Run the memory spec, then all tests.

- [ ] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/Rv32Core.scala chisel/src/test/scala/cpu/TestMemory.scala chisel/src/test/scala/cpu/Rv32CoreMemorySpec.scala
git commit -m "feat(cpu): execute RV32I memory operations"
```

---

### Task 11: Add Precise Trap and Commit Behavior

**Files:**
- Modify: `chisel/src/main/scala/cpu/Rv32Core.scala`
- Test: `chisel/src/test/scala/cpu/Rv32CoreTrapSpec.scala`

**Interfaces:**
- Produces: `TrapTrace(valid, cause, pc, inst)` and sticky `halted` until reset.
- Produces: normal `CommitTrace(valid, pc, inst, writeEnable, rd, data)` only for non-trapping instructions.

- [ ] **Step 1: Write failing trap tests**

Cover illegal instruction, EBREAK, ECALL, instruction access error, load/store bus error, misaligned branch target, and misaligned half/word memory access. Assert the trap reports the oldest faulting instruction, no younger instruction commits, and no misaligned store request fires.

- [ ] **Step 2: Implement oldest-event priority and halt**

Carry exception metadata with each stage. Before applying redirect or normal writes, choose the oldest valid exception among MEM, EX, ID, and IF. Suppress register/memory side effects for that instruction, flush younger stages, pulse `trap.valid`, and set `halted` until reset.

- [ ] **Step 3: Run focused and full tests**

Run the trap spec, then all Chisel tests.

- [ ] **Step 4: Commit**

```powershell
git add chisel/src/main/scala/cpu/Rv32Core.scala chisel/src/test/scala/cpu/Rv32CoreTrapSpec.scala
git commit -m "feat(cpu): report precise RV32I traps"
```

---

### Task 12: Compile and Run RV32I Programs

**Files:**
- Create: `chisel/src/test/resources/rv32i/link.ld`
- Create: `chisel/src/test/resources/rv32i/smoke.S`
- Create: `scripts/build-rv32i-tests.sh`
- Create: `chisel/src/test/scala/cpu/Rv32ProgramSpec.scala`

**Interfaces:**
- Consumes: compiler prefix under `/mnt/d/Chisel-environment/riscv-toolchain/usr/bin`.
- Produces: raw little-endian instruction/data images and expected signature words.

- [ ] **Step 1: Write a failing compiled-program test**

The assembly program must exercise every RV32I instruction family, write a pass signature to RAM, and end with EBREAK. The Scala test loads the binary into `TestMemory`, runs with deterministic request/response delays, and checks the signature plus final EBREAK trap.

- [ ] **Step 2: Add deterministic build commands**

```bash
prefix=/mnt/d/Chisel-environment/riscv-toolchain/usr/bin/riscv64-unknown-elf-
"${prefix}gcc" -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib \
  -T chisel/src/test/resources/rv32i/link.ld \
  -o chisel/src/test/resources/rv32i/smoke.elf \
  chisel/src/test/resources/rv32i/smoke.S
"${prefix}objcopy" -O binary chisel/src/test/resources/rv32i/smoke.elf \
  chisel/src/test/resources/rv32i/smoke.bin
```

Keep generated ELF/bin files ignored; rebuild them before the program test.

- [ ] **Step 3: Run program and full tests**

Run the build script, `sbt "testOnly cpu.Rv32ProgramSpec"`, then all tests.

Expected: program signature passes and the last event is an EBREAK trap.

- [ ] **Step 4: Commit**

```powershell
git add .gitignore scripts/build-rv32i-tests.sh chisel/src/test/resources/rv32i chisel/src/test/scala/cpu/Rv32ProgramSpec.scala
git commit -m "test(cpu): run a compiled RV32I program"
```

---

### Task 13: Run RV32I Milestone Verification

**Files:**
- Create: `scripts/verify-rv32i-core.ps1`
- Create: `docs/rv32i_core_verification.md`
- Modify: generated RTL only through the Chisel generator; do not edit it.

**Interfaces:**
- Produces: one command that runs toolchain smoke, all Chisel tests, compiled program tests, RTL generation, and selected upstream RISC-V `rv32ui` compatibility tests.
- Produces: a recorded second Vivado timing checkpoint.

- [ ] **Step 1: Add the verification command and expected checks**

The PowerShell script must stop on the first failure and print one line for each completed gate: toolchain, component tests, pipeline tests, program test, RTL generation, architecture tests, and timing report.

- [ ] **Step 2: Run selected upstream RV32I compatibility tests**

Clone `https://github.com/riscv-software-src/riscv-tests.git` at commit `2ebecad997fa58cd9e5724340ba75aa4b59bd1d0` under `D:\Chisel-environment\riscv-tests`. Build and run these `rv32ui` cases through the Chisel test memory: `add`, `addi`, `and`, `andi`, `auipc`, `beq`, `bge`, `bgeu`, `blt`, `bltu`, `bne`, `jal`, `jalr`, `lb`, `lbu`, `lh`, `lhu`, `lui`, `lw`, `or`, `ori`, `sb`, `sh`, `sll`, `slli`, `slt`, `slti`, `sltiu`, `sltu`, `sra`, `srai`, `srl`, `srli`, `sub`, `sw`, `xor`, and `xori`. Keep downloaded sources and build products outside the repository; commit only the adapter and invocation script.

- [ ] **Step 3: Generate RTL and run the second Vivado checkpoint once**

Run `Rv32Core` out-of-context synthesis. Record clock constraint, worst slack, logic levels, and endpoints in `docs/rv32i_core_verification.md`. If a path contains two major 32-bit operations or crosses an unintended ready chain, fix that path and rerun once; do not perform general frequency tuning.

- [ ] **Step 4: Run the complete verification command**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify-rv32i-core.ps1
```

Expected: every gate passes and the worktree contains no generated untracked binaries.

- [ ] **Step 5: Commit**

```powershell
git add scripts/verify-rv32i-core.ps1 docs/rv32i_core_verification.md
git commit -m "test(cpu): verify the RV32I core milestone"
```

---

## Completion Criteria

- All Chisel tests pass from a clean checkout using `scripts/test-chisel.ps1`.
- GNU-compiled RV32I/ILP32 smoke program reaches the expected signature and EBREAK trap.
- The pinned upstream RISC-V `rv32ui` compatibility set passes.
- Generated `Rv32Core` RTL compiles without hand edits.
- The first two Vivado milestone reports show no unintended cross-stage combinational path or full-core ready chain.
- Original LoongArch CPU files remain unchanged; the local reference snapshot still hashes identically to its copied source files.
- The next plan may connect this core to RAM, UART, accelerator registers, and AXI without changing `CoreBusIO` or commit semantics.
