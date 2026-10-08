# 四档游戏菜单：实现与验收记录（2026-10-08）

## 当前状态

功能源码、网页、真实驱动集成测试和候选整机编译通过；候选已实际JTAG加载。用户确认HDMI四卡完整、顶部正常、无左右错位或残影。真实四档START/MENU确认通过，64/128/256档方向输入、租约超时、R重开和自然死亡回MENU通过。**尚未全面验收：512档完整方向阶段、CPU回放途中取消、完整600tick实板回放和长期耐久仍有缺项，不能作为封版证明。**

正常启动MENU，四个等级分别请求64/128/256/512个Sprite，非保证全部可见。网页选择经以太网发给Sapphire，板端执行后ACK，再以新于ACK快照上界的遥测确认；PC不运行游戏或渲染。LIVE死亡当tick停止并返回菜单，R同档重开，网页“一键重选难度”结束当前局并回菜单（不是复位FPGA）。原C键600tick公平CPU/GPU回放保留，可通过网页重选取消；未完成CPU回放不发布半段成绩。

GPU仍为100MHz旧有序后端；CPU绘图保持最基础原路径。菜单复用Fill/Copy、原字形/HUD与双缓冲，不增菜单帧命令数组。四张368×104卡位于(96,144)/(496,144)/(96,288)/(496,288)，不覆盖顶部72行HUD/竞赛图片；同代际双缓冲各绘一次，静止菜单无重建，网络提示仅更新局部。MENU的游戏计数0，GPU计时有效位关闭，不能把菜单60Hz称作游戏60FPS。

## 已通过的离线证据

- 新协议：AGC1v1仍32B、AGT1仍128B/27字；增加GAME4、GAME_ACK5，旧HELLO/KEYS/ACK字节不变。C/Python/RTL共享golden；合法/非法命令、CRC、长度、会话、租约、序号回绕/去重、完成ACK和旧快照门槛通过。
- `scripts/test-v3-integration.ps1 -SoftwareOnly`：15个C可执行检查（UBSan）及23个Python实际UDP/HTTP检查通过。R7冻结结果、600tick回放、输入去重/真正零KEYS解锁、追赶tick死亡立即停止、取消回放保留旧完成成绩、真实GPU MMIO菜单命令检查通过。
- Node及真实Edge/Playwright网页检查通过：四档选择/重选、自动获取控制、键盘/失焦、所有权冲突、旧固件禁用菜单、无效FPS/CSV。模拟器只回显菜单协议，不模拟游戏或FPS；不当作实板测量。
- 网络完整RTL入口 `scripts/test-v3-control-rtl.sh` 及实际APB/MAC glue集成通过。本轮不重复长时全系统仿真。
- 原正常RV32候选：text42464、bss78956、4096B栈，总125516≤126976。实板问题修正后的`normal-r4`为text42672、data0、bss78956、4096B栈，总125724，余1252B；无ProbeFrames/StartCount/ShadowSubmit及栈用量警告。基础裸机链接的RWX LOAD警告仍存在，不称已解决。
- 整机候选`D:/efinity_builds/game_menu_20261008_r1`编译退出0，map/interface/pnr/pgm全PASS。core100MHz setup +1.450ns、hold +0.026ns；最终时钟关系setup/hold均正。LUT25297、FF25611、RAM10 142、DSP48 14＋DSP24 6。正式源清单与display_reset合格工程一致；GPU生成物/board_top/SDC/IP未改，唯网络control_udp_rx增加合法包字段检查，没有新增时钟域或CDC结构；映射警告差异仅日期。
- 实际布线CDC门禁`test-net-resource-report.ps1 -RequireRouted`通过：1488数据、2请求、2确认路径全部覆盖，最长分别0.916/1.189/0.766ns，低于8ns；工具实际展开约束及全部16个最终setup/hold关系核对通过。整机XLR45130（74.23%），解析器785/1RAM，未以“CDC结构没改”代替布线检查。
- 预热健康门禁：保留64位完整下溢计数，以完成显示初始化后的实际计数为基线，30预热＋300采样每帧（含PRESENT及帧间）检查新增下溢/硬件错误，立即失败并保存帧日志。初始化阶段的真实下溢仍保留在累计计数/串口基线中，不清零，不冒充上电零下溢。
- `scripts/test-game-menu-board-guards.ps1`离线通过，缺BIN/BIT、已有输出目录、非本机HTTP均在串口/JTAG之前拒绝。
- 原独立PLAY诊断链接通过；修正版`probe-r4-64/128/256/512`为text43448＋bss78956＋4096栈=126500，余476B，无栈用量警告，与正常MENU分目录。原A/B生命周期18轮600tick检查、遥测采集7项/输入证据15项及Node面板通过。

一次Windows原生HTTP非法Origin用例出现WinError10053；单项重现与随后完整两次23用例均通过，未证实稳定根因，保留为主机侧间歇异常，不通过跳过用例掩盖，也不宣称修复。

## 独立审查与修正

一次独立只读整分支审查，无Critical。Important：浏览器清键后自动重复keydown可能再次触发R，或把切场景前按住的方向带回；真实Edge用例先复现R重复触发失败，再屏蔽`event.repeat`通过（既有心跳负责保持按键，不依赖keydown重复）。清键后的按键显示也同步为0，真实网络POST证明旧方向不重传，松开再按可恢复操作。正常新按键、四档菜单与原输入回归保持。

两项低优先级留待后续：移动端<480px的卡片仍两列（媒体规则优先级问题）；当前host集成覆盖真实RX→runtime→ACK，但还没有把MENU→PLAY两缓冲绘制/PRESENT串成一项回归。分项命令检查和主循环源码支持背景恢复，不等同于该联合回归或实板无残影证明。

## 候选与整体回退

| 文件 | SHA256 |
| --- | --- |
| 新BIT `D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit` | `202d2b40ba1b919394a2cc920055a810e56c07fbd725fdb4185385124f894cf3` |
| 新正常BIN `generated/verification/v3/game_menu_20261008/normal/gpu_demo.bin` | `b9ffcb14e854e373c7b9594928903aa0c7b5c834360ca2f281e5f4f54d36291c` |
| 当前修正版BIN `generated/verification/v3/game_menu_20261008/normal-r4/gpu_demo.bin` | `22ac5c46ecd088726819765354dcbc930dc03e6d0f9a7365e376eef91f78be88` |
| 旧合格BIT `D:/efinity_builds/display_reset_20261006_r1/outflow/efinix_2d_gpu.bit` | `ca4fa62b1afe977996cb40fec5bac4931b8904086b8022df7b00ed7384d850b9` |
| 旧BIN `generated/verification/v3/submit_shadow_20261007/normal-default-restored/gpu_demo.bin` | `ec966d397e4d085e7fb40eac59a17eb865cd948396bbe1647256343830c0613c` |

旧版本源码基点`2d18a62`。旧网关参数：Python39，`gateway.py --board 192.168.1.3 --udp-bind 192.168.1.2`（HTTP127.0.0.1:8765、UDP8090）；资源服务器使用`assets/interactive/manifest.csv`与UDP8080。基点control_gateway目录完整归档/解压及参数、旧BIT/BIN哈希已保存在`generated/verification/v3/game_menu_20261008/rollback-r1`。新版网关已按原参数启动，资源服务器保持不变；旧合格文件、release/v2未覆盖，无Flash操作。旧BIT仅用于对照，之后已重载新候选BIT。

旧网关严格掩码会拒绝新MENU/CAPABLE位：新固件须配套重启新版网关，升级网页后刷新浏览器。新版网关支持旧固件基础键盘/遥测，并明确菜单不支持。失败时恢复旧BIT、旧BIN与旧网关目录/原参数一起回退，不复用过期硬编码BIT的`-LoadBit`包装。

上板脚本（只在板卡实际上电、USB/网线/HDMI就绪后）：

```powershell
powershell -NoProfile -File scripts/test-game-menu-board.ps1 `
 -Bin generated/verification/v3/game_menu_20261008/normal-r4/gpu_demo.bin `
 -Bit D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit `
 -LoadBit -OutDirectory generated/verification/v3/game_menu_20261008/board-next
```

显式`-LoadBit`才加载所给BIT，否则只重载BIN；HTTP保持本机地址，不开放远程Host/Origin。脚本采串口/HTTP/哈希，经真实`/api/control`取得所有权，再自动四档START→ACK→新快照→重选，最后释放零键并留MENU。**脚本不自动判定目视、碰撞死亡或完整600tick比较合格。**运行失败保留日志，不能用模拟器替代实板。

## 待测清单

1. PLAY/MENU实际切换后目视检查；用户本次目视确认针对菜单，不能推成全场景实景验收。
2. 512档完整RIGHT/UP/EXPIRE阶段；本次512已实际右移及自然死亡回MENU，但死亡发生在UP阶段，后续无样本，严格检查失败而非放宽断言。实体拔网线重连及真实网页失焦仍待测；无心跳超时与重新握手已有实板证据，失焦另有真实浏览器离线测试。
3. CPU比较途中取消及完整CPU/GPU各600tick实板回放：本次实际进入CPU比较，单帧约0.337～0.371秒，超过250ms控制租约；MENU命令未确认，不能称取消通过。用户明确选择“先保留此限制，后续处理”，本轮不增加CPU控制轮询、不改变CPU算法/配置或租约；完整实板回放没有完成验证。
4. 长期耐久、512@60与1024实板目标未完成。历史SoftwareDriverSpec/PangoBringupSpec异常继续保留。

## 本次实板调试证据

- `board-r1`失败：初版遥测从0计算下溢增量，把启动/资源加载的333720累计计数误报为当前增量。改为读取实际初始快照，保留累计值，不抹掉真实新下溢。
- `board-r2`失败：同构建热重载使snapshot_id回到1，脚本先等遥测再发HELLO，无法触发ACK授权的新序号基线。脚本调整为先取得零键控制握手，再等当前会话新遥测。
- `board-r3`仍失败：首次MENU出现891个真实新增下溢。独立64档首帧新BIT下溢1343；同固件旧合格BIT对照首帧下溢1774。根因见`Efinix2dGpuTop.scala`：scanoutStarted只有在首次PRESENT后置位，而旧主循环在此之前开始统计、先完成长绘制。现先完整Fill黑底后PRESENT，保持软件/硬件缓冲对一致，再加载Logo并开始实际30+300门禁。旧BIT64档对照修正版300帧60.1FPS、下溢/错误0，全部预热也通过；不丢弃预热帧，不改RTL或时钟。
- `board-r4`与最终`board-r5`：真实四档各START/MENU，result0且确认快照严格新于floor，健康增量0。资源101/102/103完整加载result0、retry0。
- `gameplay-level1-r1`方向/EXPIRE通过；死亡检查停在安全角落没有形成有效碰撞，主动结束保留原记录。`gameplay-level1-r2`暴露会话重连反复变化；真实C驱动新增回归先失败：握手前排队的未连接快照会使用新session头发送。只在接受新HELLO时作废旧待发快照，重复HELLO不改变已有状态；完整15C＋23Python通过。测试发送的action_sequence也保持单调，不把旧动作计数带回。
- 最终`gameplay-level1-r3`、`gameplay-level2-r1`、`gameplay-level3-r1`：真实RIGHT/UP位移、EXPIRE零键/age=-1、R同档重开、自然碰撞死亡reason1返回MENU及网页遥测确认通过。死亡检查先通过真实R回到普通出生点，不注入HP或游戏状态。
- `gameplay-level4-r1`：右移x552→792→952，随后自然死亡reason1返回MENU；UP/EXPIRE不完整，脚本明确失败。`replay-cancel-r1`：实际CPU比较触发，但控制租约在长绘图期间失效，MENU未确认，失败保留。不得用离线runtime通过覆盖这些实板缺项。

## 当前候选四档实测（非菜单帧率）

同一候选BIT、修正版`probe-r4-*`诊断，build20261008、resource_epoch00030002、GPU100MHz，真实以太网资源101/102/103、CRC通过、零重试；独立直接PLAY，无控制输入，各档30帧预热＋300帧采样。严格健康门禁覆盖预热/采样/PRESENT/帧间；初始化黑底呈现及加载阶段不属于游戏帧，累计下溢基线约334800仍原样记录。不是上电零下溢或30分钟耐久证明。

| 请求Sprite | 实际可见范围 | Alpha命令范围 | 完整帧FPS | 工作均值/最大(ms) | 超16.667ms帧/迟到帧 | 新增下溢/错误 |
| --- | --- | --- | --- | --- | --- | --- |
| 64 | 53～56 | 11 | 60.1 | 10.348 / 11.848 | 0 / 0 | 0 / 0 |
| 128 | 115～120 | 19 | 60.1 | 11.696 / 13.509 | 0 / 0 | 0 / 0 |
| 256 | 240～248 | 34～35 | 60.1 | 14.186 / 16.277 | 0 / 0 | 0 / 0 |
| 512 | 497～504 | 66～67 | 30.0 | 19.605 / 41.972 | 300 / 300 | 0 / 0 |

Color Key沿用真实场景绘制；本诊断摘要未逐帧统计Key数量，不从请求数伪造Key范围。512最大完整帧49.915ms、工作峰41.972ms，不能由均值30FPS推断完全均匀帧间隔。各档最大日志开销527/615/702/703us已包含在完整帧开销内，未扣除后伪报60FPS。

原始证据：`generated/verification/v3/game_menu_20261008/probe-{64,128,256,512}-board-r4.log`，每档V3_PROBE_STOP,result=0。结束后已重载`normal-r4/gpu_demo.bin`，并以`normal-restored-r4`再次确认真实四档开始/重选，最后MENU、Sprite0、under_delta0、error0，释放控制权。网页/资源服务保留运行；无Flash写入，无后台持续烧录，无远程推送。
