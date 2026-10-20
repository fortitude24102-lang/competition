# Key专用双在途写实测（2026-10-20）

代码提交 `fe70eb6a00cc0b15d6ff6c9229c6e7dfab031a9f`（包含前序独立writer提交`c4d415e`）；生成后到实板测量结束生产RTL未再改动。

## 已测收益

相同BIT配置只切换Key写流水，相同BIN、100MHz、官方Sapphire/CPU基础绘图、DDR/HDMI/以太网和游戏负载不变。A=关闭Key写流水的诊断基线，B=开启，A2回测原A。只JTAG/RAM，未写Flash、替换release或推送。

普通512探针各30帧预热＋3600帧：

|指标|A1旧|B候选|A2回旧|
|---|---:|---:|---:|
|平均work ms|9.567|8.828|9.567|
|最大work ms|12.184|12.545|12.342|
|FPS|60.1|60.1|60.1|
|超预算/迟到/新增下溢/错误|0/0/0/0|0/0/0/0|0/0/0/0|

平均work减少**7.72% / 0.739ms**，不是显示FPS增加7.72%；候选本次最大work反而更高，不宣称最坏帧改善。三组同为可见499..504、Alpha66..67，状态封存CRC `c0ecf1df`、count600/offset5228一致；这不是完整游戏帧缓冲CRC，也不是512个全活动精灵的极限资格。

固定512/1040、tick11/22/33诊断分段，以下为每阶段三tick均值（ms）。相对收益用B对两侧A均值；不同阶段的计时不能相加替代完整游戏FPS。

|负载/阶段|A1|B|A2|耗时减少|
|---|---:|---:|---:|---:|
|512 Key|1.75596|1.01716|1.75323|42.03%|
|512完整原序渲染|8.41738|7.66540|8.41341|8.91%|
|1040 Key|3.51705|2.05619|3.51027|41.48%|
|1040完整原序渲染|11.07886|9.54845|11.06647|13.77%|
|1040背景Copy|5.55662|5.55891|5.54507|−0.15%|
|1040 Alpha|2.23145|2.22610|2.21993|−0.02%|

另用未增加诊断APB读数的原保存r3分段BIN分别A/B/A，1040 Key **3.54360→2.04678→3.55036ms**（减少42.30%），完整原序 **11.37236→9.86727→11.36813ms**（减少13.22%）；512完整原序8.07595→7.29295→8.07563ms（减少9.69%）。不能把两个BIN互相比较当收益。

六组分段运行各24阶段，数量、有效read/write/cache字节一致，新增下溢0、STOP result0/hardware0；诊断B的实际R拍×4等于原读取字节、AW/B数量平衡。固定输入fixture CRC逐项核对；普通游戏和分段的工作量不同，报告各自保留。

## 为什么做这个，不先换大DMA/大Cache

[上一轮实测](../axi_diagnostics_20261019/README.md)发现1040 Key约42%窗口为B响应尾等待，而背景只有约4%。现有Copy早已有读写FIFO并行，贴图Key也早已有Cache和双像素比较；重复增加通用CDMA/Cache不是本轮最短路径。

本轮做的是**Key行发射与响应退休分离**：

- 新`AxiWritePipeline`只给缓存Key使用，最多两笔burst，W严格顺序、ID0，仍按256拍/4KiB拆分；每请求最后一个B才报告done/error。
- `CachedKeyStream`仍拿完整源行credit后才承诺写；最后W后可推进行，另计未退休行，全部B和源读排空后才完成整条命令。
- `DdrQosArbiter`增加深度2的B-owner队列，WLAST释放AW/W调度，B按原事务所有者独立返回，不误发给当前W所有者。
- 保留显示紧急准入、已呈现AW稳定、错误排空、透明色WSTRB/半字掩码以及命令顺序。Copy/Alpha/Sparse/Transform仍用原writer，不跨命令重排。

参考已有AXI状态FIFO/事务解耦思想；[开源参考与许可边界](../../gpu_performance_options.md)。没有整库移植，也不将FIFO/DMA或双在途本身宣称首创；本项目的针对性设计是用实测等待类别选中Key短行，再把发射、退休、显示保护和有限资源约束一起闭合。

流水后诊断B等待可能与有效W重叠，不再等于可直接扣掉的空闲时间，不能拿新的B等待占比再次预报收益。

## 身份和复现

- A BIT：`D:/efinity_builds/axi_diagnostics_20261019_r1/outflow/efinix_2d_gpu.bit`，SHA256 `c3f4ea6e33d66c8df8819f1946b1329660d307a37800d838053574ac3e73aef9`。
- B BIT：`D:/efinity_builds/key_write_pipeline_20261020_r1/outflow/efinix_2d_gpu.bit`，SHA256 `b7e59dfe01ae655f3ec20d80416e670304a28fb891476a3b421a9e1f0349cb82`。
- B RTL：`generated/verification/v3/key-write-pipeline-20261019/rtl-fd68945e951046e78a39e0229b137a88`，60个单模块HDL文件；`.vh`为共享定义，不是模块文件。
- 开启instances/frame-lists/key-prefetch/scanout-word-pipeline/transform-blit/alpha-pipeline/axi-diagnostics/key-write-pipeline；裁剪、条带、Copy256关闭；正式生成仍默认关闭新Key流水。
- B资源XLR52301/60800、RAM179/256、DSP37/160；核心setup+0.293ns/hold+0.026ns，最终16项全部为正，最小setup+0.167ns、hold+0.013ns。保留已有LVDS proximity与固件RWX LOAD警告。
- 普通512BIN SHA256 `dc82fae7902e1fd238a572db28e49b947535d75f876c892562b2d8c736504a0b`；LogicCopy1/SealWords256/HudDirect1固定。
- 诊断BIN SHA256 `939ff3cb4bfe3c777ec751478f3303d7e5ec967defb641a959f11f9c52f55e0d`；原r3分段BIN SHA256 `9c2a1b108814ee462a4b769527fd27d51214deb6b21e3f0db8f0c5093be64f63`。

## 验证与尚未结束的部分

新候选RTL14项定向测试分批通过：两笔在途/满credit/4KiB、两种半字相位、cache和B错误、已接收但AW阻塞的第二请求、每请求错误归属、Asset B归属、显示紧急排空，以及Key报错后排队Fill/Alpha的像素和完成顺序。独立审查未发现具体RTL错误，提出的两项重要覆盖缺口已补测试，未为测试凭空修改生产RTL。AxiDiagnostics3项及原8套C检查通过，最后30套兼容回归119/119通过（27分06秒）。三个不重复测试组合计35套136/136，未把上一轮基线122项拿来充数，也不伪称一次单批完整GREEN。

实板候选Key6例、Alpha24例、Transform/灰度/缩放80例像素/哨兵/计数检查通过。后二者不PRESENT，`under_offscreen`有增长，不能冒充显示资格；上面的正常显示测试新增下溢为0。Transform采集入口误把STOP模式加了不存在的cases字段，超时保留原始日志；逐行核对80条mismatch0/failed0和真实STOP0后采纳像素结果，没有重复已通过用例。

同版正常固件自动挑战通过：**1819个全活动Sprite＋228个Alpha光晕，3600帧60.10FPS**，最大work15.504ms、最大wall16.639ms，work_miss/late/under/error全部0，visible_min/max均1819、alpha_min/max均228。随后继续5秒未失效；最终快照新鲜、session一致、stage5/frames3600/best1819。`1+1819+ceil(1819/8)=2048`，命中当前命令容量，不能宣称硬件绝对数量极限，也不与不同历史BIT/BIN的1040直接相除声称只来自本改动。

负载维持原定义：一枚16×16、其余8×8、全部逐帧移动/更新形状并走Color Key；每8枚一枚12×12 Alpha光晕，Alpha逐帧变化，背景每帧完整Copy。不是1819枚全屏大图或1819枚均做Alpha；228个光晕作为额外绘制量单列，不充作独立活动角色。

挑战使用原`normal-r1/gpu_demo.bin`，SHA256 `bbdee4d00f57f354c03f84186eb697e38fdd1b8bfb38c040fb11095ac66160a0`，无改挑战规则、60帧预热/600帧搜索/3600帧确认及结束后持续检查。复用`test-game-menu-board.ps1 -LoadBit -PerformanceChallenge -SerialPort COM9 -ExpectedBuild 0x20261015`，独立中性心跳正常退出。四档START/MENU、租约切换、R清分与新session检查通过；结束已回正常MENU、控制权释放、遥测新鲜、错误/下溢0。本轮未人工确认HDMI目视、移动/死亡/慢CPU比较，不冒称新人工验收。

历史两项SoC异常、长期耐久与栈水位不在本轮补称通过。

原始日志目录：`generated/verification/v3/key-write-pipeline-20261019/`。本轮独立封存完整日志、源码身份、BIT/BIN与时序，既有证据ZIP不改。

[完整证据封存](evidence.zip)，SHA256 `3052798d137c6dc2d1d37f2fdfd728aca0090ed2c9a81c3ef7e27e105c8fc285`。188项归档条目已核验，包内BIT哈希与实测候选一致；包内README/计划是封包时的快照，不含封包后才生成的本段哈希/最终勾选。正式release和Flash未替换。

## 执行裁决与遗留边界

- 用户已授权连续执行，直接完成默认关闭、可回退的本地候选；不因此扩展为Flash、改CPU、改显示阈值或推送main。现有命名工作树保留，集成到共享分支仍需明确指令。
- 为避免旧回归JVM延迟加载到新class，基线与候选使用独立sbt输出；旧31套122项不挪作本候选证据。当前源树兼容回归只跑一次，已经通过的定向批次不机械重跑。
- 两项重要审查意见是测试覆盖缺口，不是已证实RTL缺陷。补上两个错误位置与Key错误后Fill/Alpha测试均通过，没有为制造RED虚改RTL。审查未评价的时序、资源、实板与性能由上述实际记录补齐；不能用审查结论代替这些门。
- 生成检查曾误把`.vh`定义文件当模块，编译前已纠正检查范围；Transform采集STOP匹配错误按原始完整结果裁决，未覆盖失败日志或重跑成功用例。
- 诊断继承两项minor：32位窗口自身不能发现43秒后绕回，本轮逐阶段64位elapsed小于40秒；APB非法clear/重复消费并未覆盖每个故障变体。它们不扩展为长期通用监控保证。

保留候选的依据是可重复整机均值收益和本轮极限长确认，而不是仅凭Key局部周期；下一轮先解除软件/前端2048项容量边界，再用同负载长确认找真正硬件极限。1040背景Copy约占B完整渲染58%，后续硬件选择须基于新等待分解，不拿重叠B计数直接估算收益。
