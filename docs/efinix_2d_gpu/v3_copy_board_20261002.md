# V3 负责人第5天：连续 Copy 上板对照

日期：2026-10-02。结论：候选正确、100 MHz时序合格，但未得到有意义的整帧净收益；保留旧硬件基线，不把连续Copy作为512@60的已完成方案。CPU绘图、游戏逻辑、R7资源和官方vendor均未修改；只通过JTAG加载，不写Flash。不是V3封版。

## 1 同条件对照与实测

新旧两工程使用同一批生成器/源码、官方SoC、板级适配、约束、种子1，区别仅为构建期enableCopyStream开关。旧对照由`--legacy-copy`生成，不拿不同年代的固件混比。两者全量compile退出0。

完整帧数据来自同一份`board-render-phases/test.bin`，复用R7生产命令构建、场景、HUD及双缓冲；每档30帧预热+300帧，probe=0是不插提交计时的主对照。probe=1用于观察提交压力，不混入主对照。

| 指标，probe=0 | 关闭新通路 | 连续Copy候选 |
| --- | --- | --- |
| 64档平均FPS / P5 FPS | 60.1 / 60 | 60.1 / 60 |
| 256档平均FPS / P5 FPS | 60.1 / 60 | 60.1 / 60 |
| 512档平均FPS / P5 FPS | 30.0 / 30 | 30.0 / 30 |
| 512场景执行 | 13.437 ms | 13.346 ms |
| 512硬件busy | 12.027 ms | 11.937 ms |
| 512 HUD Copy | 1.212 ms | 1.191 ms |
| 512完整帧工作 / P95 / 最大 | 19.265 / 19.490 / 20.876 ms | 19.153 / 19.386 / 20.758 ms |
| 512超出1/60秒工作预算帧数 | 300/300 | 300/300 |
| 六个300帧窗口（3档×probe开关）下溢/错误 | 全0/0 | 全0/0 |

双方可见元素范围一致：64档60～64、256档248～256、512档501～512；平均命令分别80.6、295.5、581.7。512场景DDR读/写每帧均919289/951204 B，cache_bytes85998，无删对象、降Alpha或缩分辨率。

512完整帧工作减少112 us（约0.58%）；还需平均至少约2.49 ms、P95约2.72 ms才进入16.667 ms预算，且不能只看均值。显示PRESENT按垂直消隐，错过截止便落到约30FPS。CPU构建、提交阻塞、硬件执行有重叠，不能相加。

隔离R7背景（512档tick0/90/180）旧7593/7603/7609 us，新7469/7463/7471 us，均读/写898560 B、下溢0；但另一个相同离屏大Copy几何的像素核对任务，旧7245 us、新7529 us。两种入口的地址/显示相位不同，不能挑快的数字宣称稳定加速；小任务单次耗时也不作为性能排行榜。此轮每入口一次对照，不是统计显著性或长期稳定认证。

正常生产入口使用完全相同的normal.bin：旧CPU2.8、GPU60.1 FPS，新CPU2.8、GPU60.1 FPS（实际启动档64）。候选正常入口日志在render_us字段处截断：采集脚本按前缀过早停止，故仅引用已经完整收到的FPS，不补写缺失耗时。最终恢复正常入口改为等待完整行。

## 2 时序和资源成本

| 综合/STA指标 | 关闭通路 | 候选 |
| --- | --- | --- |
| core_clk约束 | 100 MHz | 100 MHz |
| core setup / hold裕量 | +1.264 / +0.020 ns | +1.366 / +0.026 ns |
| 所列时钟关系最小setup / hold | +0.298 / +0.012 ns | +0.197 / +0.006 ns |
| EFX_LUT4 | 29574 | 30615（+1041） |
| EFX_FF | 27766 | 27870（+104） |
| EFX_RAM10 | 145 | 147（+2） |
| EFX_DSP48 / DSP24 | 14 / 6 | 15 / 6 |

资源为map报告中的原始primitive计数，不是手工换算的LE占用。候选额外DSP来自控制计算等综合映射，不代表新增像素乘法能力。STA可分析上限不是已验证超频；此轮始终100MHz。保持现有约束，不新增宽泛false path来隐藏失败。

## 3 DDR像素核对及失败记录

新增板级测试`test_board_copy_stream.c`：CPU只生成独立测试数据与期望值，GPU执行Copy。检查每个像素、行间padding、两端保护半字、像素数、实际AXI读写字节及下溢。它不参与生产CPU对照算法。

| 用例 | 新读/写B | 旧读/写B | 最终新/旧结果 |
| --- | --- | --- | --- |
| 960×468，stride1920，源/目的4 KiB余量不同 | 898560/898560 | 同左 | 全像素/保护区一致，下溢0 |
| 514×3，stride1028 | 3084/3084 | 同左 | 一致，下溢0 |
| 3×2，stride6，连续奇数宽 | 12/12 | 16/12 | 一致，下溢0 |
| 8×3，stride24，必须回退并保留padding | 48/48 | 同左 | 一致，下溢0 |

旧3×2逐行读会把每个6 B行取整成8 B，新连续路径只读12 B。因此最初诊断脚本要求双方读12 B属于错误断言，旧实现曾报failed=1，但像素/写入/下溢正确。修正只接受逻辑长度或逐行word取整长度，保留原失败日志；不修改生产驱动和RTL来迁就测试。

最初测试在启动scanout后由CPU连续初始化近1.8 MB DDR，新旧分别观察到139/133次下溢，Copy像素均一致。将同地址的大数据准备移到首次PRESENT之前后，两者四项均0下溢。这定位出诊断的CPU写入并发干扰，**不是修复了CPU大块写DDR的并发显示问题**。此类压力和旧热重载异常仍需单独处理。

运行本测试必须先完整重载FPGA位流，再加载固件；`gpu_init()`和CPU-only重载不会清掉GPU的scanoutStarted。不得将上述隔离通过当作热重载安全。常规R7另有独立完整帧测量，不能由这个离屏测试替代。

## 4 文件及复现

工程入口继续复用`scripts/test-efinix-board.ps1`，新增严格参数、GpuRtlDirectory和PrepareOnly。按完整filelist替换所有旧GPU design_file，保留板级/vendor/IP/约束，按XML schema顺序插入。候选45清单项＝44模块文件+1个.vh；原工程XML未修改。

```powershell
powershell -File scripts/test-v3-board-project.ps1
powershell -File scripts/test-efinix-board.ps1 -GpuRtlDirectory generated/verification/v3/copy/rtl -OutputDirectory D:/efinity_builds/NEW_COPY_RUN -Flow compile
powershell -File scripts/test-efinix-board.ps1 -GpuRtlDirectory generated/verification/v3/copy/rtl-legacy -OutputDirectory D:/efinity_builds/NEW_LEGACY_RUN -Flow compile
powershell -File scripts/build-board-hud-dma-test.ps1 -Test copy-stream
```

不要原样覆盖既有测量输出。候选上板先显式JTAG加载对应bit；历史`measure-hud-glyphs-board.ps1 -LoadBit`仍固定旧9/28位流，不能用该开关冒充新候选。采集退出码0只表示收到终止标记，必须检查固件result/failed；例如早期COPY_BOARD_STOP,result=-7并不是通过。

本轮两次准备失败也保存：第一次候选design_file插在top_vhdl_arch之后违反Efinity XML schema；第二次冗余分号include被工具当作单一路径，导致找不到DDR头文件。均在真实schema/包含路径检查RED→GREEN后修正，不改官方文件。无候选参数的脚本会忽略未知参数并启动旧构建，已通过CmdletBinding严格拒绝；误启动的独立构建已停止，未烧录。

实际成功工程：`D:/efinity_builds/v3_copy_20261002_r3`和`D:/efinity_builds/v3_copy_legacy_20261002`。CPU/R7正常固件不重编译，10/01已通过的76项GPU仿真不重复跑；本轮新验证是工程schema/源清单、综合STA、真实DDR和R7板测，不是全SoC重新通过。

## 5 工件身份

- 候选bit：adaa557667edd885d4985a6f44a9e04780ef8be719368d4c5b12e447cd2699b9。
- 关闭通路bit：0009dc913fa78744e6c7da5eb8115a28f7864461a5a7919dcd1a8424c08ee5e7。
- 原基线bit：84b2e64670b1878b806aa6504af0826280c3a99830fc60a1f79906662639057a。
- 生产normal.bin：8fef6f0c54ba4f10aa1c562e2bc80e671d49bb38f145c078e0c64cda9e5d3ffb。
- R7分段test.bin：4e210949f662fdbac10c6aa604cdea333568f4345a0e8b7bf9c8ada98867633b。
- 最终Copy像素核对test.bin：af1a84a396d2168c322c8ff2ee91261cea59324212dcd59ec6ecb1c92b784e30。
- 资源/RTL哈希继承[基线清单](v3_baseline_manifest.md)及[离线记录](v3_copy_progress_20261001.md)，本轮未修改。

串口、JTAG原始记录及综合/STA报告压缩保存在[evidence/v3/copy-board-20261002](evidence/v3/copy-board-20261002/)，保留失败到通过与原编码，用SHA256SUMS逐文件校验。ignored目录中的bit不纳入Git发布包。

## 6 下一步和边界

第5天负责人验证已做完，结果是“不采纳此候选替换基线”，不是优化成功。下一项按第6～7天做物理双缓冲epoch背景恢复，优先减少每帧898560 B背景读写，而不是继续靠减少少量burst次数。提交前端是否扩展按第9天预算另行决策，仍不动CPU基线。

尚未完成：A/B功能线、背景恢复、512@60、高档位正式极限、CPU-only热重载及30分钟耐久；SoftwareDriverSpec/PangoBringupSpec历史异常继续保留。暂无负责人组员依赖，不接管A/B。

本阶段独立审查无Critical/Important。小项暂缓：候选输出“fresh”目前仅拒绝已有XML，而非拒绝所有非空目录；复现时必须主动选择全新目录。板测要求完整FPGA重载，尚未增加自动前置状态探测。沿用离线阶段的反压保持断言补强建议，不把这些遗漏写成已解决。

收尾状态：已重新JTAG加载原9/28位流与冻结normal.bin，网络两项资源加载均result=0，64档CPU2.8/GPU60.1FPS（完整串口行已保存）。无烧录/综合/OpenOCD进程继续运行，PC素材服务保持运行供正常Demo使用。本轮不推送共享main。
