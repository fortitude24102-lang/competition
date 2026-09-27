# Ti60F225 二维图像渲染加速器

比赛主线复用官方 Sapphire RISC-V、DDR3 和 HDMI Demo；AetherGX 是 Chisel 实现的二维 GPU。PC 只提供素材文件，资源请求、CRC 校验、游戏状态与 GPU 命令均由 Sapphire 执行。

## 当前版本

**V2 候选版（2026-09-26 板测）**：[位流、固件、资源服务器与哈希](release/v2/README.md)。V1 原发布文件仍在 `release/` 根目录，勿将两版固件和位流混用。V2 使用 960×540 RGB565 双缓冲，输出 1920×1080 HDMI；支持 Fill、Copy、Color Key、Alpha、Sparse 和 Asset DMA。

四份正式素材已通过千兆以太网加载到 DDR 并由 RISC-V 完整校验，均为零重试。32 个 Sprite 的 CPU/GPU 交替测试实测约 **2.1 / 8.5 FPS**。这是首轮性能基线，未达到赛题要求的稳定 60 FPS；300 帧稳定极限、断网持续运行和长时间耐久仍待验收。具体数据与限制见 [V2 实施记录](docs/efinix_2d_gpu/v2_implementation_progress.md)。

开发板分阶段实测已定位首要瓶颈为 **Alpha 的 1–2 像素小事务和单 beat 写回**，其次是每帧全屏背景 Copy；具体计数、口径和优化顺序见 [V2 性能瓶颈定位](docs/efinix_2d_gpu/v2_bottleneck_analysis.md)。画面优化与性能优化保持两条工作线。

**当前源码性能候选（2026-09-27，尚未发布）：** Alpha 分块突发与对齐 Copy 直通已通过 61/61 项 GPU 仿真及 Efinity 构建，并通过 JTAG 临时上板；同一旧画面的 GPU/CPU 对比约为 **20.0/2.1 FPS**，背景 Copy 由约 22.0 ms 降至 8.2 ms。但正常固件的 300 帧统计报告 **242,100 次显示下溢、硬件错误 0、60 FPS 合格计数 0**；两轮短时诊断下溢为 0 不能覆盖这一问题。此源码与生成 RTL 是**带已知显示风险的实验候选**，不能作为稳定发布版、画质验收或 60 FPS 达标证据；`release/v2/` 仍为上方所述正式 V2 包。后续更换渲染画面后，要在新场景重新测量帧率和下溢，并定位此问题。完整记录见 [性能瓶颈定位](docs/efinix_2d_gpu/v2_bottleneck_analysis.md)。另有非 GPU 的 SoC 固件基线测试异常（`SoftwareDriverSpec`、`PangoBringupSpec`），本轮未处理，不能宣称全项目测试通过。

## 两条工作线

- 负责人：锁定当前同场景 CPU/GPU 基准，定位帧时间和 DDR/命令瓶颈，逐项优化并用同一测试口径复测。性能代码在 `sw/efinix_gpu/src/perf_demo.c`、`main.c`，GPU 在 `chisel/src/main/scala/gpu/`。
- 组员：优化游戏画面和资源，复用许可明确的现有素材与逻辑；素材在 `sw/efinix_gpu/assets/v2/`，生成器在 `tools/build_v2_assets.py`。改动应保持 CPU/GPU 两种模式读取同一场景，不把 PC 变成渲染节点。每个 `.v` 文件仍只能含一个模块。

画面、素材与测试档位更改后，需重新建立性能基线；不能把不同场景的 FPS 直接比较。当前有效的完整方案和接口约束分别见 [V2 一周升级计划书](docs/word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx) 与 [V2 接口合同](docs/efinix_2d_gpu/v2_interface_contract.md)。计划书中的早期进度以本 README 和实施记录为准。

## 找文件

| 目录 | 内容 |
|---|---|
| `board/efinix_ti60/` | 板级顶层、管脚/时钟约束、Verilog 网络和显示适配 |
| `board/efinix_ti60/vendor/` | 原样复用的官方 Sapphire/DDR3、HDMI、GE Demo 及哈希清单 |
| `chisel/src/main/scala/gpu/` | AetherGX 命令、渲染、Asset DMA、三路 DDR 仲裁 |
| `generated/efinix_gpu/` | 从 Chisel 生成的冻结 RC0 RTL；哈希见 `release/v2_rc0.sha256` |
| `sw/efinix_gpu/` | Sapphire C 固件、PC 资源服务器、素材和测试 |
| `tb/verilog/`、`scripts/` | 联调仿真及软件/板级检查入口 |
| `release/v2/` | 本次同版位流、固件、服务器；操作顺序见其中 README |
| `docs/efinix_2d_gpu/` | 当前接口、实测记录与历史验收资料 |

原始官方 `Ti60F225_DemoBoard_v4` 只读；自研 CPU 的历史资料可通过 Git 历史查阅，不进入比赛工程。
