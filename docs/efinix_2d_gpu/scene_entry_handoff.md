# 当前弹幕画面入口交接（2026-09-27）

已读取最新 main：`9f2eaba`（Alpha 分块突发、对齐 Copy 直通及显示下溢计数）。
本次只在 A-work 调整软件构建/诊断入口；不合并 main，不更改 GPU、板级
设计、素材、游戏逻辑、计数口径或正式 `release/` 包。

## 为什么会编译成旧画面

A-work 的 Makefile 和 main.c 原本已默认选择 BULLET，但常用
`scripts/test-efinix-software.ps1` 强制定义 `BULLET_DEMO_DEFAULT=0`，
所以该路径仍生成旧 Sprite 对比画面。现在统一默认 BULLET；保留
`-Demo legacy` 供受控旧场景对照。当前画面保持 R6 的敌我飞机、六种
子弹、Alpha 光晕/护盾、自动生存机制及清晰字体，未改其像素输出。

## 默认新画面固件

从仓库根目录执行；这里的网络参数与 main 板测记录一致，不修改 Windows
网卡、防火墙或板卡配置：

```powershell
./scripts/test-efinix-software.ps1 -FirmwareOnly `
  -RiscvGcc C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe `
  -Soc Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/par/ddr_demo_ti60/embedded_sw/soc `
  -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102
```

下载候选入口：`generated/verification/efinix-software/gpu_demo.elf`，并有
同目录 BIN/HEX。也可继续用 `build-bullet-firmware.ps1` 或 Makefile，
它们原本就默认新场景。不能直接使用旧 `release/v2/gpu_demo.*` 期待新画面，
正式包本次未替换，编译不等于已经下载/上板。

PC 资源目录要选择当前弹幕的 ID 101/102：

```powershell
./release/v2/asset_server.exe ./sw/efinix_gpu/assets/bullet/manifest.csv 8080
```

继续用旧 V2 素材目录会触发新场景本地回退，而不是加载新弹幕资源。
回退仍显示同样的新画面，但 NET 状态不同，不代表以太网验收通过。

## 保留最新 main 的诊断用途

在上方编译命令追加 `-Profile`，进入 BACKGROUND/KEY/ALPHA/FULL/PRESENT
三轮、32 个目标对象的分阶段诊断。它选择当前弹幕场景；追加
`-Demo legacy -Profile` 才是旧 32 Sprite 诊断。日志标出 BULLET/LEGACY。
main.c 只增加该条件入口，正常比较循环未改；分组借用现有 BSS HUD
缓冲，避免原来的固定 33 条限制，仍检查容量。诊断不显示正常 HUD，
也不是持续运行游戏或 512 档位压力测试。`-Profile -PublishRelease`
会在编译/写文件前被拒绝；本次从未调用发布或下载操作。

## 负责人选择文件时的边界

保留 main 当前的硬件与发布记录；只取 A-work 的画面软件文件及构建入口。
如果尚未引入之前的弹幕工作，main.c 不是单文件替换就能链接，需要一起
取现有 Makefile、bullet_demo/bullet_assets、hud/hud_cache、对应头文件及
`assets/bullet/` 素材；已有 shared driver/perf/network 代码不须替换。
主负责人有板时自行选择已验证的 V2 或性能候选位流，核对接口版本。
本次 A-work 硬件仍为 a82f3dd 基线，绝不以旧 RTL 覆盖 main 的新性能 RTL。

最新 main 约 20 FPS 是旧场景的板测结果，且长期统计有 242100 次显示
下溢；不能移植为新画面的成绩。新场景必须重新测量帧率、下溢和像素
一致性。性能方案另见 [优化建议](gpu_performance_options.md)，只提出建议，
本次未实施任何性能硬件变更。

## 离线验证记录

入口测试先在旧构建路径中失败：默认 ELF 没有 `bullet_build_frame`。
修复后四种固件均真实链接，并检查 ELF 中可达场景/诊断代码，而非检查
脚本是否含某段文字。结果：

| 固件 | text / BSS（字节） | 可达场景 |
| --- | --- | --- |
| 默认 | 23488 / 78832 | bullet_build_frame |
| legacy | 17658 / 47496 | perf_build_frame |
| 默认 Profile | 14960 / 65888 | bullet_build_frame |
| legacy Profile | 10706 / 45096 | perf_build_frame |

均满足原有 RAM/栈约束，保留原链接脚本 RWX LOAD 警告。验证脚本
`test-firmware-scene-entry.ps1` 在结束或后续用例失败时还原本轮已验证的
默认新画面固件，防止下载目录停留在旧画面/诊断版本。

原有 12 个 C 回归套件和两套真实 localhost UDP 资源目录通过；弹幕
状态、游戏机制、HUD 缓存与五档独立像素比较通过；既有像素 RTL 重放
仍为 599464 操作，代表帧 CRC 仍为 `3ef381d7`。只运行一遍完整回归及
画面仿真；没有重新跑 GPU Chisel 或 Efinity 构建，因为硬件未改。
main 已披露的 `SoftwareDriverSpec` / `PangoBringupSpec` 基线异常不在
本次范围，未修复或宣称全项目通过。诊断入口的实际板端计数/显示尚未验证。

本次日志在 `generated/verification/scene-entry/`，历史 R6 波形/预览不变。
只读审查未发现关键/重要问题。已按其建议把默认固件还原放进 finally；
针对性注入后续用例失败，确认旧场景编译之后仍恢复默认 ELF/BIN/HEX/MAP。
最后按上方 192.168.1.3/192.168.1.2 参数构建正常弹幕交接候选，并确认
只有当前场景可达、没有进入 Profile；不是诊断矩阵最后的 legacy 固件。
