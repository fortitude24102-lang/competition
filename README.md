# Ti60F225 二维图像渲染加速器

比赛主线复用官方 Sapphire RISC-V、DDR3 和 HDMI Demo；AetherGX 是 Chisel 实现的二维 GPU。PC 只提供素材文件，资源请求、CRC 校验、游戏状态与 GPU 命令均由 Sapphire 执行。

## 当前版本

**V2 候选版（2026-09-26 板测）**：[位流、固件、资源服务器与哈希](release/v2/README.md)。V1 原发布文件仍在 `release/` 根目录，勿将两版固件和位流混用。V2 使用 960×540 RGB565 双缓冲，输出 1920×1080 HDMI；支持 Fill、Copy、Color Key、Alpha、Sparse 和 Asset DMA。

四份正式素材已通过千兆以太网加载到 DDR 并由 RISC-V 完整校验，均为零重试。32 个 Sprite 的 CPU/GPU 交替测试实测约 **2.1 / 8.5 FPS**。这是首轮性能基线，未达到赛题要求的稳定 60 FPS；300 帧稳定极限、断网持续运行和长时间耐久仍待验收。具体数据与限制见 [V2 实施记录](docs/efinix_2d_gpu/v2_implementation_progress.md)。

## 两条工作线

A-work 新增了纯软件的 [100KBBH 风格二维弹幕渲染候选](docs/efinix_2d_gpu/bullet_demo_usage.md)：独立素材、32～512 对象档位、CPU/GPU 同状态回放，保留旧性能场景。它尚未上板，也未接入人物操控，不代表已完成游戏赛题或稳定 60 FPS 验收；硬件设计与 V2 发布包不变。

R2 软件完善增加原创星空/电路场地与飞船素材、HUD 栅格缓存，以及经过像素比对的 512 档位多时刻预览，见 [离线验证记录](docs/efinix_2d_gpu/bullet_demo_r2_acceptance.md)。

R3 将三个发射器替换为飞机，并加入圆、菱形、针、十字、星形和空心环六种子弹；仍仅改软件素材，见 [新画面与离线验证](docs/efinix_2d_gpu/bullet_demo_r3_acceptance.md)。

R4 进一步区分敌我轮廓：我方为尖头窄机身战机，敌方为宽翼双引擎飞机；尺寸与绘制量不变，见 [敌我飞机素材验证](docs/efinix_2d_gpu/bullet_demo_r4_acceptance.md)。

R5 增加有上限的弹幕 Alpha 光晕、护盾，以及自动移动、生命值、受击保护、擦弹计分和失败重开，见 [生存演示与验证](docs/efinix_2d_gpu/bullet_demo_r5_acceptance.md)。仍未接入键盘等真实输入；不是完整可玩游戏，也没有新的板测 FPS 结论。

R6 修正性能 HUD 字母拥挤：使用 5×7 字体、2 倍整数放大和 4 像素字间/行间留白，保留原有 960×72 HUD、缓存与计数口径，见 [字体清晰度修复与仿真](docs/efinix_2d_gpu/bullet_demo_r6_acceptance.md)。

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
