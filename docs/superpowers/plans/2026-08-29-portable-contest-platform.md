# Portable Contest Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the merged Chisel SoC, video RTL, and bare-metal software into a portable contest base with a backpressured stream, real frame semantics, performance counters, UART RX, a small CLI, and deterministic regressions.

**Architecture:** Keep the RV32I CPU and CoreBus control plane unchanged. Add a parameterized ready/valid stream beat at the accelerator boundary, extend the existing accelerator and UART register banks minimally, and verify the same contracts at RTL, Chisel integration, and software levels. Vendor AXI and board IP stay outside the implementation.

**Tech Stack:** Scala 2.13, Chisel 7.9, SystemVerilog/Verilog, Verilator 5.020, RV32I freestanding C, PowerShell, Ubuntu WSL

**Spec:** `docs/superpowers/specs/2026-08-29-portable-contest-platform-design.md`

## Global Constraints

- Keep the CPU five-stage RV32I implementation unchanged.
- Do not modify `D:/loong/CPU-5/nscscc-solo-la-soc-master/rtl/`.
- Preserve accelerator base `0x30000000`, UART base `0x10000000`, and external memory base `0x80000000`.
- Keep the data path at one registered accelerator stage and one accepted beat per cycle when unstalled.
- Do not implement vendor DDR, AXI, HDMI, MIPI, Ethernet, PCIe, or physical UART IP.
- Run no intermediate Vivado jobs; at most one final SoCTop check.
- Follow test-first red/green cycles and commit each independently testable task.

---

### Task 1: Backpressured stream and real frame semantics

**Files:**
- Create: `chisel/src/main/scala/soc/StreamBeat.scala`
- Create: `chisel/src/test/resources/video/threshold_frame.csv`
- Modify: `rtl/video/VideoAccelTop.v`
- Modify: `tb/tb_video_accel_top.sv`
- Modify: `chisel/src/main/scala/soc/VideoAccelExt.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`
- Modify: `chisel/src/test/scala/soc/VideoAccelExtSpec.scala`
- Modify: `chisel/src/test/scala/soc/SoCTopSmokeSpec.scala`
- Modify: `chisel/src/test/scala/soc/SoftwareDriverSpec.scala`
- Modify: `docs/accel_if.md`

**Interfaces:**
- Produces: `class StreamBeat(dataWidth: Int)` with `data`, `startOfFrame`, `endOfLine`, and `endOfFrame` fields
- Produces: `VideoStreamIO.in: DecoupledIO[StreamBeat]` and `VideoStreamIO.out: DecoupledIO[StreamBeat]`
- Produces: flat Verilog ports `pixel_in_ready`, `pixel_in_start_of_frame`, `pixel_in_end_of_line`, `pixel_in_end_of_frame`, `pixel_out_ready`, and matching output sidebands

- [ ] **Step 1: Write the failing standalone RTL checks**

Update `tb_video_accel_top.sv` to connect the new ports and assert these literal behaviors:

```systemverilog
out_ready=0, accepted pixel 24'h336699 -> out_valid stays 1 and all output fields stay unchanged for three clocks
out_ready=1                         -> the held beat transfers
input eof=0                         -> frame_done remains 0
input eof=1 and output transfers    -> frame_done is 1 for exactly one clock
simultaneous output/input transfer  -> no bubble and the next literal pixel appears
```

- [ ] **Step 2: Run the standalone regression and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-video-rtl.ps1
```

Expected: compile failure because `VideoAccelTop` lacks the new handshake and boundary ports.

- [ ] **Step 3: Implement the minimal one-entry stream register**

Implement `pixel_in_ready = enable && (!pixel_out_valid || pixel_out_ready)`. Hold output data and sidebands whenever `pixel_out_valid && !pixel_out_ready`. Clear `pixel_out_valid` on a transfer unless a new input is accepted on the same edge. Pulse `frame_done` from the transferred output beat's `end_of_frame` flag.

- [ ] **Step 4: Run the standalone regression and verify GREEN**

Run the command from Step 2. Expected: `PASS: VideoAccelTop standalone regression` with exit code 0.

- [ ] **Step 5: Write the failing Chisel integration test**

Create `threshold_frame.csv` with literal rows:

```text
pixel,sof,eol,eof,expected
336699,1,0,0,000000
ffffff,0,1,0,ffffff
000000,0,0,0,000000
c0c0c0,0,1,1,ffffff
```

Update `VideoAccelExtSpec` to read the file, drive threshold mode, stall the output for two cycles on the second beat, and compare every output tuple against the literal CSV fields. The test must also assert that `frameDone` occurs only on the accepted final tuple.

- [ ] **Step 6: Run the focused Chisel test and verify RED**

Run from WSL in `chisel/`:

```bash
bash /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly soc.VideoAccelExtSpec'
```

Expected: compile failure because the new Chisel stream interface does not exist.

- [ ] **Step 7: Add the Chisel stream bundle and wire the ExtModule**

Define:

```scala
class StreamBeat(val dataWidth: Int) extends Bundle {
  val data = UInt(dataWidth.W)
  val startOfFrame = Bool()
  val endOfLine = Bool()
  val endOfFrame = Bool()
}
```

Use `Flipped(Decoupled(new StreamBeat(24)))` for the input and `Decoupled(new StreamBeat(24))` for the output. Update the SoC smoke and software driver fixtures to drive input invalid, initialize all sidebands, and set output ready.

- [ ] **Step 8: Run focused stream and SoC tests**

Run `VideoAccelExtSpec`, `SoCTopSmokeSpec`, and `SoftwareDriverSpec`. Expected: all pass.

- [ ] **Step 9: Commit Task 1**

```powershell
git add chisel/src/main/scala/soc/StreamBeat.scala chisel/src/main/scala/soc/VideoAccelExt.scala chisel/src/main/scala/soc/SoCTop.scala chisel/src/test/scala/soc/VideoAccelExtSpec.scala chisel/src/test/scala/soc/SoCTopSmokeSpec.scala chisel/src/test/scala/soc/SoftwareDriverSpec.scala chisel/src/test/resources/video/threshold_frame.csv rtl/video/VideoAccelTop.v tb/tb_video_accel_top.sv docs/accel_if.md
git commit -m "feat(stream): add backpressure and frame boundaries"
```

---

### Task 2: Accelerator performance counters

**Files:**
- Modify: `chisel/src/main/scala/soc/MemoryMap.scala`
- Modify: `chisel/src/main/scala/soc/AccelRegs.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`
- Modify: `chisel/src/test/scala/soc/AccelRegsSpec.scala`
- Modify: `chisel/src/test/scala/soc/MemoryMapSpec.scala`
- Modify: `sw/drivers/accel_driver.h`
- Modify: `sw/drivers/accel_driver.c`
- Modify: `sw/tests/driver_test.c`
- Modify: `docs/memory_map.md`

**Interfaces:**
- Consumes: `inputAccepted`, `outputAccepted`, `outputStalled`, `busy`, and `frameDone` event inputs to `AccelRegs`
- Produces: offsets `PerfControlOffset=0x14`, `CycleCountOffset=0x18`, `InputCountOffset=0x1c`, `OutputCountOffset=0x20`, `FrameCountOffset=0x24`, `StallCountOffset=0x28`, `BusyCyclesOffset=0x2c`
- Produces: C functions `accel_perf_clear()` and six `uint32_t accel_read_*()` counter readers

- [ ] **Step 1: Extend `AccelRegsSpec` before production code**

Drive two input events, one output event, one frame event, two stalled cycles, and three busy cycles. Assert the exact event counts and a nonzero cycle count, write bit0 to `PERF_CTRL`, and assert every event counter returns zero before advancing another clock. Assert writes to each read-only counter return `error=1`.

- [ ] **Step 2: Run `AccelRegsSpec` and verify RED**

Expected: compile failure on missing event ports and offsets.

- [ ] **Step 3: Implement the counters and frozen offsets**

Add six 32-bit `RegInit(0.U)` counters to `AccelRegs`. Increment from the event inputs, give `PERF_CTRL` clear priority, expose literal values through the existing read mux, and reject writes to read-only counters.

- [ ] **Step 4: Run `AccelRegsSpec` and `MemoryMapSpec`**

Expected: both pass.

- [ ] **Step 5: Add the C counter API and driver validation**

Add literal address macros and direct MMIO readers. Extend `driver_test.c` to clear counters and confirm the clear readback is zero before emitting `P`; it must not depend on an exact live cycle count.

- [ ] **Step 6: Build and run `SoftwareDriverSpec`**

Run `scripts/build-software-test.ps1`, then focused `SoftwareDriverSpec`. Expected: positive image emits `P`, forced negative image emits `F`.

- [ ] **Step 7: Commit Task 2**

```powershell
git add chisel/src/main/scala/soc/MemoryMap.scala chisel/src/main/scala/soc/AccelRegs.scala chisel/src/main/scala/soc/SoCTop.scala chisel/src/test/scala/soc/AccelRegsSpec.scala chisel/src/test/scala/soc/MemoryMapSpec.scala sw/drivers/accel_driver.h sw/drivers/accel_driver.c sw/tests/driver_test.c docs/memory_map.md
git commit -m "feat(perf): add accelerator stream counters"
```

---

### Task 3: UART RX and lightweight control CLI

**Files:**
- Create: `sw/bsp/uart.h`
- Create: `sw/bsp/uart.c`
- Create: `sw/apps/cli.c`
- Create: `chisel/src/test/scala/soc/SoftwareCliSpec.scala`
- Modify: `chisel/src/main/scala/soc/MemoryMap.scala`
- Modify: `chisel/src/main/scala/soc/MmioUart.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`
- Modify: `chisel/src/test/scala/soc/MmioUartSpec.scala`
- Modify: `chisel/src/test/scala/soc/SoCTopSmokeSpec.scala`
- Modify: `chisel/src/test/scala/soc/SoftwareDriverSpec.scala`
- Modify: `scripts/build-software-test.sh`
- Modify: `docs/memory_map.md`

**Interfaces:**
- Produces: `MmioUart.io.rx: Flipped[DecoupledIO[UInt(8.W)]]`
- Produces: UART `RXDATA=0x08`, `STATUS.rxValid=bit1`
- Produces: `uart_putc`, `uart_puts`, `uart_getc`, and `uart_readline` freestanding C functions
- Produces: `sw/build/cli.hex` interactive image

- [ ] **Step 1: Write failing UART receive tests**

Extend `MmioUartSpec` to enqueue byte `0x41`, assert status `0b11`, read `RXDATA` as `0x41`, assert status returns to `0b01`, verify an empty read errors, and verify a full receive buffer deasserts `rx.ready` without corrupting the held byte.

- [ ] **Step 2: Run `MmioUartSpec` and verify RED**

Expected: compile failure because the RX port and register do not exist.

- [ ] **Step 3: Implement the one-byte receive buffer**

Set `rx.ready := !rxValid`, capture `rx.bits` on `rx.fire`, expose bit1 in STATUS, and clear `rxValid` only when a legal nonempty `RXDATA` read request fires.

- [ ] **Step 4: Run `MmioUartSpec` and verify GREEN**

Expected: all UART register behaviors pass.

- [ ] **Step 5: Write the failing end-to-end CLI test**

Add a test that boots `sw/build/cli.hex`, collects `READY\n`, sends decoded bytes for `threshold 42\n`, collects `OK\n`, and asserts `dut.io.accelThreshold == 42`. Then it sends `threshold 999\n`, collects `ERR\n`, and asserts the threshold remains 42. Update the existing SoC software fixtures to drive `uartRx.valid := false`.

- [ ] **Step 6: Run `SoftwareCliSpec` and verify RED**

Expected: failure because `cli.hex`, the UART BSP, and CLI application do not exist.

- [ ] **Step 7: Implement the freestanding UART BSP and CLI**

Use a fixed `char line[64]`; consume input until LF/CR; reject overflow; parse unsigned decimal with an overflow guard at 255; compare commands without libc; and implement exactly the commands listed in the design spec. `perf` prints all counters as unsigned decimal and `perf clear` writes `PERF_CTRL` bit0.

- [ ] **Step 8: Build the images and run focused software tests**

Run `scripts/build-software-test.ps1`, `MmioUartSpec`, `SoftwareDriverSpec`, and `SoftwareCliSpec`. Expected: all pass.

- [ ] **Step 9: Commit Task 3**

```powershell
git add sw/bsp/uart.h sw/bsp/uart.c sw/apps/cli.c chisel/src/test/scala/soc/SoftwareCliSpec.scala chisel/src/main/scala/soc/MemoryMap.scala chisel/src/main/scala/soc/MmioUart.scala chisel/src/main/scala/soc/SoCTop.scala chisel/src/test/scala/soc/MmioUartSpec.scala chisel/src/test/scala/soc/SoCTopSmokeSpec.scala chisel/src/test/scala/soc/SoftwareDriverSpec.scala scripts/build-software-test.sh docs/memory_map.md
git commit -m "feat(uart): add RX and control CLI"
```

---

### Task 4: Integration gate and portability documentation

**Files:**
- Create: `docs/contest_portability.md`
- Modify: `scripts/verify-soc.ps1`
- Modify: `docs/chisel_build.md`
- Verify: all production and test files from Tasks 1-3

**Interfaces:**
- Produces: one documented replacement boundary for algorithm RTL, stream adapters, CoreBus-to-AXI memory bridge, board wrapper, and CLI commands
- Produces: one non-Vivado regression gate that builds both software images and runs RTL plus Chisel tests

- [ ] **Step 1: Document the four replacement points**

Describe exact files and contracts for replacing `VideoAccelTop`, adapting the generic stream to AXI4-Stream, connecting `externalImem/externalDmem` through a future `CoreBusAxiBridge`, and adding CLI commands without modifying the CPU.

- [ ] **Step 2: Update the unified verification preflight**

Keep the standalone video test before software builds and Chisel tests. Ensure `cli.hex` is produced by the existing software build step and remains ignored by Git.

- [ ] **Step 3: Run complete non-Vivado verification**

Run the standalone video RTL test, software image build, SoC smoke build, and full Chisel suite. Expected: zero failed tests and no generated ELF/bin/hex files visible to Git.

- [ ] **Step 4: Generate and lint SoCTop RTL**

Run `scripts/gen-soc-rtl.ps1`, build `generated/soc-filelist.f`, and run Verilator lint over generated SoCTop plus `rtl/video/VideoAccelTop.v`.

- [ ] **Step 5: Run one final Vivado check**

Run `scripts/verify-soc.ps1` once after all pure simulations pass. Record WNS, logic levels, LUT, FF, BRAM, and DSP results in `docs/contest_portability.md`.

- [ ] **Step 6: Commit Task 4**

```powershell
git add docs/contest_portability.md docs/chisel_build.md scripts/verify-soc.ps1 docs/superpowers/specs/2026-08-29-portable-contest-platform-design.md docs/superpowers/plans/2026-08-29-portable-contest-platform.md
git commit -m "docs: define portable contest integration workflow"
```
