# 游戏难度菜单与网页同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现HDMI/网页四档选择、网页开局、键盘飞行、死亡返回菜单和一键重选，不把菜单刷新当作游戏性能。

**Architecture:** Sapphire拥有MENU/PLAY状态及64/128/256/512映射；PC沿用资源服务和管理UDP桥接。新增有界GAME/GAME_ACK而不另建服务器；网页等待执行ACK及更新快照才确认状态，HDMI复用现有Fill/Copy和字形图集。

**Tech Stack:** RV32 C、Verilog、Python标准库、原生HTML/CSS/JavaScript；WSL GCC、Verilator/Icarus、现有Node测试、Efinity。

**Spec:** [game_menu_design_20261008.md](game_menu_design_20261008.md)。执行者须先完整阅读；本计划是待执行文档，不是开发或上板记录。

## Global Constraints

- 官方Sapphire、GPU100MHz、原GPU ABI/RTL后端、960×540 RGB565和1080p60 HDMI、vblank双缓冲保持。
- 等级1/2/3/4对应请求数64/128/256/512；固定seed7，冻结R7/bullet_step和基础CPU渲染保持。
- AGC1 version1/32字节、大端/CRC；AGT1 27数据字/128字节；KEYS掩码0xff、第三字0不变。
- GAME=4、GAME_ACK=5；START=1且level1～4，MENU=2且level0；request_id非零u32。
- status bit10=MENU、bit11=GAME_MENU_CAPABLE，允许掩码0x007f0fff；MENU同时PAUSED。
- 租约250ms、每轮最多4包、遥测5Hz；总控制最多60包/秒、GAME重试间隔至少50ms且总时限2s；HTTP体最多1024字节。
- 单所有者、单待执行请求和单最近结果，不扩大FIFO，不新增依赖；每个.v仅一个模块，vendor不改。
- 正常启动MENU；仅隔离V3_PROBE_FRAMES诊断构建可直接PLAY。保留全部边界检查和旧性能口径，不启用无收益候选。
- 游戏状态留现有私有DDR；4KiB栈不放命令流/游戏副本。RAM静态段加4096必须不超过126976字节。
- 每次构建用新目录，不覆盖release/官方Demo/合格BIT；仅合格候选可JTAG加载，不写Flash；未授权不推main。

## Review Focus

1. ACK已到而旧遥测晚到：只用严格新于snapshot_floor的快照确认场景；任务2、4、6验证。
2. 超时但实际已执行：网页显示未知，不自动重开；任务2、4验证重复/丢ACK。
3. 选档前持续按键/旧R、C事件：必须新零键快照解锁，保留已消费动作序号；任务3、4验证。
4. 死亡发生在追赶tick或比较回放：LIVE当tick回菜单，回放仍公平；任务3、6验证。
5. 半画面/统计污染/内存紧张：两缓冲完整后呈现，菜单无游戏FPS，预热也检下溢；任务5～7验证。

## 文件、依赖与执行约定

工作目录为当前隔离仓库D:/ZYNQ/smallproject/.worktrees/pango-riscv-cpu，沿用现有docs目录。以下路径均相对它。
依赖为：任务1→任务2/3/4；任务3→任务5；任务2～5→任务6；任务6→任务7，无相互等待。
每项先写失败用例、记录真实失败，再实现并跑到通过；某项失败只修该项，不反复重跑未变长仿真。没有工具或板卡时写清未验证，不能跳过验收宣称成功。
以下新签名是交付合同；实现细节沿用现有结构，不能另建一套抽象框架。每项提交前检查差异，git add仅列出的文件；提交不等于推送。

### Task 1: 固定跨语言协议与网络RTL合法包入口

**Files:** 修改sw/efinix_gpu/include/v3_control_protocol.h、sw/efinix_gpu/tools/control_gateway/protocol.py、board/efinix_ti60/rtl/net/control_udp_rx.v；测试sw/efinix_gpu/tests/test_control_gateway.py及scripts/test-v3-control-rtl.sh列出的既有testbench。不改变APB地址或描述符布局。

**Interfaces:** 消费既有`encode(kind, session, sequence, words)`/`decode(data)`；产出C常量V3_PACKET_GAME=4、V3_PACKET_GAME_ACK=5、V3_GAME_START=1、V3_GAME_MENU=2及Python GAME/GAME_ACK/GAME_START/GAME_MENU同值。GAME三个字为opcode/level/request_id，ACK三个字为request_id/result/snapshot_floor；结果0/1/2。

- [ ] 写`test_game_wire_contract`和RTL GAME合法性用例，断言：
  ```python
  assert len(p.encode(p.GAME, 7, 9, (1, 4, 11))) == 32
  assert p.decode(p.encode(p.GAME_ACK, 7, 9, (11, 0, 99))).words == (11, 0, 99)
  assert p.STATUS_ALLOWED == 0x007f0fff
  ```
  另断言START的level0/5、MENU的level1、id0、ACK result3、错误CRC/长度/未知type拒绝；RTL接收GAME但不接收板端专属GAME_ACK，旧HELLO/KEYS保持原字节。
- [ ] 运行`wsl python3 sw/efinix_gpu/tests/test_control_gateway.py`和`wsl bash scripts/test-v3-control-rtl.sh --scoped`；预期新常量/包入口未实现而失败，记录实际输出。
- [ ] 在上述定义/校验入口扩展枚举和字段约束，RTL只增加合法type/opcode/level/id检查，不绕开CRC/长度/来源检查。固定一组完整大端32字节golden供C/Python/RTL共用，避免各语言自证。
- [ ] 重跑同入口，预期退出0且新旧用例全部PASS；部署旧固件的Python能力门控留给任务4。
- [ ] `git add sw/efinix_gpu/include/v3_control_protocol.h sw/efinix_gpu/tools/control_gateway/protocol.py board/efinix_ti60/rtl/net/control_udp_rx.v sw/efinix_gpu/tests/test_control_gateway.py`，加实际修改的既有testbench；提交`feat: define bounded game control packets`。

### Task 2: 板端可靠执行槽、去重及完成ACK

**Files:** 修改sw/efinix_gpu/include/net_control.h、sw/efinix_gpu/src/net_control.c、sw/efinix_gpu/tests/test_net_control.c。

**Interfaces:** 消费任务1协议；产出`nc_game_command`，五个uint32_t字段session/sequence/opcode/level/request_id；`int nc_take_game(nc_device *d, nc_game_command *out)`返回1有请求、0无请求、负值参数错误；取出不提前释放未完成槽。`int nc_complete_game(nc_device *d, const nc_game_command *cmd, uint32_t result)`校验当前槽/会话，捕获snapshot_id为floor、作废未序列化遥测并排入ACK，返回0成功或负错误。`void nc_discard_pending_telemetry(nc_device *d)`仅清未提交快照、不重置全局snapshot_id。既有nc_poll/nc_try_publish签名不变。

- [ ] 增加`test_game_exactly_once`、`test_game_ack_floor`、`test_game_session_expiry`。关键断言：
  ```c
  assert(nc_take_game(&d,&cmd)==1);
  assert(cmd.opcode==V3_GAME_START && cmd.level==4 && cmd.request_id==11);
  assert(nc_complete_game(&d,&cmd,0)==0);
  assert(nc_take_game(&d,&cmd)==0); /* 同id同payload的新线序号重试 */
  ```
  真实MMIO后端断言ACK未在complete前发出、序号回显GAME、floor包含旧已构造快照；旧pending不晚获新序号。覆盖同id不同payload、旧id、序号回绕、槽忙、年龄251ms、过期/换session取消、keys清零但action_sequence不清、HELLO优先于GAME_ACK优先于遥测。
- [ ] 运行`powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly`；预期新接口/断言失败。
- [ ] 扩展nc_device固定槽及最近结果；合法GAME更新统一控制线序号/租约，按request_id独立去重。complete的失效旧session必须拒绝，不能确认旧操作；保留非阻塞四包预算。
- [ ] 重跑同入口，预期所有C/Python用例退出0；保留完整RX/TX golden结果，不只测结构体字段。
- [ ] `git add sw/efinix_gpu/include/net_control.h sw/efinix_gpu/src/net_control.c sw/efinix_gpu/tests/test_net_control.c`；提交`feat: acknowledge game commands after board execution`。

### Task 3: Sapphire菜单/游玩状态及输入隔离

**Files:** 修改sw/efinix_gpu/include/v3_runtime.h、sw/efinix_gpu/src/v3_runtime.c、sw/efinix_gpu/tests/test_v3_runtime.c；只在确需输入过渡清理时修改input_state.h/c及test_input_state.c，不能重置消费序号。

**Interfaces:** 消费任务1opcode与既有game_input；产出`enum { V3_PHASE_MENU=0, V3_PHASE_PLAY=1 }`、`enum { V3_MENU_BOOT=0, V3_MENU_DEATH=1, V3_MENU_REQUEST=2 }`；runtime增加phase/level/menu_reason/menu_enabled/await_neutral和uint32_t scene_generation/neutral_session/neutral_sequence。`unsigned v3_level_count(unsigned level)`返回64/128/256/512，非法返回0；`int v3_runtime_menu_init(v3_runtime *r,uint32_t seed,uint32_t epoch)`；`int v3_runtime_game_command(v3_runtime *r,unsigned opcode,unsigned level,uint32_t session,uint32_t sequence)`返回0已应用、1不允许、负值执行错误。既有init保留给冻结/诊断基线，advance/frame_done/status签名保持。

- [ ] 写`test_menu_levels`、`test_menu_death_stops_catchup`、`test_start_requires_new_neutral`、`test_menu_aborts_replay`：
  ```c
  assert(v3_level_count(1)==64 && v3_level_count(4)==512 && v3_level_count(5)==0);
  assert(v3_runtime_menu_init(&r,7,3)==0 && r.phase==V3_PHASE_MENU);
  assert(v3_runtime_game_command(&r,1,4,7,9)==0);
  assert(r.phase==V3_PHASE_PLAY && r.game.count==512);
  assert(v3_runtime_game_command(&r,1,1,7,10)==1);
  ```
  再覆盖同GAME序号零键不解锁、更新有效零键后才飞行、旧session/R/C不复触发；LIVE HP=0当tick停止、不后续自动重生；MENU的R/C忽略，R同档重置录制；CPU/GPU回放内死亡不跳菜单，MENU命令可取消任意模式。原600tick录制/CPU/GPU同输入同结果测试继续通过。
- [ ] 运行`powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly`；预期新API/状态断言失败。
- [ ] 实现上述API，scene_generation在START/R/死亡/MENU实际过渡时更新，重置逻辑积累/pending边沿而不重置input消费序号。分别记录启动/死亡/请求菜单原因并在相关用例断言。LIVE死亡检查置于追赶循环每个tick之后；回放按原录制步进。runtime状态返回MENU+CAPABLE+PAUSED，菜单的GPU timing有效位不置。
- [ ] 重跑同入口，预期全部PASS、冻结R7/交互像素回归不变；不改bullet_step以迁就测试。
- [ ] `git add sw/efinix_gpu/include/v3_runtime.h sw/efinix_gpu/src/v3_runtime.c sw/efinix_gpu/tests/test_v3_runtime.c`，只添加确实修改的输入文件；提交`feat: add board-owned difficulty menu state`。

### Task 4: 网关可靠命令及网页选择界面

**Files:** 修改sw/efinix_gpu/tools/control_gateway/gateway.py、sw/efinix_gpu/tools/control_gateway/web/index.html、sw/efinix_gpu/tools/control_gateway/web/dashboard.js、sw/efinix_gpu/tools/control_gateway/web/styles.css、sw/efinix_gpu/tools/control_gateway/fake_board.py；测试sw/efinix_gpu/tests/test_control_gateway.py、sw/efinix_gpu/tests/test_control_dashboard.js、sw/efinix_gpu/tests/test_control_dashboard_browser.js。

**Interfaces:** 消费任务1 Packet及既有GatewayState控制/遥测；产出`GatewayState.game(client: str, opcode: str, level: int, request_id: int, now: float=None) -> int`，HTTP状态400/409/503/202按设计；view增加game对象或null，字段request_id/opcode/level/state/result/snapshot_floor，state仅pending/await_snapshot/applied/rejected/unknown，后二字段未取得为null。`receive`/`next_packet`复用现有签名。JS导出`gameView(view)`返回{supported,phase,level,canStart,canMenu,pending}，phase为menu/play/unknown，level为1～4或null；按钮/KeyboardState仍在原boot中接线，不新建通用客户端框架。

- [ ] 增加`test_game_http_and_retry`、`test_game_ack_then_old_snapshot`及Node菜单测试，断言：
  ```python
  assert state.game('owner','start',1,11,now=now) == 202
  assert state.game('other','start',1,12,now=now) == 409
  assert state.view(now)['game']['state'] == 'pending'
  ```
  用已有fake clock/UDP后端构造真HELLO ACK、新鲜CAPABLE；ACK result0后旧floor快照不得applied，新快照才applied；2s无ACK转unknown、同id重试不重开、换session/失焦取消。校验bool冒充int、非法Origin/Host/token/body>1024拒绝，旧固件禁用但键盘保留，总发送≤60pps且零键心跳不饥饿。
- [ ] 运行`wsl python3 sw/efinix_gpu/tests/test_control_gateway.py`及`E:/node.exe sw/efinix_gpu/tests/test_control_dashboard.js`；预期新接口/状态失败。
- [ ] 实现/api/game、单pending及最近HTTP结果，最多每50ms重发一次同id/新wireseq。网页中文四卡及重选按钮仅根据新鲜板端状态显示；点击先零键获取控制，真正ACK后提交，不抢占；清浏览器按键、禁用重复点击，KEYS心跳保持零直到过渡确认。超时不自动重开。
- [ ] 重跑上述用例；浏览器测试用已安装验证环境Playwright，设置GATEWAY_TEST_PYTHON为C:/Users/fortiutde/AppData/Local/Programs/Python/Python39/python.exe，删除测试中的过期PYTHONHOME默认注入，端口由既有freePort分配。运行`E:/node.exe sw/efinix_gpu/tests/test_control_dashboard_browser.js`，预期真实DOM菜单/PLAY/死亡返回、键盘/冲突/失联全部PASS；依赖不存在须报告，不给网关新增依赖。
- [ ] `git add sw/efinix_gpu/tools/control_gateway sw/efinix_gpu/tests/test_control_gateway.py sw/efinix_gpu/tests/test_control_dashboard.js sw/efinix_gpu/tests/test_control_dashboard_browser.js`，检查未带运行日志；提交`feat: synchronize difficulty controls with board acknowledgements`。

### Task 5: HDMI静态菜单和两缓冲缓存

**Files:** 新建sw/efinix_gpu/include/game_menu.h、sw/efinix_gpu/src/game_menu.c、sw/efinix_gpu/tests/test_game_menu.c；修改Makefile源清单、scripts/test-v3-integration.ps1注册用例。不改CPU raster或中文字库。

**Interfaces:** 消费任务3 scene_generation及现有gpu_device、hud_command_stream、HUD_GLYPH_ATLAS_ADDR；产出`game_menu_cache`含uint32_t destination[2]/generation[2]和uint8_t valid_mask/network[2]，不含新命令数组。`void game_menu_invalidate(game_menu_cache *c)`；`int game_menu_draw(gpu_device *gpu,game_menu_cache *c,unsigned buffer_index,uint32_t destination,uint32_t generation,int network_ready,hud_command_stream *scratch,uint32_t poll_limit)`返回0成功、负值失败，缓存只有等待GPU绘制完成才有效。

- [ ] 新测试捕获实际提交命令，断言四卡坐标(96,144)/(496,144)/(96,288)/(496,288)、大小368×104，标签四个请求数正确；全部目的区域在960×540且顶部72行/Logo未被菜单覆盖。第二缓冲也必须绘制；相同generation/连接状态再次draw命令数为0；任一提交失败不标valid。
- [ ] 添加host用例后运行`powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly`，预期未实现函数失败。
- [ ] 复用Fill/Copy和两色英文/数字图集，利用调用者既有overlay scratch，顺序提交有界批次，不为菜单分配全屏RAM副本。连接提示更新仅脏区，首次各缓冲完整初始化；画面呈现由任务6统一管理。
- [ ] 重跑，预期PASS；命令mock还须断言现有GPU Copy/Fill/tag含义未变。菜单不用软件CPU渲染路径，不把菜单glyph计入游戏Sprite。
- [ ] `git add sw/efinix_gpu/include/game_menu.h sw/efinix_gpu/src/game_menu.c sw/efinix_gpu/tests/test_game_menu.c sw/efinix_gpu/Makefile scripts/test-v3-integration.ps1`；提交`feat: draw cached HDMI difficulty cards`。

### Task 6: 顶层接线、统计隔离和完整离线集成

**Files:** 修改sw/efinix_gpu/src/v3_demo.c、sw/efinix_gpu/include/v3_frame_stats.h、sw/efinix_gpu/tests/test_v3_frame_stats.c；新建tests/test_v3_menu_integration.c并注册scripts/test-v3-integration.ps1。复用真实runtime/net_control/menu与GPU MMIO测试后端，不能另写模拟状态机自证。

**Interfaces:** 消费任务2取出/完成/丢快照、任务3菜单初始化/命令/scene_generation、任务5draw；产出正常固件启动MENU与诊断独立PLAY，以及AGT1能力/状态/有效位。为真实顶层host测试仅提取最小过渡处理器：`int v3_apply_game_command(v3_runtime *r,nc_device *d,const nc_game_command *cmd)`声明在v3_demo.h，实现仍v3_demo.c；result转换0/1/负值→ACK 0/1/2。成功应用后才能complete，不允许ACK失败引起游戏重复初始化。

- [ ] 添加`test_real_menu_transition`、`test_menu_stats_invalid`：真正32B包→驱动→runtime→ACK，重复包不增加scene_generation；旧pending清除，后快照严格新于floor。START后CPU有效位/FPS为0，MENU requested/visible/Alpha/Key=0、GPU timing无效；R保留完整CPU成绩但stale，取消回放不发布部分成绩；两缓冲MENU→PLAY第一次完整背景恢复，不显示半绘制。
- [ ] 运行软件集成入口，预期新处理器/接线缺失失败。不可只做源文件文本检查代替上述真实链路测试。
- [ ] 在主循环poll后、advance前处理管理命令；scene_generation变化统一作废HUD/menu、统计窗口和旧pending快照。MENU仅执行必要缓存绘制/原vblank/5Hz遥测，不构建游戏命令；PLAY首帧完整背景恢复。GPU/PRESENT失败禁止半帧交换；诊断直接PLAY只在ProbeFrames显式构建。
- [ ] 运行一次`powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly`、一次`wsl bash scripts/test-v3-control-rtl.sh`及一次`powershell -NoProfile -File scripts/test-v3-integration.ps1 -RtlOnly -IcarusRoot C:/iverilog`，预期新旧用例PASS。若某入口工具不存在，记录缺项并解决，不盲用旧软件安装路径。
- [ ] 运行`powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/verification/v3/game_menu_20261008/normal`。预期完整RV32 ELF/BIN/HEX链接成功，text+data+bss+4096≤126976，堆栈警告视为失败；正常不带StartCount/ProbeFrames/ShadowSubmit。只检查诊断开关时另用新目录，不覆盖此输出。
- [ ] `git add sw/efinix_gpu/src/v3_demo.c sw/efinix_gpu/include/v3_demo.h sw/efinix_gpu/include/v3_frame_stats.h sw/efinix_gpu/tests/test_v3_frame_stats.c sw/efinix_gpu/tests/test_v3_menu_integration.c scripts/test-v3-integration.ps1`；提交`feat: integrate menu without contaminating rendering metrics`。

### Task 7: 候选工程门禁、JTAG验收及回退资料

**Files:** 修改sw/efinix_gpu/tests/test_board_render_phases.c；必要时提取include/render_phase_health.h及tests/test_render_phase_health.c并注册host入口；新建scripts/test-game-menu-board.ps1、docs/efinix_2d_gpu/game_menu_validation_20261008.md，验收后再修改README.md。不在此任务承诺512@60或V3完整耐久完成。

**Interfaces:** 健康门禁`int render_phase_health_ok(uint32_t under_before,uint32_t under_after,uint32_t hardware_error)`，相同计数且error0返回1，否则0；预热30帧和实测300帧都每帧检查。新board脚本参数`[string]$Bin,[string]$Bit,[string]$GatewayUrl='http://192.168.1.2:8765',[string]$OutDirectory,[switch]$LoadBit`；只显式LoadBit才编程位流，Bin/Bit/输出路径需检查，Flash操作不提供。

- [ ] 写健康门禁host断言：`assert(render_phase_health_ok(4,4,0)==1); assert(render_phase_health_ok(4,5,0)==0); assert(render_phase_health_ok(4,4,1)==0);`。历史非零计数作为初始基线，但预热新增下溢同样立即失败并保存帧日志，不能到采样后才发现；运行软件集成入口确认失败后实现并验证PASS。
- [ ] 用新目录运行`powershell -NoProfile -File scripts/test-efinix-board.ps1 -EfinityHome D:/efinity -OutputDirectory D:/efinity_builds/game_menu_20261008_r1 -Flow compile`。不传GpuRtlDirectory、不调用Copy候选专用test-v3-board-project.ps1；编译前逐项比对当前XML源清单与合格display_reset_20261006_r1，GPU差异必须为零，网络仅任务1的合法包扩展，复位修复不能丢。预期100MHz时序通过、资源适配、CDC无新增危险、编译退出0，记录源/BIT/BIN哈希；否则不上板。
- [ ] 板卡实际存在且网络/HDMI就绪后，保存旧网关启动参数/版本、旧合格BIT/BIN哈希和可用副本，启动新版服务；新脚本加载上述候选只用JTAG。禁止使用带过期硬编码BIT的旧-LoadBit封装。网页测试操作经实际/api/control获取token/所有权及/api/game，不模拟直接写状态。
- [ ] 四档分别验收：开机双端MENU→START→实际飞机输入→死亡返回MENU；R同档重开、网页重选、C比较/中止、失焦清键、断网零键继续/重连。原始串口/HTTP快照保存到OutDirectory；ACK和新快照两阶段一致，无重复开局、错误、预热/采样新增下溢。先功能验收，再隔离诊断各档30预热+300实测，报请求/可见/Alpha/Key/帧率和场景版本，不把MENU60Hz冒充游戏FPS。
- [ ] 请用户观察HDMI菜单、Logo/HUD无覆盖、双buffer无残影、飞机可控；网页的状态以板端为准。若失败，恢复合格BIT `D:/efinity_builds/display_reset_20261006_r1/outflow/efinix_2d_gpu.bit`、旧BIN `generated/verification/v3/submit_shadow_20261007/normal-default-restored/gpu_demo.bin`及原网关配置，记录失败而非抹掉；不写Flash。
- [ ] 验收报告区分已通过/未测/失败，README说明新旧网关兼容边界和未完成目标。`git add`仅本任务实际修改的测试、脚本、报告及README；提交`test: qualify synchronized game menu and document rollback`。无用户推送授权不远程发布。

## 自审与交接

2026-10-08计划自审：设计章节1～7分别覆盖于任务1～7；协议、输入隔离、执行后ACK、旧快照门槛、两缓冲、容量及回退均有归属。接口名/返回值以上述Interfaces为准；不扩展GPU架构、不重写游戏引擎、不引入循环依赖。现有SoftwareDriverSpec/PangoBringupSpec异常、V3完整消融/30分钟耐久及512@60/1024目标继续保留，不以本功能验收替代。

建议本对话直接按任务顺序实施（executing-plans），接口耦合紧且可沿用现有测试。用户审阅本计划并确认执行方式后才开始改功能代码；本计划的复选框均未完成，不代表已实现。中途若实际工程与接口假设冲突，先修订计划并说明影响，不悄悄删除验收要求。
