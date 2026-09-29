# 新弹幕场景板测与瓶颈定位（2026-09-28）

**当前执行边界：** 保留屏幕 CPU/GPU 性能对比；CPU 使用新场景原基础
配置，不新增优化，不人为降速。仅保留本轮 GPU HUD DMA；共用 HUD
变化行更新已撤回，因此其五档 sweep 为历史试验数据，不能当作当前
源码的直接验收结果。当前普通固件应与下文“仅 GPU HUD DMA”哈希一致。

## 组合与测量边界

本地组合 main `9f2eaba` 的 Alpha 分块突发/对齐 Copy RTL，以及 A-work `a488664` 的最新 R6 弹幕画面与诊断入口。GPU、板级设计、核心 100 MHz 时钟和正式 `release/v2/` 均未改；使用昨日构建的 Copy 直通候选位流，仅 JTAG 临时加载，不写 Flash。固件使用官方 Sapphire，板端 `192.168.1.3`、PC `192.168.1.2`、UDP 8080。PC 只提供 ID 101/102 的素材，不计算游戏或画面。

首次从 `release/v2/asset_server.exe` 启动服务，板端超时并使用本地回退；读到该路径的 Public 防火墙阻止规则后，改用已有放行规则的 `generated/verification/v2-network-software/asset_server.exe`。两份服务器 SHA-256 相同，没有更改防火墙。正式采样的两份资源分别为 1,036,800 B 和 3,104 B，均完整加载、CRC 校验成功、重试 0、`network_result=0`。

原始板端日志见 [分段诊断](evidence/bullet-board-20260928/profile-network.log) 和 [正常运行](evidence/bullet-board-20260928/normal-64.log)。档位以串口打印为准：现有 Profile 固定 32 对象；正常运行实际为 64 档，不能把这两个档位的数字混为同一工作量。

## 当前实测

| 正常 64 档，同一状态序列 CPU/GPU 交替 | 结果 |
| --- | --- |
| CPU 整帧 FPS | 2.8（多次 30 帧窗口） |
| CPU 场景渲染时间 | 295.865–296.914 ms |
| GPU 整帧 FPS | 15.0（多次 30 帧窗口） |
| GPU 场景渲染时间 | 10.546–10.570 ms |
| GPU 300 帧 P5 | 15 FPS |
| GPU 300 帧下溢 / 硬件错误 | 0 / 0 |
| 60 FPS 窗口判定 | 未通过 |

300 个 GPU 样本跨越 CPU/GPU 交替窗口，不是连续 GPU-only 300 帧；不代表长时间耐久。旧场景的 242,100 次下溢在本轮未复现，但尚未定位其根因，不得宣称已修复。旧场景与新场景像素工作量不同，不能把跨场景 FPS 变化归因于 GPU 优化。

32 对象 Profile 后两轮（扫描已启动，均无下溢/硬件错误）：

| 阶段 | 命令 / 像素 | 时间 | 渲染授权 | 扫描授权 |
| --- | --- | --- | --- | --- |
| 背景 Copy | 1 / 518,400 | 8.577–8.620 ms | 2,566 | 675–683 |
| Color Key | 36 / 3,072 | 0.813–0.818 ms | 1,240–1,242 | 67 |
| Alpha | 8 / 1,152 | 0.318–0.334 ms | 288 | 25–29 |
| FULL | 45 / 522,624 | 9.095–9.120 ms | 4,094–4,096 | 677–680 |
| PRESENT | 1 次翻页 | 10.509–10.596 ms | — | — |

首轮 `scan_grants=0` 且有下溢，不能纳入稳态吞吐。各阶段独立执行，扫描相位不同，不能把阶段时间简单相加推算完整帧率。`render_grants` 是 AXI AR/AW 握手次数，不是 beat 或字节数。

## 首轮分析（补测前，后续结论见文末）

1. **整帧瓶颈已不只在 GPU。** 64 档约 66.7 ms/帧，但场景 GPU 渲染只约 10.6 ms，约 56 ms 在这一测量区间外。正常循环还执行 HUD 缓存重建、CPU HUD 拷贝、同步、翻页、状态更新及统计。不能把约 95 次/秒的场景命令吞吐写成游戏 95 FPS。
2. **CPU HUD 是重点嫌疑，尚需分段计时证实。** `main.c` 两种模式都调用 `perf_render_cpu` 搬运完整 960×72 HUD（138,240 B）；`golden_copy` 使用逐字节循环。HUD 文本变化又触发 `hud_update_cache` 重绘。代码证明这些工作存在，但本轮现有诊断不单独计它们，暂不把 56 ms 全部归给 HUD。
3. **GPU 内部当前以背景搬运为主。** 32 档背景 Copy 占完整命令时间约 94%，搬运 1,036,800 B 读加等量写。新场景 Sprite 比旧 64×80 图块小得多，所以 Alpha 已非当前低档首要瓶颈。高档 512 的小事务、命令提交及 Alpha 比例尚待板测，不能从 32 档外推极限。
4. **优先做分段诊断，再决定优化。** 自动测 32/64/128/256/512 的 GPU 阶段，以及 HUD 生成、CPU HUD 拷贝和 PRESENT 的时间/下溢。若证实 CPU HUD 占主要时间，先复用已有 GPU Copy/缓存策略，之后才考虑 Color Key 合并、小 Sprite 缓存或主频调整。本轮未实施这些优化。

## 复核与复现

- 新画面的状态、游戏、HUD 缓存和五档独立像素比较在 WSL C 检查通过，代表帧 CRC 为 `3ef381d7`；这不是板端整帧像素 CRC 验收。
- 默认/legacy 与正常/Profile 四种固件真实链接并检查可达场景通过，保留原有 RWX LOAD 链接警告。未重跑未改动的 GPU RTL 长仿真或 Efinity 构建。
- 本机默认 MinGW 的检查入口报 `gcc.exe: error: CreateProcess: No such file or directory`，改用已有 WSL GCC 完成上述定向检查；这不表示原生完整回归入口通过。历史 `SoftwareDriverSpec` / `PangoBringupSpec` 异常仍未处理。
- 使用 `scripts/test-efinix-software.ps1 -FirmwareOnly [-Profile] -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102` 构建；必须选择弹幕资源目录，不使用旧 V2 素材目录。COM13 为 115200 baud。

本轮使用文件 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| Copy 候选位流 | `ec70d6db7859244871c332d55ff71770d8e95f9df711668dce9d08c7f005e91d` |
| 正常弹幕 BIN | `c65d22af360654f2e52fa2bedd5741e0deb3a73a6438c4a0ec5509c73a223103` |
| 固定 32 对象 Profile BIN | `bd778faea88accd73573088e6b1dd7a0957900497aa0176163457f780ffd55ca` |

## 五档分段诊断（同日补测，优化前）

临时 `pipeline_probe.c` 复用同一场景 builder、驱动及缓存实现，自动采样每档 tick 0/90/180；只观察性能，没有修改生产渲染路径。先 PRESENT 并空闲 50 ms 启动扫描，再采样。三时刻范围如下，所有阶段下溢为 0、硬件错误为 0；日志见 [pipeline.log](evidence/bullet-board-20260928/pipeline.log)。

| 目标弹幕档 | 实际可见弹幕 | GPU FULL | Color Key | Alpha | 场景命令构建（含同步） |
| --- | --- | --- | --- | --- | --- |
| 32 | 32 | 9.108–9.841 ms | 0.778–0.819 ms | 0.313–0.322 ms | 0.259–0.271 ms |
| 64 | 64 | 9.838–10.532 ms | 1.198–1.392 ms | 0.222–0.452 ms | 0.430–0.471 ms |
| 128 | 126–128 | 11.236–12.021 ms | 2.315–2.534 ms | 0.728–0.747 ms | 0.778–0.813 ms |
| 256 | 253–256 | 14.123–14.959 ms | 4.222–4.835 ms | 1.290–1.321 ms | 1.478–1.611 ms |
| 512 | 509–511 | 19.875–20.056 ms | 8.712–9.264 ms | 2.461–2.514 ms | 3.099–3.179 ms |

背景 Copy 在这批采样约 8.03–8.79 ms。512 档背景与 Key 共同占主要时间；68 条 Alpha 不是首要瓶颈。个别短阶段 `scan_grants=0` 处于扫描消隐相位，但已完成扫描预热、各阶段无下溢，不等同于关闭扫描。

对正常公共 HUD 路径的分段观察（暂不显示已有效的 FPS 数值，只显示初始指标文本，避免伪造各档 FPS）：

| 相同 960×72 HUD | 实测 |
| --- | --- |
| 文本变化后 CPU 缓存重建 | 10.458–10.755 ms |
| 相同文本缓存命中（含同步） | 0.085–0.128 ms |
| CPU 拷贝缓存至后缓冲 | 38.742–39.030 ms |
| 同图块现有 Copy DMA | 1.176–1.222 ms |
| GPU HUD 计数 | 69,120 像素；读/写各 138,240 B；342 次渲染授权 |

**根因证据已足够支持第一项优化：正常固件虽有对齐 Copy 快路径，HUD 却仍调用 `perf_render_cpu` 的逐字节拷贝，没有用到它。** DMA/CPU 同图块搬运耗时比约 32–33 倍，这不是整帧 FPS 倍数。缓存重建是第二项软件耗时，但只有文本变化时发生，不能按每帧固定 10.6 ms 计算。

PRESENT 在这批探针中为 0.581–16.171 ms，取决于相对于 vblank 的提交时刻；分段计数快照也引入少量观察开销。探针既重复执行分组/FULL，也额外进行 HUD DMA 对照，因此不替代正常 300 帧帧率测试，不应把这些独立阶段简单求和后宣称游戏 FPS。临时探针 BIN 哈希为 `41983ebd41122cf1c085290192c35eff2ebc68620e6c69fe930d51b3cb8ef565`。

## 实施：GPU HUD DMA 与变化行缓存

`main.c` 的弹幕 GPU 模式使用现有 `perf_render_gpu` 搬运缓存 HUD，CPU
模式仍使用软件；legacy 路径不改。所有游戏逻辑、HUD 文本/缓存构建和
GPU 命令仍由官方 Sapphire 处理，PC 只提供资源。`render_us` 仍只计场景，
FPS 包含 HUD 和 PRESENT，不能把两个指标混用。完整帧比较现在包含
GPU HUD 加速，不再称“两种模式使用相同 CPU HUD”。

真实主循环板端检查先失败于 `GPU mode used CPU HUD`，修改后打印
`HUD_DMA_PASS,cpu_huds=30,pixels=69120,rd=138240,wr=138240,under=0`。
测试用已知退出码结束主循环，并非 GPU 报错；见
[失败证据](evidence/bullet-board-20260928/hud-dma-red.log)、
[通过证据](evidence/bullet-board-20260928/hud-dma-green.log)。
可用 `scripts/build-board-hud-dma-test.ps1` 构建测试固件；该脚本不烧录。

只接入 HUD DMA 后，正常 64 档 GPU 窗口约 **40.0～58.1 FPS**，场景
约 10.56～10.59 ms；300 样本 P5 30、下溢 0、错误 0，仍不合格。
见 [normal-hud-dma-64.log](evidence/bullet-board-20260928/normal-hud-dma-64.log)。
与同场景原 15 FPS 相比有提升，但窗口范围不是平均或稳定帧率。

随后 `hud_cache.c` 仅清除/绘制文字变化的 18 行区域。测试对分数 9→10
的实际填充像素由 75,112 降到 19,096，最终缓存逐字节等于完整重绘；
零变化、字体、短文字残留、跨模式变化和 DDR 边界检查均通过。
当时先观察 `filled<25000` 失败再修改；测试源已归档为
`evidence/bullet-board-20260928/test_hud_dirty_rows_retired.c`，不再是活动测试。
正常 64 档窗口仍约 40.0～58.1 FPS、P5 30、0 下溢/错误，
**这项减少写入量未在正常整帧指标上证明进一步收益**，不声称又提升 FPS。
见 [normal-hud-rows-64.log](evidence/bullet-board-20260928/normal-hud-rows-64.log)。

## 连续 GPU 五档压力测量（含已撤回的变化行更新，历史试验）

临时 [gpu_sweep.c](evidence/bullet-board-20260928/gpu_sweep.c) 使用同一生产
builder、HUD、驱动、游戏 step 和 PRESENT，每档预热 30 帧后连续采样
300 帧（逻辑 tick 30～329）。不插入 CPU 对比窗口，CPU FPS 字段显示
未测量而非假数据；GPU 数字按真实 30 帧窗口更新。每档末尾才打印，
分段计时有少量观察开销；不是正常固件的 CPU/GPU 交替测试，也不是耐久验收。
日志见 [gpu-sweep-hud-rows.log](evidence/bullet-board-20260928/gpu-sweep-hud-rows.log)。

| 目标弹幕数 | 连续 300 帧平均 FPS | 平均场景 GPU 时间 | P5 FPS | 下溢 / 错误 |
| --- | --- | --- | --- | --- |
| 32 | 52.8 | 9.472 ms | 30 | 0 / 0 |
| 64 | 47.0 | 10.419 ms | 30 | 0 / 0 |
| 128 | 43.0 | 12.011 ms | 30 | 0 / 0 |
| 256 | 30.0 | 14.770 ms | 30 | 0 / 0 |
| 512 | 28.6 | 19.944 ms | 20 | 0 / 0 |

平均 HUD 缓存更新随档位为 1.068 / 1.870 / 2.615 / 3.893 / 4.417 ms，
HUD DMA 约 1.04～1.20 ms，游戏 step 约 0.070～0.951 ms。
平均 PRESENT 等待约 5.25～11.55 ms，是同步等待，不全是无效 CPU 计算，
不能简单删除而破坏双缓冲。P5 30/20 与漏掉刷新周期一致，但未逐帧
捕获最坏 HUD 更新与 vblank 相位，尚不足以将每个低帧归因给单一阶段。
低档剩余瓶颈包括动态 HUD/刷新截止时刻，高档场景本身已经超出 16.67 ms。

硬件下一步优先减少 Color Key 单 beat 写事务，再评估背景 Copy 连续调度
与读写解耦；依据及 GitHub 作者源码复核见 [优化选型](gpu_performance_options.md)。
未新增外部 DMA 核、提高主频、减少对象或关闭 Alpha 来制造达标数字。

| 补测固件 BIN | SHA-256 |
| --- | --- |
| 仅 GPU HUD DMA 正常固件 | `df5fcd0abf980bd98b9f49f196412c2946f6bde2024b126db959b863401511a8` |
| HUD DMA＋变化行缓存正常固件 | `76a415f64cf8b6f847cd06c868bca206ae1d7aecad6b89e6ab1ed0087bff236e` |
| 连续 GPU 五档探针 | `32c9d112cdaf286bb4b8a023b4bcf3ea76241bef3aa3db70374cc611c0c8201b` |

本轮软件基础入口 `test-efinix-software.ps1` 的全部 8 个 C 检查和固件
链接通过；新 HUD 工作量检查及原 HUD 像素/边界检查通过，保留 RWX
链接警告和 WSL localhost 代理提示。未重跑无改动 RTL 的长仿真；这不
撤销历史 SoC 测试异常，也不表示默认 MinGW 回归入口已可用。
板端探针最后正常退出，当前无烧录/OpenOCD 进程，未写 Flash。

## 撤回公共 HUD 优化后重跑基线

使用仅 GPU HUD DMA 固件 `df5fcd0a…1511a8` 和原 Copy 候选位流，
重新 JTAG 加载，CPU 场景与 HUD 仍为 A-work 基础软件实现。
资源 101/102 均加载成功、重试 0。正常实际 64 档 CPU 窗口为
2.5～2.6 FPS、场景 331.962～333.621 ms；GPU 窗口为
40.0～58.1 FPS、场景 10.558～10.586 ms。300 个 GPU 样本 P5 为
30 FPS，下溢/硬件错误均为 0，`windowed_60fps=0`。
见 [本轮重跑日志](evidence/bullet-board-20260928/rerun-cpu-basic-gpu-dma.log)。
CPU 读数是实际测量而不是优化对象；窗口范围不是稳定帧率。

下一项硬件改动仅将对齐、偶数宽度 Color Key 接入已有 Copy 字突发通路，
每个 32-bit 字并行比较两个 RGB565 像素，以 WSTRB 保留透明像素。
全透明字也保持突发 beat（WSTRB=0），不读背景；错位/奇数宽度保留
原像素路径。先验证随机背压、4 KiB 分割、错误响应和像素结果，再构建
候选位流板测。此处是设计说明，不是性能达标结论。

新测试在旧 RTL 上因 Color Key 无法绕过被阻塞的像素流水线而失败，
修改后两项定向测试通过；完整 GPU 回归一次通过 **61/61**，随后生成
RTL 成功，见 [回归日志](evidence/bullet-board-20260928/key-word-gpu-regression.log)。
审查未发现阻塞问题，历史 SoC 固件测试异常不在这次 GPU 回归范围。
实现只改变 `DenseBlitEngine.scala` 与其生成文件，使用原读写引擎、
命令接口、CPU、显示/网络链路及 100 MHz 时钟。

板端短检查源码为 `sw/efinix_gpu/tests/test_board_key_burst.c`，
用 `scripts/build-board-hud-dma-test.ps1 -Test key` 构建（只生成、不烧录）。
它用已知源/背景像素逐字节检查三个情况：对齐跨 4 KiB、错位回退、
奇数宽度回退，并检查行尾保护区、处理像素数及有效读写字节。
预期串口三个 `KEY_BOARD_CASE_PASS` 及 `KEY_BOARD_STOP,result=0`；
在实际板测前不能仅凭链接成功宣布检查通过。

## Color Key 字突发候选：构建与板测

Efinity `map/interface/pnr/pgm` 全部 PASS，仅 JTAG 临时加载。
100 MHz 核心 setup/hold 余量为 2.104/0.026 ns；SDRAM 400 MHz
setup 余量 0.084 ns。保持原时钟，不按静态报告的最高分析频率超频。
综合资源相对 Copy 候选：LUT 28,694→28,835、FF 27,231→27,238；
RAM10 为 141、DSP48/DSP24 为 10/6，均未增加。
见 [构建日志](evidence/bullet-board-20260928/key-word-compile.log) 与
[最终时序](evidence/bullet-board-20260928/key-word-timing.rpt)。

三个实际 DDR 检查均通过，硬件错误 0；对齐/错位/奇数宽度分别计
24/24/22 像素、48/56/48 B 读取和各 24 B 有效写入。
所有透明像素、填充背景和保护区与独立期望一致，见
[板端字节检查](evidence/bullet-board-20260928/key-word-board-bytes.log)。
这项短检查发生在扫描开启前，不单独用它证明显示持续供给。

继续使用**完全同一份**五档探针 BIN（`41983ebd…ef565`），资源 101/102
加载成功、重试 0；扫描预热后每档 tick 0/90/180 的结果如下。
各案例的可见数、命令数、处理像素及有效读写字节与优化前完全相同，
没有缩图、裁减对象、改素材或关闭 Alpha。
见 [候选五档分段日志](evidence/bullet-board-20260928/key-word-pipeline.log)。

| 目标档位 | 原 Key → 新 Key | 原 FULL → 新 FULL |
| --- | --- | --- |
| 32 | 0.778～0.819 → 0.616～0.657 ms | 9.108～9.841 → 8.928～9.648 ms |
| 64 | 1.198～1.392 → 1.106～1.136 ms | 9.838～10.532 → 9.547～10.308 ms |
| 128 | 2.315～2.534 → 2.087～2.125 ms | 11.236～12.021 → 10.789～11.584 ms |
| 256 | 4.222～4.835 → 3.401～4.096 ms | 14.123～14.959 → 13.344～14.123 ms |
| 512 | 8.712～9.264 → 7.317～7.992 ms | 19.875～20.056 → 18.468～18.551 ms |

五档全部分段与流水探针下溢为 0、结束硬件错误为 0；不替代耐久验收。
512/tick 0 的 Key 授权次数由 14,680 降到 10,616（约减少 27.7%），
耗时 8.879→7.317 ms（约减少 17.6%）；同案例 FULL 为
20.056→18.541 ms（约减少 7.6%）。这是同工作量事务合并的实测收益，
不是跨画面比较。扫描相位影响短采样，因此不把区间极值相除当作加速比。

背景仍约 8.04～8.79 ms，512 档 Alpha 约 2.35～2.49 ms；512 FULL
仍超过 16.67 ms，不宣称稳定 60 FPS。当前对齐条件只能覆盖部分子弹，
错位 Color Key 仍落回逐像素/单 beat 路径，是下一轮候选瓶颈；背景
Copy 的调度/读写解耦也是候选。二者需分别验证，不能直接以开源核
替换并假定收益，更不能取消显示 QoS/双缓冲来制造高帧率。

| 本轮文件 | SHA-256 |
| --- | --- |
| Color Key 候选 BIT | `3704eef20a080f7ddf4bcf523f1620080ec011f5a071ddaf2a2eeb432330fbe0` |
| 生成 DenseBlitEngine.sv | `9e661173ff731d856fa0f5fffa5d5085c0884c2ef53a440949f4bc45201e8cca` |
| DDR 字节检查 BIN | `b8f072c802704558a5041f946de0b344c383c3a3cdebb496d9106bee0adeb518` |

位流保存在 `D:/efinity_builds/key_word_burst_20260928/outflow/efinix_2d_gpu.bit`，
本轮没有覆盖 `release/v2/`。普通 CPU/GPU 对比固件仍为
`df5fcd0a…1511a8`，另测包含 HUD/PRESENT 的 300 GPU 样本，结果如下。

普通实际 64 档对比：CPU 窗口 2.5～2.6 FPS，场景
332.037～333.564 ms；GPU 窗口 **40.0～58.1 FPS**，场景
10.310～10.330 ms。300 个 GPU 样本 P5 为 **30 FPS**，下溢/硬件
错误 **0/0**，`windowed_60fps=0`；见
[普通演示日志](evidence/bullet-board-20260928/key-word-normal-64.log)。
与本轮刚重跑的相同固件基线 10.558～10.586 ms 相比，九个对应窗口
的场景时间减少 2.3～2.5%（平均约 2.4%），但完整窗口
FPS 范围和 P5 **没有提升**。
HUD 重建与刷新截止时刻仍限制整帧，不能把场景改进写成整帧提速。
这轮接受的收益是高档 Key/场景执行耗时与事务数下降，不是 60 FPS 达标。

下一步聚焦硬件：先补错位 Key 的字对齐/合并通路覆盖率，再评估
背景 Copy 读写解耦与调度。GPU 专属 HUD 工作也可作为整帧瓶颈候选，
但不得改公共 CPU 对照实现。当前板上已恢复普通 CPU/GPU 演示，
采样已结束，资源服务器保留；无活动烧录/OpenOCD/构建进程。
本轮源码与记录为本地候选，尚未推送或更新正式 V2 发布包。

## 半字相位 Color Key DMA 候选

在上一轮对齐 Key 字突发上增加 RGB565 移位/携带和首尾 lane 掩码，
覆盖错位、奇数宽度及独立步长；重叠 Key 保留原像素路径。CPU、素材、
命令顺序、软件 ABI、100 MHz 主频和显示 QoS 均未改。

GPU 回归 63/63、补充定向测试 3/3、Efinity 全流程和板端 DDR 29/29
通过。核心 setup/hold 余量 1.792/0.026 ns；资源相对上一候选为
LUT 28,835→29,274、FF 27,238→27,354、DSP48 10→14，RAM10 不变。
新增 DSP 来自重叠区间判断，不是 Alpha 吞吐提升。

完全相同五档固件的 60 个阶段工作量逐项一致，全部下溢/硬件错误为 0。
512 档 Key 从 7.317～7.992 ms 降至 6.745～7.281 ms，FULL 从
18.468～18.551 ms 降至 17.724～17.884 ms。普通同固件 64 档 GPU
场景由 10.310～10.330 ms 降至 10.214～10.231 ms（平均约 0.974%）；
整帧仍 40.0～58.1 FPS、P5=30、60 FPS 判定 0。CPU 保持基础实现
2.5～2.6 FPS，未优化。

候选位流 SHA-256 为
`7f77708a18e0a71a33800fb1a62bdce094a9c21418e32244bde7b2feac327d34`；
只通过 JTAG 临时加载，没有写 Flash 或覆盖 `release/v2/`。实现、完整
对比表和证据索引见 [半字相位 DMA](key_phase_dma_20260928.md)。

## 2026-09-29 前台资源服务器复验

新增 `scripts/run-bullet-asset-server.ps1`，在运行现有 C 服务器前检查素材
清单、PC IPv4 和 UDP 端口所有者；服务器仍以前台进程运行，脚本不修改
网卡、防火墙，也不结束未知占用进程。进程级测试覆盖正常前台运行、同一
服务器重复启动、外部端口占用、缺失资源和错误本机地址；现有真实 GET、
分块、LAST 和 CRC 测试对弹幕目录为 2/2 通过。

PC `192.168.1.2/24`、千兆链路和 UDP 8080 监听确认后，重新通过 JTAG
临时加载纹理 Cache 候选位流与普通弹幕固件。COM13 实测如下：

```text
BULLET_ASSET,id=101,bytes=1036800,retries=0,result=0
BULLET_ASSET,id=102,bytes=3104,retries=0,result=0
TEXTURE_CACHE,result=0,base=02a00000,bytes=3104,network=1
```

这证明此前网络超时是 PC 服务进程未持续监听造成的运行前置条件缺失，
不是 PHY、板端 IP、协议或素材 CRC 故障。本轮没有改 C 服务器和协议；
PC 仍只提供静态素材，Sapphire 仍负责请求、校验、状态和 GPU 命令。
原始命令、UART、哈希与环境见
[network-launcher.log](evidence/bullet-board-20260929/network-launcher.log)。
本次只用 JTAG，没有写 Flash 或替换 `release/v2/`。

## 2026-09-29 HUD 覆盖区背景裁剪

普通 GPU 模式的第 0 条命令原本把 960×540 背景完整 Copy 到后缓冲，
随后 960×72 HUD 又完全覆盖顶部区域。本轮只在普通 GPU 模式把背景
命令改为从源、目标第 72 行开始，尺寸为 960×468；CPU 路径与 Profile
保持完整 540 行。每帧因此减少 69,120 像素、138,240 B 读和 138,240 B
写，未改变背景可见像素、对象数量、Alpha、分辨率、主频或显示 QoS。

Host 像素比较覆盖本地/网络背景、A/B 后缓冲、tick 0/90/180，以及穿过
第 72 行的对象；Icarus 重放 599,464 个像素通过。板端 Profile 对照实际
报告背景 518,400 像素、读写各 1,036,800 B，证明 Profile 仍为完整
960×540。普通 64 档固定探针为 64 个可见子弹、12 条 Alpha 命令。

干净重载同一纹理 Cache 位流后，网络素材 101/102 均零重试，网络图集
Cache 有效。十组完整 CPU/GPU 30 帧窗口结果如下：

| 指标 | CPU 基础路径 | GPU 裁剪候选 |
| --- | ---: | ---: |
| `render_us` 中位数 | 297,111.5 | 8,104 |
| `render_us` 范围 | 296,156～297,287 | 8,100～8,118 |
| 屏显窗口 FPS | 2.8 | 40.0～58.1（中位 48.7） |

GPU 相比同场景纹理 Cache 基线中位 9,300 us 减少 1,196 us，即
**12.86%**。300 个 GPU 样本为 `p5_fps=30`、新增欠流 0、硬件错误 0、
`windowed_60fps=0`。因此接受此候选作为 GPU 命令时间优化，但不把
8.104 ms 倒数当作游戏 FPS，也不宣称稳定 60 FPS；屏显节拍/HUD/Present
仍限制整帧。CPU 没有优化，PC 仍只提供静态资源。

位流 SHA-256 为
`84b2e64670b1878b806aa6504af0826280c3a99830fc60a1f79906662639057a`，
普通固件 SHA-256 为
`168d3822310e4df220aa658723a479ae02f8deeb1e65afe68d68a58bde1371d7`。
原始 Profile、十组窗口、300 样本摘要、命令几何和加载边界见
[hud-background-clip.log](evidence/bullet-board-20260929/hud-background-clip.log)。
只用 JTAG 临时加载，未写 Flash、未替换 `release/v2/`；已知非 GPU
`SoftwareDriverSpec`、`PangoBringupSpec` 异常未在本轮处理。
