# GPU HUD候选、909容量挑战与普通路径回退（2026-10-15）

## 结论和范围

沿用项目评估的“先解决真实最坏帧、保持CPU基准”的顺序，验证HUD批提交及物理双缓冲增量更新。批提交未获可采纳收益；直接更新正常固件通过909全活动Sprite容量挑战，但其512终止探针退化未定位。**两项均不启用为默认路径，不宣称普通512严格60。**本轮交付是909特定负载成绩、可复现候选、等价/边界检查、真实正负对照及明确回退。

基础为`8d41ae495ad87933638822f0bf664b4f5bc425c1`。不合并新的A-work；远端A-work仍为已合入的`cc86953`。官方Sapphire、960×540 RGB565、GPU100MHz、Alpha+Key、网络资源/控制/遥测、游戏与CPU绘图算法不改。没有新增生产RTL、DMA、乘法器、时钟或位流。

872全活动Sprite＋109光晕、3600帧60.10FPS是10月13日原BIN的历史成绩。新Direct正常BIN本轮909＋114成绩使用同分辨率、时钟、图形尺寸及比例，但不同BIN之差不能全部归因于局部算法；更不能与普通512档（含死亡等待和重开）混用。

## 两种设计

### HUD-list：降低提交开销

原GPU字形更新已经批量排队、最后只等待一次，不存在“每个字形都等一次”的问题。本候选减少的是逐命令寄存器写入和完整HUD Copy前后的提交/退休边界。

`hud_gpu_list_init`保留场景模板0..11，增加12=双颜色字形图集、13=完整HUD、14=竞赛图片；字形图集总39312B，最大行数1404，最后字形offset38808。完成场景后重用对应私有A/B描述符bank（最多258条），字形与图片更新在先、完整960×72 Copy在后，完成后才PRESENT。

首建/清除涉及Fill时保留原驱动路径，不扩大RTL ABI；文字未变化仍执行原单次完整Copy。部分提交/错误不得切回APB重放，缓存元数据只在完整退休后提交。单个数字变化的实驱动模型：旧路径两命令20次APB写，候选两描述符5次写；这不是FPS证据。

### HUD-direct：减少像素搬运

复用同一字形增量生成器，直接写入目标物理A/B帧缓冲，不经过共享HUD缓存再完整复制。每个物理地址各存一份文字历史，不能按随PRESENT轮换的front/back角色共用。初建仍清黑、绘制全部文字和图片；稳定时仅变更字形，没变化则零命令。

已追踪普通Sprite、列表场景、提前背景Copy、菜单及WIN，GPU场景写入均避开顶部72行。初始化、场景generation变化、CPU/GPU模式变化使两份历史失效；CPU场景会覆盖整帧，故不能继承GPU历史。发生提交/等待失败，当前历史无效、循环终止，不PRESENT不完整帧。CPU继续使用原共享HUD缓存、软件栅格和完整Copy。

单个完整HUD Copy含138240B读取和同量写入；移除它理论减少276480B/帧、约16.59MB/s@60。**这是流量推算，不等于实测带宽或帧率提升。**链接正常候选text54064/BSS66808，比原text53928/BSS66280增加136B代码和528B文字元数据；无新像素缓冲。4KiB栈仍保留，静态链接不是实测水位。

## 实板对照（完整保留负结果）

共用原合格BIT，通过JTAG载入RAM；每组30预热＋600采样，零输入、CopyAhead1、FrameList1、LogicCopy1、SealWords256。记录完整STOP、路径身份、健康、可见元素与封存CRC，不只看采集进程退出码。

| 候选/组 | HUD选择 | FPS | 平均work ms | 最大work ms | 超预算/迟到 |
|---|---:|---:|---:|---:|---:|
| list off-r1 | 0 | 59.9 | 12.795 | 16.849 | 2/2 |
| list on-r1 | 1 | 59.9 | 12.782 | 16.841 | 2/2 |
| list off-r2 | 0 | 59.9 | 12.794 | 16.864 | 2/2 |
| list on-r2 | 1 | 59.9 | 12.784 | 16.867 | 2/2 |
| direct off-r1 | 0 | 43.0 | 16.143 | 21.281 | 236/237 |
| direct on-r1 | 1 | 44.9 | 14.827 | 20.461 | 203/203 |
| 原list关闭路径回测 | 0 | 59.9 | 12.793 | 16.878 | 2/2 |

各组新增下溢/硬件错误均0，可见499..504、Alpha66..67，最大wall33.277ms；600条输入完整封存CRC均`c0ecf1df`。CRC只证明同一输入记录，不证明每个渲染帧的游戏状态相同。Direct两组的逻辑进度不同（晚帧后按已有固定步长追赶），故不能把两组均值差直接归因为某一局部操作的节约。

取舍：list只有约10–13μs均值差、未改善最坏帧/迟到，不启用。在这套终止探针中，Direct整体落后于原路径，即使同BIN开启组略快、离线像素正确，也不满足普通路径采纳条件。原路径回测恢复59.9，确认不是持续性的板卡/环境变慢；**尚未定位Direct退化的根因，不把代码布局、cache冲突、栈位置或启动重建等猜测写成结论。**没有以重复选择最好组、删除重开帧或降低Sprite/Alpha负载来合格。

以上Direct退化专指终止探针，不自动推广到原生菜单/性能挑战固件。正常菜单短窗512在首窗口57.5FPS后为60.1FPS，但不足以验证最坏帧或长时间普通游戏，不作为512@60成绩。

## 原生性能挑战：909已复核

为了区分终止探针与原生固件，另加载`direct-normal`（不含ProbeFrames入口），执行真实四档START/MENU、性能租约退出、新会话及R清空成绩，然后由Sapphire自动加压。**909个全活动Sprite＋114个硬件Alpha光晕、Color Key开启，3600帧60.10FPS；最大work15.615ms、wall16.640ms，超预算/迟到/新增下溢/硬件错误均0，可见元素始终909、Alpha始终114。**之后继续绘制5秒，成绩未作废；退出后才输出完整PERF_RESULT，不用串口阻塞采样。

参数与原挑战一致：960×540 RGB565，GPU100MHz，首Sprite16×16、其余8×8，每8个附一个12×12 Alpha光晕且不重复计入Sprite；每个元素逐帧活动且在屏内。`1+909+ceil(909/8)=1024`，正好达到16KiB场景bank容量，stage5=CAPACITY，不是测出了硬件物理极限。固定3600帧约60秒，不推广为30分钟或所有游戏保证。

该结果是新正常BIN的独立实板成绩，不能抹掉上一节的终止探针回归，不能证明CPU绘图有优化，也不能证明普通512所有重开峰值已解决。保留显式`-HudDirect`候选，不将其自动用于团队的普通游戏发布路径。

随后在同BIT/同环境加载原正常BIN作追加对照（非另挑最好一次）：884候选未通过长确认后重新搜索，最终875的3600帧统计本身为零超预算/迟到/下溢/错误，但完成后观察到迟到，状态被作废为stage6/best0，验证脚本因此失败退出1。读回板上保留状态确认frames3600、target875、best0、stage6；原3600统计max work16.505ms/max wall16.643ms，不应把这些合格窗口指标当作保留资格。**本次原固件没有新的有效最高值，不撤销此前不同运行的872历史记录，也不把875当基线合格成绩。**完整HTTP捕获保存在ZIP，解压后字节SHA与源文件核对一致。

## 验证与独立审查

实际执行的检查：

- 原批提交参考实现在“必须一次list且无旧命令”的断言RED；候选GREEN。真实HUD/list/instance/GPU驱动，物理MMIO与DDR用有界模型替代，覆盖A/B、图片、缩短、CPU共享缓存衔接、tag回绕、错误后不重放、超时及bank越界。
- Direct原参考路径在“一个数字只需一次Copy且完整HUD Copy为0”RED；候选通过100次文字/模式/图标变化、错误后失效、外部覆盖后重建与DDR边界。首次等待超时夹具错误地让LAST_DONE倒退到0，实际触发TAG错误；改为冻结真实先前tag后GREEN，没有据此改产品代码。
- 23套C及27项实际UDP/HTTP回归通过；12000旧R7＋9600新玩法实例字段及3个完整像素对照通过，列表驱动通过。没有替换或优化CPU参考算法。
- `HudListCompatibilitySpec`用未改InstanceStream RTL验证新模板、最后一个字形、图片、完整Copy、背压、tag65535→0→1及非法源offset。首轮APB夹具错误地在传输后采pready，修复后实际RTL通过；最终完整GPU回归83项/18套件通过，aborted/failed/canceled/ignored/pending均0。另有8套damage软件、18000帧golden通过。这是GPU范围回归，不是全部SoC通过。
- 采集器要求显式`HudList/HudDirect=0/1`均有唯一、匹配的固件标记，防止关闭组误用旧BIN；省略选项仍兼容历史BIN。显式0缺标记问题由独立审查发现，以真实守卫RED→GREEN修复。构建保护拒绝混用两候选、缺FrameList/Interactive/独立输出/明确IP及覆盖release。

独立只读审查分两次查看同一工作树：第一次提出身份守卫及APB测试夹具两项Important，均已修复；扩展Direct后的复审无存档阻断Critical/Important，但明确**当时512退化是启用/发布阻断项**。随后909原生容量结果由作者实板补证，不冒充第三次独立审查或普通游戏批准。保留minor：Direct自动模型手动触发失效，没有实际驱动完整`v3_demo_run`完成CPU→GPU切换；作者静态追踪不能冒充自动集成覆盖。审查未亲自上板或批准发布。

历史`SoftwareDriverSpec`/`PangoBringupSpec`两项SoC异常、CPU慢绘图期间一键重选限制、实体断网、完整CPU600tick对照、栈高水位、30分钟耐久及新候选板上逐像素/人工视觉确认仍未补齐。

## 固件身份与复现

完整SHA256见`identities.json`；BIT文件仍是`D:/efinity_builds/performance_challenge_20261013_r1/outflow/efinix_2d_gpu.bit`，SHA256为`a374b64c071e9a36d88f2fe7d09817be9b6f35f951a1bc0bc72a6b35303cf0d4`。以下路径相对本仓库，输出目录必须全新：

```powershell
# list probe。删掉 -HudList 会生成不同BIN，仅用于回退；同BIN对照用采集器0/1。
scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -FrameList -HudList -StartCount 512 -ProbeFrames 600 -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/verification/v3/new-hud-list
# direct probe：仅把 -HudList 改为 -HudDirect，不同时启用。
# 实板相同BIN比较：-HudList 0/1，或对应 -HudDirect 0/1。
scripts/capture-game-probe.ps1 -Bin generated/verification/v3/new-hud-list/gpu_demo.bin -Log generated/verification/v3/new-hud-list/off.uart.log -SerialPort COM9 -LogicCopy 1 -SealWords 256 -HudList 0
```

`V3_HUD_LIST`和`V3_HUD_DIRECT`均默认0；各候选标记`V3_HUD_LIST/ V3_HUD_DIRECT,enabled=0/1`。终止探针分别读取私有字`02d10010`、`02d10014`；正常构建不读这些选择字。原CopyAhead/List/LogicCopy/SealWords四个选择字不变。

正常候选去掉`-StartCount/-ProbeFrames`，加`-PerformanceChallenge`；Direct正常BIN已通过原生909容量挑战及四档控制检查，但未通过全部普通游戏/CPU/视觉/耐久验收。恢复构建不加任何HUD候选开关，保留已合格的CopyAhead/LogicCopy/ReplayCrcNibble/ReplaySealBudget/FrameList/PerformanceChallenge组合。恢复BIN与原872实测正常BIN逐字节一致，SHA256：`8cf952e55e785629e3a835a75d2e9cb799014b7e4037bfe699aafecc81a54107`。

## 回退、网关与下一步

本次从build20261015退回20261013时，旧网关仍把20261013保留在`retired_builds`。因此串口正常进入MENU、GPU tag仍推进、控制TX计数增长，但网页拒收旧build，恢复检查两次超时（含一次重载原BIT）。检查寄存器/网关过滤逻辑后重启本任务启动的网关，四档真实START/MENU ACK＋新快照全部通过。**回退固件时重启网关，刷新网页后重新取得控制**；不删除防回退/会话/陈旧数据检查，不拿旧缓存当新遥测。

最后已再次恢复原正常MENU，build20261013、requested0、fresh真实遥测、under/error差值0、控制权已释放、无OpenOCD/烧录进程；资源服务器和网关继续运行。用户可在`http://127.0.0.1:8765`重新选择难度。仅JTAG，未写Flash、未替换release、未推送远端。

下一轮先给Direct候选做同源分段计时，区分HUD更新/完整Copy、首建/失效重建、逻辑追赶及scene/build；同时校验诊断代码本身对原路径的扰动。若不能在原路径59.9基线上得到明确最坏帧收益，就删除/继续禁用该路径，不因已投入时间而加新DMA/Cache/提高主频。性能线不接管组员玩法或美术工作。

对独立性能挑战，新的限制已是1024条场景命令容量。下一项较小的候选是复用现有两块16KiB bank分段提交、每帧保持原Alpha→Key顺序并在全部退休后PRESENT，再测更高数量；尚未实现或验证。不能只增大PC_MAX_SPRITES：B bank后紧邻PC_STATE_ADDRESS，现有单bank寻址/长度保护也必须一起审计，避免越界覆盖挑战状态。先核算所有权和完整帧代价，不把容量常量放大当硬件性能提升。

[原始证据](evidence/hud_candidates_20261015)包含七组完整串口/采集、原生容量结果/控制转换/新鲜快照、RED/GREEN与夹具失败、构建/身份/RTL/协议检查、菜单回退异常及恢复。`SHA256SUMS.json`覆盖归档字节（清单自身除外）；大BIN/BIT不入仓库。空的早期Direct身份RED日志未当证据使用，最终实际守卫回归通过。
