# GPU优化复盘与下一步探索（2026-10-23）

本轮是离线复盘、现有RTL诊断和方案筛选，不改变GPU生产逻辑、CPU绘图、时钟、负载、Alpha/Key、网口或挑战判定；没有新位流上板、Flash写入或远端推送。上一轮已恢复的旧主路径不动。未重复长回归，也没有新增普通1024稳定60或全活动极限成绩。

## 1. 最重要的新发现：上一轮不是单变量对照

复查生成器、构建日志、两份实际Efinity工程和它们引用的RTL，发现宽口候选漏掉已有的`--scanout-word-pipeline`。生成器只在显式收到该选项时启用优化，默认关闭。旧BIT启用、宽口候选关闭；不是仅在文档里遗漏了一个参数，而是生成硬件确实不同。

|核对项|旧Alpha跨行预取BIT|10月22日宽口候选BIT|
|---|---|---|
|Efinity工程|`D:/efinity_builds/alpha_row_prefetch_20261021_r1/efinix_2d_gpu.xml`|`D:/efinity_builds/wide_copy_dma_20261022_r1/efinix_2d_gpu.xml`|
|ScanoutDma实际子模块|`PixelReadAligner_2`|`PixelReadAligner`|
|接收下一字条件|空缓冲，或当前高半字已输出且不是末像素|仅空缓冲|
|连续供数、960正确像素的首尾跨度|960拍|1439拍|
|源字消耗|480，像素/末标志正确|480，像素/末标志正确|

旧BIT SHA256 `d594d395e016353b8a4724bb5fca8400ff08d443712a6ba4171e8372143167ce`，宽口BIT `bf0d3780e356dcde14f4ac71e3db904071a119158bdc411cec1fb0456d6df0c2`，本轮重新核对一致。旧拆包文件SHA256 `2cccbcb5b5885afe72e2899a8b0fbfb414a7e8546674fb1d650cf012ae2c0b73`，宽口拆包文件 `8e733c927ee2f9cefaecc8b4a604a6081a92ea19ba36606082a58dee68cf502d`。

诊断复用两份已生成模块，不修改它们：[单模块测试](../../tb/verilog/scanout_build_throughput_tb.v)。Verilator 5.052分别通过；每个输出像素、末标志和源字数量检查一致，960/1439是本轮新跑结果。约49.9%的局部时间增加**不是**整机帧耗时增加49.9%。首选Icarus无法解析生成器的块内automatic变量，因此改用现有Verilator，没有修改生成RTL规避工具限制。

另将旧/新生成的`AxiWritePipeline`、`CachedKeyStream`、`DdrQosArbiter`、`DenseBlitEngine`、`TransformBlitEngine`、`FrameListBatch`去除行注释和空白后逐一比较，六份代码相同；这加强了先查显示配置的依据，但不替代全量特征清单检查或新候选板测。

这说明上轮“5.762→2.211ms Copy，但59.2→57.5FPS”的数据仍是真实组合结果，但不能作为宽口DMA单独导致退化的证据。当前组合不启用是正确的；漏检查功能集合一致是实验设计失误，不能称作DMA架构已被公平否决。原始证据包不改写，新报告公开更正前提。

## 2. 现有原始计数把嫌疑进一步缩小

重新解析`wide-copy-20261022/board-aba1`的三份phase日志，对target1040的tick11/22/33取均值。下面均为μs，周期按100MHz换算：

|独立阶段/计数|旧A1|候选B|回旧A2|
|---|---:|---:|---:|
|Alpha显示保护写等待awqos|343.807|726.847|349.137|
|Alpha写响应等待bwait|276.143|268.517|277.120|
|Alpha读数据断供rgap|686.923|683.133|688.200|
|Key显示保护写等待awqos|454.350|886.363|454.530|
|Key写响应等待bwait|792.307|800.923|793.943|
|Key读数据断供rgap|6.813|6.750|6.777|

Alpha/Key阶段本身不包含背景Copy命令，候选仍更慢；这与显示拆包吞吐退化、紧急保护占用变长相符。`awqos`是在旧32位QoS入口观察到的因显示保护未获准写入，不等于DDR物理AW背压；上述计数可能互相重叠，不能相加或据相关性声称已解释全部退化。更不能仅由此断言需要增加DSP或纹理容量。

另一个口径更正：`V3_PERF,mode=0,scene_us`是`render_us`窗口平均，来自渲染调用前后，包含提交/等待和未隐藏的Copy尾部；逻辑、构建另有独立计时。3548→4621→3546μs**不能证明RISC-V游戏逻辑或CPU占用率退化**。后续必须分别测logic/build/submit/execute/HUD/总work，不能用名字推断指标。

## 3. 前几轮失败到底教会了什么

|尝试|已有实测|结论及再尝试条件|
|---|---|---|
|Copy FIFO16→256字|独立大Copy仅少约0.84%，整帧无明确可重复收益|等待主因不在FIFO容量；只有实际占满/反压证据变了才扩容。[证据](gpu_memory_overlap_20261016.md)|
|960×8片上条带合成|1024隔离场景8.036→15.893ms，像素正确|小精灵低覆盖率时，装入、写回、分桶、边界裁剪比省下的RMW更贵；不能只因像现代GPU就使用Tile。[证据](row_stream_and_stripes_20261016.md)|
|透明首尾/空行裁剪|普通512 work9.618→9.784→9.618ms|减少W拍不等于整帧变快，控制开销和布局不能忽略；当前近实心小图形不启用。[证据](evidence/dual_track_20261019/README.md)|
|片上暂存描述符后memcpy发布|普通1024 work约14.4→15.066→14.4ms|多做一次搬运不等于更快；已有memcpy已展开，候选撤回。[证据](evidence/small_copy_prefetch_20261020/README.md)|
|仅扫描显示保护高水位|512最好仅约0.25%，仍不达标|没有大头结构证据时，不靠调参数找稳定60。[证据](v3_qos_ablation_20261007.md)|
|128位独立Copy|实际组合Copy显著快，普通1024反而慢|漏开Scanout换字，不能仅归咎DMA/mux；先做配置一致的复测。本轮新发现。|

共同经验：必须保留原序、像素和错误语义；同BIN、同数量仍不足以保证单变量，硬件特征集合也要一致。正确性通过≠整机加速；平均低于预算≠每帧准时；背景与逻辑已重叠，节省背景不能直接全额从work扣除。历史2194是对应旧BIT/BIN的有效窗口，不是当前所有版本的纪录，也不等于普通1024已稳定60。

有效优化反而多来自**减少共享资源占用和隐藏事务尾部**：显示同拍换字、Key两/四笔在途、小字形一次预取、Alpha跨行预取。它们提供方向，不保证继续加深就继续获益。

## 4. 下一步按什么顺序探索

### P0：先修复实验前提，不新增架构

1. 补齐`--scanout-word-pipeline`，保留上轮其他合法特征；新目录生成，不覆盖旧候选与证据。
2. 生成清单记录全部影响硬件的开关/数值及源版本，板级检查对照特征差分，只允许预定的实验差异。现有JSON只有`wideCopyDma`一个布尔值，无法阻止本次遗漏；仅检查端口/宏一致不够。
3. 精确核对Scanout实际实例，而不只看命令行。先定向Scanout/Top/宽口顺序复位测试，再资源、最终时序、实际网口CDC；通过后才能加载。
4. 同BIN旧→补齐配置候选→旧，先比固定阶段及普通1024 work/迟到/下溢；没有净收益不做极限搜索。补齐配置后的整机收益**尚未测得**，不提前承诺。

这是优先级最高、资源代价最小的步骤。完整生成参数应包含：

```text
--instances --frame-lists --key-prefetch --scanout-word-pipeline
--transform-blit --alpha-pipeline --axi-diagnostics --key-write-pipeline
--extended-list-arena --small-copy-prefetch --four-write-credits
--alpha-row-prefetch --wide-copy-dma --split-verilog
```

这份清单只是后续合法候选配置，不表示已生成/物理通过或可直接烧录。

### P1：只有补齐配置仍退化，才分离接入代价和流量竞争

以相同Scanout配置建立三组：A旧直连；B保留WideDdrMux、但Copy强制走旧合法路径；C同B且启用native Copy。B与C须只差发射选择，不能用“整个wide功能关闭”冒充“保留mux”。当前代码还没有这个独立诊断开关，不能假装已经测过。

- B比A慢：优先检查旧链路额外握手/流水限制，以及物理映射差异。
- B不慢、C慢：优先检查长突发占用、native与legacy服务配额，以及逻辑/列表/显示的共享访问竞争。
- C整帧有净收益：无需为假设重写mux，直接走正常资格验证。

最少记录AW到首W/最后W到B、AR到首R/读间隙、两方向owner等待、显示低水位持续时间与最低水位。记录最大值/分布，不只平均；使用固定计数、测量窗内不串口打印。显示请求、CPU访问和GPU访问在legacy汇合后不能凭空用同一个总计数拆出“CPU占用率”。

### P2：两种有条件的结构优化，而不是立即全做

**候选A：已锁定归属的写数据通路去气泡。** 当前WideDdrMux在`dataCount>0`才放W，即必须先完成AW握手。参考开源中“仲裁决定FIFO＋锁住已呈现地址＋W归属/响应退休分离”的机制，先验证同拍AW/W是否足够，再考虑AW尚被背压时的数据缓冲。不能简单把`dataCount`条件删除：先W、AW阻塞、W阻塞时稳定、同ID、切换owner、错误/局部复位都必须保持。它是待测假设，不是已知主要瓶颈。

**候选B：显示余量驱动的双预算服务。** 若C独有竞争，native不能只按“每轮两段”获得服务；用字节/占用周期预算约束大Copy，同时给legacy短请求设最大等待，显示低水位仍最高保护。只在地址未承诺时改变准入，不能中断已承诺Burst。针对本工程的可验证创新是让大Copy吞吐与短请求尾延迟共同受控，而不是声称发明QoS。先量出最坏服务时间，避免新增一堆不可校准参数。

两者都比更换整个AXI交叉开关、加大纹理Cache或提高主频更适合当前资源余量。宽口旧候选54617/60800，距<90%硬门槛仅103XLR；必须重新综合和布线，不能认为删功能就一定解决。若确需缩放/灰度让位，用户已允许裁剪，但只能对功能一致的控制/候选比较，明确区分功能裁剪与性能收益。

## 5. 开源核对：取机制，不整库替换

- [PULP AXI mux说明](https://github.com/pulp-platform/axi/blob/master/doc/axi_mux.md)和[实现](https://github.com/pulp-platform/axi/blob/master/src/axi_mux.sv)：有AW/W路由决策FIFO、FallThrough和spill；其源码锁存仲裁决定，避免AW到W的非必要依赖。可参考机制，但其典型路由依赖扩展ID。本板已有固定8位ID，不能偷一位或不做映射直接替换。Solderpad Hardware License0.51；本轮未复制RTL。
- [verilog-axi写交叉开关](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_crossbar_wr.v)：可参考输入/输出缓冲、写数据归属和并发事务管理；其默认主ID宽度同样增加端口索引，不能视为无代价即插即用。MIT；本轮未复制RTL。
- [axi_cdma](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_cdma.v)：现有宽Copy已具备分段、数据缓冲、读写解耦和B退休，不再为“换一个DMA名字”重做同类模块。

本轮在线核对以上PULP文档/源码和verilog-axi源码；部分额外仓库请求未返回有效内容，没有拿它们的未核实特性作为建议依据。未新增依赖或第三方IP。

## 6. 验收与停止条件

采用同BIN/同场景/同功能特征、旧→新→旧。优先看普通1024总work与尾延迟，同时保留固定场景分项；下溢、硬件错误、像素/哨兵、命令顺序均不得退化。只有普通游戏有可重复净收益且资格条件通过后，才重新挑战更多全活动Sprite。60Hz显示已封顶的档位以余量、最大帧和活动数量评价，不宣传不存在的显示FPS增长。

若修正配置后仍无收益，且B也明显拖慢旧路径，撤销外插mux思路，回到旧32位主路径继续局部优化；不因上一轮投入大而必须保留。整帧不受益就停止堆硬件，是这些失败经验最应保留的准则。

## 附：本轮短仿真复现

在工程根目录的WSL终端运行，使用本地保留的归档生成目录；输出仅位于新的`retrospective-20261023`目录。两个编译使用同一测试，只改变被测模块和匹配其接口的宏：

```sh
verilator --binary --timing -Wno-fatal --top-module scanout_build_throughput_tb -DSYNTHESIS -DOLD_SCANOUT --Mdir generated/verification/v3/retrospective-20261023/old-obj tb/verilog/scanout_build_throughput_tb.v generated/verification/v3/alpha-row-prefetch-20261021/rtl-9d06d76603d74e2a8a614e3b916229d0/PixelReadAligner_2.sv
generated/verification/v3/retrospective-20261023/old-obj/Vscanout_build_throughput_tb
verilator --binary --timing -Wno-fatal --top-module scanout_build_throughput_tb -DSYNTHESIS --Mdir generated/verification/v3/retrospective-20261023/new-obj tb/verilog/scanout_build_throughput_tb.v generated/verification/v3/wide-copy-20261022/rtl-full-r1/PixelReadAligner.sv
generated/verification/v3/retrospective-20261023/new-obj/Vscanout_build_throughput_tb
```

本轮实际输出：

```text
SCANOUT_BUILD_PASS,pixels=960,words=480,first_to_last_cycles=960
SCANOUT_BUILD_PASS,pixels=960,words=480,first_to_last_cycles=1439
```

它们是局部诊断，不是整机回归通过、补齐配置后的性能结果或新60FPS资格。
