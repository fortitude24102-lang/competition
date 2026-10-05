# V3 第8天整合与第10天首轮功能板测

## 范围与基线

本轮从 main `79a0b7f` 快进接收 A-work `fbde986` 的 A/B 联合交付，再由负责人修改顶层、工程清单和固件入口。沿用官方 Sapphire 100 MHz、原 GPU 后端、4 KiB 纹理 Cache、960×540 RGB565 双缓冲和 HDMI 输出；没有优化 CPU 绘制，没有写 Flash，没有替换 release。

背景恢复与连续 Copy 都不在本功能候选中默认启用。它们之前的独立板测仍见 `v3_damage_progress_20261002.md` 和 `v3_copy_board_20261002.md`，不得把本轮接入网口当成新的 GPU 提速成绩。

## 接入后的文件和职责

| 文件 | 本轮职责与输入输出 |
|---|---|
| `board/efinix_ti60/rtl/net/efinix_network_subsystem.v` | 唯一网络胶合模块；输入 APB、GMII 和原 Asset DMA 状态，输出资源流、管理窗口读回和共享 MAC TX。每个 `.v` 仍仅含一个模块 |
| `efinix_sapphire_adapter.v`、工程 XML | 保留 0000/0100/0200，增加 0300 管理选择；明确列入 A 的控制/路由/仲裁模块 |
| `efinix_asset_network_shared.v`、`net_control_bridge.v` | 管理包复用 020c/0210 的 IP 配置，在 TX COMMIT 时随包原子跨域；不从 GPU 域直接多位采样到 GE，不新增 APB 地址 |
| `sw/efinix_gpu/src/v3_runtime.c` | 60 Hz 逻辑时钟、最多4次追帧、逐逻辑 tick 录制、CPU/GPU 各600 tick 同初态回放、恢复实时状态和遥测有效性 |
| `sw/efinix_gpu/src/v3_demo.c` | 有界轮询输入→软核游戏更新→原命令流→原 CPU/GPU 绘制→HUD→PRESENT；200 ms 尝试发布完整128 B快照，不等待网口 |
| `hud.c/h` | LIVE/REPLAY、CPU STALE、逻辑 SLOW 标签；旧 R7 零初始化字段仍输出原 AUTO 内容 |
| `main.c`、固件构建脚本 | `-Interactive` 显式选择候选；默认仍走原 R7。管理 ID 不存在时回退旧入口 |
| `scripts/test-v3-integration.ps1` | 实际模块的8个 C 检查、19个本机 UDP/HTTP 检查与真实 MAC/APB 胶合测试；可仅跑受影响部分 |
| `scripts/test-v3-board-control.ps1` | 对已运行固件做真实控制、遥测、租约和可选回放验收；不下载位流/固件，不写 Flash |

`v3_runtime`/录像较大，放在私有 DDR `0x02d00000`，不放4 KiB栈；场景/HUD命令暂存区复用 main 原对象。该地址必须保留，后续资源分配不得覆盖。固件 text=36184 B、BSS=78952 B，合计115136 B，另预留4096 B栈，链接末端 `_sp=0x1d1c0` 在固件区内。编译无超过2048 B单函数栈警告；这不等同于完整运行时栈水位测量。

## 审核修正与证据

本轮只做一次独立只读审核，重要问题均在最小范围修正：

1. 去掉管理 IP 写死值，使用资源 APB 已有配置。实际 MAC 测试覆盖默认 `192.168.0.2/3` 和重新复位后的非默认配置；桥测试验证 COMMIT 后配置变化不会修改待发包。官方 MAC 不承诺无复位热换 IP，本轮不添加这种功能。
2. CPU 回放时不把 CPU 的 work/P95/PRESENT 时间标成有效 GPU 时间；GPU timing 组无效。CPU 旧成绩在新30帧窗口完成前保持 STALE，离开 CPU 阶段亦标 STALE；屏幕可保留最近成绩。
3. 追帧仍在推进游戏，不能标 PAUSED。保留 HUD 的 SLOW，只有真正停止逻辑才能使用暂停标志。
4. 回放结束不清空已消费的输入 session/sequence/action_sequence，避免长按 R/C 在恢复 LIVE 时误触发重开/新回放。

RED→GREEN：无管理胶合时0300访问失败；无逐 tick 录制时4次更新只留下0条记录；旧状态标志在 SLOW 检查失败；管理 IP 默认配置在真实 MAC 测试超时。对应实现与针对性检查随后通过。长按回放边界另用实板检查，不以纯函数测试替代集成路径。

未重复跑未修改 GPU 的76项长仿真。原资源RTL两项已通过；审核修改后重跑3项管理RTL、实际顶层胶合和受影响C/HTTP检查，均通过。旧 HUD 光栅与 GPU 字形 Cache 检查也通过。R7 32/128/512档600 tick冻结摘要与原值相同；互动场景离线黄金像素 CRC `8f62707a`。这些不能替代整机每帧像素或长期耐久验收。

## 实现与时序

首次布局 seed1 的官方 DDR FIFO 路径 setup=-0.342 ns，未上板。seed2 初候选全部 setup/hold 满足要求，并完成首轮功能板测。修正配置 CDC 后，在新目录 `_r3` 重建；最终 setup：core100 MHz +0.842 ns、GE125 MHz +1.329 ns、DDR最小 +0.298 ns；hold 全部非负。

最终占用 XLR 58503/60800（96.22%）、RAM 217/256（84.77%）、DSP 20/160（12.50%）。余量是下一步设计的重要约束，不能再假定可以无成本增加大 FIFO/Cache。Gray 计数源保持寄存器，并增加源到第一同步级的一个源时钟周期布线约束；这里不声称完成了所有物理 CDC 的独立签核。

## 首轮实板观察（初候选）

- Windows PC `192.168.1.2`，板卡 `192.168.1.3`；资源8080，管理8090，网页仅 `127.0.0.1:8765`。
- 两个资源1036800 B和3104 B均通过网口加载，重试0；随后128 B遥测被真实网关收到并校验，不是假板数据。
- 64请求档位，通常54～56实际可见（8个友方弹槽未发射时不计可见）；稳态约60.1 FPS。实际键盘右移/上移改变软核坐标，停止心跳后零输入。
- 相同600 tick记录分别经原 CPU/GPU 后端完成；CPU完整帧约2.5～2.6 FPS，GPU稳态约60.1 FPS。阶段转换的首个GPU窗口约58.1 FPS，保留该记录，不冒充每个窗口都60。
- 测量窗口下溢/错误0；首次记录 CRC `64508837`。本轮不是512档性能测量，不据此宣称最终60 FPS上限。

## 最终修正版板测

最终 `_r3` 已通过真实控制/断连释放、遥测与CPU/GPU各600 tick回放。CPU本轮约2.8 FPS，GPU稳态60.1 FPS；转换首窗58.1 FPS，启动首窗59.4 FPS均保留，不当成稳定窗口。全部捕获遥测的下溢/硬件错误0。

长按 R/C 专项的 RED→GREEN 使用相同实板脚本：旧候选回放结束误重开，LIVE tick由60555附近降到28；修正版恢复到tick4451、原坐标(840,192)，长按仍不重开，检查通过。CPU回放885条真实快照的GPU时间组全部无效，旧CPU标签43条为STALE，新窗口完成后842条为新结果；没有误报PAUSED。不同候选的CPU分数分别记载，不归因于CPU优化或构造跨版本加速比。

同一新硬件还加载了哈希不变的冻结 R7 `normal.bin`，原资源客户端两项加载result=0，旧自动场景运行，CPU2.8/GPU60.1 FPS，验证0200资源入口向后兼容。该单次固件重载不代表历史热重载/启动异常已解决。完成后冷加载本轮互动BIT/BIN并保留其运行。

最终候选 SHA256：

- BIT，`D:/efinity_builds/v3_integration_20261005_r3/outflow/efinix_2d_gpu.bit`：`319ae9eb014c5f193a643884a57a2890aa20e5026fccf82f85091a752b35f14d`。
- BIN，`generated/verification/v3/integration/gpu_demo.bin`：`b55d038d4d7e7973e9de2f1960087052e07bf52c4b162c3e5e7738a001562483`。

原始串口、完整HTTP快照和最终时序报告压缩归档于 [evidence/v3-integration-20261005](evidence/v3-integration-20261005)。其中 `board-action-red` 是已确认失败的旧候选，`board-final-control` 才是修正后的同项检查，不能混用。首次600 tick是启动后录制的轨迹；后续手动移动验证属于独立控制检查，不将其伪称为该次录像中的动作。

## 复现入口及后续

```powershell
powershell -File scripts/test-v3-integration.ps1
powershell -File scripts/test-efinix-software.ps1 -Interactive -FirmwareOnly -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102
powershell -File scripts/test-efinix-board.ps1 -OutputDirectory D:/efinity_builds/v3_fresh_output -Flow compile
```

检查最终 STA 后才可用 JTAG 加载其 BIT/BIN；板测脚本假设已经加载，不自行选择旧位流。首次重新配置后留出 PHY 协商时间。同固件复位会使快照序号重置，网页可能保守显示过期；通过新控制 HELLO/ACK 或重启本地网关恢复，不降低抗旧包检查。收尾冷加载后再次检查移动/断连通过，保留互动候选和本地网关运行，烧录/综合/OpenOCD进程均已退出。

网关及键位见 `v3_control_usage.md`。方向键/WASD移动，空格/Z开火，Shift慢速，R重开，C发起/排队公平回放；CPU阶段因基础软件绘制而较慢，没有新增优化或人为降速。若录制还没到600 tick，比较请求会等其完成。冷加载后CPU成绩尚未测量时显示不可用；按C完成比较后，LIVE保留新测成绩并标STALE，不写死或从历史日志填入FPS。

下一步仍按第9天做冻结R7五档同版瓶颈复测，按测得的构建/提交/busy/背景/PRESENT决定是否值得做实例前端。互动候选目前固定64请求档，暂未接入扩档/实例前端；背景换代、断网复位矩阵、完整物理CDC、整机像素和30分钟耐久尚未验收。单函数丢弃时间统计的250 ms以上部分、首次下溢统计包含启动区间是已记录的次要限制。历史 SoC 两项测试异常和启动/热重载问题仍保留，不宣称已解决。没有新的组员文件依赖。
