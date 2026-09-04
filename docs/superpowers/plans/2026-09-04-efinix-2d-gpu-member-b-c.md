# Efinix 2D GPU Member B C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 由组员 B 用 C 完成 GPU 驱动、逐位黄金渲染器、Sparse Sprite 打包器、双缓冲 API、互动游戏和自动性能测试，生成赛题基础/高阶挑战及三个创新点的可复现证据。

**Architecture:** 应用只调用 gpu_driver，不直接碰 MMIO。相同场景可以切换 CPU 黄金渲染与 FPGA 非阻塞命令；帧尾通过 PRESENT 在 vblank 换帧。主机工具把透明 Sprite 编为 Sparse skip/run 流；性能界面显示 FPS、队列、DDR 字节、stall、underflow 和 60 FPS Sprite 上限。

**Tech Stack:** ISO C11、主机 GCC/Clang、RISC-V GCC、现有 bare-metal BSP/UART/计时器、PowerShell、可选 PPM 图像作为无依赖回归格式。

**Spec:** docs/superpowers/specs/2026-09-04-efinix-2d-gpu-design.md

## Global Constraints

- 组员 B 只修改本计划的 C、头文件、资源、软件脚本和验收报告；不修改 Chisel、Verilog、链接地址或硬件寄存器定义。
- 应用不得直接访问 0x3000_0000；所有 MMIO 必须通过 gpu_driver.c。
- gpu_model.c 是 PixelPipe、引擎和 Demo 的共同黄金模型，RGB565 Alpha 采用每通道 (fg*a + bg*(255-a) + 127)/255。
- 资源生成器不依赖 Python/Pillow；读取简单 PPM P6 或编译内置测试数组，输出确定性的 .c/.h。
- CPU 和 GPU 对比必须使用相同资源、命令序列、缓冲区尺寸和计时窗口。
- 60 FPS 上限以连续 300 帧的第 5 百分位 FPS 不低于 60、scanout underflow=0 为通过；采用可重复的阶梯加二分搜索。
- QoS、非阻塞队列和 Sparse Blit 都必须能切换到基线模式并显示差值，不能只展示优化后的单个数字。
- 每天先写失败测试，再实现最小功能，运行通过后提交；禁止未完成标记、临时资源和伪造测量值。

## Frozen Public C API

    typedef struct {
      uint32_t src_addr;
      uint32_t dst_addr;
      uint16_t width;
      uint16_t height;
      uint32_t src_stride;
      uint32_t dst_stride;
      uint16_t color;
      uint16_t color_key;
      uint8_t alpha;
      uint16_t flags;
      uint16_t tag;
    } gpu_command_t;

    typedef struct {
      uint64_t cycles;
      uint64_t pixels;
      uint64_t read_bytes;
      uint64_t write_bytes;
      uint64_t axi_stall_cycles;
      uint32_t queue_high_water;
      uint32_t scanout_underflows;
    } gpu_perf_t;

    int gpu_try_submit(const gpu_command_t *command);
    int gpu_wait_tag(uint16_t tag, uint32_t timeout_ticks);
    int gpu_fill(uint32_t dst, uint16_t w, uint16_t h, uint32_t stride, uint16_t color, uint16_t tag);
    int gpu_copy(uint32_t src, uint32_t dst, uint16_t w, uint16_t h, uint32_t src_stride, uint32_t dst_stride, uint16_t tag);
    int gpu_color_key(uint32_t src, uint32_t dst, uint16_t w, uint16_t h, uint32_t src_stride, uint32_t dst_stride, uint16_t key, uint16_t tag);
    int gpu_alpha(uint32_t src, uint32_t dst, uint16_t w, uint16_t h, uint32_t src_stride, uint32_t dst_stride, uint8_t alpha, uint16_t tag);
    int gpu_sparse(uint32_t stream, uint32_t dst, uint16_t w, uint16_t h, uint32_t dst_stride, uint16_t tag);
    int gpu_present(uint32_t framebuffer, uint16_t tag);
    void gpu_get_perf(gpu_perf_t *out);

## File and Module Map

| File | Responsibility | Required inputs | Target outputs | Depends on |
|---|---|---|---|---|
| sw/drivers/gpu_driver.h | 寄存器、命令、错误和公开 API 声明 | docs/gpu_interface.md | C11 ABI and constants | stdint.h |
| sw/drivers/gpu_driver.c | MMIO、提交、等待、IRQ、便捷命令和性能快照 | gpu_command_t, base address, timer | status codes and commands | existing BSP |
| sw/gpu/rgb565.h | 无状态 RGB565 pack/unpack/blend helpers | channel values/pixels | exact uint16_t results | stdint.h |
| sw/gpu/sparse_format.h | Sparse header、边界和编码辅助 | skip/run | uint32_t stream words | frozen format |
| sw/gpu/gpu_model.h | 黄金渲染器声明 | framebuffer descriptors | host/target callable API | rgb565.h |
| sw/gpu/gpu_model.c | CPU Fill/Copy/Key/Alpha/Sparse 参考实现 | buffers/commands | reference framebuffer/error | gpu_model.h |
| sw/tools/sparse_packer.c | PPM/测试像素转 Sparse C 数组并报告压缩率 | P6 PPM or built-in vector/key | deterministic .h/.c text and byte counts | sparse_format.h |
| sw/assets/gpu_demo_assets.h | Sprite、字体、尺寸和调色声明 | generated assets | const declarations | stdint.h |
| sw/assets/gpu_demo_assets.c | 密集/Sparse sprite 与 5x7 字体数据 | packer output | const arrays in read-only memory | assets header |
| sw/apps/gpu_demo.c | 互动场景、三种渲染模式、双缓冲、HUD、压力测试 | driver/model/assets/input/timer | HDMI frames, UART CSV, PASS signature | all software modules |
| sw/tests/rgb565_test.c | pack/unpack/alpha 定向与全量随机测试 | helpers | pass/fail | rgb565.h |
| sw/tests/gpu_model_test.c | 五种操作和错误边界测试 | synthetic buffers | CRC/reference pixels | gpu_model |
| sw/tests/sparse_packer_test.c | 编码确定性、解码等价、边界测试 | test sprites | expected words/ratio | packer, model |
| sw/tests/gpu_driver_test.c | 假 MMIO 下的寄存器顺序、full、tag、timeout 测试 | fake register bank | pass/fail trace | gpu_driver |
| sw/tests/gpu_demo_smoke.c | 无显示主机模式下运行固定 10 帧 | fake driver/model/assets | frame CRC and CSV schema | gpu_demo components |
| scripts/build-gpu-software.ps1, scripts/build-gpu-software.sh | 构建 host tests、packer 和 RV32 demo | C sources/toolchains | generated/bin artifacts | GCC/Clang |
| scripts/test-gpu-software.ps1, scripts/test-gpu-software.sh | 一键运行测试和 CRC 回归 | built binaries | nonzero on failure | build script |
| generated/reports/gpu/c-member-b-acceptance.txt | 测试、FPS、Sprite 上限与创新对比 | board/host results | auditable evidence | all member B files |

## Error and Return Contract

- 0: GPU_OK。
- -1: GPU_EINVAL，本地参数非法，不能写 SUBMIT。
- -2: GPU_EFULL，硬件 Command FIFO 满，gpu_try_submit 立即返回。
- -3: GPU_ETIMEOUT，等待 tag 超时。
- -4: GPU_EHW，完成状态带硬件错误；通过 gpu_last_error() 读取细码。
- 地址和 stride 以字节计；RGB565 地址必须 2 字节对齐；width/height 必须非零。

## Day-by-Day Plan

### Day 1 — Freeze C protocol and compile assertions

- [ ] Add gpu_driver.h with exact register offsets, opcode/error enums, structs, APIs and _Static_assert checks for integer widths.
- [ ] Add a compile-only gpu_driver_test.c that includes the header and verifies offsets against docs/gpu_interface.md.
- [ ] Compile with cc -std=c11 -Wall -Wextra -Werror -Isw -c sw/tests/gpu_driver_test.c; expect zero warnings.
- [ ] Review names and numeric values with the lead and record accepted spec SHA.
- [ ] Commit: docs: freeze gpu c interface

### Day 2 — RGB565 helpers

- [ ] Add failing rgb565_test.c for pack/unpack, channel extremes and known red/green/blue values.
- [ ] Implement header-only static inline helpers in rgb565.h without heap or floating point.
- [ ] Run scripts/test-gpu-software.ps1 rgb565; expect all fixed cases pass.
- [ ] Commit: feat: add rgb565 software helpers

### Day 3 — Golden Solid Fill

- [ ] Add gpu_model.h/c shell and failing model tests for 1x1, odd width, padded stride and clipped-invalid rejection.
- [ ] Implement gpu_model_fill over caller-provided bounded memory.
- [ ] Run gpu_model_test under host address sanitizer when available; expect exact pixels and unchanged padding.
- [ ] Commit: feat: add cpu golden fill renderer

### Day 4 — Golden Block Copy

- [ ] Add tests for distinct strides, row tails and rejected overlapping source/destination rectangles.
- [ ] Implement forward non-overlapping gpu_model_copy using row-local memmove semantics only after validation.
- [ ] Run model test; expect byte-exact output and GPU_EINVAL for overlap.
- [ ] Commit: feat: add cpu golden block copy

### Day 5 — Golden Color Key

- [ ] Add keyed transparent, one-bit-different and padding-preservation cases.
- [ ] Implement gpu_model_color_key comparing all 16 RGB565 bits.
- [ ] Run model test; expect destination preserved only at exact-key pixels.
- [ ] Commit: feat: add cpu golden color key

### Day 6 — Golden Global Alpha

- [ ] Add alpha cases 0,1,127,128,254,255 plus 50,000 seeded random foreground/background pairs.
- [ ] Implement per-channel integer blend with +127 then /255 and no floating point.
- [ ] Emit a small fixed vector table for member A/lead tests.
- [ ] Run rgb565_test and gpu_model_test; expect exact endpoint identity and stable vector CRC.
- [ ] Commit: feat: add bit exact rgb565 alpha model

### Day 7 — Sparse format and packer

- [ ] Add sparse_format.h and failing sparse_packer_test.c for empty row, full run, alternating pixels, odd run and maximum 16-bit count.
- [ ] Implement sparse_packer.c reading P6 PPM and emitting little-endian skip/run headers plus RGB565 words.
- [ ] Run the packer twice on the same fixture; expect byte-identical output and reported dense/sparse sizes.
- [ ] Commit: feat: pack transparent sprites into sparse runs

### Day 8 — Sparse golden decode

- [ ] Extend gpu_model_test.c with valid and malformed Sparse streams, row boundaries and truncated data.
- [ ] Implement gpu_model_sparse using bounded reads and the same row-end rule as hardware.
- [ ] Round-trip pack then render; expect framebuffer equality with dense Color Key and deterministic error on malformed input.
- [ ] Commit: feat: add cpu sparse blit oracle

### Day 9 — MMIO driver foundation

- [ ] Add gpu_driver.c with injectable read32/write32 hooks for host tests and volatile MMIO hooks for RV32.
- [ ] Test reset status, staged field write order, byte/halfword masking assumptions and status decode.
- [ ] Run gpu_driver_test; expect exact fake-MMIO transaction log.
- [ ] Commit: feat: add gpu mmio driver foundation

### Day 10 — Non-blocking submit, tags and status

- [ ] Add tests for atomic SUBMIT, FIFO full immediate return, ordered completion tags, W1C IRQ and timeout.
- [ ] Implement gpu_try_submit, gpu_wait_tag, gpu_irq_ack, gpu_last_error and monotonic 16-bit tag allocation helper.
- [ ] Run driver test; expect no polling inside gpu_try_submit and no staging writes after local validation failure.
- [ ] Commit: feat: submit tagged gpu commands nonblocking

### Day 11 — Fill and Copy driver APIs

- [ ] Add driver tests for exact staged registers and opcode on gpu_fill/gpu_copy.
- [ ] Validate zero size, alignment, stride and overlap before submission.
- [ ] Run driver and model tests; expect invalid calls return GPU_EINVAL without MMIO writes.
- [ ] Commit: feat: add gpu fill and copy apis

### Day 12 — Key, Alpha and Sparse driver APIs

- [ ] Add exact register-log tests for gpu_color_key, gpu_alpha and gpu_sparse.
- [ ] Implement thin wrappers that populate gpu_command_t and reuse gpu_try_submit.
- [ ] Run driver tests; expect alpha endpoints, key and stream addresses preserved exactly.
- [ ] Commit: feat: add advanced gpu blit apis

### Day 13 — Double buffering and PRESENT

- [ ] Add a small framebuffer state inside gpu_demo.c with front/back addresses from the frozen layout.
- [ ] Add tests proving drawing always targets back and gpu_present swaps software roles only after the completion tag.
- [ ] Run gpu_demo_smoke for three frames; expect address sequence A draw, A present, B draw, B present, A draw.
- [ ] Commit: feat: add tear free double buffer api

### Day 14 — Performance snapshots and frame metrics

- [ ] Implement coherent gpu_get_perf using the hardware snapshot register and 64-bit low/high read order.
- [ ] Add timer helpers for frame time, average FPS, 5th percentile FPS, queue-full count and underflow delta.
- [ ] Test counter wrap/snapshot against fake MMIO; expect stable values even while fake live counters change.
- [ ] Commit: feat: collect gpu frame performance metrics

### Day 15 — Basic rectangles demo

- [ ] Build gpu_demo.c mode 0 using Fill and Copy to draw moving rectangles into the back buffer.
- [ ] Add keyboard/GPIO mode switch and UART one-line-per-second CSV output.
- [ ] Run 300 host smoke frames with deterministic input; expect fixed final CRC and valid CSV columns.
- [ ] Commit: feat: add fill copy double buffer demo

### Day 16 — Sprite assets and game scene

- [ ] Generate committed dense and Sparse arrays for at least three RGB565 sprites plus background tiles.
- [ ] Add deterministic sprite positions/velocities with boundary bounce and no heap allocation.
- [ ] Run host model for 300 frames; expect same CRC on repeated runs and no buffer overrun.
- [ ] Commit: feat: add deterministic sprite stress scene

### Day 17 — On-screen HUD

- [ ] Add a compact 5x7 font to gpu_demo_assets and integer-only drawing helpers.
- [ ] Display mode, FPS, sprite count, queue high-water, DDR bytes, stalls and underflows.
- [ ] Run smoke test checking selected glyph pixels and final CRC.
- [ ] Commit: feat: add gpu performance hud

### Day 18 — CPU, blocking GPU and non-blocking GPU modes

- [ ] Implement three modes using one scene command list: CPU golden, GPU wait-after-each-command, and GPU queued.
- [ ] Add queue retry on GPU_EFULL while allowing game logic to continue until the next synchronization point.
- [ ] Run host smoke and RV32 full-system simulation; expect visual CRC equality across all three modes.
- [ ] Commit: feat: compare cpu blocking and queued gpu rendering

### Day 19 — Automatic stable-60-FPS Sprite limit

- [ ] Implement warm-up 60 frames, 300 measured frames, staircase growth and binary refinement.
- [ ] Pass only when 5th-percentile FPS >=60 and underflow delta=0; print searched counts and final limit as CSV.
- [ ] Unit-test the search against a synthetic monotonic FPS function; expect exact known threshold.
- [ ] Commit: feat: measure stable 60fps sprite capacity

### Day 20 — Adaptive QoS comparison

- [ ] Add a menu/UART command switching hardware QoS between fixed round-robin baseline and adaptive watermark mode.
- [ ] Run identical 300-frame stress windows and report underflows, scan FIFO low events, CPU latency and GPU stalls.
- [ ] Reject comparison if scene seed or sprite count differs; display both results side by side.
- [ ] Commit: feat: benchmark adaptive ddr qos

### Day 21 — Sparse Blit comparison

- [ ] Add dense Color Key and Sparse modes using the same source image and destination positions.
- [ ] Verify frame CRC equality, then report source bytes, DDR read bytes, render cycles and compression ratio.
- [ ] Include at least one sparse-friendly and one opaque sprite so tradeoffs are visible.
- [ ] Commit: feat: benchmark sparse sprite transfer

### Day 22 — Full RV32 software integration

- [ ] Build gpu_demo.elf with existing startup/linker/BSP and generate the memory image requested by the lead.
- [ ] Run the lead's full-system simulator for two frames in every mode.
- [ ] Require PASS signature, ordered completion tags, zero model/GPU CRC mismatch and zero scanout underflow.
- [ ] Commit: test: qualify gpu software on rv32 simulation

### Day 23 — Board bring-up

- [ ] Verify UART command menu, timer rate, framebuffer addresses, cache-free volatile access and asset placement on hardware.
- [ ] Exercise each command independently before running the full scene; print the failing tag/error if any.
- [ ] Record a board smoke log containing device/build IDs and one successful PRESENT for A and B buffers.
- [ ] Commit: test: bring up gpu demo on efinix board

### Day 24 — Interactive game polish

- [ ] Add responsive button/UART control, pause/reset, mode cycling and sprite-count adjustment without changing renderer internals.
- [ ] Keep input handling bounded so one frame cannot spin indefinitely; show dropped/retried commands.
- [ ] Run 10-minute mixed-input soak; require no crash, tag loss, tearing or counter corruption.
- [ ] Commit: feat: finalize interactive gpu game demo

### Day 25 — Final C acceptance

- [ ] From a clean checkout run scripts/build-gpu-software.ps1 and scripts/test-gpu-software.ps1 with -Wall -Wextra -Werror.
- [ ] Run board measurements for CPU, blocking GPU, queued GPU, baseline/adaptive QoS and dense/Sparse modes with identical seeds.
- [ ] Write generated/reports/gpu/c-member-b-acceptance.txt with SHA, tool versions, test totals, CRCs, FPS distribution, stable-60 limit, bytes, stalls and underflows.
- [ ] Scan owned files for unfinished markers or temporary implementations; expect no matches.
- [ ] Commit: test: record c gpu acceptance evidence

## Member B Exit Criteria

- CPU model is bit-exact with hardware for Fill, Copy, Color Key, Global Alpha and Sparse Blit.
- Driver can fill all 16 queue entries, recover from full, wait by tag, service completion IRQ and read coherent counters.
- Demo switches among CPU/blocking/queued modes without changing the scene and presents only completed back buffers.
- It automatically reports the maximum stable 60 FPS Sprite count using the frozen statistical rule.
- It shows measured benefit and cost for adaptive QoS, non-blocking FIFO and Sparse Blit, and records reproducible CSV/CRC evidence.
