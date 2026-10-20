# GPU前端与小块Copy专项（2026-10-20）

基线6c19143，复用官方Sapphire、960×540、100MHz、网口资源和六档游戏。CPU基础栅格算法及配置不优化，不修改Alpha比例、场景数量或挑战判定。仅JTAG/RAM；本轮未要求推送，release/Flash不替换。

## 先测再选

1024现有源码详细探针3600帧：59.1FPS、56帧work超预算/60帧迟到、下溢/错误0。最坏帧tick410含两次逻辑推进：logic11.493ms、build4.670ms、scene3.939ms、HUD0.310ms、other0.375ms，总20.787ms。其他帧的命令构建可到约7.15ms。该诊断BIN改变代码布局和日志，不能与先前普通55.3FPS直接当作优化对比，也不能把所有1024掉帧归咎于GPU硬件。

### 已否决：片上命令暂存后连续发布

用已有scene缓存暂存相同16字节描述符，通过标准memcpy发布，不增加RAM；完整边界校验后才发布。320帧独立旧语义对照及集成测试通过，但同一BIN、同一a476 BIT的1024 A/B/A各3600帧没有收益：

|路径|FPS|work均值/最大ms|超预算/迟到|
|---|---:|---:|---:|
|原直写A1|54.9|14.436 /22.120|335 /337|
|暂存B|52.0|15.066 /23.857|555 /557|
|原直写A2|56.6|14.383 /21.020|219 /219|

三组下溢/错误0，场景可见1006..1016、Alpha130..131，封存状态CRC均a7bd652f。暂存平均work更差约4.4..4.7%；不保留该候选。反汇编确认现有memcpy已使用字搬运展开，不另造一个memcpy。候选源码/补丁和负结果保存在原始证据，生产源码已恢复，没有遗留暂存选项。

### 首次取得资格失效帧

test-only performance-trace包含实际main/v3_demo，调用原pc_record，首次PC_FAILED后才在DDR0x02d3f000冻结72字节；采样时不输出串口或写快照，不放松任何规则。单元测试覆盖真实stage4/5→6、搜索阶段未合格、健康异常、非法输入和首错冻结。诊断BIN仍有包装/布局开销，不能作为生产成绩。

同一a476 BIT的目标1995全活动Sprite＋250个额外Alpha完成3600帧后，由stage4变为stage6/best0。失败帧原始100MHz tick换算：

|部分|耗时ms|
|---|---:|
|逻辑pc_advance|4.34953|
|命令构建|2.37900|
|场景执行等待|8.49900|
|HUD更新|1.04579|
|其他帧内工作|0.34935|
|总work|16.62267|
|完整wall|33.27731|

GPU busy14.83448ms与CPU/Copy重叠，不可再与上表相加。下溢/错误0、可见1995/Alpha250。work虽然小于理想16.66667ms，实际显示约60.10Hz且PRESENT之前还有固定开销，仍错过刷新；不能通过放宽wall规则或取平均FPS保留资格。此前2007未保留资格的具体失败帧未采到，本次1995诊断不是把它追认成同一帧。

## 选定的最小硬件变化

不是新增一套CDMA：现有CopyStream已为紧凑背景提供Burst/FIFO DMA。小块跨行Copy（HUD字形14×18、源stride28、目的stride1920）原来每行发读，18次AR；复用Key预取FIFO、RGB565对齐器和两笔在途writer，一次取完整字形，各行有完整数据信用后才发AW。

显式默认关闭`enableSmallCopyPrefetch` / `--small-copy-prefetch`；要求已有Key prefetch和未裁剪的Key write pipeline。Copy仅限偶数宽2..16、高1..32、word对齐紧凑源、halfword对齐目的、偶数且严格大于行字节的目的stride、非重叠；其他Copy继续旧路径。Copy复制所有合法像素，包括品红，不使用Key透明掩码；Key仍走原纹理缓存，不改变Alpha/Transform或命令ABI。连续Copy独占原CopyStream，避免双重接受。

借鉴[verilog-axi](https://github.com/alexforencich/verilog-axi)中axi_fifo的完整写突发数据信用和独立读写流水思路，复用本工程模块，未导入第三方代码/依赖，不主张首创；上游README已建议新项目看[taxi](https://github.com/fpganinja/taxi)。

旧BIT＋同一HUD oracle已通过20轮逐字节黄金像素比较：单字201us、50字形约1.5ms、完整恢复4740us、新增下溢/硬件错误0；这只是旧路径对照，不是新候选收益。

新增真实RenderEngine三项测试通过：正常/回退、6类R/B故障与后续Fill/Key/Alpha、真实纹理缓存共存。独立字节期望、哨兵、品红、14×18、半字+stride1922、高32/33、源+2、奇数宽、紧凑Copy、4KiB均覆盖；延迟B条件14×18从2035到1122周期（约−44.86%），AR18→1、AW仍18。仿真周期不是板端FPS，固定延迟不是对DDR时序的完整建模。

生成目录`generated/verification/v3/copy-retirement-20261020/rtl-c5c807b86b51474d904f027dfcbef193`，60个单模块HDL。Efinity工程`D:/efinity_builds/small_copy_prefetch_20261020_r1`的map/interface/pnr/pgm通过；最终16项setup/hold全正，core+0.278/+0.026ns，全局最小setup+0.257ns/hold+0.012ns。XLR52768/60800（较旧版增加30），RAM179/256、DSP37/160不增；仍不是超频依据。原网口CDC映射1488对数据/2请求/2应答全覆盖，实际布线最大1.315/0.815/1.153ns，均小于原8ns约束；解析器XLR786/RAM1，既有SDC警告保留，不宣称零警告或所有历史SoC问题已解决。

新BIT SHA256`118491efb159cc4c8ad2f47b42fc073b5d956a43e9d106fe944df4db2f250dce`。

## 板端HUD与完整游戏对照

同一HUD oracle BIN（SHA256`76ec20a32f0078e20af804477281c6a5d6c5236b481cf64c29bd78faee8918be`），旧→新→旧各20轮逐字节黄金像素校验通过。每组都有8轮50字形更新：

|路径|50字形平均us|完整恢复us|读取/写入字节变化|新增下溢/硬件错误|
|---|---:|---:|---|---|
|旧A1|1493.500|4740|基线|0/0|
|新B|754.250|3157|相同|0/0|
|旧A2|1486.625|4718|相同|0/0|

50字形平均耗时减少约49.3..49.5%，完整恢复约少33.1..33.4%。字节负载没有减少，改善来自读事务合并和写退休流水；这不是CPU渲染加速或整帧FPS翻倍。单字固定调用开销较大（201→192us），不拿单字结果夸大比例。

普通1024使用**完全相同的既有探针BIN**，SHA256`bd5489d8a8e39fca40dbbdeed357be035b619204b44a4422fa96bd95d39d77b7`，只换BIT。各30帧预热+3600帧采样：

|路径|FPS|work均值/最大ms|超预算/迟到|
|---|---:|---:|---:|
|旧A1|57.7|14.264 /20.793|146 /148|
|新B|58.9|14.185 /20.809|69 /71|
|旧A2|56.2|14.353 /21.539|243 /245|

三组均网络素材101/102/103完整加载、下溢/硬件错误0、visible1006..1016、Alpha130..131、封存状态CRC a7bd652f；串口日志均值25us、最大791/792/792us。work均值较两侧旧版少0.55%/1.17%，FPS和迟到帧存在波动，不能承诺固定FPS百分比；新B最大work还略高于A1，不能称最坏帧改善。**普通1024仍未稳定60FPS。**HUD专项收益大，但只是全帧的一部分，较大的逻辑追帧峰值仍在。

## 正常固件全活动挑战：2065已复核

正常六档固件使用原SHA256`33aac5fa90d290c3820d9e3c537fe7c8c51785e9409c668410744bf27d42311e`，无诊断包装/源代码修改；候选BIT118491...。真实六档START/MENU、租约退出、新session和R清分通过。2069短搜索候选的长确认未通过，原程序降档重搜；不记2069。最终同一运行找到并完成：

`PERF_RESULT,target=2065,stage=4,best=2065,frames=3600,fps_x100=6010,work_max_us=16605,wall_max_us=16642,work_miss=0,late=0,under=0,error=0,visible_min=2065,visible_max=2065,alpha_min=259,alpha_max=259`

随后5秒仍为同一已确认owner/session1307749609、stage4/best2065、frames3600，已保存performance-final.json。**2065个全活动Sprite＋259额外Alpha、60.10FPS，通过本窗口；不是3640容量或普通1024游戏通过。**Alpha/Color Key、尺寸、100MHz和完整背景均不削减，场景命令含1背景+259Alpha+2065Key=2325项。只代表这组BIT/BIN和测量窗口，不证明2066永远失败或30分钟耐久，也不把跨BIN旧1819差值宣传成纯硬件百分比。

## 残余瓶颈与下一方向

同候选追加既有AXI分段诊断，512/1040各3种状态全部完成，计数AW/B相等、下溢/硬件错误0。这个程序故意分段、串口输出且不用正常重叠调度，**不是游戏FPS或新的资格**。

1040场景三个KEY窗口中，B等待计数102081..110280ticks /窗口195027..210179ticks，约52.2..52.7%；W背压为0。缓存读取133504字节等于全部Key源像素，DDR读取16640字节对应1040条描述符，进一步叠纹理Cache不是首先要解的点。计数会重叠，不把等待比例视为可直接获得的提速上限。

背景Copy仍约5.55..5.57ms，B等待仅约4.2%、AW QoS等待约29%；在正常CopyAhead中又与逻辑/命令构建重叠，不能把该分段耗时整个加到CPU工作上。因此下一项优先测**两笔→四笔小块写在途及跨Sprite发射/退休解耦**，同时保持顺序、读写信用、错误排空和scanout紧急保护；先做可回退A/B，不先替换成独立CDMA、再加Cache或超频。普通1024的逻辑追帧峰值需与GPU提交/执行分开定位，CPU基础栅格算法继续不优化。

## 验证、复现与交付边界

实现66e954f，设计/计划54ca692。新增RenderEngine测试分两次增量通过（2项正常/故障＋1项缓存共存）；原受影响8套34项通过，完整软件集成含新增trace、协议/网关/心跳和真实APB/MAC子系统通过。不重复已验证且未改变的旧35套136项，不把历史SoC两项异常补称修复。

一次独立只读全差异审查未发现新的生产正确性问题。审查指出报告的最小setup曾误写+0.273ns，已按tx_cal_clk实际+0.257ns更正（仍全正）；同时把缓存切换用例扩为偶数宽2、包含品红跳过和非透明像素，直接覆盖共享FIFO的DDR Copy→缓存Key→Alpha，补充1/1通过。只改测试和文档，不改已测BIT/BIN，也不为该补测重跑未变化的全部长仿真。

故障仿真中的错误RLAST仍提供请求规定的拍数，只证明错误标记/排空，不证明任意从设备缺拍或永久停响应的自动恢复。既有reader/arbiter协议约束未改，这类破损总线恢复仍需另测，必要时系统复位；不把本轮测试包装成完整容错认证。

在既有Chisel环境中生成时用：

```text
runMain gpu.GenerateEfinix2dGpu --target-dir <全新目录> --split-verilog --instances --frame-lists --key-prefetch --scanout-word-pipeline --transform-blit --alpha-pipeline --axi-diagnostics --key-write-pipeline --extended-list-arena --small-copy-prefetch
```

随后复用scripts/test-efinix-board.ps1的GpuRtlDirectory/OutputDirectory生成全新工程；不要改写generated/efinix_gpu或旧证据。省略新开关即可构建旧行为，正式默认仍不启用候选。正常固件及1024探针直接用上述已保存BIN哈希，无需重编译CPU代码。测试入口performance-trace仅用于诊断，SHA256`b9921a537f02b2f78c9b4effc1da6478c4cebe24c6a102b9bd21a93fb6ff03d5`，不能拿它替代正常资格BIN。

收尾已再次完整JTAG重载候选＋正常BIN，六档START/MENU复测通过，最终MENU、owner释放、遥测新鲜、下溢/硬件错误增量0，烧录和串口采集已结束。人工HDMI目视/按键、30分钟耐久、栈水位及CPU慢绘图期间退出限制未新增验证或处理。没有写Flash、替换release或推送main。

执行取舍：沿用现有Windows链接工作区与原生记录（WSL技能辅助脚本不识别D:/ gitdir，不改.git）；按用户既有无中断授权直接执行默认关闭候选；只重测受影响GPU套件并保留旧全量证据。因此无关模块和长期稳定性仍不作为本轮新增保证；这些取舍不改变像素或资格规则。

原始证据目录：generated/verification/v3/copy-retirement-20261020/。负结果和未通过的候选均保留；2065是本轮复核值，不是硬件绝对极限。

[证据封存](evidence.zip)，SHA256`c93137f108c81c34a24ab35898af9ff723219d32a607c85e019b05ff4816dd1c`。185项条目，含最终BIT/正常BIN、旧BIT对照、隔离的诊断BIN、实际RTL、源码/计划/审查、正负日志、原始HTTP和失败帧DDR快照；包内BIT哈希复核一致。被否决暂存方案只收源码/补丁，不收可误用的暂存BIN。包内README为封包前快照，不包含本段自身ZIP哈希；旧容量封存ZIP仍为06b415...未改动。
