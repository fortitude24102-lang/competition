# AetherGX V3 两周架构与接口设计

日期：2026-10-01。分析基点：85b7dc0、9/28 纹理 Cache 硬件和 9/30 R7 分段测量。本文件规定拟实施接口，不表示功能已实现。实施入口是 [V3 两周计划](v3_two_week_plan_20261001.md)，前序依据是 [V2 回顾](../../README.md) 和 [研发调研](v3_research_20260930.md)。

## 1 目标与两条线

负责人仅承担 GPU 性能优化、GPU 专属提交和背景调度、顶层集成及整机测量。组员 A 承担网口管理通道、PC 网关、网页和键盘转发；组员 B 承担 Sapphire 管理驱动、输入解析、游戏逻辑、输入回放及资源和画面。分工沿用 A 的 Verilog、B 的 C；A 的 PC 侧使用 Python 标准库和原生 HTML/JavaScript，不增加大型前端框架。

核心异构计算仍是官方 Sapphire RISC-V 加 AetherGX。PC 的新增职责是输入设备桥接和结果展示，不执行游戏状态更新、碰撞、AI、轨迹计算、命令生成或渲染。资源服务保持原有 ASST 协议与服务器。

功能线与 GPU 线共同使用下述固定合同，各自先用测试桩开发。只有负责人修改 main.c、SoC 适配和工程源清单；组员不在自己的分支改这些共有文件。

## 2 不可改变的约束

- 官方 Sapphire 和 GPU 均保持 100 MHz；不改 CPU 微架构，不加入 CPU 专属绘图优化，不人为降速。纯 CPU 绘制仍完整恢复背景和 HUD。
- 保持 960×540 RGB565、HDMI 1920×1080 60 Hz、vblank 双缓冲及现有 Copy、Fill、Key、Alpha、Sparse 语义。不能删 Alpha 或减少可见元素来换取 FPS。
- 地址窗口为 0x02000000 至 0x10000000，右端不含；A/B 为 0x02000000/0x02200000，stride 为 1920 B。新增区先在清单中检查不重叠，不自行宣称整片 DDR 可用。
- 原有 GPU 0x0000～0x00ff、Asset DMA 0x0100～0x01ff、网络 0x0200～0x02ff 的局部 APB 地址不变。拟新增管理 0x0300～0x03ff；可选实例前端 0x0400～0x04ff。SoC 适配必须显式分发，不能只接一个未被选中的模块。
- 每个 .v 文件只定义一个模块；复用官方 vendor 文件不直接改，适配改动放 rtl/net 等自有目录。生成 RTL 也按模块拆分。
- 所有模块有关闭或旧路径回退；当前 release/v2 是 9/26 冻结包，不覆盖它，不把新候选称为旧发布物。
- 本阶段最多实施一个较大的 GPU 前端扩展；完整多 ID 仲裁重构、整套 CDMA 移植和目的 Tile 合成器不同时承诺。暂不超频。

## 3 网口方案与取舍

采用浏览器到 PC 本地网关，再到板卡 UDP 的路径。浏览器通过 HTTP POST 传完整按键状态，通过 SSE 接收遥测。PC 网关用 Python ThreadingHTTPServer、socket 和有界状态缓冲，HTTP 仅监听 127.0.0.1:8765；UDP 监听网卡地址的 8090，板端管理发往 PC:8090。PC 保留现有资源 UDP:8080 服务，管理请求发往板卡:8090。网关不替代资源服务器，两者独立启动。

原生浏览器网页不按可直接发送任意 UDP 包设计。完整 FPGA HTTP/TCP/WebSocket 栈与直接 USB Host 键盘均不进入两周必交项。SSE 是服务端单向推送，输入走 POST；原生 fetch/EventSource 足够完成此处需求。Python http.server 不是面向公网的生产服务，禁止默认绑定所有网卡，禁止开放任意文件目录、远程执行或随意修改板端寄存器。

现有 efinix_ge_mac_wrapper.v 的 TX 是固定 32 B，现有 efinix_asset_network.v 的发送还依赖 asset_active。V3控制包仍32 B，遥测用一包128 B完整快照：为wrapper增加有界tx_length和最多128 B的发送缓存，只接纳32/128两种长度，资源GET仍32 B。不能拆成每帧发一页再要求500 ms内收齐，因为CPU慢回放时做不到。新增管理提交不依赖Asset DMA活跃；两路描述符在GE域整包仲裁，共用原MAC。已有wrapper未输出UDP端口元数据，接收按完整包的magic分流；端口不同只是PC socket分离，不能假设FPGA已按端口过滤。

分类器先缓存前四字节，选择分支后把这四字节连同余下内容原样送出。ASST 流仍进入原解析器；AGC1 流进入管理解析器。未知 magic、短包和超长管理包排空丢弃，不能把残余字节留给下一包。单条输入不与资源载荷共同进入 Asset DMA。

资源解析器的current_session必须来自独立的资源请求/Asset DMA会话，不能再引用共享MAC的“最后发出的描述符session”；管理包会改该描述符，若不隔离就会误丢随后合法ASST回复。管理会话不改资源local_ip/peer_ip配置或Asset DMA活跃/abort状态。

共享 RX RAM 目前是一帧一帧接收，不能在其忙时声称绝不丢包。交互期间大资源只在加载/暂停阶段请求；键盘传完整状态并周期刷新，可恢复少量丢包。管理处理忙时不拖住资源流，计数并排空；高压资源与输入共存需要测丢包、延迟和资源重试。资源请求与管理 TX 采用包边界轮转，最多等当前包及另一类一个包，不允许字节交错或借用 Asset DMA 会话。

## 4 管理包合同

所有多字节字段网络大端，无结构体直接memcpy。输入包32 B，0～3 magic=AGC1；4 version=1；5 type；6～7 total_length=32；8～11 session；12～15 sequence；16～27三个u32数据；28～31 CRC32覆盖前28 B。遥测包128 B，magic=AGT1、type=0x80、total_length=128，头16 B同结构；16～123为27个u32数据，124～127 CRC32覆盖前124 B。CRC算法复用asst_crc32，初值和终值取反，反射多项式0xedb88320。

type=1 为 HELLO，三个数据字必须为零；type=2 为 KEYS，数据字依次为 key_mask、action_sequence、0。key_mask 的 bit0～7 为左、右、上、下、射击、慢速、重开、比较模式请求，其他位必须为零。重开与比较模式按新的 action_sequence 执行一次，不能将持续按键重复当作事件。

板端确认为32 B AGC1、type=3 ACK，session与sequence回显HELLO，数据字为1、0、0表示接受；拒绝不发成功ACK。RX只接纳HELLO/KEYS，不能接受来自PC的ACK作为输入。Sapphire将ACK排入管理待发槽，nc_try_publish优先发送该确认再发遥测，每次仍最多1包、不等待TX；网关收到正确ACK才转发非零KEYS，不能靠尚未到达的周期遥测完成握手。

网关为每次控制会话生成非零随机 session，HELLO 被 Sapphire 确认后才能发送非零 KEYS。Sapphire 启动和失联后默认为零键；活动会话租约内拒绝另一 session 抢占。HELLO 不使角色运动，断连超过 250 ms 释放会话。KEYS 严格采用模 2^32 新序号规则：差值在 1～0x7fffffff 才是更新；收到重复/过时序号不刷新租约。新会话需零键握手，测试跨复位和延迟旧包。

浏览器每 33 ms 最多一个 POST，状态变化立即安排发送；始终最多一个在途 POST，其后只保留最新状态，不堆事件。keyup、blur、visibilitychange 和关闭页面尽力发送零键，网关从最后一次浏览器心跳起 250 ms 超时则只发零键并停止持有控制。网关以最高 60 包/秒转发完整状态，禁止离开页面后持续重发旧非零键。握手重试限频 2 次/秒。

长度、version、保留位和CRC在RTL完成检查，session和序号由Sapphire检查，全部通过后才成为有效输入状态。管理 RX 通过复用 pixel_async_fifo 跨域；FIFO 深度 4，不足时排空丢弃并计数，不等待 CPU。每记录含包和接收时戳；CPU 每次最多取 4 包，保留最新有效状态。APB 提供接收年龄，超过 250 ms 的旧记录不被当作新按键。时戳统一使用gpu_clk域1ms计数，经Gray计数同步提供给GE采样，再随包跨回；不得将GE计数直接减CPU计数或异步采样多位二进制总线。GPU 实时模式每帧轮询；比较回放期间不接收真人输入影响回放。

遥测sequence为snapshot_id，一包全部CRC正确后发布，不能逐字段混用不同时间的数据。未建立控制会话时session=0的遥测仍可展示，但不能控制。以下每行三项依次排列，即共27个u32：

- 字0～2：firmware_build_id、resource_epoch、simulation_tick。
- 字3～5：requested_sprites、visible_sprites、GPU full_frame_fps_x100。
- 字6～8：CPU full_frame_fps_x100、pre_present_us、gpu_busy_us。
- 字9～11：command_build_us、submit_blocked_us、background_copy_us。
- 字12～14：render_read_bytes、render_write_bytes、texture_cache_bytes。
- 字15～17：scanout_underflow_delta、GPU_error_delta、missed_vblank_delta。
- 字18～20：asset_retry_delta、control_drop_delta、input_age_ms。
- 字21～23：status_flags、p95_work_us、present_wait_us。
- 字24～26：alpha_commands、alpha_pixels、key_commands。

字节/事件数为采样窗口增量 u32；窗口最长 1 s，溢出/缺计数置无效位，不伪造零。耗时为最近完整帧或最近完整测量窗口，窗口语义随 status_flags 标注；CPU 无新窗口时保留最近成绩并标过期。未开启逐命令探针的字段置无效，不为网页每帧重新打开高扰动测量。firmware_build_id 对应版本清单，不是完整哈希替代品。

status_flags：bit0 GPU实时，bit1比较回放，bit2加载，bit3本地回退，bit4控制已握手，bit5 CPU数据过期，bit6细分探针开启，bit7有无效计数，bit8游戏暂停，bit9错误恢复。bit16～22依次表示GPU帧时间/FPS组、CPU FPS、细分探针组、流量组、错误/下溢组、输入/网络组、Alpha/Key工作量组有效，其余零；无有效位的字段网页显示不可用而非0。默认每秒5个快照、最多10个；nc_try_publish一次提交一份完整128 B快照，不等待发送。发送忙仅保留最新待发快照，不修改正在发送的快照。CPU慢回放期间主循环可低频发布，网页500 ms无新快照显示数据过期，不宣称任意CPU负载下都能10 Hz更新。网页只显示值、有效性、时间与图表，不计算游戏结果。

## 5 管理 APB 与模块接口

局部地址新增如下：0300 ID=0x4d475431；0304 STATUS；0308 RX_SNAPSHOT；030c RX_RELEASE；0310 RX_AGE_MS；0314 RX_DROP_COUNT；0318 TX_COMMIT；031c TX_DONE_COUNT；0320～033c RX_WORD0～7；0340～03bc TX_WORD0～31；03c0 TX_LENGTH。所有访问为对齐32-bit。TX_LENGTH仅32/128合法；输入握手回复可以发32 B，遥测发128 B。

STATUS bit0 rx_available、bit1 rx_snapshot_valid、bit2 tx_ready、bit3 tx_error，其余零。写RX_SNAPSHOT=1固定队头包和年龄的读快照；读取八字不会被新包覆盖。RX_RELEASE=1消费该快照，一包只释放一次。按TX_LENGTH写齐8或32字后TX_COMMIT=1发送一次；忙时拒绝提交并保留原TX包，软件重试须有上限。需要的影子字均已写入才允许COMMIT，提交后清已写掩码；复位清快照、掩码和有效标志。无快照读RX_WORD、重复RELEASE、未写齐COMMIT、busy写TX和未定义/不对齐地址均pslverror；TX error保持至下次合法COMMIT或复位。这些行为在A文档中复述，不能自行重定义地址或位。

新RTL端口统一使用clk/reset（高有效）、valid/ready包流。udp_payload_router.v采用GE时钟字节rx_byte[7:0]/rx_valid/rx_ready/rx_last/rx_length[15:0]，输出同型asset_*和control_*。control_udp_rx.v输入control_*，输出packet[255:0]/packet_valid/packet_ready/arrival_ms[31:0]和drop_count。net_control_bridge.v以gpu_clk/ge_clk与独立reset跨域，提供paddr[15:0]、psel/penable/pwrite/pwdata、prdata/pready/pslverror，GE域TX为packet_valid/ready/packet[1023:0]/length[15:0]和done/error。udp_tx_arbiter.v两输入描述符含session[31:0]、ports[31:0]、peer_ip[31:0]、local_ip[31:0]、length[15:0]、packet[1023:0]，输出一份给MAC，完成只回原owner。资源描述符用length=32、packet高768 bit清零；低位字节0最先发送，与旧tx_header保持一致。

以上是包接口，不暴露游戏坐标。只有 owner 的 efinix_sapphire_adapter.v 增加管理地址选择和模块连线；A 可以提交最小测试 harness，但不改集成顶层。efinix_asset_network.v 的拆口由 A 完成，旧资源端口与寄存器 ABI 不变，既有资源测试必须继续通过。

## 6 软件与玩法合同

新增include/v3_control_protocol.h固定上述包/遥测序列化常量；include/net_control.h定义nc_input {uint32_t session, sequence, action_sequence, age_ms; uint16_t keys; uint8_t connected;}、nc_telemetry（上述27字段与有效性）、nc_device。接口为nc_init(nc_device*, uintptr_t apb_base)、nc_poll(nc_device*, uint32_t now_ms, nc_input*)、nc_try_publish(nc_device*, const nc_telemetry*, uint32_t now_ms)。nc_poll每次最多4包，nc_try_publish每次最多提交1份快照或优先ACK，均非阻塞，返回负值为错误、0为无进展、正值为有进展。nc_device保存接收会话/最新序号/租约与一份待发ACK和最新遥测，不使用无界队列。

新增 input_state.h/c：game_input {uint16_t held, pressed, released;}；input_update(game_input*, const nc_input*) 将序号/事件转成游戏输入，失联和过期清键。新增 replay_input.h/c：600 tick 的 u16 键位记录、seed、资源 epoch、逻辑初态和记录 CRC；replay_record、replay_begin、replay_next 的状态由调用方保存，完整记录不依赖 PC 文件才能继续运行。

R7 原始性能场景保持独立，不改其 seed=7、六种弹形、每八个对象一个 Alpha 光晕的规则与CPU基础绘图。新增 interactive_game.h/c 包装现有 bullet_state，不重写通用游戏引擎。game_update(bullet_state*, const game_input*) 为每步 1/60 s 的固定逻辑更新；game_build(const bullet_state*, uint32_t dst, int network, int glow, unsigned capacity, bullet_stream*) 生成原有 gpu_command 列表。实时模式禁止自动驾驶覆盖玩家坐标；固定步长在 GPU 卡顿时有上限追赶，网页/HDMI同时显示逻辑速度下降，不用多步跳帧隐藏丢帧。

原 bullet_step 如需支持输入，B 只在内部提取共享游戏更新并增加输入入口，旧入口和原基准输出必须逐 tick 相同。CPU与GPU比较执行同一录制序列、初态和资源版本，每 tick 的命令语义一致。GPU优化可以替换等价背景恢复/提交表示，但最终像素需与基础CPU路径一致；不能要求优化后命令数量与基础全背景路径相同。

实时游玩默认 GPU；比较模式暂停真人输入，播放同一600 tick记录或现有自动基准，CPU/GPU分时成绩保留在HDMI，完成后恢复实时游玩。组员 B 交付纯函数/可主机运行模块，负责人把它们接进 main.c。图像借鉴必须记录许可证和来源，不以“开源游戏”推断其美术资产可自由使用；不复制未经授权的植物大战僵尸原版素材。

新增素材变更通过 resource_manifest.json 描述尺寸、stride、格式、CRC、图集布局、许可和资源 epoch。优先沿用当前3104 B图集，新增后超过4 KiB则明确切换批次或走未缓存回退；两周不改GPU去兼容一个超大图集。改变背景或图集必须使两块缓冲的恢复历史失效。

## 7 GPU 优化选择与完成边界

先做兼容旧ABI的连续 Copy 专用通路。src/dst 字对齐、src_stride=dst_stride=width×2、长度为4的倍数且不重叠时，把多行展开为连续任务；其他情况保持旧DenseBlit回退。沿用256 beat和4 KiB切分，先限定一个未完成读事务和一个未完成写事务，通过有界数据FIFO解耦已存在的逐 beat 读写重叠。完成需要所有R和B返回；不能让后续Alpha提前读未提交背景。若收益不足，下一阶段才扩大在途窗口，并一起修改仲裁owner/credits，不宣称接入CDMA即可自动多在途。

背景按每块物理 back buffer 保存覆盖和resource_epoch，恢复旧覆盖后按原顺序画全部当前Sprite一次，包含光晕。模型成本同时计搬运字节、burst和新增命令；选16/32 tile与合并策略或全背景回退，不固定“最小面积就是最快”。CPU窗口、资源切换、异常、复位使两块历史失效。现有主机27000帧逐字节比较只验证这条算法可保持ROI像素，不代表硬件已提速。

可选紧凑实例前端是两周的伸展项，不挤占功能验收。数据仅由RISC-V生成，硬件只展开绘图描述。若第9天512档仍不达标，且命令构建加提交的非阻塞成本超过1 ms而硬件已有足够余量，允许用2天做受限APB流前端原型；否则继续Copy/恢复调参或封版，不开目的Tile新后端。

实例原型采用最多16个模板、16 B实例，四字依次为template_id[7:0]/flags[15:8]/alpha[23:16]/reserved[31:24]、dst_addr、src_offset、width[15:0]/height[31:16]。flags仅bit0表示有效Alpha，其他零；模板包含op、src_base、src_stride、dst_stride、最大宽高、key。16槽可覆盖六弹形、共享光晕、玩家和三个发射器，不假设8槽能放下所有纹理。CPU已裁剪，硬件检查offset+二维跨度、尺寸、DDR窗口和模板边界，保持原顺序，tag与原批尾完成接口一致。模板只能在队列空时更新。拒绝完整列表与中途错误不可无条件从头再放一遍，因为会重复Alpha；仅在确定未执行时回退，否则使目标历史失效并完整重建。

可选局部地址：0400 ID、0404 STATUS、0408 CONTROL、040c TEMPLATE_INDEX；0410～0428七个模板字段（op/base/src_stride/dst_stride/width_max/height_max/key）；0430～043c四个实例影子字，0440 INSTANCE_COMMIT，0444 BATCH_TAG。先单元展开比对后再修改Efinix2dGpuTop.scala地址分发。实例与旧命令互斥提交一批，所有批先等前批结束，防止顺序歧义。不存在新前端时驱动通过ID探测，使用原接口。

## 8 验收口径

一级目标为同版稳定512档60 FPS，并提升可见活动Sprite上限；这是目标，不是性能保证。1024是伸展测试档，2048仅在1024达标且内存容量检查通过后探索；两周不保证稳定1024/2048，更不承诺无限元素。

保留两套测量：冻结R7性能场景用于V2/V3架构比较；交互场景用于功能展示和其自身极限。画面、Alpha占比、尺寸或遮挡改变后，不能直接和旧R7数字计算加速比。枚举档位时同时报目标数量、真实可见数量、Alpha/Key数量和像素工作量。

稳定60定义为逐帧到达显示截止、missed_vblank=0、underflow=0、GPU错误=0。实际HDMI节拍略有误差，约60.1 FPS不是必须精确60.000；不能只看平均FPS或P5。统计PRESENT前平均/P95/最大、CPU逻辑/构建、提交阻塞、硬件busy、背景、字节、burst、FIFO峰值和显示最低水位，区分重叠与非重叠项。显示完整帧FPS受60Hz限制；优化成果主要体现为60FPS下更多可见Sprite和更大最坏帧余量。另可报告PRESENT前工作速率或纯渲染吞吐，但明确这是预算/吞吐指标，不把1000000除以busy_us当成HDMI实显FPS，也不关闭扫描制造高FPS。

第14天至少30分钟整机耐久，并做冷启动、完整复位、热重载、服务器缺席、断网、失焦松键和资源切换。网络开启相对关闭的GPU P95额外预算以0.25 ms为验收目标，超标先降遥测采样或修阻塞，不能用关掉输入完成“功能通过”。热重载下溢与两项旧SoC异常继续单独记录；未修复不得被总通过声明遮盖。

## 9 参考来源与创新表述

[verilog-axi CDMA](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_cdma.v)用于读写解耦与完成跟踪参考，MIT但仓库已停用维护；不整库移植。[LVGL刷新](https://github.com/lvgl/lvgl/blob/master/src/core/lv_refr.c)与[Khronos buffer age](https://registry.khronos.org/EGL/extensions/KHR/EGL_KHR_partial_update.txt)用于区域合并和物理缓冲历史。[iDMA](https://github.com/pulp-platform/iDMA)与[OpenGlory](https://github.com/egorxe/openglory)用于维度展开、有序命令思路，许可证分别核对；只借鉴思路不把参考实现标成自研。

[MDN SSE](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events)、[MDN失焦事件](https://developer.mozilla.org/en-US/docs/Web/API/Window/blur_event)、[Python HTTP服务器](https://docs.python.org/3/library/http.server.html)支持本地管理网页的实现选择。需要复制源代码时先固定commit并登记文件级许可；原生网页API不等于复制第三方库。

可争取的项目特色是“显示截止约束的连续二维搬运”“物理双缓冲epoch和碎片成本共同驱动的恢复策略”“真实输入记录驱动的公平异构回放和轻量网口遥测”。三者各有可核验的指标；DMA、Cache、SSE和脏矩形本身不是首创。
