# V3 组员 B 游戏、输入回放与资源交接

## 当前状态补记（2026-10-07，main b3fc15d）

下面 10/05 独立包说明保留为历史。负责人已经将 A/B 接入生产互动候选，并完成第12天冻结；当前应使用 `v3_runtime`，而不是重新拼一个模式机。当前硬件保留旧GPU、实例原型关闭、正常启动64、对象容量512；256只有300帧短测通过，512仍约30FPS，1024完整固件RAM超限。详见 [冻结结论](v3_freeze_20261007.md)。

**重要更正：回放期间继续 `nc_poll` / `input_update`，返回LIVE不能清零仍有效会话的输入去重对象。**负责人已修正这条旧集成建议，否则持续按住R/C会变成新事件而重触发。`v3_runtime` 保存现场、逐tick录制、封存600步、先CPU后GPU回放、恢复现场并清零墙钟积压；真人输入只更新去重状态，不进入回放。需要重新初始化的是真正断开的新会话/失效状态，不是每次LIVE恢复。

### A/B 第13～14天离线收尾

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-ab-closeout.ps1
```

原生Windows入口，不需要WSL；四个工具路径均可参数覆盖。每次创建新的 `generated/verification/v3/ab-closeout-<时间>` 目录；指定 `-Out` 时必须不存在。只运行软件/本机临时端口服务，不打开COM/JTAG、不加载固件、不改变release，不重跑未改RTL。输出包含各检查日志、RV32对象/栈报告和 `receipt.json`（实际源码SHA256及离线资格标签）。与原 `test-v3-game.ps1` 分工：后者提供像素/RTL资源回放，这里聚焦已集成输入/模式的生命周期，不复制整套像素长测。

新检查直接使用实际 `net_control / input_state / v3_runtime / game / replay`：

- 64/256/512三档各36,000次计划内LIVE更新，合计108,000；另18次返回LIVE后的更新，共108,018次。不是连续墙钟30分钟。
- 每档6轮、共18轮CPU/GPU各600tick，额外21,600次回放更新；每步按规范字段比较完整对象状态、全部命令字段与Alpha计数，不依赖结构体padding，不声称本轮重测像素。
- R长按、回放中真人R/C、LIVE恢复不重触发、现场保存、epoch更换/旧回放拒绝、250/251ms释放边界、退休/新会话与旧KEYS隔离，时间/序号跨32位回绕。
- 8个严格C套件、Node网页行为、Python网关/采集/方向证据/资源/三服务并存及脚本失败保护；6个生产模块RV32编译。1024仅独立主机容量，不作为完整固件内存或板测通过。

[实施与核对记录](v3_ab_closeout_20261007.md) 列出准确结果和未完成硬件项。负责人仍需最终综合资源/时序、消融矩阵、CPU慢回放、离线回退/断网/恢复与真实30分钟耐久、输入P95及遥测扰动P95。工具只采集或检查证据，不自动升级为V3封版资格。

## 10/05 原始功能包说明

源码基点 `main 79a0b7f`，实际执行日期 2026-10-05，交付分支 **A-work**（用户要求 A/B 一并交付）。依据 `v3_two_week_plan_20261001.md` 与 `v3_interface_design_20261001.md`。以下是独立功能包和离线证据，**尚未接入生产 main/SoC，不是可烧录 V3 固件，不代表已达 512@60**。

## 模块与调用

加入固件候选的软件文件：`src/net_control.c`、`input_state.c`、`interactive_game.c`、`replay_input.c`，以及对应头文件和 `v3_control_protocol.h`。驱动还链接既有 `asset_protocol.c` 的 CRC。本次允许修改的旧文件只有 `bullet_demo.c/h`：增加手动坐标及友方弹入口，原 `bullet_step`、`bullet_build_frame` 继续使用冻结 R7 规则。CPU 基础绘图、GPU 驱动、背景恢复与 `main.c` 未修改。

```c
int game_reset(bullet_state *, unsigned count, uint32_t seed);
int game_update(bullet_state *, const game_input *); /* 固定 1/60 秒一步 */
int game_build(const bullet_state *, uint32_t dst, int network, int glow,
               unsigned capacity, bullet_stream *);
int game_advance(game_clock *, bullet_state *, const game_input *, uint32_t elapsed_us);
```

`game_reset`/`game_build` 成功返回 0，失败返回负值；`game_update` 返回 1 表示比较请求，0 表示普通更新或重开，负值为参数错误。重开优先于同 tick 比较请求。`game_build` 只构造原 `gpu_command` 流，不提交 GPU、不读网口、不调用恢复算法；`network=0/1` 选择既有本地/网络资源地址。

`nc_init`、`nc_poll`、`nc_try_publish` 与 `input_update` 的详细合同见 [驱动交接](v3_net_control_handoff.md)。`game_input` 前三项是 held/pressed/released，后面是调用方持有的输入去重状态；必须整个清零初始化。输入断开/年龄超过 250 ms 释放键；方向相反同时按下抵消。重开和比较由新的 action_sequence 产生一次 pressed，不按持续 held 重复执行。

共享动作计数器推进时，若可辨认新的动作键上升沿，只触发新动作（例如按住 R 再按 C 不会再次重开）。若两动作均持续 held 且没有可辨认边沿，协议不能辨别丢失的松开/重按来自哪一个；此时保留两个候选事件，游戏按既有重开优先处理，不伪称能恢复所有丢包事件意图。

## 玩法和键位

浏览器方向键/WASD 移动，Space/Z 射击，Shift 慢速，R 重开，C 请求比较回放；网页需主动获取控制，失焦/隐藏释放控制。PC 仅转发键掩码，游戏更新仍由 Sapphire 执行。实体按键方案保留为另案，未混入本轮固定网口接口。

沿用 R7 六种弹形、玩家飞机和三种发射器、Alpha 光晕、擦弹积分、碰撞、3 点生命、60 tick 受击保护及 120 tick 游戏结束后自动重开。手动入口不再覆盖玩家坐标：通常每 tick 4 像素，斜向每轴 3，慢速每轴 1；玩家中心限制 x=8..952、y=80..532。友方弹每 6 tick 尝试发射一次（首个 tick 也可发射），以 8 像素/tick 上行，命中一个固定发射器中心 ±10 像素时回收并加 25 分。发射器是持续弹幕目标，没有新增敌机 HP、摧毁或剧情系统；友方弹不会伤害玩家。

固定池最大 512 个对象，通常最后 8 槽给友方弹；低于等于 8 个对象时分配一半给友方弹。闲置友方槽既不绘制核心也不绘制幽灵光晕，不靠扩容数组冒险。**交互 512 池不是冻结 R7 的 512 敌弹场景**：敌弹槽减少 8，但总活动/可见元素仍据实统计；不能拿交互场景数字直接计算 R7 加速比。当前容量仍最多 585 条场景命令、68 条 Alpha（含玩家/敌机效果），没有删旧 Alpha 规则换性能。

## 固定 tick、慢速与模式

`game_clock` 全零初始化即可使用。`game_advance` 用整数累积器处理微秒（us×60，每百万单位一步），每调用最多追赶 4 个逻辑 tick；不足一步时保存 pressed/released 到下次，追赶时事件只在第一步消费。超长输入间隔先限制至 250 ms，再将剩余积压上限设为 4 步，多余墙钟时间记入饱和 `discarded_wall_us`，`slow=1`。它**不跳过逻辑 tick**，也不承诺慢 CPU 能与真实时间保持同步；负责人须在 HDMI/网页显示逻辑减速，不用跳帧掩盖。

`game_advance` 返回本次步数；`clock.compare_requested` 为比较请求。它不是整机模式机。负责人负责实时 GPU → 暂停真人输入 → CPU/GPU 同记录比较 → 恢复实时 GPU 的转换；比较/加载/恢复期间重置或暂停实时 clock 的墙钟积压，不能把 CPU 慢窗口内真人键放进回放。原交接关于恢复时“清零输入去重状态”的建议已由10/07补记更正：保持已消费动作序号，避免长按重触发。模式/HUD 的实时、比较、加载、暂停、CPU 成绩过期等 flags 由负责人填充，不改测量公式。

若需要录制，**每个实际逻辑 tick 之前**调用 `replay_record`，再 `game_update`；不要每个显示帧录一次，也不要在 `game_advance` 外录一次却内部推进四次。需要逐 tick 录制的主循环可自行按相同固定步长调用 `game_update`。生产轮询节奏、暂停恢复、画面提交与 vblank 归负责人集成。

## 600 tick 公平回放

`replay_init(record, initial, epoch)` 保存逻辑初态及 seed（非零 epoch）；每 tick `replay_record` 保存方向/射击/慢速 held 和 R/C 的 pressed 事件，连续两个 tick 的新动作也各执行一次。录满 600 步后 `replay_seal` 生成规范字段 CRC 并封存；不足 600 不能封存，超容量拒绝，不分配堆内存。

CPU 和 GPU 各自 `replay_begin(record, current_epoch, state, cursor)` 恢复同一初态，循环 `replay_next`（1 有 tick、0 结束、负值错误）→ `game_update` → `game_build`，只更换绘图后端。两次回放不接收新真人键；CPU 基础绘图保持完整背景/原算法。优化 GPU 可以用等价恢复和提交表示，不能要求其优化后命令数等于全背景命令数，但最终像素必须一致。

CRC 覆盖版本、seed、epoch、初态所有逻辑字段和全部键记录，排除 C padding；回放开始拒绝错误 CRC、资源代际、非法初态。`record` 在 begin 后到回放结束必须不可修改，begin 只做一次完整校验，next 不重复整段 CRC；记录不是可直接搬运的跨 ABI 文件格式。换素材时拒绝旧 epoch 记录，恢复匹配版本后才能回放。断网不影响已封存记录。

## 资源与内存

`assets/interactive` 包含真实 RGB565、原 ASST 格式 `manifest.csv`、`resource_manifest.json` 和 `LICENSES.md`；PC 仍使用原 `asset_server.c`，不要另建游戏资源协议。资源 ID 101/102 与 R7 一致，背景 DDR=0x02900000、图集=0x02a00000；本地回退在 0x02b00000/0x02c00000，不改变原地址布局。

当前背景 960×540、stride=1920、1036800 B，图集 3104 B（小于现有 4096 B Cache），使用已有程序化项目自绘素材，交互包以 CC0-1.0 发布；来源/逐图布局/CRC/SHA256 在清单中。背景 CRC=`4a9556cc`、图集 CRC=`9d6b31f2`，与 R7 字节相同。

重新生成：`python tools/build_interactive_assets.py --epoch 0x00030002`。使用新 epoch 替换包后，负责人必须先暂停玩法、使**两块物理 backbuffer** 恢复历史失效，再完整加载并验证 CRC，完成后更新 current_epoch/纹理 Cache 和遥测；任何失败保持不可见并选择既有回退。manifest 描述这个要求，本包没有擅自修改负责人恢复或加载函数。

离线 RV32 编译对象无隐藏 BSS；实际存储由调用方决定。`bullet_state=10280 B`、`bullet_stream=18740 B`、`replay_recording=11496 B`、`game_clock=20 B`，回放记录内部已含初态；不要在小栈上分配或传值这些大对象。当前 RV32 单函数栈报告最高为 nc_try_publish 的 272 B（不是整机总栈）。最终链接 map/BSS/嵌套调用栈和 DDR 布局须在候选固件中复核，主机的大帧缓冲仅属测试，不能搬进片上 BSS。

## 复现与实际证据

仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-game.ps1
```

脚本使用本机已有 GCC、Efinity Python、D:/FPGA/iverilog 和 RISC-V 工具链，可参数覆盖；不安装依赖、不修改固件入口。输出在 `generated/verification/v3/game`。

- 6 个严格 C 套件：管理驱动、输入边沿、冻结 R7、交互玩法、600 tick 回放、真实资源 CPU/独立像素参考。
- 真实资源 manifest/CRC/epoch 检查；原资源服务器从新包逐块传输、完整 CRC 与文件逐字节一致。
- 每 tick CPU/GPU 初态/输入/状态/命令语义相同；真实像素取 10 个每 60 tick 的样本，600 tick 最终整帧 CRC=`8f62707a`。不是声称每个中间 tick 都绘制核对。
- 60 tick 活跃样本：508 个可见弹对象，8 友方弹，581 条命令，68 条 Alpha；原 `gpu_pixel_pipe` 接收 561444 像素（Copy 518400、Key 33360、Alpha 9684），实际透明跳写/读旧目的值及背压全部核对。
- 冻结 R7 的 32/128/512 档各 600 tick，基点摘要分别 `0cec877a / 225e4a68 / 598a29df`；既有 R7 状态、玩法、HUD、像素、性能 harness 和原像素 RTL 回归通过。
- 5 个生产 RV32 模块编译通过，启用 `-Wstack-usage=2048 -fstack-usage`；不把对象编译当成固件完整链接。

测试产生 `preview.png` 是真实离线帧（未集成 HUD 的场景区域）；本包不宣称输入 P95、GPU P95 增量、HDMI FPS、板级 BSS、热重载或 30 分钟整机耐久已完成。全套生产集成/板测仍由负责人执行。
