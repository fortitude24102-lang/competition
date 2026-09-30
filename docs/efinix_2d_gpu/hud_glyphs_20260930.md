# GPU HUD 字形局部更新：2026-09-30

## 实施边界

R7 + 当前纹理 Cache 位流，官方 Sapphire / GPU 100 MHz，960×540 RGB565 双缓冲，HDMI 1920×1080。只改普通 GPU 模式 HUD 重建：CPU 仍调用原 `hud_update_cache` 与软件 HUD Copy；`hud_cache.c`、`golden_renderer.c`、`perf_demo.c` 均未修改。Profile/legacy 不包含新路径。PC 仅提供资源。

启动时由 Sapphire 从已有点阵字体生成 39 个白/绿色字形单元，每格 14×18 RGB565，图集 `[0x02c40000, 0x02c49990)`，39,312 B。不挤占 4 KiB Sprite Cache。Sapphire 格式化文字并判定变化字符，GPU 使用现有 Copy 批量更新 `[0x02c10000, 0x02c31c00)` 的 HUD 缓存；文字缩短时复制空白单元擦除旧字。首次/失效恢复用一次全区 Fill。命令完成后才提交文本元数据，随后仍搬运完整 HUD 至后缓冲。

设计借鉴 [Fontstash](https://github.com/memononen/fontstash) 的字形图集与 [LVGL](https://docs.lvgl.io/master/API/core/lv_refr_private.html) 的局部更新，不复制第三方代码、不引入 TTF/GUI 框架、不新增 DMA/RTL。专用 DMA 是否需要，由测量决定。

## 像素与故障验证

先观察新 API 缺失导致 RED，再实现；单字符、相同文本、长→短、网络状态、CPU/GPU 切换、最大字段、部分提交超时后的完整恢复、DDR canary 均通过。数字 6→7 恰好一条 Copy，写入 504 B，无全区 Fill。字形 C 的手工点阵独立检查白/绿色及间距；其余变化序列逐字节对比原完整重绘。

`test-hud-glyphs.ps1` 的两项 UBSan 检查、原九项软件 sanitizer 检查（含 texture_cache）、R7 各档像素检查及普通/Profile/legacy 链接入口检查通过；板端 20/20 字形更新结果与真实完整软件重绘相同。已知 `SoftwareDriverSpec` / `PangoBringupSpec` 异常与链接 RWX 警告保留。本次不改 RTL，未重复 Efinity 构建或长 RTL 仿真。

## 板端 HUD 分段探针

日志：[hud-glyph-probe.log](evidence/bullet-board-20260930/hud-glyph-probe.log)。计时包括 updater 与既有 DDR 同步，不包括 UART、性能计数快照和软件像素比对。此探针只显示初始测试画面，不能代替正常整帧 FPS。

| 操作 | 实测时间 | GPU 工作量 |
|---|---:|---:|
| 原 CPU 完整重建测试文字 | 15.196 ms | — |
| 单数字变化 | 0.216 ms | 1 Copy，读写各 504 B |
| 首次/失效完整恢复 | 6.157 ms | 102 命令，含整区 Fill |
| 文字未变 | 0.115 ms | 0 命令 |
| 多字段变化 | 0.992–2.000 ms | 24–51 Copy，读写各 12,096–25,704 B |

所有探针下溢增量/硬件错误为 0。历史 10.458–10.755 ms 是另一组文字的 CPU 重建结果，不将两组数据当作完全相同输入的加速比。

## 连续 GPU 五档压力

日志：[hud-glyph-sweep.log](evidence/bullet-board-20260930/hud-glyph-sweep.log)。完整复位位流、等待 3 秒 PHY 协商后加载探针，两份网络资源零重试。每档预热 30 帧，连续测 300 帧（tick 30–329），保留游戏逻辑、Alpha/Key、纹理 Cache、背景裁剪、动态 HUD、PRESENT 与硬件计数。CPU 字段显示未测量，不编造 CPU FPS；此终端探针不是正常交替演示，也不是长时间耐久。

| 目标弹幕档 | 平均 FPS | 平均场景 GPU | P5 FPS | 下溢/错误 |
|---|---:|---:|---:|---:|
| 32 | 60.1 | 7.809 ms | 60 | 0/0 |
| 64 | 60.1 | 8.250 ms | 60 | 0/0 |
| 128 | 60.1 | 8.761 ms | 60 | 0/0 |
| 256 | 59.7 | 9.813 ms | 60 | 0/0 |
| 512 | 30.0 | 11.200 ms | 30 | 0/0 |

32/64/128 通过本轮短时连续测试。256 虽然现有 P5 判据 `qualified=1`，平均只有 59.7 FPS，个别帧仍错过刷新截止时刻，**不称为每帧稳定 60 FPS**。档位为对象槽位目标，不是保证每帧全部可见的 Sprite 数。实测 FPS 使用标称 100 MHz CLINT 换算，不将 60.1 当作 HDMI 超频结果。

HUD 更新平均从低到高为 0.147/0.163/0.187/0.220/0.258 ms，最大 1.232/1.202/1.180/1.355/1.365 ms；完整 HUD DMA 平均约 1.193–1.200 ms。256/512 的最大 PRESENT 前累计时间为 16.806/23.260 ms，已经超过 16.67 ms。该累计区间包含上一帧状态更新/统计、当前命令准备/同步与渲染，不能全部归给 GPU 内核。分段计数有少量观察开销。

**下一步判断：** 暂不增加专用文字 DMA。512 的 HUD 更新平均仅 0.258 ms，主要剩余开销在背景/场景搬运和命令准备、提交、游戏状态/同步区间。先进一步分开 GPU 命令构建、APB 提交与硬件执行，再决定描述符 DMA、Copy 读写解耦或命令批处理；不为提高分数优化 CPU 对照，也不减少 Alpha/Key 或对象数量。

## 正常交替演示与重启异常

第一轮完整位流复位后立即加载普通固件，网络启动超时（资源 101，5 重试），使用内容相同的本地后备资源。300 个 GPU 样本 P5=60，下溢/错误 0/0，`windowed_60fps=1`；此日志在摘要后截断最后窗口行，保留原样：[hud-glyph-normal.log](evidence/bullet-board-20260930/hud-glyph-normal.log)。不作为网络加载成功证据。

随后只重载固件、不复位显示硬件：资源 101/102 零重试，十个 GPU 窗口均 60.1 FPS，场景 8.087–8.130 ms（中位 8.102 ms）；CPU 2.7–2.8 FPS，场景 297.753–298.907 ms。但 300 样本出现 **80,700 次下溢**、错误 0，`windowed_60fps=0`，此轮不合格，见 [hud-glyph-network.log](evidence/bullet-board-20260930/hud-glyph-network.log)。完整复位的连续五档探针没有复现，提示热重载保留状态是待排查因素，**不是已经定位或修复根因**。

最后恢复正常交替演示，完整重载同一 BIT、等待 3 秒 PHY 协商、再加载相同普通 BIN：两份资源零重试，十个 GPU 窗口均为 **60.1 FPS**，场景 8.121–8.152 ms、中位 8.134 ms；300 个 GPU 样本 **P5=60、下溢/错误 0/0、windowed_60fps=1**。CPU 仍为 2.7–2.8 FPS，场景 296.658–297.853 ms。原始日志见 [hud-glyph-normal-reset.log](evidence/bullet-board-20260930/hud-glyph-normal-reset.log)。这是交替窗口短时通过，不等于长期耐久；连续负载另看五档探针。开发板最后运行普通 CPU/GPU 对比，没有持续烧录进程。

## 复现与哈希

```powershell
./scripts/test-hud-glyphs.ps1
./scripts/test-hud-glyph-entry.ps1
./scripts/build-board-hud-dma-test.ps1 -Test hud-glyphs
./scripts/build-board-hud-dma-test.ps1 -Test hud-glyph-sweep
./scripts/measure-hud-glyphs-board.ps1 -Bin generated/verification/board-hud-glyph-sweep/test.bin -Log generated/verification/hud-glyphs/new-sweep.log -StopPattern GLYPH_SWEEP_STOP -LoadBit
```

测量脚本打开 COM13、仅通过 JTAG 加载，拒绝覆盖已有日志；`-LoadBit` 后默认等待 3 秒。等待是测量条件，不是固件网口超时的修复。PC 服务必须保持运行：`scripts/run-bullet-asset-server.ps1`。

| 文件 | SHA-256 |
|---|---|
| 未修改的纹理 Cache BIT | `84b2e64670b1878b806aa6504af0826280c3a99830fc60a1f79906662639057a` |
| 普通候选 BIN | `8fef6f0c54ba4f10aa1c562e2bc80e671d49bb38f145c078e0c64cda9e5d3ffb` |
| 字形探针 BIN | `4147994c430a05d6a54abbf4f7571664f4a5182abe4a0ed37b61b85069de5ae2` |
| 连续五档探针 BIN | `dec3ac4b1e2b2a95dfa49da5dcaa9af361f8c3416851120356c9957f0d76f80f` |

仅 JTAG 临时测试，未写 Flash、未替换 `release/v2/`、未提高主频，已知异常未隐藏。

## 收尾审查与执行取舍

独立只读审查范围 `5c0b577..6abf188`，无 Critical/Important 问题，允许作为已标明风险的实验候选保留。两项非阻断检查待补：

- 测量脚本默认收到结束标记立即停止，连续探针最后一行被截断为 `hardware` 字段的一部分；各档完整摘要已报告 errors=0，但下次应等结束行换行后再关闭串口。原始日志不补写。
- 主机故障测试覆盖部分提交超时，尚未注入最终 tag 等待超时；实现检查表明两条错误路径都会使元数据失效，但此检查缺口保留，不称为覆盖所有故障。

执行决定按发生顺序记录，便于后续接手：

1. 用户已批准三阶段顺序，直接在既有隔离工作区执行，不再次请求同一计划批准；仅本地提交，不自动推送。代价：若理解有误，需要撤回局部实现。
2. 字形从现有字体在启动时生成，而不是新增预生成二进制资源。代价：一次启动生成时间，位于 FPS 采样之外。
3. 缓存命中测试值改为 8098→8099；8099→8100 本来就跨过 0.1ms 显示边界。代价：该测试不覆盖精度跨界，不改变产品显示规则。
4. 首次复位加载超时保留为后备资源结果，追加稳定 PHY 下的网络测量；不宣称网络根因修复。代价：启动时序问题仍需后续诊断。
5. 追加连续五档诊断，不能只用交替窗口证明连续稳定；结束后恢复普通对比。代价：额外临时 JTAG 测量，无产品路径变更。
6. 专用文字 DMA 暂不实施，按实测将下一阶段转向高档位命令/搬运区间。代价：512 档仍为 30 FPS，后续专项优化尚未完成。
