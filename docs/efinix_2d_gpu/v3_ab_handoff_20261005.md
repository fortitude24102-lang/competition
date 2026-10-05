# V3 A/B 联合交接（A-work，2026-10-05）

## 目前状态

本轮先获取并快进同步 `origin/main 79a0b7f`，理解 README、两周计划、固定接口、Copy/背景恢复进度后实施。main 负责人已完成第1～7天 GPU 候选和部分板测：Copy 收益约 0.6%，512 档仍约 30 FPS，背景恢复不默认开启；这些事实不因本轮功能交付而改变。release/v2 保持冻结。

用户要求 A 和 B 全部交付 A-work，因此没有另推 B-work。A/B 的**独立源码、资源、工具和检查入口**在此交付；第8天以后的整机连线、正式候选、实板交互/性能/耐久须由负责人继续执行，不把独立验证写成整机封版。原实体按键与单向 CPU→GPU 展示计划保留为另案；此次严格实现 V3 的浏览器键盘固定合同。

## 负责人拿走什么

| 部分 | 自有文件 | 入口/交接 |
| --- | --- | --- |
| A 网口 RTL | `rtl/net/udp_payload_router.v`、`control_udp_rx.v`、`net_control_bridge.v`、`udp_tx_arbiter.v`、`efinix_asset_network_shared.v`；兼容修改原 wrapper/legacy entry | [RTL 接线与 APB 合同](v3_control_rtl_handoff.md)，`scripts/test-v3-control-rtl.ps1` / `.sh` |
| A 本地管理工具 | `tools/control_gateway` 协议/网关/假板/三份网页资源，启动脚本，黄金包向量 | [真实/假板启动与网页使用](v3_control_usage.md)，`scripts/run-control-gateway.ps1` |
| B 网络输入 | `include/src` 下 `v3_control_protocol`、`net_control`、`input_state` 及独立测试 | [会话、时戳、TX 与输入接口](v3_net_control_handoff.md) |
| B 游戏与回放 | `interactive_game`、`replay_input`，允许的 `bullet_demo.c/h` 提取共享更新 | [键位、玩法、固定 tick、公平回放](v3_game_usage.md)，`scripts/test-v3-game.ps1` |
| B 资源 | `assets/interactive` 实际 RGB565/ASST manifest/JSON epoch/许可，生成器 | `tools/build_interactive_assets.py`，图集 3104 B，保持现有 Cache/DDR 布局 |

RTL 路径相对 `board/efinix_ti60`；软件相对 `sw/efinix_gpu`。没有替换 vendor、GPU、SoC adapter、生产 main、正式工程/source list、CPU 绘图或 release 文件。

关键兼容取舍：新共享 MAC 入口命名为 `efinix_asset_network_shared #(.ENABLE_CONTROL(1))`，原 `efinix_asset_network` 保持精确旧端口/层级。不能仅拿新 bridge 却继续实例化旧入口，否则管理通路不会接入。管理长包仅允许 32/128 B，原 ASST GET 仍 32 B，资源 session 与管理 TX 隔离。

## 集成顺序（负责人所有权）

1. 先保存当前 R7 固件/位流/资源及测量入口。工程显式加入新的 RTL、现有 FIFO/vendor 依赖；GPU/PHY 时钟和原三个 APB 窗口不变。
2. adapter 显式选择 0x0300..0x03ff bridge，按 RTL 交接连接 GE 字节流→管理解析→深度4 CDC→APB、bridge TX→包级 arbiter→MAC。两种复位均清跨域状态，GE 解析器同步释放复位。设置真实固定 IP/管理 UDP8090，不借用资源会话。
3. 候选固件链接四个新 C 模块及既有 CRC。`nc_init` 探测不可用时回退原场景；GPU 实时循环有界 `nc_poll`、`input_update`、固定 tick 更新、原绘图、`nc_try_publish`（ACK 优先、遥测默认5 Hz）。不要往生产主循环搬入测试桩。
4. 负责人实现实时/比较/加载/恢复模式与 HUD：实时默认 GPU；比较冻结真人键，用同一600 tick初态/seed/epoch跑两后端，保留两组成绩并标 CPU 过期；完成后恢复 GPU。只在真实逻辑 tick 边界录制，每次多步追赶时逐步采样，显示逻辑减速。
5. 资源/模式切换使两块物理缓冲历史失效，资源完整 CRC 后才可见；候选链接后核查 BSS/栈/map/DDR，R7 冻结场景保持独立。新交互玩法不能与旧 R7 不等价对比。
6. 先做端到端输入/ACK/完整遥测/断网/失焦/复位，再做网络开关 GPU P95 增量（目标≤0.25 ms）与输入 P95（目标≤100 ms）；最后真实30分钟耐久/冷启动/热重载/服务器缺席/资源切换。保留热重载下溢和两项旧 SoC 异常，不声称已经修复。

## 已有离线证据

- 原生 Icarus：3 个新管理 suite + 2 个**未修改**旧资源 suite；包含真实 vendor FIFO/MAC，包级仲裁、资源 session、32/128 B、不依赖 DMA 的遥测、快照/CRC/年龄/满队列/复位均检查。
- 严格 C：驱动/输入/R7冻结/交互/600 tick回放/实际资源像素共6 suite；实际 CPU 黄金绘图与独立像素参考最终整帧一致，10个采样帧，最终 CRC=`8f62707a`。
- 未修改像素 RTL 检查活跃交互样本：561444 像素（Copy 518400、Key 33360、Alpha 9684），含背压/透明跳写；友方弹8、可见508、命令581、Alpha68。
- 原 R7 六个 C/像素 RTL/资源工具 suite：通过；32/128/512 档600 tick状态和命令摘要仍为 `0cec877a / 225e4a68 / 598a29df`。不是反复跑未受影响的76项长 RTL。
- 5 个生产 RV32 对象编译，无隐藏 BSS，单函数栈报告最高272 B；state/stream/record/clock 为10280/18740/11496/20 B。完整候选链接尚待集成。
- 交互资源 manifest/CRC/epoch/许可检查；原 ASST 服务器真实 UDP 两项测试通过，整个背景及图集逐字节一致。
- 网关真实本机 HTTP/UDP、CRC黄金向量、ACK/租约/限频、慢SSE/压力、断板恢复检查；Node 单在途键状态检查；实际 Edge/两种 PowerShell 启动入口验证假板 ACK、失焦清键、409独占冲突、无效FPS与原始CSV。假板明确只回显管理协议，不计算游戏、不伪造性能。

最终代码复核确认当前 Python 19 项检查通过；修正了 Windows 无对端时 ICMP 异常结束工作线程，以及延迟旧 session0 遥测倒退快照/撤销控制的问题。输入动作在可辨认新边沿时只执行新动作，按住 R 再按 C 不重复重开。没有扩展固定 wire ABI。

本机 WSL 无发行版，Verilator shell 入口尚未执行；没有安装软件或更改网络/防火墙。所有离线证据输出到 `generated/verification/v3/{control-rtl,game,gateway}`（按仓库既有规则忽略，不把大量波形/临时EXE提交）。可用上述入口复现，交互预览为 `game/preview.png`，网页预览为 `gateway/dashboard.png`。

## 必须保留的限制

这不是整机闭环/上板验收；共享 RX RAM 忙时仍可能丢帧，真实网络负载下的延迟/丢包未测。固定协议没有 boot nonce：管理硬件复位后即使 ID 未变也须负责人重新 `nc_init`；同固件 session0 观察模式下 snapshot_id 复位不能与延迟包可靠区分，须新握手/网关重启。IP/端口过滤不是身份认证，只用于可信本地网络。

回放 begin 校验封存记录，消费期间调用方保持记录不可变；资源 epoch 校验不能替代实际资源 CRC/Cache 更新。所有 GPU 收益、稳定512@60/更高元素数仍需主负责人同画面板测，不能从这次功能仿真推出。
