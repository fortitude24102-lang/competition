# Chisel SoC Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the task-book SoC around the existing RV32I core, including memory, UART, accelerator registers, replaceable video Verilog, reproducible RTL generation, and a stable future AXI boundary.

**Architecture:** `Rv32Core` keeps its independent ready-valid instruction and data `CoreBusIO` ports. A small address-decoding interconnect routes them to a 64 KiB dual-port boot RAM, MMIO UART, accelerator registers, or two external CoreBus master ports reserved for a future `CoreBusAxiBridge`; video processing remains an external Verilog module wrapped by Chisel `ExtModule`.

**Tech Stack:** Scala 2.13.18, Chisel 7.7.0, ScalaTest/ChiselSim, Verilator 5.050, GNU RISC-V toolchain, Vivado 2019.2.

**Spec:** `docs/superpowers/specs/2026-08-28-chisel-soc-demo-design.md`

## Global Constraints

- Reuse `chisel/src/main/scala/cpu/Rv32Core.scala`; do not change the CPU pipeline architecture.
- Keep `CoreBusIO` between CPU, SoC targets, and the future AXI bridge; do not add incomplete AXI channels in this milestone.
- Reserve external memory at `0x8000_0000`～`0xFFFF_FFFF`; future AXI work must not change existing MMIO addresses.
- Keep the original LoongArch project read-only and work only in `D:\ZYNQ\smallproject`.
- Generate SystemVerilog from Chisel; never edit generated RTL by hand.
- Use TDD for every behavior: focused RED, minimal GREEN, then the existing full suite.
- Invoke Vivado only once at the final SoC checkpoint unless that checkpoint exposes one plan-defined critical-path defect.

---

### Task 1: Freeze the SoC Bus and Memory Map

**Files:**
- Create: `chisel/src/main/scala/soc/SocBus.scala`
- Create: `chisel/src/main/scala/soc/MemoryMap.scala`
- Create: `chisel/src/test/scala/soc/MemoryMapSpec.scala`
- Create: `docs/memory_map.md`
- Create: `docs/accel_if.md`

**Interfaces:**
- Consumes: `cpu.CoreBusReq`, `cpu.CoreBusResp`, and `cpu.CoreBusIO`.
- Produces: `SocBusTargetIO`, `MemoryMap.BootRamBase`, `UartBase`, `AccelBase`, `ExternalBase`, register offsets, and hardware/pure-Scala address predicates.

- [ ] **Step 1: Write the failing memory-map test**

```scala
class MemoryMapSpec extends AnyFunSpec with Matchers {
  describe("MemoryMap") {
    it("classifies every boundary without aliasing holes") {
      MemoryMap.regionOf(BigInt("00000000", 16)) shouldBe MemoryRegion.BootRam
      MemoryMap.regionOf(BigInt("0000ffff", 16)) shouldBe MemoryRegion.BootRam
      MemoryMap.regionOf(BigInt("10000000", 16)) shouldBe MemoryRegion.Uart
      MemoryMap.regionOf(BigInt("30000000", 16)) shouldBe MemoryRegion.Accelerator
      MemoryMap.regionOf(BigInt("80000000", 16)) shouldBe MemoryRegion.External
      MemoryMap.regionOf(BigInt("40000000", 16)) shouldBe MemoryRegion.Unmapped
    }
  }
}
```

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.MemoryMapSpec"`

Expected: compilation fails because `MemoryMap` and `MemoryRegion` do not exist.

- [ ] **Step 3: Implement the minimal bus target type and constants**

```scala
class SocBusTargetIO extends Bundle {
  val req = Flipped(Decoupled(new CoreBusReq))
  val resp = Decoupled(new CoreBusResp)
}

sealed trait MemoryRegion
object MemoryRegion {
  case object BootRam extends MemoryRegion
  case object Uart extends MemoryRegion
  case object Accelerator extends MemoryRegion
  case object External extends MemoryRegion
  case object Unmapped extends MemoryRegion
}
```

`MemoryMap.regionOf` must implement the exact ranges from the spec. `MemoryMap.isBootRam/isUart/isAccelerator/isExternal` must accept `UInt` and compare only address bounds; address-offset legality remains inside each target.

- [ ] **Step 4: Write the two interface documents**

`docs/memory_map.md` must contain the four address windows, UART and accelerator register tables, access type, reset value, and unmapped-error rule. `docs/accel_if.md` must contain the exact `VideoAccelTop` ports, 24-bit RGB ordering, active-high synchronous reset, and mode definitions.

- [ ] **Step 5: Run GREEN and the existing suite**

Run: `sbt "testOnly soc.MemoryMapSpec" test`

Expected: `MemoryMapSpec` and all existing tests pass.

- [ ] **Step 6: Commit**

```powershell
git add chisel/src/main/scala/soc/SocBus.scala chisel/src/main/scala/soc/MemoryMap.scala chisel/src/test/scala/soc/MemoryMapSpec.scala docs/memory_map.md docs/accel_if.md
git commit -m "feat(soc): freeze the demo memory map"
```

---

### Task 2: Implement Accelerator Control Registers

**Files:**
- Create: `chisel/src/main/scala/soc/AccelRegs.scala`
- Create: `chisel/src/test/scala/soc/AccelRegsSpec.scala`

**Interfaces:**
- Consumes: one `SocBusTargetIO`, `busy: Bool`, and `frameDone: Bool`.
- Produces: `enable: Bool`, `mode: UInt(2.W)`, `threshold: UInt(8.W)`, and `bypass: Bool`.

- [ ] **Step 1: Write failing register tests**

The tests must drive a real request/response handshake and assert:

```scala
dut.io.mode.expect(0)
dut.io.threshold.expect(128)
dut.io.bypass.expect(true)
```

Then write MODE=2, THRESHOLD=128, BYPASS=0 and read each back. A byte write with `wstrb=0` must not change state; writing STATUS or an unknown offset must return `error=true` without side effects.

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.AccelRegsSpec"`

Expected: compilation fails because `AccelRegs` does not exist.

- [ ] **Step 3: Implement one-request/one-response register behavior**

Use RegInit values from the spec. Accept a request only when no response is pending, compute offset from `req.bits.addr`, update only writable fields and asserted byte lanes, and hold `resp.valid/bits` until `resp.ready`.

- [ ] **Step 4: Run GREEN**

Run: `sbt "testOnly soc.AccelRegsSpec"`

Expected: reset, read/write, write-strobe, read-only and illegal-offset cases pass.

- [ ] **Step 5: Commit**

```powershell
git add chisel/src/main/scala/soc/AccelRegs.scala chisel/src/test/scala/soc/AccelRegsSpec.scala
git commit -m "feat(soc): add accelerator control registers"
```

---

### Task 3: Implement the Minimal MMIO UART Port

**Files:**
- Create: `chisel/src/main/scala/soc/MmioUart.scala`
- Create: `chisel/src/test/scala/soc/MmioUartSpec.scala`

**Interfaces:**
- Consumes: one `SocBusTargetIO` and downstream `tx.ready`.
- Produces: `tx: Decoupled(UInt(8.W))`; STATUS bit0 mirrors whether a new byte can be accepted.

- [ ] **Step 1: Write failing UART tests**

Test that a TXDATA write captures the low byte and holds `tx.valid/bits` during downstream backpressure, releases it exactly once on handshake, and does not accept a second TXDATA write while occupied. STATUS must report ready before the write and not-ready while a byte is pending. Reads of TXDATA and unknown offsets return `error=true`.

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.MmioUartSpec"`

Expected: compilation fails because `MmioUart` does not exist.

- [ ] **Step 3: Implement the one-byte transmit buffer**

Use one `Reg(UInt(8.W))` and one valid bit. A legal TXDATA write requires `wstrb(0)` and an empty buffer; the bus write response is independent of the later tx handshake. STATUS is always readable. Reject unsupported sizes, reads, offsets, or a write while full with `error=true`.

- [ ] **Step 4: Run GREEN and commit**

Run: `sbt "testOnly soc.MmioUartSpec"`

```powershell
git add chisel/src/main/scala/soc/MmioUart.scala chisel/src/test/scala/soc/MmioUartSpec.scala
git commit -m "feat(soc): add the MMIO UART byte port"
```

---

### Task 4: Implement the Dual-Port Boot RAM

**Files:**
- Create: `chisel/src/main/scala/soc/DualPortRam.scala`
- Create: `chisel/src/test/scala/soc/DualPortRamSpec.scala`

**Interfaces:**
- Consumes: instruction and data `SocBusTargetIO` requests.
- Produces: independent one-cycle-later responses; optional `initFile: Option[String]` passed to `loadMemoryFromFileInline`.

- [ ] **Step 1: Write failing RAM tests**

Instantiate a small 64-word RAM and check instruction reads, data word writes, byte-strobe updates, simultaneous instruction/data reads, instruction writes rejected, and out-of-range addresses returning `error=true`.

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.DualPortRamSpec"`

Expected: compilation fails because `DualPortRam` does not exist.

- [ ] **Step 3: Implement a synthesizable two-port memory**

Use `SyncReadMem(words, Vec(4, UInt(8.W)))`. Keep one pending-response register per port. The instruction port never writes; the data port converts `wdata` and `wstrb` into four byte lanes. Both accepted reads return the addressed 32-bit little-endian word on the next cycle and hold it through response backpressure.

- [ ] **Step 4: Run GREEN and commit**

Run: `sbt "testOnly soc.DualPortRamSpec"`

```powershell
git add chisel/src/main/scala/soc/DualPortRam.scala chisel/src/test/scala/soc/DualPortRamSpec.scala
git commit -m "feat(soc): add dual-port boot RAM"
```

---

### Task 5: Route CPU Requests Through the SoC Interconnect

**Files:**
- Create: `chisel/src/main/scala/soc/SoCInterconnect.scala`
- Create: `chisel/src/test/scala/soc/SoCInterconnectSpec.scala`

**Interfaces:**
- Consumes: `cpuImem` and `cpuDmem` as `Flipped(new CoreBusIO)` slave-facing ports.
- Produces: master `CoreBusIO` ports `ramImem`, `ramDmem`, `uart`, `accelerator`, `externalImem`, and `externalDmem`.

- [ ] **Step 1: Write failing routing tests**

Test each base and end address. Hold a selected target response under CPU backpressure while changing other target inputs and assert the response remains from the accepted target. Verify instruction access to UART/Accelerator and data access to an unmapped hole produce local error responses without issuing downstream requests. Verify `0x8000_0000` routes to the external ports.

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.SoCInterconnectSpec"`

Expected: compilation fails because `SoCInterconnect` does not exist.

- [ ] **Step 3: Implement fixed-priority target selection**

Use one target register per CPU port. Drive all downstream request valids false by default, route only the selected request, and lock the selection from request handshake through response handshake. Generate a registered local error response for illegal regions. Do not connect any target `ready` signal combinationally into a different target.

- [ ] **Step 4: Run GREEN and commit**

Run: `sbt "testOnly soc.SoCInterconnectSpec"`

```powershell
git add chisel/src/main/scala/soc/SoCInterconnect.scala chisel/src/test/scala/soc/SoCInterconnectSpec.scala
git commit -m "feat(soc): route the CPU system bus"
```

---

### Task 6: Add the Replaceable Verilog Video Accelerator

**Files:**
- Create: `rtl/video/VideoAccelTop.v`
- Create: `chisel/src/main/scala/soc/VideoAccelExt.scala`
- Create: `chisel/src/test/scala/soc/VideoAccelExtSpec.scala`
- Create: `docs/video_blackbox_check.md`

**Interfaces:**
- Consumes: clock, active-high synchronous reset, `pixel_in[23:0]`, `pixel_in_valid`, `mode[1:0]`, `threshold[7:0]`, and `bypass`.
- Produces: `pixel_out[23:0]`, `pixel_out_valid`, `busy`, and one-cycle `frame_done` when a valid pixel is accepted.

- [ ] **Step 1: Write the external-module test first**

The test must compile the real `rtl/video/VideoAccelTop.v`, send RGB `0x336699`, and assert: bypass returns the same pixel; gray returns equal R/G/B bytes; threshold returns all-zero below threshold and all-one above threshold; valid is delayed by exactly one clock.

- [ ] **Step 2: Run RED**

Run: `sbt "testOnly soc.VideoAccelExtSpec"`

Expected: compilation/elaboration fails because the wrapper and Verilog module do not exist.

- [ ] **Step 3: Implement the stable port wrapper and minimal Verilog**

Declare `class VideoAccelExt(sourcePath: String) extends ExtModule`, declare every port explicitly, and call the Chisel 7 API `addPath(sourcePath)` in its body. The test instantiates it with `../rtl/video/VideoAccelTop.v`. `VideoAccelTop.v` must be one registered stage; gray may use `(R + G + B) / 3`, threshold compares the gray byte, mode 0/bypass selects input, mode 1 selects gray, mode 2 selects threshold.

- [ ] **Step 4: Run GREEN, lint, document, and commit**

Run: `sbt "testOnly soc.VideoAccelExtSpec"`

Run: `verilator --lint-only rtl/video/VideoAccelTop.v`

```powershell
git add rtl/video/VideoAccelTop.v chisel/src/main/scala/soc/VideoAccelExt.scala chisel/src/test/scala/soc/VideoAccelExtSpec.scala docs/video_blackbox_check.md
git commit -m "feat(ext): integrate the video accelerator module"
```

---

### Task 7: Assemble SoCTop and Run a Software-Level Smoke Test

**Files:**
- Create: `chisel/src/main/scala/soc/SoCTop.scala`
- Create: `chisel/src/test/resources/soc/link.ld`
- Create: `chisel/src/test/resources/soc/smoke.S`
- Create: `chisel/src/test/scala/soc/SoCTopSmokeSpec.scala`
- Create: `scripts/build-soc-smoke.sh`

**Interfaces:**
- Consumes: the existing `Rv32Core`, all Tasks 2～6 modules, and an optional RAM init file.
- Produces: video stream IO, UART `Decoupled(UInt(8.W))`, external instruction/data `CoreBusIO`, commit/trap/halted debug outputs.

- [ ] **Step 1: Write the smoke program and failing test**

The RV32I assembly program must write CTRL=1, MODE=2, THRESHOLD=128, BYPASS=0; read MODE and THRESHOLD back and branch to fail if wrong; write ASCII `P` to UART TXDATA; then execute EBREAK. Failure writes ASCII `F` before EBREAK.

The test must build/load the binary into Boot RAM, keep both external buses responding with errors, keep UART ready, and assert the observed UART byte is `P`, video control outputs are 1/2/128/0, and the final trap cause is 3.

- [ ] **Step 2: Run RED**

Run: `bash scripts/build-soc-smoke.sh && sbt "testOnly soc.SoCTopSmokeSpec"`

Expected: compilation fails because `SoCTop` does not exist.

- [ ] **Step 3: Implement the minimal SoC top**

Instantiate core, interconnect, RAM, UART, AccelRegs and VideoAccelExt. Connect every Decoupled channel explicitly, pass commit/trap/halted through unchanged, and expose both external CoreBus master ports without adding AXI signals.

- [ ] **Step 4: Run GREEN and the complete Chisel suite**

Run: `bash scripts/build-soc-smoke.sh && sbt "testOnly soc.SoCTopSmokeSpec" test`

Expected: software writes the MMIO controls, UART emits `P`, EBREAK traps, and all CPU tests remain green.

- [ ] **Step 5: Commit**

```powershell
git add chisel/src/main/scala/soc/SoCTop.scala chisel/src/test/resources/soc chisel/src/test/scala/soc/SoCTopSmokeSpec.scala scripts/build-soc-smoke.sh
git commit -m "feat(soc): assemble the RV32I demo SoC"
```

---

### Task 8: Make SoC RTL Reproducible and Record the Checkpoint

**Files:**
- Modify: `chisel/src/main/scala/Generate.scala`
- Create: `scripts/gen-soc-rtl.ps1`
- Create: `scripts/verify-soc.ps1`
- Create: `scripts/vivado-soc.tcl`
- Create: `docs/chisel_build.md`
- Create: `docs/integration_fix.md`
- Generate: `generated/SoCTop.sv` and its Chisel-generated companion modules
- Generate: `generated/reports/soc-demo/*`

**Interfaces:**
- Consumes: `Generate soc --target-dir ../generated` and `rtl/video/VideoAccelTop.v`.
- Produces: one PowerShell command that builds the program, runs all tests, regenerates RTL, lints all sources, runs the single SoC Vivado OOC checkpoint, and checks repository hygiene.

- [ ] **Step 1: Add a failing generator/verification gate**

`scripts/verify-soc.ps1` must fail unless `generated/SoCTop.sv` contains module `SoCTop`, contains an instance of `VideoAccelTop`, all Chisel tests pass, Verilator resolves the external Verilog module, and Vivado reports non-negative WNS at 100 MHz.

- [ ] **Step 2: Extend the generator minimally**

`Generate.scala` must select `SoCTop` only when the first argument is `soc`; existing `rv32` and default Blink behavior must remain unchanged.

- [ ] **Step 3: Document the exact build and integration flow**

`docs/chisel_build.md` records versions, clean generation command, required Vivado source order, and the future AXI bridge boundary. `docs/integration_fix.md` records the current fixed interface, expected software readback chain, and the absence of board-level XDC/C/video-physical files as explicit Day 11～14 prerequisites.

- [ ] **Step 4: Run the complete verification command**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-soc.ps1
```

Expected gates: environment, program build, component tests, interconnect tests, SoCTop program, RTL generation, external Verilog lint, Vivado timing, and repository hygiene all pass.

- [ ] **Step 5: Inspect the only SoC Vivado checkpoint**

Record clock, WNS, logic levels, startpoint, endpoint and LUT/FF/BRAM/DSP in `docs/chisel_build.md`. If the worst internal path contains two major 32-bit operations or an unintended full ready chain, fix only that path and rerun once; otherwise do not tune frequency.

- [ ] **Step 6: Commit**

```powershell
git add chisel/src/main/scala/Generate.scala scripts/gen-soc-rtl.ps1 scripts/verify-soc.ps1 scripts/vivado-soc.tcl docs/chisel_build.md docs/integration_fix.md generated/SoCTop.sv generated/reports/soc-demo
git commit -m "build(soc): verify the reproducible SoC milestone"
```

---

## Completion Criteria

- A clean source checkout can build the SoC smoke program and generate `SoCTop.sv` with one command.
- The compiled RV32I program controls MODE/THRESHOLD/BYPASS through real MMIO, observes readback, emits UART `P`, and ends with EBREAK.
- The generated SoC plus replaceable `VideoAccelTop.v` passes Verilator and a 100 MHz Vivado OOC checkpoint.
- `0x8000_0000` and above exits through stable external CoreBus ports suitable for a later AXI bridge; no incomplete AXI protocol logic exists in this milestone.
- Existing RV32I core tests and timing artifacts remain unchanged.
- Board-level bitstream, 30-minute run, C CLI and `demo-v1` tag remain explicitly gated on board XDC/top, actual C software, and physical video files; no placeholder bitstream or false completion claim is allowed.
