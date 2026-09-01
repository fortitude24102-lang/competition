# Pango Bring-up Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add board-independent GPIO and a CLINT-layout 64-bit machine timer so the Chisel SoC has the minimum observable and measurable foundation needed for the Pango MES2L676-100HP board.

**Architecture:** Two small CoreBus peripherals are decoded by the existing single-outstanding interconnect. `SoCTop` exposes eight GPIO inputs, eight GPIO outputs, and the timer interrupt; the interrupt remains outside the CPU until the separate CSR plan.

**Tech Stack:** Scala 2.13, Chisel 7.7, ScalaTest, CIRCT simulator, RV32I bare-metal C

**Spec:** `docs/superpowers/specs/2026-09-01-pango-riscv-platform-design.md`

## Global Constraints

- Do not modify `D:/loong/CPU-5/nscscc-solo-la-soc-master/rtl/`.
- Write CPU and generic SoC RTL in Chisel and generate SystemVerilog for PDS.
- Keep the current five-stage single-issue core and avoid adding long combinational paths.
- Preserve the external-memory window beginning at `0x8000_0000` for a future AXI4 bridge.
- Do not invoke Vivado during intermediate tasks.

---

### Task 1: Freeze the GPIO and machine-timer memory map

**Files:**
- Modify: `chisel/src/main/scala/soc/MemoryMap.scala`
- Modify: `chisel/src/test/scala/soc/MemoryMapSpec.scala`
- Modify: `docs/memory_map.md`

**Interfaces:**
- Produces: `MemoryMap.TimerBase`, `TimerBytes`, `GpioBase`, `GpioBytes`, `isTimer(UInt)`, `isGpio(UInt)`, `MemoryMap.Timer.*Offset`, and `MemoryMap.Gpio.*Offset`

- [x] **Step 1: Write the failing address-map tests**

Add literal boundary assertions for `0x0200_0000..0x0200_FFFF` and `0x1000_1000..0x1000_1FFF`, plus literal offset assertions for `0x4000`, `0x4004`, `0xBFF8`, `0xBFFC`, `0x00`, and `0x04`.

- [x] **Step 2: Run the focused test and verify RED**

Run: `sbt "testOnly soc.MemoryMapSpec"`

Expected: compilation fails because the timer/GPIO regions and offsets do not exist.

- [x] **Step 3: Implement the minimal map**

Add `MemoryRegion.Timer` and `MemoryRegion.Gpio`; place Timer before UART in `regionOf`, add the UInt predicates, and document the exact ranges and register behavior in `docs/memory_map.md`.

- [x] **Step 4: Run the focused test and verify GREEN**

Run: `sbt "testOnly soc.MemoryMapSpec"`

Expected: all `MemoryMapSpec` tests pass.

- [x] **Step 5: Commit**

```bash
git add chisel/src/main/scala/soc/MemoryMap.scala chisel/src/test/scala/soc/MemoryMapSpec.scala docs/memory_map.md
git commit -m "feat(soc): reserve timer and gpio address regions"
```

### Task 2: Implement GPIO and machine-timer peripherals

**Files:**
- Create: `chisel/src/main/scala/soc/Gpio.scala`
- Create: `chisel/src/main/scala/soc/MachineTimer.scala`
- Create: `chisel/src/test/scala/soc/GpioSpec.scala`
- Create: `chisel/src/test/scala/soc/MachineTimerSpec.scala`

**Interfaces:**
- Consumes: the offsets introduced by Task 1 and `SocBusTargetIO`
- Produces: `Gpio.io.bus`, `Gpio.io.input: UInt(8.W)`, `Gpio.io.output: UInt(8.W)`, `MachineTimer.io.bus`, and `MachineTimer.io.interrupt: Bool`

- [x] **Step 1: Write failing GPIO tests**

Exercise reset output 0, full-word output write/readback, live input read, response backpressure, and errors for partial writes and writes to `INPUT`. The production mutation caught is accepting an illegal access or changing output without a valid full-word write.

- [x] **Step 2: Run `GpioSpec` and verify RED**

Run: `sbt "testOnly soc.GpioSpec"`

Expected: compilation fails because `Gpio` does not exist.

- [x] **Step 3: Implement minimal GPIO**

Use one 8-bit output register and the same one-response holding pattern as `MmioUart`; require aligned 32-bit accesses and `wstrb == 0xF` for the writable register.

- [x] **Step 4: Run `GpioSpec` and verify GREEN**

Run: `sbt "testOnly soc.GpioSpec"`

Expected: all GPIO tests pass.

- [x] **Step 5: Write failing timer tests**

Check monotonic `mtime`, reset `mtimecmp == 0xFFFF_FFFF_FFFF_FFFF`, split comparison writes, interrupt assertion at the programmed count, interrupt deassertion after moving the comparison forward, invalid-access errors, and response stability under backpressure. The production mutation caught is a timer that stops, compares with `>` instead of `>=`, or loses a held response.

- [x] **Step 6: Run `MachineTimerSpec` and verify RED**

Run: `sbt "testOnly soc.MachineTimerSpec"`

Expected: compilation fails because `MachineTimer` does not exist.

- [x] **Step 7: Implement minimal machine timer**

Use two 64-bit registers, increment `mtime` every clock, update only the selected half of `mtimecmp` on valid full-word writes, compute `interrupt := mtime >= mtimecmp`, and hold one response until accepted.

- [x] **Step 8: Run both peripheral tests and verify GREEN**

Run: `sbt "testOnly soc.GpioSpec soc.MachineTimerSpec"`

Expected: both suites pass.

- [x] **Step 9: Commit**

```bash
git add chisel/src/main/scala/soc/Gpio.scala chisel/src/main/scala/soc/MachineTimer.scala chisel/src/test/scala/soc/GpioSpec.scala chisel/src/test/scala/soc/MachineTimerSpec.scala
git commit -m "feat(soc): add gpio and machine timer peripherals"
```

### Task 3: Route and expose the new peripherals

**Files:**
- Modify: `chisel/src/main/scala/soc/SoCInterconnect.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`
- Modify: `chisel/src/test/scala/soc/SoCInterconnectSpec.scala`
- Create: `chisel/src/test/scala/soc/PangoBringupSpec.scala`

**Interfaces:**
- Consumes: `Gpio`, `MachineTimer`, and Task 1 address predicates
- Produces: `SoCTop.io.gpioInput: UInt(8.W)`, `gpioOutput: UInt(8.W)`, and `timerInterrupt: Bool`

- [x] **Step 1: Extend the interconnect test and verify RED**

Add timer and GPIO targets to the target set and exercise the first and last address of each region. Run `sbt "testOnly soc.SoCInterconnectSpec"`; compilation must fail because the new target ports do not exist.

- [x] **Step 2: Add timer/GPIO target decoding**

Widen the target selector to four bits, route only data-memory accesses to the two new targets, and preserve the existing single accepted response-source lock.

- [x] **Step 3: Run the interconnect test and verify GREEN**

Run: `sbt "testOnly soc.SoCInterconnectSpec"`

Expected: all routing and backpressure assertions pass.

- [x] **Step 4: Write a failing top-level software-visible smoke test**

Instantiate `SoCTop`, drive `gpioInput`, and use a short RV32I image that reads GPIO, writes GPIO output, reads `mtime`, then reports pass over UART. Assert UART `P`, GPIO output value, and increasing time. Run the new test and observe failure before integration.

- [x] **Step 5: Integrate the peripherals in `SoCTop`**

Instantiate and connect both peripherals, expose the three top-level signals, and leave `timerInterrupt` unconnected to `Rv32Core` until the CSR task.

- [x] **Step 6: Run focused integration tests**

Run: `sbt "testOnly soc.SoCInterconnectSpec soc.PangoBringupSpec soc.SoCTopSmokeSpec"`

Expected: all suites pass.

- [x] **Step 7: Commit**

```bash
git add chisel/src/main/scala/soc/SoCInterconnect.scala chisel/src/main/scala/soc/SoCTop.scala chisel/src/test/scala/soc/SoCInterconnectSpec.scala chisel/src/test/scala/soc/PangoBringupSpec.scala
git commit -m "feat(soc): integrate timer and gpio"
```

### Task 4: Add bare-metal accessors and close the stage

**Files:**
- Create: `sw/bsp/gpio.h`
- Create: `sw/bsp/timer.h`
- Create: `sw/tests/pango_bringup.c`
- Modify: `scripts/build-software-test.sh`
- Modify: `chisel/src/test/scala/soc/PangoBringupSpec.scala`
- Modify: `docs/chisel_build.md`

**Interfaces:**
- Produces: `gpio_write(uint8_t)`, `gpio_read(void) -> uint8_t`, and `timer_read(void) -> uint64_t`

- [x] **Step 1: Make the integration test require `pango_bringup.hex` and verify RED**

Run: `sbt "testOnly soc.PangoBringupSpec"`

Expected: test fails because the software image is absent.

- [x] **Step 2: Implement the minimal header-only BSP**

`gpio_write` writes `0x10001000`, `gpio_read` reads `0x10001004`, and `timer_read` uses the high-low-high retry sequence at `0x0200BFFC/0x0200BFF8`.

- [x] **Step 3: Add the bring-up program and build target**

The program verifies GPIO input, writes a literal LED pattern, verifies `timer_read()` increased, sends `P` over UART, and executes `EBREAK` by returning from `main`.

- [x] **Step 4: Build software and verify GREEN**

Run `scripts/build-software-test.ps1`, then `sbt "testOnly soc.PangoBringupSpec"`.

Expected: the image builds and the top-level test passes.

- [x] **Step 5: Run the stage regression**

Run `sbt "testOnly soc.MemoryMapSpec soc.GpioSpec soc.MachineTimerSpec soc.SoCInterconnectSpec soc.PangoBringupSpec soc.SoCTopSmokeSpec"`, generate SoCTop SystemVerilog, and run Verilator lint. Do not run Vivado.

- [x] **Step 6: Commit**

```bash
git add sw/bsp/gpio.h sw/bsp/timer.h sw/tests/pango_bringup.c scripts/build-software-test.sh chisel/src/test/scala/soc/PangoBringupSpec.scala docs/chisel_build.md
git commit -m "test(soc): add pango bringup software smoke"
```

