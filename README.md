# 易灵思 Ti60F225 2D 图像渲染加速器

本项目参加 2026 年嵌入式 FPGA 赛道，唯一有效实施计划是 [`Efinix_2D图像渲染三人开发计划书_官方Demo版.docx`](docs/word/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx)。该文件现为三人三天收尾版，替代原二十五天排期，但保留原计划全部最终功能和验收结果。

项目直接复用官方 Ti60F225 Demo：以 Sapphire RISC-V + DDR3 工程为主工程底座，以官方 HDMI TX 工程为显示输出底座。原有自研 Chisel CPU 仅保留为历史研究和回退参考，不进入正式 2D GPU 主线。

## 当前进度与后三天

当前基线为主负责人完成原第 18 天、组员 A 完成原第 19 天、组员 B 完成原第 20 天；官方 Sapphire CPU、DDR3、8 个用户 LED 和 HDMI 已完成基础实机验证。

- 第 1 天：完成 Sparse token、C 打包器、Chisel 解码与 Blit、Dense/Sparse CRC 和 DDR 字节比较，同时建立显示下溢同步与 Dense 压力基线。
- 第 2 天：完成可配置的 FIFO 水位自适应 DDR QoS、APB 性能计数、板级接线以及固定轮询/自适应模式对比。
- 第 3 天：统一生成 RTL 和正式位流，完成时序、启动、300 帧性能、Dense/Sparse 显示一致性、30 分钟耐久和三方封版。

当前主负责人已完成第 1、2 天的 Chisel 源码与仿真用例。`A-work` 已基于主线 `3032c45` 完成 `underflow_pulse_gpu` CDC 接入、统一生成 `generated/efinix_gpu/`、更新官方 Efinity 工程源清单，并通过完整 Efinity compile；组员 B 的 Sparse 资源、C 寄存器定义和板上基准仍需独立合入。主负责人可从 `A-work` 取用 A 的板级接线、生成 RTL、工程 XML 与离线验收记录。

详细文件、输入、输出、依赖和逐日验收均以正式 Word 计划书为准。历史阶段记录只用于追溯，不再决定后续排期。

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
├─ release/                           # 最终 bit/hex、固件、基准、视频和 SHA256 清单
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

## 测试入口

在本工作树中执行：

```powershell
./scripts/test-efinix-gpu.ps1
./scripts/test-efinix-verilog.ps1 -IcarusHome D:/FPGA/iverilog
./scripts/test-efinix-software.ps1
./scripts/test-efinix-board.ps1 -EfinityHome C:/efinity/efinity -Flow compile
```

前三条脚本依次检查负责人 GPU、组员 A 的官方 HDMI/RGB565 边界和组员 B 的 Sapphire 软件接口；第四条检查派生工程的 Efinity 映射。最终完成还必须使用同一正式候选位流执行板上 DDR、CPU、LED、HDMI、性能和耐久验收。此前离线阶段的证据见 [A、B 离线推进记录](docs/efinix_2d_gpu/ab_offline_progress.md)。
