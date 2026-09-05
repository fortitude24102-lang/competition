# 易灵思 2D GPU 正式目录和复用边界

## 当前计划

唯一有效计划：`docs/word/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx`。

已删除的 `docs/superpowers/plans/2026-09-04-efinix-2d-gpu-*.md` 和 `docs/superpowers/specs/2026-09-04-efinix-2d-gpu-design.md` 属于旧的全自研 SoC 路线，不再执行。需要追溯时只通过 Git 历史查看，不能作为开发依据。

## 官方 Demo 复用方式

| 来源 | 用途 | 放置位置 |
|---|---|---|
| `08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo` | Sapphire、APB、外部 AXI、DDR3、启动和板级约束 | `board/efinix_ti60/vendor/sapphire_ddr3/` |
| `03_hdmi_tx_demo/hdmi_tx_demo_v2` | 148.5 MHz/742.5 MHz 时钟、DVI 编码和 10:1 LVDS 串化 | `board/efinix_ti60/vendor/hdmi_tx/` |
| `10_Ti60f225_sc431hai2hdmi_demo/...v6.rar` | frame buffer、Burst、FIFO 和 1080p 链路参考 | 只读参考，不整体并入工程 |

官方文件复制后保持内容不变，统一写入 `board/efinix_ti60/vendor/manifest.sha256`。比赛工程修改只发生在 `board/efinix_ti60/` 的自研 RTL、派生工程文件和约束中。

## 负责人目录

```text
chisel/src/main/scala/gpu/
├─ GpuTypes.scala
├─ GpuMemoryMap.scala
├─ GpuApbRegs.scala
├─ CommandQueue.scala
├─ CommandValidator.scala
├─ Axi4.scala
├─ RectAddressGen.scala
├─ AxiReadEngine.scala
├─ AxiWriteEngine.scala
├─ PixelReadAligner.scala
├─ PixelWritePacker.scala
├─ DenseBlitEngine.scala
├─ SparseDecoder.scala
├─ RenderEngine.scala
├─ ScanoutDma.scala
├─ DdrQosArbiter.scala
├─ FrameSwapController.scala
├─ GpuPerfCounters.scala
├─ PixelPipeExt.scala
├─ GpuSubsystem.scala
├─ Efinix2dGpuTop.scala
└─ GenerateEfinix2dGpu.scala

chisel/src/test/scala/gpu/
├─ GpuFrontEndSpec.scala
├─ RenderEngineSpec.scala
├─ SparseDecoderSpec.scala
├─ DdrQosArbiterSpec.scala
└─ GpuSystemSpec.scala
```

负责人模块通过 APB 接收 Sapphire 命令，并把 Render AXI 和 Scanout AXI 经 QoS 仲裁合并为一个 32 位 AXI Master，连接官方 Sapphire external AXI Master 0。

## 组员 A 目录

```text
board/efinix_ti60/rtl/
├─ pixel/
│  ├─ gpu_pixel_contract.vh
│  ├─ gpu_pixel_copy.v
│  ├─ gpu_pixel_fill.v
│  ├─ gpu_pixel_color_key.v
│  ├─ gpu_pixel_alpha_blend.v
│  └─ gpu_pixel_pipe.v
├─ display/
│  ├─ rgb565_to_rgb888.v
│  ├─ pixel_async_fifo.v
│  ├─ display_line_buffer.v
│  ├─ display_scale2x_1080p.v
│  ├─ vblank_pulse_sync.v
│  ├─ hdmi_tx_adapter.v
│  └─ hdmi_subsystem.v
├─ efinix_sapphire_adapter.v
└─ board_top.v
```

每个新增或修改的 `.v` 文件只能包含一个 `module`；`.vh` 只能包含常量和宏。

## 组员 B 目录

```text
sw/efinix_gpu/
├─ include/
│  ├─ gpu_regs.h
│  ├─ gpu.h
│  └─ framebuffer.h
├─ src/                              # 驱动、黄金模型、资源、HUD、游戏和 benchmark
├─ tests/
├─ linker.ld
└─ Makefile
```

软件基于官方 Sapphire BSP，显存使用 `0x02000000` 和 `0x02200000` 双缓冲，GPU APB 地址为 `0xF8100000`。

## 生成物与验收

```text
generated/efinix_gpu/                # Chisel split-verilog 输出
board/efinix_ti60/output/            # bit、hex、Efinity 报告和板级日志
docs/efinix_2d_gpu/                  # 接口、测试和验收记录
scripts/test-efinix-gpu.ps1          # 负责人测试入口
scripts/test-efinix-verilog.ps1      # 组员 A 测试入口
scripts/test-efinix-software.ps1     # 组员 B 测试入口
```

原有 `chisel/src/main/scala/cpu/`、`chisel/src/main/scala/soc/`、`rtl/video/` 和旧软件驱动保留为历史基线，但不属于正式 Ti60F225 2D GPU 主线。
