# AetherGX V3 两周开发计划书

供执行者使用：按日任务使用复选框记录进度；实施时使用 executing-plans 逐项执行，不在计划未确认时修改生产代码。每项先写能够暴露缺口的检查，再实现，再运行该项检查，保存结果并提交所负责文件。

**Goal：** 在官方 Sapphire 与现有 V2 上提高 GPU 稳定 60 FPS 的活动 Sprite 上限，并交付网口性能网页、键盘操控、可回放互动游戏。

**Architecture：** 负责人优化连续 Copy、物理双缓冲背景恢复与有条件的实例提交前端，完成唯一顶层集成。A/B 独立交付网口和游戏功能模块；PC 只提供素材、转发键位和显示遥测，Sapphire 处理协议、输入、游戏逻辑和命令，AetherGX 执行渲染。

**Tech Stack：** Chisel 7.7.0、Scala 2.13.18、单模块 Verilog、现有 Sapphire C/BSP、Python 标准库、原生 HTML/JavaScript、既有 Efinity/Verilator 与软件黄金模型。

**Spec：** [V3 架构与固定接口](v3_interface_design_20261001.md)。本计划的 Word 版附有该接口全文，读者不需要从聊天记录推断端口和协议。

日期从 2026-10-01 至 2026-10-14；若实际开工日晚于10月1日，整体顺延，依赖关系不变。两周是 V3 开发窗口，不等于比赛截止日期，后续剩余时间留给验收、修复和答辩。

## 1 全局约束

- 官方 Sapphire 和 GPU 均保持100 MHz；不改CPU微架构，不加入CPU专属绘图优化，不人为降速。GPU专属驱动/命令准备优化属于负责人GPU线。
- 保持960×540 RGB565、1080p60 HDMI、vblank双缓冲及Copy/Fill/Key/Alpha/Sparse；不通过减画质、关Alpha、减可见元素或停止扫描提速。
- 合法DDR窗口0x02000000～0x10000000，右端不含；A/B=0x02000000/0x02200000，stride=1920 B；新增内存区必须有边界断言。
- 保留旧APB ABI、ASST协议、既有资源服务器、诊断入口和CPU基础绘图。每个.v一个模块，官方vendor只读。
- 功能组只提交自身模块、资源和独立检查；main.c、efinix_sapphire_adapter.v、板级源清单与正式候选由负责人统一修改。不能用组员分支中的临时顶层覆盖主线。
- 实时GPU游玩与公平CPU/GPU回放分开；两者均保留CPU/GPU成绩和来源标识。新画面不得覆盖冻结R7架构比较场景。
- 仿真能定位的先仿真，不为每个小变化生成位流；上板只对专项正确且综合/时序合格的候选进行。默认JTAG，不写Flash。
- 第12天起停止新增高风险架构，收尾和验收优先。没有独立测出的收益不能写成已实现成绩。

## 2 自检重点

1. 输入乱序、断网、网页失焦或CPU慢窗口后，不能保持旧移动键；A第3/5天、B第2/4天覆盖。
2. ASST和控制共用接收RAM及TX，不能字节混包、死锁或把控制写进资源；A第2/3天和负责人第10天覆盖。
3. 同一物理缓冲历史失效时不能用另一块历史或旧背景，Alpha必须只画一次；负责人第6/7天覆盖。
4. GPU描述符被部分执行后报错，不能从头重播Alpha；负责人第4天及可选第11天覆盖。
5. 新素材、遥测、输入或人数改变后不能用不等价画面声称加速，也不能只用平均FPS掩盖错过刷新；B第6天、负责人第12/14天覆盖。

## 3 起点和选型

V2测量基点85b7dc0。9/30 R7 512档PRESENT前平均19.263 ms、最大20.855 ms，仍30 FPS；60 Hz预算约16.67 ms。背景Copy约7.6 ms、命令构建约3.101 ms；背景占场景DDR读约97.7%、写约94.5%。提交压力与GPU busy互相重叠，不把时间直接相加。此前已有逐beat读写重叠、256 beat、FIFO、4 KiB纹理Cache，不重复包装为首次实现。

主方案是连续Copy小改加GPU背景恢复算法，保持现有后端和CPU。仅挂通用CDMA可能被当前仲裁/完成串行限制，不作为两周承诺；完整目的Tile后端工期更长，留到后续。如果第9天实测仍指向命令前端，再进入已定义合同的受限实例原型，不因“现代GPU都有它”直接开工。

参考 [verilog-axi CDMA](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_cdma.v) 的解耦机制、[LVGL区域合并](https://github.com/lvgl/lvgl/blob/master/src/core/lv_refr.c) 和 [Khronos物理buffer历史](https://registry.khronos.org/EGL/extensions/KHR/EGL_KHR_partial_update.txt)。引用、许可与初步像素检查见前序调研，不整库导入。

## 4 两条线和文件归属

性能集成线只由负责人实施。功能线内A负责Verilog网口与PC工具，B负责C语言逻辑和画面；A/B可以协作，但不能修改负责人模块。以下路径均相对仓库根；“新增”是计划创建，不表示文件当前已存在。

### 4.1 负责人 GPU与唯一集成入口

- 新增 chisel/src/main/scala/gpu/CopyStreamEngine.scala：输入已经验证的Copy描述符与AXI读写握手，输出顺序数据和完成/错误；仅处理对齐连续子集。依赖原AXI类型、Burst切分和QoS；输出接DenseBlit的派发/完成选择，不另开未经仲裁的DDR端口。
- 修改 DenseBlitEngine.scala、RenderEngine.scala：选择专用Copy与旧通路，保留后续Key/Alpha的依赖和tag完成语义。必要时修改AxiReadEngine.scala、AxiWriteEngine.scala，仅用于已确认的受限流水；不先重构全部仲裁。
- 新增 sw/efinix_gpu/include/gpu_damage.h、src/gpu_damage.c：输入backbuffer标识、epoch、旧覆盖及当前命令；输出背景恢复Copy列表和代价，全部当前Sprite仍按原顺序绘制。依赖gpu.h/gpu_command，不依赖网络或interactive_game.c；gpu_damage_plan返回非负恢复条数或负错误，gpu_damage_invalidate使A/B同时失效。
- 修改 src/perf_demo.c，必要时修改src/gpu.c：仅GPU路径采用恢复列表和更轻提交；输入旧gpu_command流，输出等价显存结果/计数。纯CPU路径保持原状。
- 条件新增InstanceStream.scala、include/gpu_instances.h、src/gpu_instances.c：输入16模板/16 B实例，输出原渲染命令；仅第9天判定后执行。依赖冻结合同和现有验证器，不依赖组员游戏实现。
- 修改 main.c、Efinix2dGpuTop.scala、efinix_sapphire_adapter.v、工程XML和源清单：输入已验收模块，输出唯一可上板顶层、正常固件和诊断固件。负责人拥有所有共有文件的合入权。
- 新增测试 CopyStreamSpec.scala、tests/test_gpu_damage.c，以及条件测试InstanceStreamSpec.scala；新增 scripts/test-v3-gpu.ps1 汇总定向检查；测量脚本扩展 tools/collect_bullet_evidence.py。输出证据放 docs/efinix_2d_gpu/evidence/v3/，正式候选放 release/v3/，不修改release/v2。

Scala文件所在根为chisel/src/main/scala/gpu/，其测试根为chisel/src/test/scala/gpu/；C文件根为sw/efinix_gpu/。后续按天表中的简称沿用本节完整路径。

### 4.2 组员A 网口与网页

- 新增 board/efinix_ti60/rtl/net/udp_payload_router.v：完整UDP字节流输入，按magic输出asset/control两条原样流；未知包排空。依赖现有wrapper的rx长度/last，不改vendor MAC。
- 新增同目录 control_udp_rx.v：输入32 B AGC1流，输出完成且CRC正确的packet/时戳，坏包输出drop计数。依赖协议合同，不解析游戏坐标或生成GPU命令。
- 新增同目录 net_control_bridge.v：输入完成管理包、APB读写及两时钟复位，输出Sapphire接收快照、受保护管理TX与状态。复用pixel_async_fifo；输入RX过期信息可供C判断，不在RTL运行玩法。
- 新增同目录 udp_tx_arbiter.v：输入资源/管理描述符，整包轮转发给MAC，done/error回原owner。依赖wrapper ready/done；绝不在同一包中途换owner。
- 修改同目录efinix_asset_network.v和efinix_ge_mac_wrapper.v：前者拆出共享描述符/RX口，后者增加32/128 B有界发送长度和缓存；资源GET仍32 B，旧APB/Asset DMA侧不变，保持原测试可用。不做无界大通用发包引擎。
- 新增 sw/efinix_gpu/tools/control_gateway/gateway.py、protocol.py：HTTP/SSE、UDP转发和固定包编解码。输入网页键掩码及板端遥测，输出键包/SSE；不导入游戏模块、不处理资源像素。依赖标准库和第1天合同，不等RTL上线。
- 新增该工具下 web/index.html、web/dashboard.js、web/styles.css：展示两组FPS、Sprite/Alpha数、分段耗时、网络/错误/下溢、数据是否过期；采集键状态。输入SSE/用户键盘，输出同源POST，无游戏模拟或帧渲染。
- 新增 tb/verilog/tb_net_control.sv、sw/efinix_gpu/tests/test_control_gateway.py、scripts/test-v3-control-rtl.sh、scripts/run-control-gateway.ps1：独立检查和本地启动；启动脚本不杀未知进程、不更改防火墙或网卡配置。交付 docs/efinix_2d_gpu/v3_control_usage.md。

### 4.3 组员B 输入逻辑与画面

- 新增include/v3_control_protocol.h、include/net_control.h、src/net_control.c：输入管理APB包与已有性能快照，输出nc_input和完整128 B遥测；非阻塞，每次轮询最多4包/发布最多1包。使用gpu_regs中的基地址，不重新创建一套地址空间。
- 新增 include/input_state.h、src/input_state.c：输入有效nc_input，输出game_input的held/pressed/released；失联清键、事件去重。可单独主机运行，不依赖A的RTL。
- 新增 include/interactive_game.h、src/interactive_game.c：输入游戏状态与game_input，输出移动/射击/碰撞/重开状态及原gpu_command流。复用R7，不移植完整商业游戏；必要时修改bullet_demo.c/h增加输入入口，旧自动基准逐tick不变。
- 新增 include/replay_input.h、src/replay_input.c：输入真实每tick按键、seed、epoch与初态，输出600tick记录与可重置回放。CPU/GPU消费同记录，网络断开后记录仍可用。
- 新增 tools/build_interactive_assets.py、sw/efinix_gpu/assets/interactive/resource_manifest.json 和 LICENSES.md，以及实际使用的rgb565资源：输入有许可素材，输出尺寸/CRC/epoch/资源清单。继续使用既有asset_server.c，不改ASST来迁就游戏。性能模式沿用R7背景/图集；展示模式允许独立素材。
- 新增 tests/test_net_control.c、test_input_replay.c、test_interactive_game.c 和 scripts/test-v3-game.ps1；交付 docs/efinix_2d_gpu/v3_game_usage.md。可以修改HUD的内容/布局模块，但不修改CPU绘图算法、gpu.c、main.c或背景恢复模块。

## 5 第1天 冻结合同并能独立开工

- [ ] 负责人：登记源码/位流/正常固件/资源哈希和R7测量入口；提交 docs/efinix_2d_gpu/v3_baseline_manifest.md。核查新增管理0x0300与条件实例0x0400解码；本天不改CPU和画面。输入为现有基线，输出可复现清单。
- [ ] A：按接口合同写protocol.py、tests/test_control_gateway.py，提交包黄金向量与最小假板回传器，向量放tb/vectors/v3_control_packets.json。覆盖32 B输入/确认、128 B遥测、大小端、CRC、坏长度。A的假板仅回显输入/遥测，不计算游戏。
- [ ] B：写v3_control_protocol.h、net_control.h和 tests/test_net_control.c 的寄存器桩；提交input_state.h、interactive_game.h、replay_input.h的完整类型和声明。用A向量对照；若A尚未提交，按合同自己生成，合入前逐字节交叉比较，禁止等对方实现。
- [ ] 三人确认合同及分支：A-work/B-work只提交功能自有文件，负责人从main建立或复用codex/前缀集成分支。接口提交先落主线，后续改接口需一起更新向量/两端版本。

验收：Python和C各自编码相同字段得到相同32字节；APB与内存区没有冲突；三个角色各有无需别人实现即可运行的检查。

## 6 第2天 连续Copy测试和输入基本模块

- [ ] 负责人：新增CopyStreamSpec.scala，先使缺失专用通路的目标检查失败；覆盖连续/跨4 KiB/256 beat、零尺寸、非连续回退和非重叠限制；开始CopyStreamEngine.scala。输入为旧Copy语义，输出可比较的写地址/字节与完成tag；只依赖第1天基线。
- [ ] A：实现udp_payload_router.v、control_udp_rx.v及tb_net_control.sv的RX部分；测试ASST包头四字节回放、未知magic、短包、CRC错、last错、下游阻塞后下一合法包恢复。源流与asset输出必须逐字节相同。
- [ ] B：实现input_state.c与test_input_replay.c中键状态部分；测试上下反向键、重复action、序号回绕、失联清键和过期包。实现net_control.c RX侧，对寄存器桩每次最多读取4包；不阻塞等数据。

验收：GPU旧路径像素不变；控制错误不污染ASST；独立输入解析返回正确held/pressed/released。

## 7 第3天 Copy接入与网口包级仲裁

- [ ] 负责人：接入DenseBlit/RenderEngine选择与受限FIFO，维持一个未完成R/一个未完成W上限；记录AXI空洞、FIFO峰值和完成先后。不修改DdrQosArbiter的owner体系。
- [ ] A：实现net_control_bridge.v、udp_tx_arbiter.v，拆出efinix_asset_network.v共享口，wrapper增加32/128 B限定长度。测试两个时钟异步、时戳跨域、任一复位、CPU不读、输入FIFO满排空、TX忙拒绝、两个owner同时请求和完成错误路由。
- [ ] B：实现net_control.c的握手确认和完整快照TX及nc_try_publish；伪TX繁忙时立即返回，不混不同时间的性能字段。完成test_net_control.c，测试读八字期间新包到达不撕裂快照、未写齐32/128 B不能提交。

验收：Copy的tag不能早于全部B；资源和控制不混包；管理TX不要求asset_active且不会改变原ASST事务。

## 8 第4天 Copy错误恢复与可玩逻辑

- [ ] 负责人：Copy随机AXI反压、R/B错误和复位检查，源地址/目的地址非法拒绝，后续Alpha只能在前Copy完成后启动。修改范围仅专项通路；将通过的定向记录写入evidence/v3/copy/。
- [ ] A：实现gateway.py的UDP、会话握手、SSE和POST端点，绑定127.0.0.1；测试另一Origin/无令牌POST拒绝、JSON过大/坏键掩码、只允许配置的板IP、线程慢客户端不阻塞UDP。
- [ ] B：实现interactive_game.c及test_interactive_game.c；玩家坐标由按键更新，复用碰撞/HP/光晕/Key绘图，慢速/射击/重开由Sapphire决策。测试无按键不自动驾驶、失联不继续走、重开仅一次、裁剪不越界、旧R7 replay输出不变。

验收：硬件错误不能被软件从头重放Alpha；PC只传键；逻辑模块在主机测试中可玩但不接生产main。

## 9 第5天 首轮GPU候选和网页

- [ ] 负责人：仅对Copy专项通过的候选生成拆模块RTL并综合/时序；检查100MHz、无负裕量及资源变化。上板同R7、正常入口，测背景/HUD Copy与完整帧，保存原始日志/哈希。若无净收益或出现下溢，保留旧路径，不将候选替换基线。
- [ ] A：完成index.html、dashboard.js、styles.css；假遥测显示有效/CRC错/过期状态，键盘最多一个在途POST并最新状态覆盖；blur/关闭/断网后网关250ms清键。实现run-control-gateway.ps1，启动后不修改系统网络设置。
- [ ] B：实现replay_input.c和记录600tick的主机检查；两次同输入重建相同状态与命令语义。CPU慢回放不使用新真人键，不新增CPU绘图优化。

验收：Copy收益是同入口实测，不以burst理论降幅冒充FPS；网页和回放均可独立演示，不依赖GPU新硬件。

## 10 第6天 GPU背景恢复与素材交付

- [ ] 负责人：新增gpu_damage.c/h、test_gpu_damage.c，复用现有研究探针的正确性规则，但正式模块不直接依赖probe_damage_tiles.c。输入每块backbuffer历史和当前流，输出恢复列表；包含Alpha旧足迹、HUD裁剪、CPU覆盖/背景换代两块失效。先以16/32tile、0/2/4间隙和全背景做黄金像素比较。
- [ ] A：完善test-v3-control-rtl.sh，运行原test-v2-network-rtl.sh；提交对接README与源码清单，保留旧MAC资源测试harness。先用RTL假CPU/假MAC验证不抢共享顶层。
- [ ] B：交付build_interactive_assets.py、manifest和LICENSES，沿用原接口导出RGB565；测试图集不超过4KiB或明确未缓存回退、资源CRC/epoch和地址跨度。优先借鉴许可明确的效果和素材，不新写图形引擎。

验收：GPU恢复ROI逐字节相同，两块历史不能互用；素材未被完整校验前不能可见；A模块单独通过并可交负责人集成。

## 11 第7天 成本模型与组员模块首交

- [ ] 负责人：在旧后端或Copy候选上测恢复矩形/短burst/命令固定成本，gpu_damage_plan按实际系数选择恢复或全背景；容量不足、CPU窗口后失效、异常皆回退完整重建。不把额外Copy命令忽略。接入perf_demo.c的GPU路径，CPU仍全背景。
- [ ] A：提交网口RTL、PC工具、网页、独立检查及v3_control_usage.md到A-work，写明文件哈希/所用向量和启动参数；未知设备、坏包、包洪泛仅丢弃计数，不长时间等待。
- [ ] B：提交驱动、输入、游戏、回放、素材及v3_game_usage.md到B-work；用APB寄存器桩完成全部功能检查，提供固定键轨迹。源码不能调用PC游戏服务或GPU专属恢复函数。

验收：两组功能模块可以在不存在新GPU时独立检查；负责人GPU可以在不存在新网口时独立检查。此日是首个集成依赖点，不是所有人此前都等顶层。

## 12 第8天 GPU恢复板测和离线整合

- [ ] 负责人：先保存独立GPU候选成绩，再合入A/B自有模块；修改efinix_sapphire_adapter.v管理地址选择、main.c轮询/遥测/模式、工程源清单和脚本，不覆盖vendor。离线检查完整资源→输入→逻辑→绘图合同。
- [ ] A：配合实际APB/TX连线，保持已冻结接口；用假板测完整128 B快照原子发布、坏CRC拒绝、500ms无更新标过期，检查浏览器不开启时零输入且不持续发送。
- [ ] B：配合集成器使用nc_poll、game_update、replay接口；检查模式切换导致背景历史失效，比较回放初态恢复，输入录制仅在逻辑tick边界采样。HUD状态标出实时/回放/过期CPU值。

验收：所有新模块关闭时R7旧基线仍运行；开启背景恢复与完整背景的像素等价；组员不回写负责人的顶层。

## 13 第9天 同版瓶颈复测和取舍

- [ ] 负责人：同版冻结R7测32/64/128/256/512，逐档不少于300GPU帧；分别记录构建、提交阻塞、busy、背景、PRESENT前分位/最大、miss和下溢。探针正常/诊断分开，保留纯CPU成绩。
- [ ] 负责人：写v3_decision_day9.md。只有“512仍不达标，构建+非阻塞提交超过1ms，且GPU后端有可用余量”才选择第10/11天受限实例原型。硬件busy仍超过预算则不做实例，继续Copy/恢复参数和必要局部流水；不启完整Tile后端或多ID仲裁。
- [ ] A：关闭网页/开启网页/模拟慢浏览器三组离线压力，遥测始终有界丢旧，网络数据不得阻塞渲染线程。核对资产服务器8080、管理8090、HTTP8765可同时启动。
- [ ] B：对固定600tick录制进行CPU/GPU语义和最终像素检查；素材epoch改变使回放拒绝旧资源或重建正确版本。锁定首版互动玩法，不继续扩展无关剧情/大型场景。

验收：有实际主瓶颈和明确下一任务，不因为“帧率感觉没变”直接加Cache。512目标未达必须保留失败边界。

## 14 第10天 网口与互动上板以及条件实例前端

- [ ] 负责人：网口专项与离线联合通过后，生成功能集成候选，JTAG上板检查遥测、键盘→Sapphire反应、断网继续GPU游玩、资源CRC和HDMI两组成绩；测管理开/关扰动，不先优化CPU。
- [ ] 负责人：如第9天选择实例，新增InstanceStreamSpec.scala/InstanceStream.scala与gpu_instances.h/c的原型，先比较展开命令逐字段相同，旧ABI可回退；否则本项替换为Copy/恢复的有证据参数调整，不创建空壳实例文件。
- [ ] A：网口连通、ARP/PHY稳定/服务器未启动/资源与控制并行发送检查，网页导出原始遥测CSV。浏览器键入不生成坐标，断连250ms后零键状态可核验。
- [ ] B：玩家方向、慢速、射击、HP碰撞、重开、进入比较/返回游玩检查。对游戏错误修逻辑；不能改变冻结R7性能场景掩盖GPU问题。

验收：可用真实键盘进行互动；Sapphire在日志中给出输入序号及反应tick。输入反应目标为本地网口无丢包时P95≤100ms，记录端到端条件，未达不虚称达标。

## 15 第11天 条件原型验收和交互恢复

- [ ] 负责人：实例分支覆盖模板界限、offset溢出、裁剪、队列满、批尾tag、busy模板写拒绝、混合旧/新批次的顺序和部分执行错误；中途错误完整重建而非重放Alpha。仿真无净前端收益或时序不合格即不合入正式候选。
- [ ] 负责人：无实例分支仅验证第10天定向调整的净收益和最坏帧，不新增未经测量的GPU结构。
- [ ] A：热重载/复位/网页重连、旧session/乱序包、多个客户端竞争及控制通道洪泛；对溢出采用排空丢弃计数，保持资源和TX可以继续完成。网页不能混用不同snapshot的字段。
- [ ] B：600tick录制、相同seed/epoch的CPU与GPU对比、重开和暂停恢复；同图、同逻辑，只换渲染后端。调HUD标签/美术，不能改变测量公式。

验收：可选原型没有抢占必须功能的交付；启动/恢复异常有记录，不以一次完整复位成功宣称热重载问题消失。

## 16 第12天 扩档和功能冻结

- [ ] 负责人：正式候选冻结GPU结构，先测当前稳定上限，再尝试1024。扩容bullet_state/stream时检查BSS/栈/命令容量/图集，保持光晕比例和可见工作量；CPU绘图仍基础配置。1024达标才探索2048；失败时记录瓶颈，不减少可见元素冒充成功。
- [ ] A：完成网页界面和键位说明，显示真实visible而非仅requested、GPU/CPU数据年龄、背景时间/构建/阻塞、加载回退、下溢/错误。禁止每帧串口打印/网络阻塞采样。
- [ ] B：展示画面和游戏逻辑冻结，提交来源许可、资源哈希、测试轨迹，独立包可由旧GPU渲染。借鉴现有素材/效果，画面服务于Key/Alpha/高负载互动展示。

验收：无进一步大型架构需求进入两周必交；高清场景与冻结R7的数字分别报告。

## 17 第13天 回归与极限证据

- [ ] 负责人：同版关闭/开启连续Copy、背景恢复、条件实例做消融；像素一致且测真实净收益，避免收益直接相加。保存每档真实可见数、Key/Alpha数/像素、完整帧与最坏帧、扫描最低水位及资源/时序报告。
- [ ] A：长时间网页、慢连接、断网重连和坏/过时数据检查；输出v3_control_usage.md最终参数、错误含义、只本机开放的安全边界。
- [ ] B：独立回放/正常游玩/资源更换检查，确认旧输入不能控制新会话、旧epoch不会出错；输出v3_game_usage.md的键位、模式、资源更新方式和CPU/GPU公平条件。

验收：已知SoftwareDriverSpec/PangoBringupSpec旧异常独立列出，不把定向GPU/网口通过写成全项目无异常。

## 18 第14天 两周封版

- [ ] 负责人：至少30分钟GPU高负载互动加遥测耐久，做冷启动、完整复位、热重载、缺服务器、断网继续和比较切换。零underflow/错误/missed_vblank的最高档才记稳定60上限；异常候选不封为最终合格。
- [ ] A：运行仅按文档启动资源服务与控制台的复现，验证失焦/关闭浏览器松键，保存网页遥测导出，提交最终独立功能包。
- [ ] B：运行录制输入的CPU/GPU同段回放，保持基础CPU绘图及屏幕两组结果；提交逻辑/画面模块、素材和完整许可。
- [ ] 负责人：生成release/v3/README.md、SHA256SUMS和对应位流/固件/资源/源码提交清单；更新根README的V3状态，明确已达/未达、稳定极限、创新证据及旧异常。三人提交由负责人审查整合，推送需按实际用户授权，不在计划生成阶段自动执行。

验收：V3功能闭环、成果可复现且无夸大。若512@60未达到，两周交付优化效果和实测上限，并给下一周明确剩余瓶颈，不把“目标”改写成“完成”。

## 19 独立检查命令和交付标准

负责人交付scripts/test-v3-gpu.ps1，入口为 powershell -File scripts/test-v3-gpu.ps1；内部运行CopyStreamSpec、test_gpu_damage.c黄金比较、现有WordKey/TextureCache与受影响完成/仲裁定向测试，条件实例只有实现才加入。脚本输出每项PASS/FAIL与证据目录；两个历史SoC异常不混进定向通过统计。可直接在chisel目录运行 sbt "testOnly gpu.CopyStreamSpec"。

A交付入口：wsl bash scripts/test-v3-control-rtl.sh；它以现有Verilator流程编译tb_net_control，并覆盖全部新增.v，随后运行原资源测试。PC检查：python sw/efinix_gpu/tests/test_control_gateway.py，使用当前可用Python标准库，无额外框架。假板模式必须有显著标签，不能被当成板端实测。

B交付入口：powershell -File scripts/test-v3-game.ps1；使用现有C测试编译方式，运行test_net_control、test_input_replay、test_interactive_game，严格警告和失败非零。检查软件包不需A的RTL、不需板卡、不需负责人的新DMA。

每个提交附修改文件、输入输出变化、运行命令、结果、源commit和已知问题。先新增会失败的测试并确认失败原因，再实现到通过；不为相同未修改候选重复长仿真。共享文件由负责人单独合入，解决真正依赖后再做整机测试。

## 20 无循环依赖的交付顺序

依赖顺序为：固定协议/寄存器/原GPU ABI → A网口与网关、B驱动/逻辑、负责人GPU各自独立检查 → 第7天模块首交 → 第8天唯一顶层离线集成 → 第10天功能上板 → 同版性能/公平回放 → 第14天封版。

负责人Copy与背景恢复只消费原gpu_command，不等待新游戏；B的game_build只输出原gpu_command，不等待新DMA；A的网关只消费固定管理包，不等待游戏坐标；B的驱动用寄存器桩，不等待RTL。互相调用仅由负责人main/SoC胶合，接口定义是共同输入，不是另一组实现输出。A/B首交晚于第7天时，GPU线继续用R7，功能线保留假板/寄存器桩，整机验收顺延而不是绕过缺项。

只有“集成需要独立模块交付”和“封版需要集成结果”这类单向依赖，没有“先完成顶层才能开始写模块，再等待模块完成顶层”的循环。临时harness、寄存器桩和假板不进正式发布。

## 21 两周完成结果和后续边界

必须结果：网口性能网页和键盘互动闭环；官方Sapphire保持游戏逻辑责任；可录制回放的CPU/GPU屏显对比；至少一种同画面、同负载、有净收益的GPU优化；真实稳定60极限与失效边界；源码/位流/资源许可和哈希齐全。

性能愿景：争取512稳定60并向1024扩展。完整多在途CDMA、目的Tile合成器、超频、USB Host、SD卡/音频和多场景大地图不属于两周必须结果。不能用创新数量代替正确性与性能证据。

完整架构合同见相邻v3_interface_design_20261001.md；Word版附录包含全文，模块签名、管理包、遥测字段、地址、错误与回退以该版本为准。
