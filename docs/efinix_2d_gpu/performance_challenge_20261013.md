# 60 FPS全活动Sprite性能挑战（2026-10-13）

独立于普通游戏的性能模式：HDMI菜单新增性能挑战入口，网页点击开始；Sapphire产生运动、动画、搜索档位、生成GPU列表和判定成绩，PC仍只负责资源、键盘和显示遥测。原四档游戏、死亡回菜单及CPU绘图算法不变，挑战中不进入CPU比较。

## 固定负载与成绩口径

960×540 RGB565、GPU100MHz；N个逻辑Sprite全部在屏幕内并每帧运动。第一架飞机16×16，其余8×8、六类原精灵形状；全部使用硬件Color Key。每8个Sprite额外绘制一个12×12硬件Alpha光晕，Alpha64..124，光晕不重复计入N。仍每帧搬运HUD下方完整背景，保留HUD、网口控制、命令生成、硬件执行和PRESENT的真实成本。无死亡等待、失活、屏外裁剪、隐藏降载或静态帧代替。

每档预热60帧（健康检查不跳过），测600帧。每帧work≤1/60秒、呈现间隔≤1/40秒，精确累计帧率≥60，活动N固定、Alpha=ceil(N/8)、新增下溢和错误均0，才是候选。最高候选再完整复核3600帧，之后才显示已复核最佳；后续超预算、迟到或健康异常会作废。600帧结果和四舍五入的60.0不等于合格。

先64→128→256→512→容量档，再在通过/失败之间收缩到1个Sprite。该搜索假设固定负载成本近似单调，结果叫“本负载已复核最佳”，不是穷举所有布局得到的全局物理最大值，也不承诺无限时间稳定。一个16KiB列表最多1024条描述符，背景1条、N条Key、ceil(N/8)条Alpha，当前软件容量909；到909只报告容量已到，不报告GPU极限。

## 使用、兼容和退出

网页 `http://127.0.0.1:8765` 点击“开始性能挑战”，自动逐档测量。方向键控制第一架飞机，R重跑挑战，C在挑战中禁用；“一键重选难度”退出并清除网页挑战成绩。新的遥测结果来自板端，不由PC估算；会话、超时、固件/资源变更或普通菜单不复用旧结果。

只给显式 `-PerformanceChallenge` 候选启用。必须有真实FrameList以及新RX能力位（NC STATUS bit5）；旧BIT或普通固件不公布入口能力。GAME opcode3/level0沿用32B V1/CRC/请求幂等流程，原命令1/2不变；原128B/27字段遥测语义不变，新status bits12/13标记能力/活动，独立32B type6回传target、best、stage和窗口帧数。ACK优先，普通和挑战结果分别200ms限频，同一全局快照计数、防旧包、单所有者TX。

状态是私有DDR `0x02d28000`，在原双列表bank之后，不扩大游戏对象BSS或搬动CPU命令缓冲。未新增GPU像素流水、DMA或RAM队列。正常游戏/CPU诊断仍保留；挑战期间禁用阻塞式串口报告，退出菜单后才打印 `PERF_RESULT` 的最终统计，避免诊断输出本身使下一帧超预算。网页管理处理仍计入实测。

候选构建（全新目录，不能覆盖release；两个IP必须显式传入，示例是当前板卡.3/PC.2）：

```powershell
./scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -FrameList -PerformanceChallenge -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory <全新目录>
```

网关复用 `scripts/run-control-gateway.ps1 -BoardIp 192.168.1.3 -UdpBind 192.168.1.2`；资源服务原interactive manifest不变。候选BIT `D:/efinity_builds/performance_challenge_20261013_r1/outflow/efinix_2d_gpu.bit` 使用原已合格列表GPU，仅新增网口opcode接收/能力位。Efinity编译完成，core setup0.651ns/hold0.026ns，DDR setup0.185ns，RAM172，无同步器告警。测试脚本 `test-game-menu-board.ps1 -ExpectedBuild 0x20261013 -PerformanceChallenge` 先四档START/MENU，再自动挑战/3600复核/5秒后续保持，最后回菜单；只JTAG，不写Flash。

## 验证记录与限制

21套C、25项真实UDP/HTTP协议测试、JS行为和实际Edge浏览器协议/键盘测试通过；浏览器模拟明确零FPS/零best，不作为板上性能。网口6组RTL及真实owner子系统通过，默认/候选完整Sapphire链接通过，保留4KiB栈和既有RWX段警告；未实测栈高水位。独立参考覆盖909个对象连续运动/地址/形状，1024描述符容量、边界、600vs3600、精确FPS/预热健康失败/长复核重搜/后续作废。

两次早期构建地址错误导致资源超时/无ACK（用了旧192.168.0网段，第二次仅改了主机顺序），失败日志保留；正确配置是c0a80103/c0a80102，未将参数修正冒充网络算法优化。第一轮R4固件626完成3600复核，但复核结束的串口报告使下一帧迟到，成绩随即清零；不能发布该值为当前稳定结果。R5消除挑战中的阻塞式诊断后，按同BIT/固定负载重新实测，最终数据待回填。

尚未计入本轮：普通游戏512严格60、CPU600tick慢比较、30分钟耐久、实体断网重连和新的人工HDMI照片。没有更改这些结论，不把一次3600复核推广为长期保证。
