# 易灵思 Ti60F225 2D 图像渲染加速器

本仓库是面向 Ti60F225 开发板的 RISC-V + FPGA 2D 图像渲染工程。正式开发主线为 `codex/efinix-2d-gpu`，官方 Demo 仅作参考，不直接修改。

## 目录说明

```text
.
├─ chisel/
│  ├─ src/main/scala/soc/gpu/       # 负责人：GPU、Command FIFO、BitBlt、AXI、QoS、显示 DMA
│  ├─ src/main/scala/board/efinix/  # 负责人：DDR3 黑盒和易灵思板级顶层
│  └─ src/test/scala/soc/gpu/       # ChiselTest、AXI RAM、系统集成测试
├─ rtl/
│  ├─ gpu/                          # 组员 A：PixelPipe 和 RGB565 像素运算
│  ├─ video/                        # 组员 A：640×480 时序、彩条、TMDS 编码/串行化
│  └─ board/efinix/                 # 组员 A：HDMI 时钟和差分输出适配
├─ sw/
│  ├─ drivers/gpu/                  # 组员 B：GPU 寄存器、提交/等待、IRQ、性能 API
│  ├─ gpu/                          # 组员 B：RGB565、CPU 黄金模型、Sparse 格式
│  ├─ assets/                       # 组员 B：Sprite、字体和演示资源
│  ├─ tools/                        # 组员 B：Sparse 资源打包器
│  ├─ apps/                         # 组员 B：游戏 Demo、HUD、FPS 对比
│  └─ bsp/                          # 现有 Sapphire/RV32 BSP
├─ tb/                              # Verilog/HDMI 测试平台和固定测试向量
├─ generated/gpu/                   # Chisel 生成的 SystemVerilog，不手工修改
├─ generated/reports/efinix_2d_gpu/ # 资源、时序、带宽、FPS 报告
├─ scripts/                         # RTL 生成、仿真、软件构建和板级验收
├─ references/official/ti60f225/   # 官方工程路径、版本和校验记录
├─ docs/                            # 接口、地址空间、计划和验收记录
└─ third_party/                     # 已确认许可证的外部参考代码
```

## 三人文件边界

- 负责人：`chisel/src/main/scala/soc/gpu/`、`chisel/src/main/scala/board/efinix/` 及对应测试。
- 组员 A：`rtl/gpu/`、`rtl/video/`、`rtl/board/efinix/` 及 `tb/` 中对应测试。每个 `.v` 文件只能包含一个 `module`。
- 组员 B：`sw/drivers/gpu/`、`sw/gpu/`、`sw/assets/`、`sw/tools/`、`sw/apps/` 及软件测试。应用不得直接散布裸 MMIO。

## 官方 Demo

官方资料目录：`Ti60F225_DemoBoard_v4/`（位于仓库根目录或本地资料目录）。重点参考 `08_ti60f225_soc_demo`、`03_hdmi_tx_demo` 和 `10_Ti60f225_sc431hai2hdmi_demo`。复用文件时复制到本工程适配目录，并记录来源版本。

完整文件/模块映射见 [`docs/efinix_2d_gpu/directory_layout.md`](docs/efinix_2d_gpu/directory_layout.md)。
