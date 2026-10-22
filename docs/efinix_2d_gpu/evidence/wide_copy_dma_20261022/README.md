# 原生128位Copy DMA验证记录（2026-10-22）

结论：实现、完整回归、物理检查和同BIN旧→新→旧已完成。**大背景Copy明显加快，但正常游戏整帧变慢，因此候选不启用、不升主线，已经恢复旧BIT＋正常六档MENU。** 没有新60FPS成绩。实验本地保留，未推送main、未写Flash、未替换release。

## 范围与架构

只给原Copy命令增加默认关闭的`--wide-copy-dma`后端。连续RGB565、两端16字节对齐、长度为16倍数且不少于4096字节、经原命令验证的非重叠DDR区域走新后端；其余合法命令在发事务前回原32位像素通路。Alpha/Color Key、小Copy、CPU基础绘图、100MHz、游戏负载、HDMI和以太网职责不改。

`WideCopyDma`直接产生128位、SIZE4、INCR事务，两个1KiB bank，按源/目的4KiB边界分段，每段不超过64拍。整段读齐后才承诺AW，W与B归属保留到退休。不是将旧32位数据复制或包装成宽拍。旧SoC的128位DDR出口与新DMA通过固定两主一从`WideDdrMux`接DDR控制器，旧8位ID原样保留，读写各自归属并排空后切换。

显示低水位时禁止DMA尚未承诺的新地址，旧显示通路可继续补充；已承诺事务不能撤回。共同DDR复位可清总线状态；GPU局部复位只能停止发新事务并排空旧DMA，不能清掉未送完的W、旧SoC响应或把旧完成返回新GPU。

统计沿用旧寄存器ABI，按真实握手计宽R16字节、宽W有效字节和8个RGB565像素，周期取时间并集。原AXI等待诊断仍只计32位通路，不能把其拍数当全部DDR流量，更不等于DDR芯片物理利用率。

旧条带Scratchpad只拦截窄口私有窗口，不能与绕过窄口的DMA组合；生成器明确拒绝两项同时开启，不增设私有窗口路由框架。当前候选条带关闭，缩放/灰度保留；不支持的可选组合不会静默画错。

## 身份与门槛

- 控制BIT：`D:/efinity_builds/alpha_row_prefetch_20261021_r1/outflow/efinix_2d_gpu.bit`，SHA256 `d594d395e016353b8a4724bb5fca8400ff08d443712a6ba4171e8372143167ce`。
- 候选BIT：`D:/efinity_builds/wide_copy_dma_20261022_r1/outflow/efinix_2d_gpu.bit`，SHA256 `bf0d3780e356dcde14f4ac71e3db904071a119158bdc411cec1fb0456d6df0c2`。
- 原生成目录：`generated/verification/v3/wide-copy-20261022/rtl-full-r1`；增加可选组合拦截后再生成`rtl-full-guard-r2`，68个模块逐一去注释/空白后代码一致。后者只改变构造阶段拒绝条件，不改变选中合法网表。
- 正常六档BIN与1024探针BIN沿用上轮，不改固件、场景、素材、CPU编译参数或资格门槛。固定阶段BIN SHA256 `427430ee6c9b678fe244407cdacb56a94b7f97494a0f884ff85c25085413a801`。
- 正常BIN SHA256 `33aac5fa90d290c3820d9e3c537fe7c8c51785e9409c668410744bf27d42311e`；1024探针BIN `bd5489d8a8e39fca40dbbdeed357be035b619204b44a4422fa96bd95d39d77b7`；对齐Copy黄金BIN `5ec8797cb584985e6e57c447ce31d055093c5555d4e16213f28e38abe6dc2ce5`。
- 对齐Copy黄金固件复用原`test_board_copy_stream.c`，仅新增可配置地址，原默认地址不变；本轮使用源`0x02400ff0`、目的`0x02600fe0`，故确实满足宽口条件并跨两端页边界。它不是普通游戏固件。

完整r1：map/interface/pnr/pgm全部PASS。XLR54617/60800（89.83%，硬门槛<54720）；RAM186/256；DSP38/160。相对上轮净增1751XLR，**没有达到净增≤1500的目标**，但硬预算通过，暂不裁剪Transform。独立DMA综合746LUT、678FF、7RAM、0DSP；整板新增1DSP来自命令尺寸计算等周边，不能把独立模块估算替代整板占用。

最终16项setup/hold均严格为正，核心setup+0.262ns/hold+0.026ns。网口实际mapped覆盖1488数据/2请求/2应答，routed最大1.357/0.699/0.663ns，均<8ns。保留薄裕量与温漂长稳风险，不称超频认证。

## 测试与审查

先RED后GREEN：后端3项、仲裁2项、Render2项和统计4项；验证真实像素/字节与哨兵、两端4KiB、两bank、稳定VALID、最后B围栏、错误/复位排空、后继命令以及Fill/Key/Alpha/PRESENT顺序。新增Render局部复位AW排空1项通过；整机旧SoC响应跨GPU复位检查也通过。

一次独立审查未发现当前条带关闭候选的协议/复位错误，但提出3项Important：不兼容可选配置、错误时已承诺W的字节证据不足、满信用计分板/先W后AW覆盖不足。已经复现两个旧检查RED并补齐：隔离8项全通过，其中对每拍W（含错误和abort）比较原始源字节，明确构造“后续R错时另一bank欠W”和“坏B到达时另一个R仍被阻塞”；确认满16信用的R/B同拍替换实际发生，先W后AW正确反压。

构建选择5项通过：原默认无宽口；合法宽口；宽口无manifest、manifest关闭却有宽口、manifest开启却无宽口均拒绝。宏由所选生成RTL/manifest派生，不允许另给板级开关绕过一致性检查。每个生成HDL文件仅一个模块，共68个。

完整GPU回归只运行一次，**40套164项全部通过**；审查补强8项在独立目录通过，含原用例加严，不能直接合称172个不同用例。不为提交再跑未改变的长套件。历史V2冻结清单检查在`generated/efinix_gpu/filelist.f`哈希报错，该文件本轮未改；不修改旧release清单使其假通过。旧Windows Icarus路径缺失使相应动态脚本未运行，StaticOnly及网口结构检查通过。以上不是已修复SoC异常或新整机资格。

## 板端对照与不启用决定

所有加载仅JTAG/RAM，先完整BIT再加载BIN，避免历史HDMI相位错位问题；串口和控制采集互斥。A1/B/A2各24固定阶段合计72组STOP0/hardware0/under0；6份fixture CRC、每阶段命令数及read/write/cache字节逐项一致。正常probe三轮均为同BIN、相同LogicCopy=1/SealWords=256/HudDirect=1，3600帧，stateCRC `a7bd652f`，visible1006..1016、Alpha130..131。网关无owner时不发周期控制包，资源服务器/固件素材保持一致，不修改CPU算法或编译配置。

| 普通1024，各3600帧 | 旧A1 | 宽口B | 旧A2 |
|---|---:|---:|---:|
| FPS | 59.2 | 57.5 | 59.1 |
| work均值ms | 13.389 | 13.845 | 13.391 |
| work最大ms | 20.370 | 21.065 | 19.971 |
| 超预算帧 | 51 | 160 | 56 |
| 迟到帧 | 52 | 160 | 57 |
| 下溢/错误 | 0/0 | 0/0 | 0/0 |

| 固定1040诊断，三帧均值ms | 旧A1 | 宽口B | 旧A2 |
|---|---:|---:|---:|
| 背景Copy | 5.55561 | 2.73332 | 5.56019 |
| Alpha | 1.88789 | 2.58053 | 1.88447 |
| Key | 1.64161 | 2.11053 | 1.63923 |
| FULL原序渲染 | 8.87230 | 7.34594 | 8.88012 |

独立对齐黄金Copy的898560字节背景为**5.762→2.211→5.767ms**（约少61.6%），三轮逐像素与哨兵完全一致、读写均898560字节、under/error0。其余3种小/奇数/有stride回退场景也正确，但候选单点耗时43→69us、21/25→38us、24/25→44us，存在窄口副作用，不隐去。

候选另通过24例硬件Alpha离屏像素、缓存与哨兵检查；该专用固件没有PRESENT，日志`under_offscreen`最高22，不是有正常显示的性能资格测试，不能称这24例“零下溢整机通过”。正常probe/固定阶段/Copy显示黄金窗口上述下溢仍均0，分别判断，不混用计数。

背景至少减少30%的局部目标达成，完整固定阶段约少17.2%；但普通游戏work反而增加约3.4%，尾延迟及迟到变差，**整帧准入失败**。因此不继续候选全活动极限搜索，不放宽任何规则，也不把历史2194或软件3640容量当候选成绩。原方案明确要求无整帧可重复收益时回退，此处执行回退，不是未测就默认有益。

## 进一步定位：事实与假设分开

- 事实：每轮121条`V3_PERF,mode=0`的`scene_us`中位数为**3548→4621→3546us**；这只是遥测采样，不是CPU占用率。相同状态CRC、Sprite/Alpha工作量、字节量和固件下，窄口Alpha/Key和CPU场景阶段都退化，回旧即恢复。
- 推断：新128位旁路的服务分配/legacy通路时序已成为重要嫌疑，不是像素乘法能力不足。背景独立提速并不等于其与RISC-V逻辑重叠后仍省下整帧时间。
- 待证假设：本版mux必须先接受AW才放W，官方旧链路允许W提前；小事务流水可能因此受损。另外，native每轮最多两段而legacy很快让出方向，可能增加CPU缓存缺失和显示补充的等待。现有结果**不足以单独确诊其中哪一个是主因**。
- 最小下一步：隔离“保留仲裁、但不发宽口Copy”的控制测量，再分别测legacy的AW→首W、R首拍/间隙、CPU场景时间与显示FIFO水位；有证据后才选择提前W缓冲/归属跟踪或调整服务量子。不先堆Cache、加乘法器、提高主频，也不优化CPU算法来掩盖GPU接入代价。

## 收尾与决策记录

保持本地`codex/efinix-2d-gpu`，默认关闭新路径，不改release；板上恢复已验证的Alpha跨行预取旧BIT＋不改动的正常六档BIN。真实六档START/MENU ACK与快照通过，已释放控制，无活动JTAG/OpenOCD烧录进程；未新增目视或长期资格声明。资源服务器和网页网关继续提供原功能。

执行中的明确取舍：按用户持续授权本对话执行、不再逐阶段审批；Windows原生记录替代不能解析该gitdir的Bash簿记；一次独立源码审查提前到板测前；禁止条带缓存与宽口组合；整机/完整回归/CDC由执行者验收、不以源码审查代替；缺失/额外AXI响应仍需公共复位；+1751XLR未达软目标但硬门槛通过故保留Transform；实测整帧负收益后恢复旧主线。前几项只影响本地实验/记录，协议故障需人工复位、资源余量仅103XLR，以及本候选不能提供整机提速，是保留的实际限制。

## 复现入口

- 规格：[宽口DMA规格](../../../superpowers/specs/2026-10-22-wide-copy-dma-design.md)；[实施计划](../../../superpowers/plans/2026-10-22-wide-copy-dma.md)。
- 生成使用原全功能参数：`--instances --frame-lists --key-prefetch --transform-blit --alpha-pipeline --axi-diagnostics --key-write-pipeline --extended-list-arena --small-copy-prefetch --four-write-credits --alpha-row-prefetch --wide-copy-dma --split-verilog`。
- `scripts/test-wide-copy-build.ps1`验证配置一致性，`scripts/test-efinix-board.ps1 -GpuRtlDirectory <生成目录> -OutputDirectory <新目录>`做完整构建。
- `scripts/build-board-hud-dma-test.ps1 -Test copy-stream -WideCopyAligned -OutDirectory <新目录>`生成对齐黄金BIN；正常/固定阶段仍用已记录的不改动BIN。

禁止未过资源/最终时序/CDC及新通路仿真的候选上板，不写Flash，不自动替换release或推送共享分支。无整帧可重复收益时保留旧路径为主线。

## 封存

[证据包](wide-copy-dma-evidence.zip)：222个文件（含manifest，另有2个目录条目），10,401,474字节，SHA256 `00331d008fbeb0df5777acc1a3d6abe412cf969f11c2507461eb3ffbdd9049ad`。解压读取后逐个核对manifest中221个有效载荷文件的字节数和SHA256，全部一致；包含两套生成RTL、选中源代码、构建/时序/CDC、正负仿真、A/B/A UART、BIT/BIN及最终菜单恢复证据。不含网页bootstrap、令牌、资源/网关进程日志或不相关用户文件。包内报告/规格为封存时副本，外部文档的最终封存元数据不再回写ZIP。

代码本地提交`c381445`（前置DMA/仲裁分别`eb645d9`/`a89189c`）；本记录和根README另作本地收尾提交。旧候选、历史证据包和用户未跟踪文件保留；私有工作目录因资源服务器/网关日志仍在使用而保留，不为清理中断正常服务。
