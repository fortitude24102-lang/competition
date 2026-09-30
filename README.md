# Ti60F225 二维图像渲染加速器

比赛主线复用官方 Sapphire RISC-V、DDR3 和 HDMI Demo；AetherGX 是 Chisel 实现的二维 GPU。PC 只提供素材文件，资源请求、CRC 校验、游戏状态与 GPU 命令均由 Sapphire 执行。

## 当前版本

**V2 候选版（2026-09-26 板测）**：[位流、固件、资源服务器与哈希](release/v2/README.md)。V1 原发布文件仍在 `release/` 根目录，勿将两版固件和位流混用。V2 使用 960×540 RGB565 双缓冲，输出 1920×1080 HDMI；支持 Fill、Copy、Color Key、Alpha、Sparse 和 Asset DMA。

四份正式素材已通过千兆以太网加载到 DDR 并由 RISC-V 完整校验，均为零重试。32 个 Sprite 的 CPU/GPU 交替测试实测约 **2.1 / 8.5 FPS**。这是首轮性能基线，未达到赛题要求的稳定 60 FPS；300 帧稳定极限、断网持续运行和长时间耐久仍待验收。具体数据与限制见 [V2 实施记录](docs/efinix_2d_gpu/v2_implementation_progress.md)。

开发板分阶段实测已定位首要瓶颈为 **Alpha 的 1–2 像素小事务和单 beat 写回**，其次是每帧全屏背景 Copy；具体计数、口径和优化顺序见 [V2 性能瓶颈定位](docs/efinix_2d_gpu/v2_bottleneck_analysis.md)。画面优化与性能优化保持两条工作线。

**当前源码性能候选（2026-09-27，尚未发布）：** Alpha 分块突发与对齐 Copy 直通已通过 61/61 项 GPU 仿真及 Efinity 构建，并通过 JTAG 临时上板；同一旧画面的 GPU/CPU 对比约为 **20.0/2.1 FPS**，背景 Copy 由约 22.0 ms 降至 8.2 ms。但正常固件的 300 帧统计报告 **242,100 次显示下溢、硬件错误 0、60 FPS 合格计数 0**；两轮短时诊断下溢为 0 不能覆盖这一问题。此源码与生成 RTL 是**带已知显示风险的实验候选**，不能作为稳定发布版、画质验收或 60 FPS 达标证据；`release/v2/` 仍为上方所述正式 V2 包。后续更换渲染画面后，要在新场景重新测量帧率和下溢，并定位此问题。完整记录见 [性能瓶颈定位](docs/efinix_2d_gpu/v2_bottleneck_analysis.md)。另有非 GPU 的 SoC 固件基线测试异常（`SoftwareDriverSpec`、`PangoBringupSpec`），本轮未处理，不能宣称全项目测试通过。

## 两条工作线

**性能工作边界：** 屏幕继续显示 CPU/GPU 对比；CPU 保持新场景原基础
配置，不新增优化、不接入 GPU 渲染，也不人为降速。只优化 GPU 路径，
画面美化由组员负责。共用 HUD 按变化行更新已撤回；当前增加的是仅 GPU
模式字形局部更新及 HUD DMA，CPU 仍完整重建。下文含变化行更新的五档连续测量属于历史试验，非当前
源码直接验收结果。主频、分辨率、Alpha/Key 功能与同屏工作量不因提高
GPU FPS 而降低。正式演示仍显示实测 CPU 数字，不用占位数代替。

A-work 新增了纯软件的 [100KBBH 风格二维弹幕渲染候选](docs/efinix_2d_gpu/bullet_demo_usage.md)：独立素材、32～512 对象档位、CPU/GPU 同状态回放，保留旧性能场景。2026-09-28 已用最新 R6 软件配合 main 性能候选上板：优化前实际 64 档 CPU/GPU 为 **2.8/15.0 FPS**。已将 GPU 模式 HUD 接入现有 Copy DMA，CPU 模式保留软件 HUD；正常 GPU 窗口升至约 **40.0～58.1 FPS**，300 样本 P5 30、下溢/错误 0/0，仍未稳定达到 60 FPS。另做连续 GPU 测量：32/64/128/256/512 档平均为 **52.8/47.0/43.0/30.0/28.6 FPS**，各档 300 样本均无下溢或错误，但不等同于交替模式或长期耐久。按变化行更新 HUD 已减少写入量，尚未证明额外帧率收益。旧画面下溢未在本轮复现，不等于根因已修复。数据、固件哈希与原始日志见 [新画面板测与瓶颈定位](docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md)，开源选型和下一项 Color Key 短突发方向见 [GPU 优化选型](docs/efinix_2d_gpu/gpu_performance_options.md)。未接入人物操控，不代表已完成游戏赛题；硬件设计与 V2 发布包不变。

**上一轮已板测的硬件性能候选（2026-09-28，尚未发布）：** 对齐、偶数宽度
Color Key 已复用 Copy 的字突发 DMA，以 WSTRB 保留透明像素；错位和
奇数宽度仍走原路径。61/61 项 GPU 回归、Efinity 构建及三个 DDR
像素/计数检查通过，100 MHz 不变。512 档同探针 Key 从
8.71～9.26 ms 降至 7.32～7.99 ms，FULL 从 19.88～20.06 ms 降至
18.47～18.55 ms；15 个案例工作量完全相同，分段下溢/硬件错误为 0。
512 档仍超过 16.67 ms，不能宣称稳定 60 FPS。普通 CPU/GPU 演示仍用
同一固件，CPU 保持基础实现；整帧测量与候选哈希见
[本轮记录](docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md#color-key-字突发候选构建与板测)。
仅 JTAG 临时验证，未写 Flash、未覆盖 `release/v2/`，历史异常保留。

**最新半字相位候选（2026-09-28，尚未发布）：** Key DMA 已覆盖错位
地址、奇数宽度和独立步长，保留首尾/透明掩码、重叠回退及准确计数。
GPU 回归 63/63、补充边界测试 3/3、Efinity 构建和板端 DDR 29/29 通过；
100 MHz 核心余量 1.792 ns。512 档 Key 比上一候选再降 6.5%～9.0%，
FULL 再降 3.5%～4.5%，但仍为 17.724～17.884 ms；普通整帧仍
40.0～58.1 FPS、P5=30，未稳定达到 60 FPS。CPU 保持 2.5～2.6 FPS
基础实现。详见 [半字相位 DMA](docs/efinix_2d_gpu/key_phase_dma_20260928.md)。

**当前最新源码性能候选（2026-09-28，尚未发布）：** 在半字相位 DMA
之后增加 4 KiB、由 Sapphire 显式预载的 GPU 纹理 Cache。512 档同工作量
Key 降至 2.621～2.796 ms，FULL 降至 12.304～12.365 ms，分别改善
58.5%～64.0% 和 30.4%～30.9%；三组板测均为零下溢、零硬件错误。
资源增加 4 个 RAM10，100 MHz 核心 setup/hold 余量为
+0.871/+0.026 ns。普通 64 档 GPU 渲染约 9.30 ms，但屏显窗口仍为
40.0～58.1 FPS、300 帧 P5=30，不能宣称稳定 60 FPS；主要瓶颈已转向
全屏背景 Copy 和显示节拍。本次普通演示因 PC 的 UDP 8080 服务进程已
退出而使用内容相同的本地后备图集，不计作新的以太网成功加载证据。
板测前应在仓库根目录运行
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-bullet-asset-server.ps1`
并保持该终端开启；脚本会检查素材、`192.168.1.2` 和 UDP 8080 所有者，
但不会修改网卡、防火墙或结束其他进程。
完整设计、哈希、复现命令及原始记录见
[纹理 Cache 板测](docs/efinix_2d_gpu/texture_cache_20260928.md)。仅 JTAG 临时
验证，未写 Flash、未替换 `release/v2/`；CPU 基础路径未接入 Cache。

**HUD 覆盖区背景裁剪候选（2026-09-29，尚未发布）：** 普通 GPU 模式
不再搬运随后会被 960×72 HUD 完全覆盖的背景行；背景 Copy 由 960×540
缩为 960×468，每帧少读、少写各 138,240 B。Profile、CPU 对照、对象、
Alpha、960×540 RGB565 双缓冲和 100 MHz 主频均未改变。板端 64 档十组
GPU 命令时间为 **8.100～8.118 ms，中位 8.104 ms**，比同场景纹理
Cache 基线中位 9.300 ms 降低 **12.9%**；CPU 保持约 297.1 ms。
屏显窗口仍为 **40.0～58.1 FPS**，300 个 GPU 样本 P5=30、欠流/错误
0/0、`windowed_60fps=0`，因此仍不能宣称稳定 60 FPS。网络素材 101/102
均为零重试，Cache 使用网络图集；Profile 计数确认未裁剪控制仍搬运
518,400 像素、读写各 1,036,800 B。完整日志见
[HUD 背景裁剪板测](docs/efinix_2d_gpu/evidence/bullet-board-20260929/hud-background-clip.log)。
本轮仅 JTAG 临时加载，没有写 Flash 或替换 `release/v2/`；已知非 GPU
基线异常 `SoftwareDriverSpec`、`PangoBringupSpec` 仍保留。

R2 软件完善增加原创星空/电路场地与飞船素材、HUD 栅格缓存，以及经过像素比对的 512 档位多时刻预览，见 [离线验证记录](docs/efinix_2d_gpu/bullet_demo_r2_acceptance.md)。

R3 将三个发射器替换为飞机，并加入圆、菱形、针、十字、星形和空心环六种子弹；仍仅改软件素材，见 [新画面与离线验证](docs/efinix_2d_gpu/bullet_demo_r3_acceptance.md)。

R4 进一步区分敌我轮廓：我方为尖头窄机身战机，敌方为宽翼双引擎飞机；尺寸与绘制量不变，见 [敌我飞机素材验证](docs/efinix_2d_gpu/bullet_demo_r4_acceptance.md)。

R5 增加有上限的弹幕 Alpha 光晕、护盾，以及自动移动、生命值、受击保护、擦弹计分和失败重开，见 [生存演示与验证](docs/efinix_2d_gpu/bullet_demo_r5_acceptance.md)。该历史记录仅为离线验证；仍未接入键盘等真实输入，不是完整可玩游戏。

R6 修正性能 HUD 字母拥挤：使用 5×7 字体、2 倍整数放大和 4 像素字间/行间留白，保留原有 960×72 HUD、缓存与计数口径，见 [字体清晰度修复与仿真](docs/efinix_2d_gpu/bullet_demo_r6_acceptance.md)。

R7 软件场景增加四段循环弹幕：敌机出弹方向、速度与弹形逐段变化，切换前 16 帧用原有 Alpha 光晕预警；绘制命令数与像素预算不增加，见 [离线验证和预览](docs/efinix_2d_gpu/bullet_demo_r7_acceptance.md)。实体按键及 CPU→GPU 单向展示仍待负责人审批，未接入。

2026-09-30 已将 A-work `c0e155d` 的 R7 合入当前性能候选，并通过 JTAG
临时加载运行。GPU 纹理 Cache、HUD DMA、背景 72 行裁剪保留；CPU
基础路径保留。两份素材加载均零重试；首个 64 档 GPU 30 帧窗口为
56.3 FPS、场景 8.099 ms，仅作运行检查。上方 R6 的十窗口/300 样本
性能结果仍是历史基线，不能直接作为 R7 的稳定性验收。合并后的游戏
边界、最终像素等价、RTL 重放和普通/Profile 固件入口检查通过；见
[R7 集成记录](docs/efinix_2d_gpu/bullet_demo_r7_acceptance.md#2026-09-30-性能候选集成与临时加载)。

**GPU HUD 字形候选（2026-09-30，尚未发布）：** 复用现有字体和 Copy，
启动时在 DDR 生成白/绿色字形图集；GPU 仅复制变化字符，CPU 完整重建
与软件搬运不变。单数字变化板测 0.216 ms，多字段变化 0.992～2.000 ms，
20 个案例与完整软件重绘逐字节一致。网络零重试、完整复位后的连续
300 帧/档测试：32/64/128 档约 **60.1 FPS、P5=60、下溢/错误 0/0**；
256 档平均 **59.7 FPS**（虽 P5=60，不能称每帧稳定 60），512 档 **30 FPS**。
HUD 更新平均仅 0.147～0.258 ms，暂不加专用文字 DMA；下一步分离
高档位命令准备/提交、同步和背景搬运的开销。固件热重载的另一轮
正常 64 档虽然读到 60.1 FPS，却出现 **80,700 次显示下溢**，不合格；
完整复位探针没有复现，但根因尚未定位，不宣称所有启动方式稳定。
随后完整复位并等待 PHY 稳定的正常 64 档对照通过：十窗口均 60.1 FPS，
300 个 GPU 样本 P5=60、下溢/错误 0/0；CPU 保持 2.7～2.8 FPS。
原始日志、采样边界、地址、哈希与复现见
[HUD 字形板测](docs/efinix_2d_gpu/hud_glyphs_20260930.md)。不改 RTL/主频、
不写 Flash、不替换正式发布包，CPU 数字仍为真实测量。

**R7 分段诊断（2026-09-30）：** 已测命令构建、队列压力、批尾等待、
硬件 busy 与背景 Copy。关闭逐命令探针时，64/256/512 档各 300 连续帧
分别约 60.1/60.1/30.0 FPS，下溢/错误均 0；512 档构建 3.101 ms、
场景 13.436 ms、PRESENT 前工作平均 19.263 ms。隔离背景 Copy 为
7.589～7.626 ms，是最大的单项 GPU 硬件开销，下一项优先其流水与
读写背压，随后评估小 Sprite 有序批量提交。提交阻塞与 GPU 执行重叠，
不能相加；开启逐命令探针额外增加约 0.839 ms，分段入口也有观察开销，
不将本次时间替代普通固件或历史成绩。CPU/RTL/主频/发布包未变，
未实施新的 Copy 架构，测后已恢复原普通对比固件。完整口径、日志、
开源参考和后续决策见 [分段测量](docs/efinix_2d_gpu/render_phases_20260930.md)。

- 负责人：锁定当前同场景 CPU/GPU 基准，定位帧时间和 DDR/命令瓶颈，逐项优化并用同一测试口径复测。性能代码在 `sw/efinix_gpu/src/perf_demo.c`、`main.c`，GPU 在 `chisel/src/main/scala/gpu/`。
- 组员：优化游戏画面和资源，复用许可明确的现有素材与逻辑；素材在 `sw/efinix_gpu/assets/v2/`，生成器在 `tools/build_v2_assets.py`。改动应保持 CPU/GPU 两种模式读取同一场景，不把 PC 变成渲染节点。每个 `.v` 文件仍只能含一个模块。

画面、素材与测试档位更改后，需重新建立性能基线；不能把不同场景的 FPS 直接比较。当前有效的完整方案和接口约束分别见 [V2 一周升级计划书](docs/word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx) 与 [V2 接口合同](docs/efinix_2d_gpu/v2_interface_contract.md)。计划书中的早期进度以本 README 和实施记录为准。

## 找文件

| 目录 | 内容 |
|---|---|
| `board/efinix_ti60/` | 板级顶层、管脚/时钟约束、Verilog 网络和显示适配 |
| `board/efinix_ti60/vendor/` | 原样复用的官方 Sapphire/DDR3、HDMI、GE Demo 及哈希清单 |
| `chisel/src/main/scala/gpu/` | AetherGX 命令、渲染、Asset DMA、三路 DDR 仲裁 |
| `generated/efinix_gpu/` | 当前 Chisel 性能候选 RTL；冻结 RC0 的哈希仅对应历史版本 |
| `sw/efinix_gpu/` | Sapphire C 固件、PC 资源服务器、素材和测试 |
| `tb/verilog/`、`scripts/` | 联调仿真及软件/板级检查入口 |
| `release/v2/` | 本次同版位流、固件、服务器；操作顺序见其中 README |
| `docs/efinix_2d_gpu/` | 当前接口、实测记录与历史验收资料 |

原始官方 `Ti60F225_DemoBoard_v4` 只读；自研 CPU 的历史资料可通过 Git 历史查阅，不进入比赛工程。
