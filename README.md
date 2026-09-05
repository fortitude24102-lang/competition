# 易灵思 Ti60F225 2D 图像渲染加速器

本项目参加 2026 年嵌入式 FPGA 赛道，唯一有效实施计划是 [`Efinix_2D图像渲染三人开发计划书_官方Demo版.docx`](docs/word/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx)。

项目直接复用官方 Ti60F225 Demo：以 Sapphire RISC-V + DDR3 工程为主工程底座，以官方 HDMI TX 工程为显示输出底座。原有自研 Chisel CPU 仅保留为历史研究和回退参考，不进入本项目 25 天开发主线。

## 官方工程来源

- 主工程：`Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo/par/ddr_demo_ti60`
- HDMI：`Ti60F225_DemoBoard_v4/03_hdmi_tx_demo/hdmi_tx_demo_v2`
- 帧缓存参考：`Ti60F225_DemoBoard_v4/10_Ti60f225_sc431hai2hdmi_demo/Ti60f225_sc431hai2hdmi_v6.rar`

原始 `Ti60F225_DemoBoard_v4` 始终只读。需要复用的文件复制到 `board/efinix_ti60/vendor/`，保持原内容并登记 SHA256。

## 目录说明

```text
.
├─ board/efinix_ti60/                 # 从官方 08/03 Demo 派生的比赛板级工程
│  ├─ rtl/pixel/                      # 组员 A：Copy/Fill/Key/Alpha 像素模块
│  ├─ rtl/display/                    # 组员 A：FIFO、行缓存、2 倍缩放、HDMI 适配
│  ├─ vendor/sapphire_ddr3/           # 原样复用的官方 Sapphire/DDR3 文件
│  ├─ vendor/hdmi_tx/                 # 原样复用的官方 HDMI TX 文件
│  ├─ vendor/manifest.sha256          # 官方文件来源与哈希
│  ├─ constraints/                    # DDR3、GPU、HDMI 和 CDC 约束
│  ├─ output/                         # bit、hex、日志和 Efinity 报告
│  ├─ efinix_2d_gpu.xml
│  ├─ efinix_2d_gpu.peri.xml
│  ├─ efinix_2d_gpu.sdc
│  └─ rtl/board_top.v
├─ chisel/
│  ├─ src/main/scala/gpu/             # 负责人：APB、命令队列、AXI、渲染、Scanout、QoS
│  └─ src/test/scala/gpu/             # 负责人：各 Chisel 模块及系统测试
├─ generated/efinix_gpu/              # Chisel split-verilog 输出，一文件一模块
├─ sw/efinix_gpu/                     # 组员 B：Sapphire BSP 驱动、黄金模型、游戏 Demo
├─ tb/verilog/                        # 组员 A：像素和 HDMI 自检 testbench
├─ tb/vectors/                        # 三人共用固定向量、CRC 和随机种子
├─ scripts/                           # 三条一键测试、生成和板级验收入口
├─ docs/efinix_2d_gpu/                # 接口合同、验收记录和目录说明
└─ docs/word/                         # 唯一有效 Word 计划书
```

## 三人边界

- 负责人使用 Chisel 实现 GPU 核心，接入官方 APB Slave 0（`0xF8100000`）和 Sapphire 已启用的 32 位外部 AXI Master，不重写 Sapphire CPU、DDR3 控制器或 HDMI。
- 组员 A 只负责 `board/efinix_ti60/rtl/` 和 `tb/verilog/`；每个新增或修改的 `.v` 文件只能包含一个 `module`。
- 组员 B 只负责 `sw/efinix_gpu/`；软件建立在官方 Sapphire BSP 上。

更详细的目录和复用边界见 [`docs/efinix_2d_gpu/directory_layout.md`](docs/efinix_2d_gpu/directory_layout.md)。
