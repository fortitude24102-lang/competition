# 易灵思 Ti60F225 2D 图像渲染加速器

本项目参加 2026 年嵌入式 FPGA 赛道，正式方案复用官方 Ti60F225 Sapphire RISC-V、DDR3 与 HDMI Demo，在其上增加自研 2D GPU（AetherGX）。原有自研 CPU 只保留为历史参考，不进入比赛主线。

已验证的板上版本为 **V1 基线**；当前负责人 Chisel/生成 RTL 正按 V2 升级，板级工程和固件须按 V2 接口同步后再构建。唯一有效的后续实施计划是 [`Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx`](docs/word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx)。

2026-09-23 已接入 A-work `96f46c8` 的 960×540 → 1080p 全屏显示与欠流 CDC，8 项相关仿真及工程清单/RC0 哈希检查通过；GPU RC0 不变。**网络链路、V2 固件与整板验收仍未完成**，不能直接把当前工程当成已上板的 V2。接收范围和 A/B 待交付项见 [V2 最终验收状态](docs/efinix_2d_gpu/v2_final_acceptance.md)。

A、B 组员下一步直接看：[AB 接下来怎么做](docs/efinix_2d_gpu/AB_接下来怎么做.md)。

## V1 基线

V1 已形成从 Sapphire 软件、APB 命令、AetherGX、DDR3 帧缓存到 HDMI 显示的完整闭环，并完成实机显示验证。

- 官方 Sapphire RISC-V 运行频率为 100 MHz；GPU 位于 APB Slave 0，基地址为 `0xF8100000`。
- DDR3 型号为 MT41J128M16JT-125，像素格式为 RGB565，采用前后台双缓冲并在 vblank 执行 PRESENT。
- 内部渲染分辨率为 640×480@60 FPS，经 2×整数放大后居中输出至 1920×1080 HDMI。
- AetherGX 支持 Solid Fill、Block Copy、Color Key、Global Alpha、Sparse Blit。
- 已实现 16 项带 tag 的非阻塞命令队列、AXI Burst、显示异步 FIFO、Scanout DMA、自适应 DDR QoS、性能计数器和下溢统计。
- Sapphire 固件负责输入、游戏状态更新、命令生成、批量提交和性能统计；当前 300 帧流程能够执行 wait-each/batch、fixed/adaptive QoS 和 Dense/Sparse 对比。
- 当前板上 Demo 已正常显示并完成固件返回值、寄存器状态、DDR 固件回读和显示下溢检查。

V1 仍有两个任务书缺口：

1. `gpu_benchmark()` 已能测量 CPU 与 GPU 周期，但当前主程序和 HUD 尚未同时显示纯软件 CPU 渲染与硬件加速渲染的帧率/加速比。
2. 当前游戏能够统计 300 帧稳定 Sprite 数量，但尚未按 16、32、64、96……逐档施压并确定稳定 60 FPS 的真实上限。

因此，V1 可以作为完整硬件管线基线和后续优化对照，但不能表述为已经满足任务书全部要求。

## V2 一周目标

接下来一周只做两件事：

1. 补齐 V1 的 CPU/GPU 可视化性能对比与 Sprite 数量极限测试。
2. 复用官方千兆以太网 Demo，实现 PC 资源服务器，并把画面升级为 960×540 内部渲染、1920×1080 全屏输出的植物防线式游戏。

### V2 架构边界

```text
PC Asset Server（只保存和返回资源包）
        │  UDP：GET(asset_id, offset, length)
        ▼
官方 GE/RGMII + FPGA 包接收与 Asset DMA
        │
        ▼
DDR3 资源缓存 ───────────────┐
        ▲                    │
        │                    ▼
Sapphire RISC-V          AetherGX
资源请求与校验            Fill / Copy / Key / Alpha / Sparse
缓存与场景管理                 │
输入、植物/敌人/弹丸逻辑        ▼
碰撞、波次、动画状态       双缓冲 Framebuffer
GPU Command 生成               │
        │                      ▼
        └────────────────── HDMI 1080p60
```

PC 不参与逐帧游戏运算、不生成 GPU 命令、不合成画面；它只相当于通过千兆以太网连接的外部资源盘。Sapphire RISC-V 必须主动请求资源、验证 CRC、管理 DDR 缓存，并独立完成游戏逻辑和渲染调度。断开网线后，已经加载到 DDR 的当前场景仍应继续运行。

## 游戏逻辑与素材复用原则

游戏不是本项目的创新重点，V2 不从零设计玩法。实现时优先移植许可清晰的开源 C 代码，并仅改造平台接口、定点数据、输入层和 AetherGX 命令生成层。

- 首选逻辑参考：[ZombieGardenTD](https://github.com/JamesC01/ZombieGardenTD)，C + MIT，适合提取植物、敌人、弹丸、波次和网格逻辑。
- 架构参考：[PlantsVsZombies-CPP](https://github.com/stefanpeiculeasa/PlantsVsZombies-CPP)，其无图形游戏核心、固定时间步和只读渲染状态的分层方式适合移植到 Sapphire。
- 素材优先使用自制资源或许可明确的资源，例如 [CC0 tower-defense sprites](https://opengameart.org/content/gameboy-tower-defense-sprites)。
- 不导入 PopCap/EA 原版图片、字体、音乐、名称或 Logo；所有第三方代码和素材必须保留许可证与来源记录。

## 官方工程来源

- Sapphire + DDR3：`Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo/par/ddr_demo_ti60`
- HDMI：`Ti60F225_DemoBoard_v4/03_hdmi_tx_demo/hdmi_tx_demo_v2`
- 千兆以太网：`Ti60F225_DemoBoard_v4/04_Ti60f225_GE_demo/04_Ti60F225_tse_hj_demo_v5`
- 帧缓存参考：`Ti60F225_DemoBoard_v4/10_Ti60f225_sc431hai2hdmi_demo/Ti60f225_sc431hai2hdmi_v6.rar`

原始 `Ti60F225_DemoBoard_v4` 始终只读。需要复用的文件复制到 `board/efinix_ti60/vendor/`，保持原内容并登记 SHA256；派生修改只能进入自研 RTL、派生工程、约束和软件目录。

## 当前目录

```text
.
├─ board/efinix_ti60/                 # 官方 Demo 派生的板级工程
│  ├─ rtl/pixel/                      # A：Copy/Fill/Key/Alpha 像素模块
│  ├─ rtl/display/                    # A：FIFO、行缓存、缩放、HDMI 适配
│  ├─ vendor/sapphire_ddr3/           # 原样复用的官方 Sapphire/DDR3 文件
│  ├─ vendor/hdmi_tx/                 # 原样复用的官方 HDMI TX 文件
│  ├─ vendor/manifest.sha256          # 官方文件来源与哈希
│  ├─ constraints/                    # DDR3、GPU、HDMI 和 CDC 约束
│  └─ rtl/board_top.v
├─ chisel/
│  ├─ src/main/scala/gpu/             # 负责人：APB、AXI、渲染、DMA、QoS
│  └─ src/test/scala/gpu/             # 负责人：Chisel 单元与系统测试
├─ generated/efinix_gpu/              # Chisel split-verilog 输出
├─ sw/efinix_gpu/                     # B：Sapphire 驱动、游戏、基准
├─ release/                           # 最终位流、固件、基准和清单
├─ tb/verilog/                        # A：像素、显示和板级 testbench
├─ tb/vectors/                        # 三人共用固定向量、CRC 和随机种子
├─ scripts/                           # 测试、生成和板级验收入口
├─ docs/efinix_2d_gpu/                # 接口合同与验收记录
└─ docs/word/                         # 当前有效 Word 计划书
```

V2 实施后将新增 `board/efinix_ti60/rtl/net/`、`board/efinix_ti60/vendor/ge_udp/`、`sw/efinix_gpu/tools/asset_server/` 和 `sw/efinix_gpu/assets_v2/`。这些目录在对应任务验收前不能被 README 描述为已完成。

## 三人边界

- 负责人使用 Chisel：Asset DMA、三路 DDR QoS、GPU/Scanout 参数化、性能计数与最终集成。
- 组员 A 使用 Verilog：官方 GE Demo 复用、RGMII/MAC 包通路、UDP 资源流、FIFO/CDC、960×540 全屏显示、板级约束与 Efinity 集成。每个新增或修改的 `.v` 文件只能包含一个 `module`。
- 组员 B 使用 C：CPU/GPU 对比、Sprite 极限测试、PC 资源服务器、Sapphire 资源客户端/缓存、开源游戏逻辑移植和资源打包。

每个人每天必须提交哪些文件、每个文件的职责、输入、输出、依赖和验收条件，以有效 Word 计划书为准。

主负责人 V2 离线实现、生成 RTL 的接线说明及尚需 A/B 交付的清单见 [V2 主负责人离线交付与接线边界](docs/efinix_2d_gpu/v2_lead_offline_acceptance.md)；其中仿真结果不等于板上验收。

## 测试入口

```powershell
./scripts/test-efinix-gpu.ps1
./scripts/test-efinix-verilog.ps1
./scripts/test-efinix-software.ps1
./scripts/test-efinix-board.ps1 -EfinityHome D:/efinity -Flow map
```

V2 还必须增加以太网回环/丢包/乱序仿真、资源 CRC、960×540 整帧显示、CPU/GPU 对比和 Sprite 逐档压力测试。最终验收必须使用同一候选位流完成资源加载、网线断开继续运行、1080p60 全屏显示、稳定 60 FPS Sprite 上限和 30 分钟耐久测试。
