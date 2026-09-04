# Efinix 2D GPU Member A Verilog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 由组员 A 用 Verilog 完成可停顿的 RGB565 PixelPipe、640x480 视频时序和 HDMI/TMDS 输出链，并提供可独立运行的仿真与板级验收证据。

**Architecture:** Chisel BitBltEngine 只提供像素运算请求；PixelPipe 负责 Copy、Fill、Color Key 和 Global Alpha 的逐像素结果。ScanoutDma 提供 RGB565 流；VideoTiming640x480 产生坐标、消隐和同步；TMDS 编码及板级适配器输出 HDMI。

**Tech Stack:** Verilog-2001、SystemVerilog testbench、iverilog 或 Verilator、PowerShell、Efinity 时序分析与板级逻辑分析。

**Spec:** docs/superpowers/specs/2026-09-04-efinix-2d-gpu-design.md

## Global Constraints

- 每个 .v 文件只能包含一个 module；gpu_defs.vh 只能包含常量/宏，不能包含 module。
- 每个 .sv 测试文件只放一个 testbench 顶层；公共测试任务放 tb/gpu_tb_tasks.svh。
- 组员 A 不实现 DDR、地址生成、MMIO、Command FIFO、Sparse 解析或软件驱动，也不修改 Chisel 和 C 文件。
- PixelPipe 必须严格遵守 valid/ready：停顿时所有有效负载保持稳定，不丢、不重、不重排。
- RGB565 Alpha 必须与软件黄金模型逐位一致：每个通道按 (fg*a + bg*(255-a) + 127)/255 舍入，再裁剪到原位宽。
- Color Key 比较完整 16 位 RGB565；相等时 write_enable=0，不相等时输出前景像素。
- HDMI 初始目标固定 640x480@60 Hz、25.175 MHz 像素时钟语义；实际 PLL/IO 原语只封装在板级适配文件中。
- 先写失败测试，结束当天前运行通过并提交；禁止未完成标记、空分支和不可重复的目测验收。

## Frozen Module Interfaces

    module PixelPipe(
      input wire clock,
      input wire reset,
      input wire in_valid,
      output wire in_ready,
      input wire [2:0] op,
      input wire [15:0] foreground,
      input wire [15:0] background,
      input wire [15:0] fill_color,
      input wire [15:0] color_key,
      input wire [7:0] alpha,
      output wire out_valid,
      input wire out_ready,
      output wire [15:0] result_pixel,
      output wire write_enable
    );

    module VideoTiming640x480(
      input wire pixel_clock,
      input wire reset,
      output wire [9:0] x,
      output wire [9:0] y,
      output wire active_video,
      output wire hsync,
      output wire vsync,
      output wire line_start,
      output wire frame_start,
      output wire vblank
    );

    module HdmiOutAdapter(
      input wire pixel_clock,
      input wire serial_clock_5x,
      input wire reset,
      input wire [15:0] rgb565,
      input wire pixel_valid,
      input wire hsync,
      input wire vsync,
      input wire active_video,
      output wire [3:0] tmds_p,
      output wire [3:0] tmds_n
    );

## File and Module Map

| File / module | Responsibility | Required inputs | Target outputs | Depends on |
|---|---|---|---|---|
| rtl/gpu/gpu_defs.vh | PixelPipe 操作码和共享宽度常量 | docs/gpu_interface.md | Verilog macros matching Chisel | frozen contract |
| rtl/gpu/PixelPipe.v / PixelPipe | Copy、Fill、Color Key、Global Alpha，带反压 | op, RGB565 fg/bg/color/key, alpha, valid/ready | RGB565 result, write_enable, valid/ready | gpu_defs.vh |
| rtl/video/VideoTiming640x480.v / VideoTiming640x480 | VGA/HDMI 640x480 计数和同步 | pixel clock/reset | x/y/active/hsync/vsync/vblank pulses | fixed timing constants |
| rtl/video/VideoTestPattern.v / VideoTestPattern | 硬件无 DDR 时生成彩条/网格 | x/y/active | RGB565 pixel/valid | VideoTiming640x480 |
| rtl/video/TmdsEncoder.v / TmdsEncoder | 8b/10b 风格 TMDS 数据/控制编码 | 8-bit data, control, data enable | 10-bit symbol | HDMI/DVI TMDS rule |
| rtl/video/TmdsSerializer10to1.v / TmdsSerializer10to1 | 10-bit symbol 串行化 | pixel clock, 5x clock, symbol | serial bit | Efinix-supported DDR output primitive boundary |
| rtl/board/efinix/HdmiClockAdapter.v / HdmiClockAdapter | 隔离 PLL/时钟原语和锁定复位 | board clock/reset | pixel clock, 5x clock, locked | Efinity PLL configuration |
| rtl/board/efinix/HdmiOutAdapter.v / HdmiOutAdapter | RGB565 扩展、3 路 TMDS 编码、时钟通道和差分输出 | RGB565/video timing/clocks | tmds_p/n[3:0] | TmdsEncoder, serializer, board IO |
| tb/gpu_tb_tasks.svh | 公共时钟、握手和断言任务，无 module | simulator | reusable tasks | none |
| tb/tb_pixel_pipe.sv / tb_pixel_pipe | PixelPipe 定向与随机反压测试 | software vectors | pass/fail | PixelPipe |
| tb/tb_video_timing_640x480.sv / tb_video_timing_640x480 | 完整帧时序检查 | pixel clock | counts/sync assertions | VideoTiming640x480 |
| tb/tb_video_test_pattern.sv / tb_video_test_pattern | 像素采样与彩条边界检查 | timing coordinates | expected RGB565 | VideoTestPattern |
| tb/tb_tmds_encoder.sv / tb_tmds_encoder | 控制码、数据码和运行差分检查 | exhaustive bytes | legal 10-bit symbols | TmdsEncoder |
| tb/tb_tmds_serializer.sv / tb_tmds_serializer | bit order、symbol boundary、reset | 10-bit symbols/clocks | serial trace | serializer |
| tb/tb_hdmi_out_adapter.sv / tb_hdmi_out_adapter | 一行 RGB565 到三路 TMDS 端到端 | pixels/timing | decoded channel equality | HDMI modules |
| scripts/test-gpu-rtl.ps1, scripts/test-gpu-rtl.sh | 一键编译全部模块并运行测试 | RTL/TB files | nonzero on any failure | iverilog or Verilator |
| generated/reports/gpu/verilog-member-a-acceptance.txt | 仿真、综合、时序、板测证据 | verified results | auditable handoff | all member A files |

## Day-by-Day Plan

### Day 1 — Freeze Verilog constants and shell

- [ ] Read docs/gpu_interface.md and add gpu_defs.vh with COPY=0, FILL=1, KEY=2, ALPHA=3 matching PixelPipeExt.
- [ ] Add a compile-only PixelPipe.v port shell and failing tb_pixel_pipe.sv for a COPY transaction.
- [ ] Compile with iverilog -g2012 -I rtl/gpu -s tb_pixel_pipe -o generated/tb_pixel_pipe.vvp tb/tb_pixel_pipe.sv rtl/gpu/PixelPipe.v; expect compile succeeds and test fails on missing result.
- [ ] Commit: test: define pixel pipe verilog contract

### Day 2 — COPY operation

- [ ] Implement one-entry elastic output buffering and COPY result=foreground.
- [ ] Test consecutive inputs, one-cycle output stall and reset during idle.
- [ ] Run scripts/test-gpu-rtl.ps1 pixel-pipe; expect COPY_PASS and no stability assertion failure.
- [ ] Commit: feat: implement pixel pipe copy path

### Day 3 — FILL operation

- [ ] Add failing Fill vectors that vary foreground/background independently.
- [ ] Implement result=fill_color with the same handshake path as COPY.
- [ ] Run pixel-pipe test; expect COPY and FILL pass for 1,000 randomized transactions.
- [ ] Commit: feat: implement pixel pipe fill path

### Day 4 — Color Key operation

- [ ] Add equal-key and one-bit-different cases for every RGB565 field.
- [ ] Implement KEY result=foreground and write_enable=(foreground!=color_key).
- [ ] Run pixel-pipe test under random out_ready; expect no write on exact key and one ordered output per input.
- [ ] Commit: feat: implement rgb565 color key

### Day 5 — Exact Global Alpha arithmetic

- [ ] Add fixed vectors for alpha 0, 1, 127, 128, 254, 255 and channel extremes from member B's model.
- [ ] Implement independent R5/G6/B5 products, +127 rounding, division by 255 and repacking.
- [ ] Run pixel-pipe test; expect bit-exact match for the fixed vectors.
- [ ] Commit: feat: implement rounded rgb565 alpha blend

### Day 6 — Exhaustive handshake stress

- [ ] Extend tb_pixel_pipe.sv to generate 20,000 seeded mixed operations and random valid/ready/reset gaps.
- [ ] Assert payload stability while stalled, input/output counts, order, write_enable and absence of X after reset.
- [ ] Run the test with seeds 1, 7 and 20260904; expect identical PASS totals and zero assertion errors.
- [ ] Commit: test: stress pixel pipe backpressure

### Day 7 — PixelPipe integration handoff

- [ ] Run the exact source list used by Chisel black-box simulation and correct only port naming/polarity mismatches.
- [ ] Produce a waveform for one transaction of every operation and review it with the lead.
- [ ] Tag the accepted interface SHA in generated/reports/gpu/verilog-member-a-acceptance.txt.
- [ ] Commit: test: qualify pixel pipe for chisel integration

### Day 8 — Video timing counters

- [ ] Add failing tb_video_timing_640x480.sv checking 800 clocks/line, 525 lines/frame and x/y wrap.
- [ ] Implement VideoTiming640x480.v with localparams: active 640/480, H front/sync/back 16/96/48, V front/sync/back 10/2/33.
- [ ] Run timing test for one frame; expect exact totals and coordinate bounds.
- [ ] Commit: feat: add 640x480 video counters

### Day 9 — Sync, blanking and vblank verification

- [ ] Add assertions for active_video, active-low hsync/vsync windows, line_start, frame_start and vblank.
- [ ] Run for three complete frames; expect pulse counts 1575 line starts, 3 frame starts, and no active pixel in blanking.
- [ ] Commit: test: verify 640x480 sync and blanking

### Day 10 — Standalone test pattern

- [ ] Add failing tb_video_test_pattern.sv at every color boundary and active/blank transition.
- [ ] Implement VideoTestPattern.v with eight vertical RGB565 bars and a one-pixel white grid every 64 pixels.
- [ ] Run pattern test; expect blank pixels invalid/black and active samples exact.
- [ ] Commit: feat: add hdmi bringup test pattern

### Day 11 — TMDS encoder control symbols

- [ ] Add tb_tmds_encoder.sv with the four mandated control symbols and reset running disparity.
- [ ] Implement blanking/control branch in TmdsEncoder.v.
- [ ] Run encoder test; expect the exact four 10-bit control codes.
- [ ] Commit: feat: encode tmds control periods

### Day 12 — TMDS active data encoding

- [ ] Extend the encoder test to all 256 byte values across positive/negative running disparity.
- [ ] Implement transition minimization and DC balancing; assert legal symbol output each clock.
- [ ] Compare against a testbench reference function; expect exhaustive equality.
- [ ] Commit: feat: encode dc balanced tmds data

### Day 13 — 10:1 serializer

- [ ] Add failing tb_tmds_serializer.sv for LSB-first order, reset and adjacent symbols.
- [ ] Implement TmdsSerializer10to1.v with a single documented pixel-to-serial clock relationship.
- [ ] Run serializer test for 1,000 symbols; expect every reconstructed symbol equals input.
- [ ] Commit: feat: serialize tmds symbols

### Day 14 — Serializer CDC and boundary stress

- [ ] Add clock phase offsets and randomized reset release to tb_tmds_serializer.sv.
- [ ] Add the minimum symbol handoff storage required to prevent tearing at the 10-bit boundary.
- [ ] Run seeds 1, 7 and 20260904; expect zero duplicated/mixed symbols.
- [ ] Commit: test: harden tmds serializer boundary

### Day 15 — HDMI output adapter

- [ ] Add HdmiOutAdapter.v wiring blue data+sync, green data, red data, and the TMDS clock channel.
- [ ] Convert RGB565 to RGB888 by bit replication: R5->{R5,R5[4:2]}, G6->{G6,G6[5:4]}, B5->{B5,B5[4:2]}.
- [ ] Compile each .v separately and scan module declarations; expect exactly one module per file.
- [ ] Commit: feat: assemble hdmi tmds output adapter

### Day 16 — HDMI end-to-end simulation

- [ ] Add tb_hdmi_out_adapter.sv sending one active line plus blanking and reconstructing 10-bit symbols.
- [ ] Check RGB expansion, blue sync controls, channel order and differential complement.
- [ ] Run HDMI test; expect decoded values equal source samples and tmds_n is complement of tmds_p.
- [ ] Commit: test: verify hdmi output chain

### Day 17 — Board clocks and color bars

- [ ] Add HdmiClockAdapter.v as the only file containing board PLL/clock primitive bindings.
- [ ] Integrate VideoTiming640x480 plus VideoTestPattern in the board sandbox without DDR.
- [ ] Build in Efinity; require PLL lock, no unconstrained HDMI clock, and stable color bars on monitor.
- [ ] Commit: feat: add efinix hdmi clock boundary

### Day 18 — Framebuffer stream connection

- [ ] Replace the pattern source with lead's scanout RGB565/valid stream at the frozen adapter boundary.
- [ ] Simulate one line with deterministic pixels and check the first/last active sample alignment to x=0/639.
- [ ] Run RTL and Chisel integration tests; expect no one-pixel horizontal shift.
- [ ] Commit: feat: connect scanout stream to hdmi

### Day 19 — Underflow and blank behavior

- [ ] Add cases where pixel_valid drops during active and blanking intervals.
- [ ] Define deterministic underflow output as magenta RGB565 0xF81F during active; blanking always emits TMDS control symbols.
- [ ] Run HDMI test; expect visible diagnostic only on true active underflow and no stale pixel reuse.
- [ ] Commit: feat: make scanout underflow observable

### Day 20 — Mixed-operation image regression

- [ ] Feed the lead/member B reference frame containing Fill, Copy, Key and Alpha regions into the scanout interface.
- [ ] Sample fixed coordinates before TMDS encoding and compare exact RGB565 values.
- [ ] Run scripts/test-gpu-rtl.ps1; expect all module and image regression tests pass.
- [ ] Commit: test: add gpu display image regression

### Day 21 — Pipeline and timing closure

- [ ] Synthesize PixelPipe and HDMI modules at target clocks; record worst paths and resource use.
- [ ] Add only registers required by failing timing paths while preserving handshake latency independence.
- [ ] Re-run all simulations and Efinity timing; expect zero failing paths at documented clocks.
- [ ] Commit: perf: close pixel and hdmi timing

### Day 22 — Physical monitor validation

- [ ] Test three HDMI monitors/capture modes when available, documenting detected resolution and link stability.
- [ ] Run color bars for 10 minutes and record absence of resync/blanking.
- [ ] Save clock, pin and Efinity version evidence in the acceptance report.
- [ ] Commit: test: validate hdmi monitor compatibility

### Day 23 — Alpha and Color Key visual QA

- [ ] Display a checkerboard background with alpha values 0/64/128/192/255 and keyed sprite edges.
- [ ] Compare captured checkpoints with the golden RGB565 values; require no key halo caused by PixelPipe.
- [ ] Run the standard RTL suite afterward; expect no regression.
- [ ] Commit: test: visually qualify alpha and color key

### Day 24 — Sparse-mode display regression

- [ ] Display member B's same sprite once through normal Key and once through lead's Sparse Blit.
- [ ] Compare active-frame CRCs before TMDS; require equality while the Sparse path reports fewer source bytes.
- [ ] Record CRC and byte counts; no Sparse parser logic may be added to Verilog.
- [ ] Commit: test: verify sparse and dense display equality

### Day 25 — Final Verilog acceptance

- [ ] From a clean checkout run scripts/test-gpu-rtl.ps1 and the Efinity synthesis/timing flow.
- [ ] Check every .v under owned directories contains exactly one module and gpu_defs.vh contains none.
- [ ] Write generated/reports/gpu/verilog-member-a-acceptance.txt with SHA, tool versions, test totals, timing, resources, monitor results and frame CRCs.
- [ ] Scan owned files for unfinished markers or empty implementations; expect no matches.
- [ ] Commit: test: record verilog gpu acceptance evidence

## Member A Exit Criteria

- PixelPipe is bit-exact with the C golden model for Copy, Fill, Color Key and Global Alpha, including arbitrary backpressure.
- 640x480 timing is exact across complete frames; vblank and active-video signals match the frozen interface.
- HDMI color bars and framebuffer output remain locked on hardware with no channel swap or one-pixel offset.
- Each owned .v contains one and only one module, every test is repeatable, and the final report records timing and visual evidence.
