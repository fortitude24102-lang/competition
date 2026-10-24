# 宽口 Copy 配置一致性修复与复测（2026-10-24）

## 范围与当前状态

执行10月23日复盘P0：补齐已有`--scanout-word-pipeline`，建立同源、同功能、同BIN的对照。GPU生产数据通路、CPU绘图、100MHz、游戏负载、Alpha/Key和网口保持原设计；仅修改构建清单及比较检查。没有用新Cache、DSP或改CPU算法掩盖配置遗漏。

**配置修正后的宽口Copy取得了整机工作均值收益：同BIN、同源控制→候选→控制，各3600帧，13.408→11.927→13.402ms，按两次控制均值计算减少11.03%。但候选仍有6帧超预算/迟到，最坏18.610ms，未达到普通1024严格稳定60。** 三组窗口新增下溢/硬件错误均0，状态CRC及工作量一致；没有继续全活动极限搜索或新增极限成绩。

两份新位流均完成map/interface/pnr/pgm，资源、16项严格正的最终setup/hold及实际网口CDC检查通过。7套26项定向GPU回归全部通过后才上板。候选保留为显式优化实验，默认开关不变；板上已经恢复旧Alpha跨行预取BIT＋原正常六档MENU，六档START/MENU真实ACK检查通过并释放控制。未写Flash、推送或替换release。

## 防止再次漏配的改动

- `GenerateEfinix2dGpu.scala`将原有单一`wideCopyDma`清单扩充为schema1，记录全部17个有效Top参数、GPU Scala源码SHA256及filelist里每份HDL/头文件的SHA256。
- `compare-gpu-build.ps1`拒绝缺项/多项、非法值、不同源码、未知豁免、没有实际发生的预定差异、文件清单/哈希不一致。本实验只允许`wideCopyDma`一项不同。
- 独立审查发现六份手写像素RTL未包含在Scala摘要中；现额外强制两版的这六份文件哈希相同。已用“更改像素文件且同步更新其合法哈希”的用例复现旧检查漏放，再修复为拒绝。
- `test-efinix-board.ps1 -ReferenceGpuRtlDirectory ...`在准备输出前比较实际所选生成目录，并保存选中清单。历史无清单/单字段清单仍可用于历史构建，但不能通过新的公平对照检查。

11项错误输入拒绝、板级准备不得绕过比较、全功能实际生成参数检查及原有5项板级选择检查均通过。先在旧清单上得到缺失schema的RED；独立审查问题另有RED→GREEN记录。默认不带`--split-verilog`的生成入口也已实际运行成功。

构建防护代码已本地提交`46f1781`。本轮定向回归为ScanoutWordPipeline、ScanoutWordBoundary、WideCopyDma、WideDdrMux、WideCopyRender、GpuPerfCounters和Efinix2dGpuTop，26/26通过，用时29分30秒；覆盖宽口顺序/排空/错误恢复、真实Scanout吞吐及Top公共/局部复位。脚本同时执行8套C/18000帧黄金模型与UBSan检查并通过。未重复未改变的40套164项长回归，也没有重跑或宣称修复历史SoC异常。

## 对照版本身份

本轮起点：本地`codex/efinix-2d-gpu`，HEAD `3e4ce54`；原有未提交README、复盘、测试和无关文件保留。构建源码摘要：

```text
db2577eb8cb2fbfd15a44cfa5a1081ae10c28ba201252b436be674cf66e618a4
```

共同参数：

```text
--instances --frame-lists --key-prefetch --scanout-word-pipeline
--transform-blit --alpha-pipeline --axi-diagnostics --key-write-pipeline
--extended-list-arena --small-copy-prefetch --four-write-credits
--alpha-row-prefetch --split-verilog
```

候选仅额外增加`--wide-copy-dma`。StripeScratchpad、CopyBurstBuffer、KeyRowTrim均关闭；CopyStream保留开启。控制/候选的完整filelist分别61/70项，其中HDL单模块文件60/69份，另各一份像素常量头文件。

对比10月21日旧生成物，当前关闭宽口的生成物仍有一份`GpuPerfCounters.sv`可执行表达式不同，来自此前宽口统计的实现调整。没有忽略这项差异直接沿用历史BIT；本轮重新构建同源控制BIT，避免把旧统计表达式/物理映射变化夹进实验。另核对76个共享板级源码/约束输入的哈希一致。

|身份|同源控制A|宽口候选B|
|---|---|---|
|生成目录|`generated/verification/v3/wide-copy-fair-20261024/rtl-control-r2`|`generated/verification/v3/wide-copy-fair-20261024/rtl-candidate-r2`|
|Efinity目录|`D:/efinity_builds/wide_copy_fair_control_20261024_r1`|`D:/efinity_builds/wide_copy_fair_20261024_r1`|
|BIT SHA256|`39e9592e66acb8e57fedaeb77794cc8b79e2d7d5489a09a49653bc96183c3209`|`4f19579ced2d8d08a2281292847d56d08c8bc767cc7253a9623c2c389aa81f3a`|

旧主路径恢复目标仍是10月21日Alpha跨行预取BIT：`d594d395e016353b8a4724bb5fca8400ff08d443712a6ba4171e8372143167ce`。

## 显示配置的实际检查

两版实际`ScanoutDma.sv`均实例化`PixelReadAligner_2`，对应生成模块哈希完全相同。用已有单模块诊断测试直接运行候选生成模块，逐像素/末标志/源字消费检查通过：

```text
SCANOUT_BUILD_PASS,pixels=960,words=480,first_to_last_cycles=960
```

这修复了上轮字间空拍的局部吞吐差异；960拍不是整机帧耗时或FPS测量。未修改已有未跟踪测试文件或生成RTL。

## 物理结果

|指标|同源控制A|宽口候选B|
|---|---:|---:|
|XLR|52954/60800|53945/60800|
|RAM|179/256|186/256|
|DSP|37/160|38/160|
|core setup slack|+0.375ns|+0.299ns|
|core hold slack|+0.026ns|+0.026ns|
|最终16项setup/hold|全部严格正|全部严格正|
|实际1488条数据CDC最大|1.155ns|1.304ns|
|实际2条请求CDC最大|0.693ns|0.741ns|
|实际2条应答CDC最大|0.772ns|1.347ns|

候选净增991XLR，达到原≤1500的软目标；两版均低于54720XLR硬门槛。CDC核对实际映射寄存器、实际布线路径与生效8ns约束。该结果不代替板上像素检查、普通1024、长期稳定性或温漂验证。

## 固件与测量口径

所有固件直接复用既有文件，重新核对SHA256后复制到本实验`input-bins/`，没有重编译或改CPU参数：

|用途|SHA256|
|---|---|
|正常六档MENU|`33aac5fa90d290c3820d9e3c537fe7c8c51785e9409c668410744bf27d42311e`|
|普通1024，3600帧终止探针|`bd5489d8a8e39fca40dbbdeed357be035b619204b44a4422fa96bd95d39d77b7`|
|固定AXI阶段诊断|`427430ee6c9b678fe244407cdacb56a94b7f97494a0f884ff85c25085413a801`|
|跨双端4KiB对齐Copy黄金|`5ec8797cb584985e6e57c447ce31d055093c5555d4e16213f28e38abe6dc2ce5`|
|24项Alpha黄金|`5a841aead984c26fb19b2ab8f6917a14c4b7c48a6f45fda0b6752c62a412e5e9`|

普通探针固定LogicCopy1、SealWords256、HudDirect1；同状态CRC `a7bd652f`，正常逻辑/素材/活动范围不变。阶段诊断的序列化和打印改变负载，只能比较同用途诊断BIN。`scene_us`仍是渲染调用窗口平均，不解释为CPU逻辑或CPU占用率。

实际按同源控制A1→候选B→同源控制A2加载完整BIT后再加载同BIN；逐组完成Copy像素/哨兵、Alpha黄金、固定阶段和3600帧普通1024。没有并发JTAG/串口/控制写入。原始素材哈希在采集前后保持一致，PC只提供资源与交互终端，不代算游戏或合成画面。

## 普通1024：整帧工作均值改善，迟到仍未消除

|各3600帧|同源控制A1|宽口B|回控制A2|
|---|---:|---:|---:|
|报告FPS|60.0|60.0|60.0|
|work均值ms|13.408|11.927|13.402|
|work最大ms|19.046|18.610|21.238|
|最大呈现间隔ms|33.277|33.277|33.277|
|超预算帧|6|6|5|
|迟到帧|6|6|5|
|新增下溢/硬件错误|0/0|0/0|0/0|

两次控制均值13.405ms，候选每帧平均少1.478ms，即11.0257%；回到控制即恢复原成本。这里证明本轮A/B/A的平均工作净收益，**不是FPS增长11%，也不是多次冷启动或长期稳定性证明**。候选窗口只有一组，最坏帧仍超过16.667ms；迟到数没有改善，不能因报告FPS四舍五入为60.0就升为严格稳定60。

三组同状态CRC `a7bd652f`；普通档位请求1024，但实际可见1006..1016、Alpha130..131，不是1024恒定全活动的挑战口径。不能将这些人数或本BIT套用到历史2194成绩。

## 固定阶段与像素检查

|1040固定诊断，三个tick均值ms|控制A1|宽口B|回控制A2|
|---|---:|---:|---:|
|背景Copy|5.548|2.021|5.553|
|Alpha|1.878|1.940|1.887|
|Key|1.652|1.657|1.647|
|FULL原序渲染|8.888|5.585|8.874|

相对两次控制均值，FULL少约37.1%，背景少约63.6%；Alpha仍多约3.0%，Key多约0.5%，没有把所有接入代价说成零。上轮Alpha/Key约37%/29%的退化不再重现，支持先修复显示配置的决策；剩余差异不能直接确诊mux或CPU瓶颈。

独立对齐黄金Copy（898560字节）的耗时为**5.761→1.844→5.762ms，减少67.99%**，三轮逐像素、哨兵、读写各898560字节及under/failed均0。三种小/奇数/stride回退耗时分别27→29→27us、17→21→17us、18→18→18us；仍有小事务副作用，不隐去。

三轮共72个阶段的fixture CRC、命令数及read/write/cache字节逐项一致，阶段新增under均0。12项Copy黄金和72项Alpha黄金均通过；Alpha专用固件不PRESENT，记录中`under_offscreen`最高22，不能把它算作正常显示窗口的零下溢资格。

## 决策与下一步

宽口Copy在正确配置下值得继续保留，不能再使用10月22日不一致配置的负结果否定它。当前结论是“平均工作有净收益，普通1024仍未严格稳定60”，因此保留实验默认关闭、原主路径与全部失败边界，不进行新的极限搜索，不宣布封版。

下一步优先逐帧记录这类迟到事件的logic/build/submit/execute/HUD和总work，固定同BIN/场景并在计时窗口外输出；现有窗口均值、`scene_us`和单点P95不足以确定迟到发生在哪个阶段。不因均值改善就继续扩大DMA、Cache或重写mux，也不优化CPU基础绘图来改变对照。

本轮没有新增长期耐久、CPU完整对照或缩放/灰度的人工目视资格；没有将正常菜单ACK检查当作移动/死亡/回放或HDMI外观验收。

## 原始证据与执行取舍

原始工作目录：`generated/verification/v3/wide-copy-fair-20261024/`。包含完整生成清单、实际生成Scanout诊断、清单检查正负记录、编译/时序/CDC记录、固件/素材身份及本轮运行脚本。

保留两个工具调用问题的失败记录：首次Scanout shell包装器在仿真PASS后因stdin尾部CR退出127，改为直接执行已有仿真二进制，退出0；首次CDC调用遗漏`--prj`而在分析前失败，补齐参数后通过。没有为规避工具问题修改硬件或改写旧证据。

执行使用现有工作树和原生PowerShell逐任务记录，因为WSL无法解析此工作树的Windows绝对gitdir。新构建和原始数据全部进入新目录；原始官方Demo、vendor、旧证据包和既有工作文件不改写。

独立审查仅覆盖本轮构建防护代码；物理门槛、仿真和板测均由执行者另行完成验收，既有改动排除在本轮审查外。未新增依赖、未推送共享分支、未写Flash、未替换release。

## 封存与收尾

[证据包](evidence.zip)：308个文件条目，其中307个有效载荷和一份逐文件manifest，17,993,817字节，SHA256：

```text
eea59e02a7fda3d981ca2bbc7edb2900b8d5bc3c65c9a5f99d87dfcbc69104cd
```

已从ZIP逐个读取307份有效载荷并核对字节数/SHA256，全部一致。包含两版完整生成RTL和清单、BIT、固定BIN、实际映射/时序/CDC、所选GPU源码和相关测试、本轮构建检查正负记录、A/B/A串口及菜单恢复证据。不包含bootstrap、控制令牌、资源服务器/网关进程日志或无关用户文件。包内报告与执行记录为封存前快照，外部封存元数据不再回写旧包。

最后只读状态另存`final-released-state.json`：owned=false、stale=false、MENU且requested_sprites=0；这是菜单测试释放控制之后的新快照。菜单测试自身http日志最后一条仍是释放前owned=true，不能仅据那一条断言控制未释放。无活动JTAG/OpenOCD烧录进程，资源服务和真实网关继续提供原功能。

本轮按既定本地实验范围保留当前分支和工作树；原先未提交的README、10月23日复盘、单模块测试及无关文件保持原样。下一轮应从本报告的实际迟到边界继续，而不是重新执行旧全自研SoC计划、重复已完成的配置排查或把本轮均值收益当作稳定60。
