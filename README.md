# AetherGX · Ti60F225 二维图像渲染加速器

**2026-10-27 最终演示版。** 官方 Sapphire RISC-V 在板上执行资源选择、CRC 校验、游戏逻辑和 GPU 命令调度，Chisel GPU 完成二维渲染；PC 提供资源、输入转发和网页数据展示。目标平台为 Ti60F225 Demo V4，核心 100 MHz，HDMI 960×540 RGB565。

## 直接开始

- 本机网页：[AetherGX-2D渲染加速异构平台](http://127.0.0.1:8765/)。这是连接板卡电脑上的本地地址；GitHub 保存工程与交付文件，不能代替本地网关连接硬件。
- [最终 BIT / BIN / HEX 与校验值](release/final-20261027/README.md)。只用 JTAG 加载 BIT 和 RAM 固件，未写 Flash；原有 V1/V2 发布包保留。
- [网页、输入与网络使用说明](docs/efinix_2d_gpu/v3_control_usage.md)，[游戏玩法](docs/efinix_2d_gpu/v3_game_usage.md)。

板卡 IP `192.168.1.3`，电脑直连网卡 `192.168.1.2`。资源服务 UDP `8080`，管理服务 UDP `8090`，浏览器 HTTP `127.0.0.1:8765`。资源服务与管理网关需要各自保持运行；现有本机会话已启动。

```powershell
# 工程根目录；Python 路径按本机安装位置填写。
powershell -File scripts/run-bullet-asset-server.ps1 -PcAddress 192.168.1.2
powershell -File scripts/run-control-gateway.ps1 -BoardIp 192.168.1.3 -UdpBind 192.168.1.2 -Python D:/efinity/python311/bin/python.exe
```

## 两种独立展示

原生游戏保留 **64 / 128 / 256 / 512 / 786 / 1024** 六档，画面与游戏流程保持原样。档位是请求数量，不等于每帧可见数量，也不是全活动 60 FPS 极限。五向键可操作板端菜单，浏览器也可选择难度、控制和返回菜单。

菜单另有 **CPU / GPU 同屏展示**：左 CPU、右 GPU，原场景按比例缩为相同的 **480×270**；256、512 档各运行 **15 秒**，双方独立刷新，不再限制 300 帧。网页点击“开始同屏展示”，或者在 HDMI 菜单移到第七张展示卡后按 MID。完成后保留成绩，网页“一键重选难度”退出。

| 请求档位 | CPU 新显示帧数 | GPU 场景显示帧数 | CPU FPS | GPU FPS |
|---|---:|---:|---:|---:|
| 256 | 69 | 901 | 4.60 | 60.06 |
| 512 | 35 | 901 | 2.33 | 60.06 |

以上为最终交付 BIN 的一次实板记录，每档 15 秒，新增下溢/硬件错误均 0。统计各自真正显示的新图像；GPU 受约 60 Hz 显示刷新率限制。CPU 同时承担游戏逻辑与 GPU 调度，所以这些是**同屏协作运行成绩**，不能当作各渲染器独占整机的吞吐。边界轮询可能保守少计一帧。完整来源见[同屏实测与验证证据](docs/efinix_2d_gpu/evidence/split_comparison_20261027/README.md)。

网页将游戏档位选择、CPU/GPU 同屏比较、性能测试并列展示，指标区显示实时 GPU 帧率和场景精灵数量，并展示已保存的 GPU 侧 DDR 有效吞吐和 RISC 核已测工作占比。后两项来自 2026-10-17 的 512 全活动专项记录：工作占比只覆盖逻辑与命令构建，不是 RISC 核总占用率；GPU 侧吞吐不代表整机 DDR 物理吞吐。页面标明数据来源，不将历史记录冒充实时值。遥测过期时隐藏实时成绩；未收到的完整成绩不以历史值补齐。原始 CSV 保留有效标志和全部字段。

## 本轮采用的最终优化

缓存行最终写入与下一行交接重叠已采用。同 BIN、1024 普通游戏四轮短 A/B/A/B，各 720 帧：平均帧工作时间 **8702.5 → 8656.5 µs，减少 0.529%**，四轮超预算、迟到、新增下溢和错误均 0。不是新增耐久或硬件极限成绩。[硬件配置、像素、时序与 A/B 证据](docs/efinix_2d_gpu/evidence/key_row_handoff_20261027/README.md)。

同屏展示复用原有紧凑命令构建、纹理缓存和 CPU 基础栅格算法；CPU 逐行推进，GPU 不等待 CPU 完整绘制。仅拷贝已更新的 CPU 图像和变化的 HUD 字形。离开展示后恢复原生纹理缓存，六档游戏已逐一验证。还修复了驱动把连续前进的完成标记误判为错误的问题，保留真实错误、回绕和越界检查。

最终 BIT：`c9c55d8a022e9fa226aa6168185743af67c1a83470bc7f1709c89bbd1f09e94f`。

最终 BIN：`5cff130805e8f00cf918ee07be3a8c69c5e260eb4e66a740b5e8c5b5a8068029`。

## 复现与检查

```powershell
# 软件集成检查；不连接 JTAG，不跑长板测。
powershell -File scripts/test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble -ShapeLut
# 最终交互固件；输出目录必须是新目录，工具链可按脚本参数覆盖。
powershell -File scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -FrameList -HudDirect -ShapeLut -PerformanceChallenge -ObjectCapacity 1024 -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/final-rebuild
```

本轮验证覆盖 32 个真实场景的全部 480×270 像素对照、2400 次逻辑时钟差分、完成标记连续前进/回绕、两段计时与中途退出、双缓冲/HUD 所有权，以及真实浏览器控制和退出后六档游戏。硬件沿用已通过像素与 16 项正裕量时序检查的最终 BIT；本轮不再继续性能搜索或跑长测试。

## 工程入口与历史资料

| 路径 | 内容 |
|---|---|
| `chisel/src/main/scala/gpu/` | GPU、DMA、缓存、仲裁与显示 |
| `board/efinix_ti60/` | 官方 SoC 集成、板级 RTL、管脚和约束 |
| `sw/efinix_gpu/` | 驱动、游戏、CPU 对照、资源与网页 |
| `scripts/` | 构建、软件检查、JTAG/RAM 加载与采集 |
| `release/final-20261027/` | 最终演示 BIT、BIN、HEX 和 SHA256 |
| `docs/efinix_2d_gpu/evidence/` | 原始测量、时序与版本身份 |

旧 README 的全部开发记录与用户更正移至[历史记录](docs/efinix_2d_gpu/README.history.md)。15 份已被替代、无文件名引用的阶段计划/报告已[归档压缩](docs/efinix_2d_gpu/archive/README.md)并删除散落副本；失败记录、最新复盘与原始实测依据保留。历史“下一步”“当前”“未推送”只适用于相应日期，不覆盖本最终版。
