# Efinix 2D GPU Lead Chisel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 由主负责人用 Chisel 完成命令前端、2D 地址生成、Sparse Blit、AXI4 主机、扫描输出、双缓冲、自适应 DDR QoS、性能统计与 SoC/板级集成。

**Architecture:** CPU 通过 CoreBus MMIO 原子提交 16 项带标签命令；BitBltEngine 将二维操作拆成 DDR burst 并调用 Verilog PixelPipe；ScanoutDma 与 CPU/GPU 经 DdrQosArbiter 共享 DDR3；FramePresenter 仅在 vblank 切换前台缓冲。

**Tech Stack:** Scala 2.13.18、Chisel 7.7.0、ScalaTest、sbt、Verilator、PowerShell、Efinity 生成的 DDR3 AXI4 控制器。

**Spec:** docs/superpowers/specs/2026-09-04-efinix-2d-gpu-design.md

## Global Constraints

- 只实现规格中的基础功能、三个高阶挑战和三个创新点；不做旋转、缩放、三角形、Z Buffer 或缓存一致性。
- 主负责人拥有本计划列出的 Chisel、集成、生成脚本和接口文档；不改组员 A 的 rtl/gpu、rtl/video、rtl/board/efinix Verilog，也不改组员 B 的 sw/gpu、sw/apps 和 sw/drivers/gpu_driver 文件。
- GpuCommand、寄存器偏移、Sparse 格式、RGB565 Alpha 舍入公式一旦在 Day 1 冻结，三人只能通过共同评审变更。
- 所有非平凡状态机先写失败测试；每个工作日结束时测试通过并形成一个可回退提交。
- AXI 仿真默认 64 位，板级宽度参数化；burst 不跨 4 KiB；无 AXI ID 乱序。
- 任何跨时钟域只使用显式异步 FIFO 或厂商已验证 CDC，不直接同步多位总线。
- 每个完成声明必须附命令输出；禁止未完成标记、空实现和跳过测试。

## Frozen External Interfaces

    class GpuCommand extends Bundle {
      val op = UInt(4.W)
      val srcAddr = UInt(32.W)
      val dstAddr = UInt(32.W)
      val width = UInt(16.W)
      val height = UInt(16.W)
      val srcStride = UInt(32.W)
      val dstStride = UInt(32.W)
      val color = UInt(16.W)
      val colorKey = UInt(16.W)
      val alpha = UInt(8.W)
      val flags = UInt(16.W)
      val tag = UInt(16.W)
    }

    class PixelPipeIO extends Bundle {
      val inValid = Output(Bool())
      val inReady = Input(Bool())
      val op = Output(UInt(3.W))
      val foreground = Output(UInt(16.W))
      val background = Output(UInt(16.W))
      val fillColor = Output(UInt(16.W))
      val colorKey = Output(UInt(16.W))
      val alpha = Output(UInt(8.W))
      val outValid = Input(Bool())
      val outReady = Output(Bool())
      val resultPixel = Input(UInt(16.W))
      val writeEnable = Input(Bool())
    }

## File and Module Map

| File / module | Responsibility | Required inputs | Target outputs | Depends on |
|---|---|---|---|---|
| docs/gpu_interface.md | 三人唯一接口合同 | approved spec | 寄存器、命令、像素流、Sparse、IRQ 表 | design spec |
| chisel/src/main/scala/soc/gpu/GpuTypes.scala | GpuCommand、状态、操作码 | frozen fields | typed Bundles/constants | Chisel |
| chisel/src/main/scala/soc/gpu/GpuRegisterMap.scala | MMIO 偏移和位定义 | 0x3000_0000 base | Scala constants matching C | GpuTypes |
| chisel/src/main/scala/soc/gpu/GpuRegs.scala | staging、原子提交、16-entry FIFO、IRQ | CoreBus req/resp, engine completion | Decoupled command, status, IRQ | GpuTypes, GpuRegisterMap |
| chisel/src/main/scala/soc/gpu/GpuCommandValidator.scala | 拒绝非法尺寸、对齐、地址和重叠 | GpuCommand | valid/error code | GpuTypes |
| chisel/src/main/scala/soc/gpu/GpuMem.scala | 内部读写请求协议与仿真内存 | address/length/data/ready | read beats/write responses | GpuTypes |
| chisel/src/main/scala/soc/gpu/BitBltEngine.scala | Fill/Copy/Key/Alpha/Sparse/PRESENT 调度与二维地址 | command, GpuMem, PixelPipe | memory requests, completion tag/error | validator, sparse decoder, PixelPipeExt |
| chisel/src/main/scala/soc/gpu/SparseBlitDecoder.scala | 解析 skip/run/row end | 32-bit headers and RGB565 words | destination offsets and foreground pixels | GpuMem protocol |
| chisel/src/main/scala/soc/gpu/PixelPipeExt.scala | Verilog PixelPipe 黑盒 | BitBlt pixel stream | result/write-enable stream | rtl/gpu/PixelPipe.v |
| chisel/src/main/scala/soc/gpu/GpuPerf.scala | 周期、像素、字节、stall、队列高水位计数 | engine/AXI/FIFO events | MMIO snapshots | GpuRegs |
| chisel/src/main/scala/soc/gpu/Axi4.scala | 参数化 AXI4 Bundle | widths | AW/W/B/AR/R channels | Chisel |
| chisel/src/main/scala/soc/gpu/GpuAxiMaster.scala | GpuMem 到 AXI burst | GpuMem requests, AXI responses | legal AXI4 master traffic | Axi4 |
| chisel/src/main/scala/soc/gpu/CoreBusAxiBridge.scala | CPU 外存访问桥 | CoreBus | single-beat/burst-safe AXI traffic | CoreBus, Axi4 |
| chisel/src/main/scala/soc/gpu/ScanoutDma.scala | 连续读取当前前台帧并维护像素 FIFO | framebuffer base, timing demand, AXI | RGB565 pixel stream, FIFO level/underflow | Axi4 |
| chisel/src/main/scala/soc/gpu/FramePresenter.scala | vblank 原子换帧 | PRESENT command, vblank | active base, completion | GpuTypes |
| chisel/src/main/scala/soc/gpu/DdrQosArbiter.scala | 截止时间感知的三主机仲裁 | scan FIFO level, CPU/GPU/scan AXI | one DDR AXI master, grant/stall events | Axi4 |
| chisel/src/main/scala/soc/gpu/GpuSubsystem.scala | GPU 内部总集成 | MMIO, DDR AXI, vblank, pixel ready | IRQ, pixel stream, counters | all gpu modules |
| chisel/src/main/scala/board/efinix/EfinixDdrExt.scala | 厂商 DDR3 AXI 黑盒边界 | board clocks/reset, AXI | DDR pins/status/responses | Efinity IP contract |
| chisel/src/main/scala/board/efinix/EfinixGpuTop.scala | 板级 CPU/GPU/DDR/HDMI 顶层 | board clocks/reset/UART/GPIO/DDR | HDMI stream ports, DDR pins | SoCTop, EfinixDdrExt |
| chisel/src/test/scala/soc/gpu/*Spec.scala | 每个上述模块的行为与随机停顿测试 | deterministic seeds/models | pass/fail evidence | matching module |
| chisel/src/main/scala/soc/MemoryMap.scala | 增加 GPU 寄存器窗口 | existing map | non-overlapping decode | GpuRegisterMap |
| chisel/src/main/scala/soc/SoCInterconnect.scala | CPU、GPU、DDR 路由 | CoreBus requests | selected response | MemoryMap |
| chisel/src/main/scala/soc/SoCTop.scala | SoC 级连接和 IRQ | CPU bus, peripherals | integrated GPU SoC | GpuSubsystem |
| chisel/src/main/scala/Generate.scala | GPU/板级 RTL 生成入口 | target selector | generated SystemVerilog | top modules |
| scripts/test-gpu-chisel.ps1, scripts/test-gpu-chisel.sh | 一键运行 GPU 测试 | repository checkout | nonzero on failure | sbt |
| scripts/gen-gpu-rtl.ps1, scripts/gen-gpu-rtl.sh | 可重复生成 RTL | Chisel sources | generated/gpu/*.sv | Generate.scala |
| generated/reports/gpu/lead-acceptance.txt | 最终命令、版本、结果记录 | verified runs | auditable acceptance | all lead deliverables |

## Day-by-Day Plan

### Day 1 — Freeze contracts and types

- [ ] Add docs/gpu_interface.md with exact register table, command layout, error codes, Sparse words, PixelPipe handshake and IRQ semantics.
- [ ] Add GpuTypes.scala and GpuRegisterMap.scala; add GpuTypesSpec.scala with width and constant assertions first.
- [ ] Run sbt "testOnly soc.gpu.GpuTypesSpec"; expect all assertions pass.
- [ ] Cross-review the document with members A/B; record accepted SHA in the document.
- [ ] Commit: docs: freeze gpu hardware software contract

### Day 2 — MMIO staging registers

- [ ] Add failing GpuRegsSpec.scala for reset values, byte strobes, readback and staging fields.
- [ ] Implement the CoreBus-facing staging registers in GpuRegs.scala without queue submission.
- [ ] Run sbt "testOnly soc.gpu.GpuRegsSpec"; expect reset/read/write cases pass.
- [ ] Commit: feat: add gpu mmio staging registers

### Day 3 — Observable 16-entry command FIFO

- [ ] Extend GpuRegsSpec.scala for atomic SUBMIT, full bus error, FIFO level/high-water mark and ordered tags.
- [ ] Implement exactly 16 synchronous entries and Decoupled output; a rejected SUBMIT must not alter pointers.
- [ ] Run sbt "testOnly soc.gpu.GpuRegsSpec"; expect wraparound and full/empty random sequence pass.
- [ ] Commit: feat: add tagged nonblocking gpu command fifo

### Day 4 — Command validation and error reporting

- [ ] Add failing GpuCommandValidatorSpec.scala for zero size, overflow, alignment, unsupported opcode and overlapping Copy.
- [ ] Implement combinational validation with stable numeric error codes; connect rejection status to GpuRegs.
- [ ] Run sbt "testOnly soc.gpu.GpuCommandValidatorSpec soc.gpu.GpuRegsSpec"; expect every invalid command rejected without DDR request.
- [ ] Commit: feat: validate gpu commands before execution

### Day 5 — Internal memory protocol

- [ ] Define GpuMem request/response Bundles and add GpuMemModel.scala under test sources with programmable backpressure.
- [ ] Add GpuMemSpec.scala for held-valid, ordered response and error propagation.
- [ ] Run sbt "testOnly soc.gpu.GpuMemSpec"; expect random stalls complete without lost beats.
- [ ] Commit: test: add gpu memory protocol model

### Day 6 — Solid Fill engine

- [ ] Add failing BitBltEngineSpec.scala for 1x1, odd width, multi-row stride and zero-stall Fill.
- [ ] Implement Fill address generation and write packing in BitBltEngine.scala.
- [ ] Run sbt "testOnly soc.gpu.BitBltEngineSpec"; expect memory image equals software oracle.
- [ ] Commit: feat: implement rgb565 solid fill

### Day 7 — Block Copy and legal bursts

- [ ] Add Copy tests with non-equal strides, unaligned row tail, backpressure and a row crossing a 4 KiB boundary.
- [ ] Implement forward non-overlapping Copy, row splitting and maximum burst limiting.
- [ ] Run BitBltEngineSpec; expect exact destination bytes and no request crosses 4 KiB.
- [ ] Commit: feat: implement strided block copy

### Day 8 — PixelPipe black-box boundary

- [ ] Add PixelPipeExt.scala matching the frozen Verilog ports exactly and a compile/elaboration test.
- [ ] Add a test-only behavioral replacement to prove valid/ready stability while stalled.
- [ ] Run sbt "testOnly soc.gpu.PixelPipeExtSpec"; expect elaboration and handshake trace pass.
- [ ] Commit: feat: add pixel pipe chisel boundary

### Day 9 — Color Key and Global Alpha scheduling

- [ ] Add engine tests that feed foreground/background pairs and random PixelPipe stalls.
- [ ] Route KEY and ALPHA reads through PixelPipe; suppress writes when writeEnable is false.
- [ ] Run BitBltEngineSpec against member B's fixed vectors; expect bit-exact RGB565 output.
- [ ] Commit: feat: schedule key and alpha blits

### Day 10 — Sparse stream decoder

- [ ] Add failing SparseBlitDecoderSpec.scala for skip/run, packed odd run, row end and truncated data.
- [ ] Implement header parsing and destination offset generation in SparseBlitDecoder.scala.
- [ ] Run sbt "testOnly soc.gpu.SparseBlitDecoderSpec"; expect decoded coordinates/pixels match vectors.
- [ ] Commit: feat: decode sparse sprite stream

### Day 11 — Sparse Blit integration

- [ ] Add end-to-end Sparse tests for transparent rows, mixed runs and malformed streams.
- [ ] Connect decoder to BitBltEngine and report a deterministic sparse-format error tag.
- [ ] Run BitBltEngineSpec and SparseBlitDecoderSpec; expect skipped pixels generate no DDR writes.
- [ ] Commit: feat: integrate sparse blit acceleration

### Day 12 — Completion IRQ and performance counters

- [ ] Add GpuPerfSpec.scala and extend GpuRegsSpec for W1C IRQ, last tag/error, cycles, pixels, read/write bytes, stalls and queue high-water.
- [ ] Implement saturating 64-bit counters with explicit snapshot/clear control.
- [ ] Run both specs; expect one completion per accepted command and stable snapshots.
- [ ] Commit: feat: expose gpu irq and performance counters

### Day 13 — AXI4 types and RAM model

- [ ] Add Axi4.scala plus AxiRamModel.scala in tests; assert channel widths and stable payload under stall.
- [ ] Add GpuAxiMasterSpec.scala with a failing single-read case.
- [ ] Run GpuAxiMasterSpec; expect initial failure only for missing master behavior, then commit the model.
- [ ] Commit: test: add parameterized axi4 gpu model

### Day 14 — AXI read bursts

- [ ] Implement AR/R path, beat counting, error propagation and 4 KiB splitting in GpuAxiMaster.scala.
- [ ] Test lengths 1..257, random R stalls and row boundaries with fixed seed.
- [ ] Run GpuAxiMasterSpec; expect all read data ordered and RLAST checked.
- [ ] Commit: feat: add gpu axi read bursts

### Day 15 — AXI write bursts

- [ ] Add failing AW/W/B tests for byte strobes, partial last beat, B error and independent channel stalls.
- [ ] Implement write buffering so AW and W obey AXI stability independently.
- [ ] Run GpuAxiMasterSpec; expect byte-exact RAM image and no deadlock in 100 randomized trials.
- [ ] Commit: feat: add gpu axi write bursts

### Day 16 — CPU external-memory bridge

- [ ] Add CoreBusAxiBridgeSpec.scala for loads/stores, byte masks, bus errors and backpressure.
- [ ] Implement CoreBusAxiBridge.scala while preserving existing CoreBus semantics.
- [ ] Run the bridge spec plus existing SoC interconnect tests; expect no regression.
- [ ] Commit: feat: bridge cpu corebus to ddr axi

### Day 17 — Scanout DMA

- [ ] Add ScanoutDmaSpec.scala for frame start, line continuity, FIFO refill thresholds, AXI stalls and underflow.
- [ ] Implement burst prefetch from active framebuffer and expose FIFO level/underflow events.
- [ ] Run ScanoutDmaSpec for two 640x480 frames; expect exact pixel order and bounded reads.
- [ ] Commit: feat: add framebuffer scanout dma

### Day 18 — Vblank-only double-buffer presentation

- [ ] Add FramePresenterSpec.scala for queued PRESENT, busy rejection policy, vblank edge and returned tag.
- [ ] Implement FramePresenter; active base may change only on vblank and after prior drawing completion.
- [ ] Run FramePresenterSpec; expect zero mid-frame base transitions.
- [ ] Commit: feat: add tear free framebuffer presentation

### Day 19 — Adaptive DDR QoS

- [ ] Add DdrQosArbiterSpec.scala with CPU/GPU/scan contention, low/high watermarks, hysteresis and starvation bounds.
- [ ] Implement scanout promotion below 1/4 FIFO, release above 3/4, round-robin otherwise, and counters per master.
- [ ] Run 10-frame randomized test; expect zero underflow in feasible bandwidth and CPU/GPU forward progress.
- [ ] Commit: feat: arbitrate ddr with scanout deadline qos

### Day 20 — GPU subsystem integration

- [ ] Add GpuSubsystemSpec.scala driving MMIO commands into an AXI RAM and consuming the scanout stream.
- [ ] Wire GpuRegs, engine, AXI masters, presenter, QoS, scanout, IRQ and performance events.
- [ ] Run Fill/Copy/Key/Alpha/Sparse/PRESENT sequence; expect tags ordered and final frame matches oracle.
- [ ] Commit: feat: integrate complete gpu subsystem

### Day 21 — Existing SoC integration

- [ ] Update MemoryMap.scala, SoCInterconnect.scala and SoCTop.scala; add GPU MMIO decode and CPU interrupt connection.
- [ ] Extend existing SoC tests for legacy UART/GPIO/RAM plus GPU register access.
- [ ] Run scripts/test-chisel.ps1 and scripts/test-gpu-chisel.ps1; expect all old and new tests pass.
- [ ] Commit: feat: connect gpu subsystem to rv32 soc

### Day 22 — RV32 full-system simulation

- [ ] Load member B's gpu_demo_smoke ELF and AXI RAM assets in a full-SoC test.
- [ ] Verify CPU submits non-blocking tagged commands, services IRQ and presents two different frames.
- [ ] Run the full-system ScalaTest with a documented timeout; expect PASS signature and no scanout underflow.
- [ ] Commit: test: run gpu demo on rv32 full system

### Day 23 — Efinity DDR3 boundary

- [ ] Add EfinixDdrExt.scala and EfinixGpuTop.scala using the generated controller's actual AXI widths and reset/calibration signals.
- [ ] Add elaboration assertions for data width, address width and clock-domain connections.
- [ ] Run scripts/gen-gpu-rtl.ps1; expect EfinixGpuTop.sv and no unconnected mandatory AXI signals.
- [ ] Commit: feat: add efinix ddr3 gpu board boundary

### Day 24 — Board bandwidth and QoS tuning

- [ ] Run color-bar scanout, then Fill stress, then sprite stress while logging FIFO low-water, underflow and per-master stall counters.
- [ ] Tune only documented watermark parameters; retain hysteresis and the same arbitration algorithm.
- [ ] Record the highest zero-underflow load and clock configuration in docs/gpu_interface.md.
- [ ] Commit: perf: tune ddr qos for 640x480 scanout

### Day 25 — Final lead acceptance

- [ ] Run scripts/test-chisel.ps1, scripts/test-gpu-chisel.ps1 and scripts/gen-gpu-rtl.ps1 from a clean checkout.
- [ ] Run the board demo for at least 10 minutes; require zero visible tearing, zero scanout underflow and ordered completion tags.
- [ ] Write generated/reports/gpu/lead-acceptance.txt with commit SHA, tool versions, commands, PASS totals, clocks, FIFO watermarks and measured bandwidth.
- [ ] Scan this plan and owned sources for unfinished markers or empty implementations; expect no matches.
- [ ] Commit: test: record lead gpu acceptance evidence

## Lead Exit Criteria

- All seven commands NOP/FILL/COPY/KEY/ALPHA/SPARSE/PRESENT follow the frozen contract; invalid commands fail before DDR access.
- The 16-entry FIFO, tags, IRQ and counters are observable from C and remain correct under backpressure.
- Scanout remains continuous at 640x480@60 Hz under the documented competition workload.
- QoS, non-blocking queue and Sparse Blit each have a switchable baseline mode and measured comparison data for the final report.
- Generated board RTL is reproducible, and the acceptance report names the exact source commit and Efinity configuration.
