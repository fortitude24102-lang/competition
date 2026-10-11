# 整帧命令前端基础：直接列表与突发预取

用户要求继续负责人GPU性能优化，已免除中间审批，当前对话自行执行。代码基点e9b55c4。目标是在保持Sapphire游戏/指令职责、CPU基础渲染、Key/Alpha顺序、100MHz、960×540、网口/菜单的前提下，消除后续GPU逐Sprite APB提交。按Ponytail先复用既有16B模板格式和AXI读引擎，不叠新CDMA/缓存/主频改动。

## 分阶段边界

本子项目交付两件可独立验证的基础部件：当前互动/R7直接描述符构建器，以及完整列表AXI预取器。顶层0500门铃、批执行适配、运行固件切换、综合/时序/实板旧新旧测量留给下一个集成子项目。本阶段不改变生产Top/生成器/source清单，不烧录未接入候选，不声称512@60或真实提交成本已降低。板卡保持已合格正常菜单。

## 取舍

1. 继续旧逐实例APB不可取，历史512构建节约约0.85ms但场景提交反增约10ms。
2. 从旧32B命令数组再压缩需要第二遍全帧，额外占用软核时间/RAM，不采用。
3. 从游戏状态直接写16B实例到调用者缓冲，再AXI预取完整列表，选此路线。全帧预取需要16KiB片内列表缓存，但避免一边阻塞像素读一边等待描述符造成新的共享DDR死锁；后续综合资源不合格或预取代价抵消收益时再评估小FIFO流式方案。

## 软件接口和语义

保留gpu_instance四个uint32_t字、12个模板、gpu_instances_build的R7语义。新增gpu_instance_stats五字段：unsigned count/visible/alpha_commands，uint32_t scene_pixels/alpha_pixels。新增gpu_instances_build_into(state,dst,network,glow,manual,hud_height,capacity,items,stats)，int返回既有GPU_DRIVER_*；调用者提供至少capacity项可写缓冲（未来可以直接是DDR），state/items/stats必须不重叠，这是可信内部C调用的前置条件，不是对任意裸指针做运行时安全校验。不分配全帧临时数组、不先构建旧命令。manual0保留R7拒绝kind3，manual1允许友军kind3并跳过age=UINT16_MAX的失活项及其glow。错误stats全部清零，部分数组不可提交；容量越界不得写到缓冲外。

背景第0项先裁掉指定HUD；弹幕全部glow先于全部core，玩家glow/core、三个发射器glow/core顺序不变。负Q8坐标向下取整，边缘透明裁剪、可见/Alpha/像素统计与真实原构建器一致。旧API薄包装同一直接构建流程，保持公开stream布局/API不变。未来调用者在CPU存储发布栅栏后才交GPU读取，读取/执行期间列表和模板不可修改；本阶段没有发布驱动，因此不冒称所有权/epoch锁已实现。

## 硬件接口和限制

新增FrameListRequest(address UInt32,count UInt16)和FrameListReader(maxDescriptors=1024)。IO：request Flipped Decoupled、descriptor Decoupled Vec(4,UInt32)、axiAr Decoupled Axi4Address、axiR Flipped Decoupled Axi4ReadData、busy/fetching/done Bool、error UInt8、fetchedBytes UInt32。done仅表示列表被全部消费或本部件错误，不代表像素渲染/PRESENT完成。

复用AxiReadEngine(ID6)，32bit INCR、每突发最多256拍、拆4KiB边界。列表仅允许16B对齐、1..maxDescriptors、范围0x02d20000..0x02d28000，单批不跨16KiB bank：bank0 0x02d20000..0x02d24000，bank1 0x02d24000..0x02d28000。不与现有runtime 0x02d00000/探针0x02d10000、素材/显存或CRC隔离探针0x02e00000重叠。

先把整批四字逐项写SyncReadMem，再在读事务完整成功后输出有序、稳定的16B描述符。请求非法不发AXI，完成带AddressRange；响应ID/RESP/RLAST错误经原引擎报告AxiResponse，整批不输出任何描述符。忙时不接新请求；输出背压稳定，最后descriptor握手才done并释放busy。复位丢弃未发布列表，不重放旧RAM内容。AXI无响应不能安全自行猜测完成，交后续软件有界超时/GPU显式复位处理，不添加凭空计时器。

maxDescriptors允许1..1024，默认1024，只足够当前512 Sprite的585上界；未来1024Sprite可超过此描述符数，需要修改硬件容量上限/bank契约、重新综合并与软件协商容量，不能仅改变当前参数或把host1024检查当作本默认硬件支持1024游戏。

## 验证

软件：既有12000帧R7等价/真实驱动继续通过；新增互动四档×600tick×本地/网口×有无glow，与原game_build+HUD裁剪展开字段/顺序/统计一致，友军持续发射/失活/死亡/重开、字面边缘与容量护栏、无全帧复制的缓冲写入检查。选定完整像素样本用真实golden_renderer，而不是只比较描述符自身。

硬件：真实AXI引擎联接，跨4KiB/256拍拆分、地址/数据和消费背压、最大1024描述符及第二批/复位无旧数据，非法0/1025/溢出/跨bank请求零AR，错误响应不输出部分列表。完整现有GPU套件和18C+23UDP/HTTP作为回归；已知历史SoC异常单列不混称整SoC通过。

后续集成须另验模板验证器、队列/完成tag回绕、排空/PRESENT栅栏、epoch锁、旧位流安全能力探测、部分执行错误不重放、扫描DMA保留优先权。还没有这些证据时不能上板验证本前端性能。
