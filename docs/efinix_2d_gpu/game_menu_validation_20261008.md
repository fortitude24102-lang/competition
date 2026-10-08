# 四档游戏菜单：实现与验收记录（2026-10-08）

## 当前状态

功能源码、网页、真实驱动集成测试和候选整机编译已经通过。**尚未加载候选到实板；HDMI实景、实际飞机移动/死亡、四档实板性能和完整CPU回放暂未验收。**本文件不能作为512@60、30分钟耐久或V3封版证明。

正常启动MENU，四个等级分别请求64/128/256/512个Sprite，非保证全部可见。网页选择经以太网发给Sapphire，板端执行后ACK，再以新于ACK快照上界的遥测确认；PC不运行游戏或渲染。LIVE死亡当tick停止并返回菜单，R同档重开，网页“一键重选难度”结束当前局并回菜单（不是复位FPGA）。原C键600tick公平CPU/GPU回放保留，可通过网页重选取消；未完成CPU回放不发布半段成绩。

GPU仍为100MHz旧有序后端；CPU绘图保持最基础原路径。菜单复用Fill/Copy、原字形/HUD与双缓冲，不增菜单帧命令数组。四张368×104卡位于(96,144)/(496,144)/(96,288)/(496,288)，不覆盖顶部72行HUD/竞赛图片；同代际双缓冲各绘一次，静止菜单无重建，网络提示仅更新局部。MENU的游戏计数0，GPU计时有效位关闭，不能把菜单60Hz称作游戏60FPS。

## 已通过的离线证据

- 新协议：AGC1v1仍32B、AGT1仍128B/27字；增加GAME4、GAME_ACK5，旧HELLO/KEYS/ACK字节不变。C/Python/RTL共享golden；合法/非法命令、CRC、长度、会话、租约、序号回绕/去重、完成ACK和旧快照门槛通过。
- `scripts/test-v3-integration.ps1 -SoftwareOnly`：15个C可执行检查（UBSan）及23个Python实际UDP/HTTP检查通过。R7冻结结果、600tick回放、输入去重/真正零KEYS解锁、追赶tick死亡立即停止、取消回放保留旧完成成绩、真实GPU MMIO菜单命令检查通过。
- Node及真实Edge/Playwright网页检查通过：四档选择/重选、自动获取控制、键盘/失焦、所有权冲突、旧固件禁用菜单、无效FPS/CSV。模拟器只回显菜单协议，不模拟游戏或FPS；不当作实板测量。
- 网络完整RTL入口 `scripts/test-v3-control-rtl.sh` 及实际APB/MAC glue集成通过。本轮不重复长时全系统仿真。
- 正常RV32构建：text42464、data0、bss78956，另保留4096B栈，总125516≤126976，余1460B；未出现栈用量警告。构建无ProbeFrames/StartCount/ShadowSubmit，输出`generated/verification/v3/game_menu_20261008/normal/gpu_demo.bin`。基础裸机链接的RWX LOAD警告仍存在，不称已解决。
- 整机候选`D:/efinity_builds/game_menu_20261008_r1`编译退出0，map/interface/pnr/pgm全PASS。core100MHz setup +1.450ns、hold +0.026ns；最终时钟关系setup/hold均正。LUT25297、FF25611、RAM10 142、DSP48 14＋DSP24 6。正式源清单与display_reset合格工程一致；GPU生成物/board_top/SDC/IP未改，唯网络control_udp_rx增加合法包字段检查，没有新增时钟域或CDC结构；映射警告差异仅日期。
- 实际布线CDC门禁`test-net-resource-report.ps1 -RequireRouted`通过：1488数据、2请求、2确认路径全部覆盖，最长分别0.916/1.189/0.766ns，低于8ns；工具实际展开约束及全部16个最终setup/hold关系核对通过。整机XLR45130（74.23%），解析器785/1RAM，未以“CDC结构没改”代替布线检查。
- 预热健康门禁：保留64位完整下溢计数，以已有计数为初始基线，30预热＋300采样每帧（含PRESENT及帧间）检查新增下溢/硬件错误，立即失败并保存帧日志；原诊断丢弃预热的限制已修。仅host验证此门禁，尚未重新实板四档跑分。
- `scripts/test-game-menu-board-guards.ps1`离线通过，缺BIN/BIT、已有输出目录、非本机HTTP均在串口/JTAG之前拒绝。
- 独立直接PLAY的四档300帧诊断固件分别链接通过（`probe-64/128/256/512`），text43240＋bss78956＋4096栈=126292，余684B，无栈用量警告，尚未板上执行；不覆盖正常MENU固件。另原A/B生命周期18轮600tick检查、遥测采集7项/输入证据15项及Node面板通过。

一次Windows原生HTTP非法Origin用例出现WinError10053；单项重现与随后完整两次23用例均通过，未证实稳定根因，保留为主机侧间歇异常，不通过跳过用例掩盖，也不宣称修复。

## 独立审查与修正

一次独立只读整分支审查，无Critical。Important：浏览器清键后自动重复keydown可能再次触发R，或把切场景前按住的方向带回；真实Edge用例先复现R重复触发失败，再屏蔽`event.repeat`通过（既有心跳负责保持按键，不依赖keydown重复）。清键后的按键显示也同步为0，真实网络POST证明旧方向不重传，松开再按可恢复操作。正常新按键、四档菜单与原输入回归保持。

两项低优先级留待后续：移动端<480px的卡片仍两列（媒体规则优先级问题）；当前host集成覆盖真实RX→runtime→ACK，但还没有把MENU→PLAY两缓冲绘制/PRESENT串成一项回归。分项命令检查和主循环源码支持背景恢复，不等同于该联合回归或实板无残影证明。

## 候选与整体回退

| 文件 | SHA256 |
| --- | --- |
| 新BIT `D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit` | `202d2b40ba1b919394a2cc920055a810e56c07fbd725fdb4185385124f894cf3` |
| 新正常BIN `generated/verification/v3/game_menu_20261008/normal/gpu_demo.bin` | `b9ffcb14e854e373c7b9594928903aa0c7b5c834360ca2f281e5f4f54d36291c` |
| 旧合格BIT `D:/efinity_builds/display_reset_20261006_r1/outflow/efinix_2d_gpu.bit` | `ca4fa62b1afe977996cb40fec5bac4931b8904086b8022df7b00ed7384d850b9` |
| 旧BIN `generated/verification/v3/submit_shadow_20261007/normal-default-restored/gpu_demo.bin` | `ec966d397e4d085e7fb40eac59a17eb865cd948396bbe1647256343830c0613c` |

旧版本源码基点`2d18a62`。旧网关运行参数已检查：Python39，`gateway.py --board 192.168.1.3 --udp-bind 192.168.1.2`（HTTP127.0.0.1:8765、UDP8090）；资源服务器使用`assets/interactive/manifest.csv`与UDP8080。当前服务未重启、旧合格BIT/BIN未覆盖，release/v2未修改，没有Flash操作。升级前保存基点的整个control_gateway目录（含protocol/web），不要只保存gateway.py。

旧网关严格掩码会拒绝新MENU/CAPABLE位：新固件须配套重启新版网关，升级网页后刷新浏览器。新版网关支持旧固件基础键盘/遥测，并明确菜单不支持。失败时恢复旧BIT、旧BIN与旧网关目录/原参数一起回退，不复用过期硬编码BIT的`-LoadBit`包装。

上板脚本（只在板卡实际上电、USB/网线/HDMI就绪后）：

```powershell
powershell -NoProfile -File scripts/test-game-menu-board.ps1 `
 -Bin generated/verification/v3/game_menu_20261008/normal/gpu_demo.bin `
 -Bit D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit `
 -LoadBit -OutDirectory generated/verification/v3/game_menu_20261008/board-r1
```

显式`-LoadBit`才加载所给BIT，否则只重载BIN；HTTP保持本机地址，不开放远程Host/Origin。脚本采串口/HTTP/哈希，经真实`/api/control`取得所有权，再自动四档START→ACK→新快照→重选，最后释放零键并留MENU。**脚本不自动判定目视、碰撞死亡或完整600tick比较合格。**运行失败保留日志，不能用模拟器替代实板。

## 待测清单

1. 开机HDMI/网页均MENU；四档完整背景恢复、两缓冲无残影；Logo/HUD不遮挡。
2. 四档真实RIGHT/UP输入、失焦/断网清键、重连；不能用R自动移动抵扣方向输入。
3. LIVE死亡立即回MENU且网页同步，R同档重开；C公平回放及中止无半段CPU成绩，旧完成成绩标过期。
4. 各档独立直接PLAY诊断30预热＋300采样，记录请求/可见/Alpha/Key/FPS/错误/下溢与场景版本，再恢复正常MENU固件。512历史约30FPS仍只是历史，不能挪为本版本结果。
5. 用户实景确认与长期耐久。历史SoftwareDriverSpec/PangoBringupSpec异常继续保留，不因菜单通过而消除。
