# GPU 纹理 Cache 实现与板测（2026-09-28）

## 结论

本轮接受 4 KiB、软件管理的 GPU 纹理 Cache，作为下一版源码性能候选，
但不替换 `release/v2/`。它不改变 960×540 RGB565 双缓冲、100 MHz GPU、
CPU 软件对照、游戏逻辑、对象数量、Alpha 或 Color Key 功能。

同一 512 档弹幕工作量下，Color Key 阶段由 6.745～7.281 ms 降到
2.621～2.796 ms，改善 58.5%～64.0%；FULL 由 17.724～17.884 ms 降到
12.304～12.365 ms，改善 30.4%～30.9%。三组结果均为零显示下溢、零
硬件错误，且 512 档 Key 的 DDR 前景读取降为 0。因此收益明显超过测量
噪声，满足保留条件。

普通 64 档演示的 GPU 渲染时间仅由约 10.22 ms 降到约 9.30 ms，改善约
9%；屏显窗口仍为 40.0～58.1 FPS，300 帧 P5=30，未稳定达到 60 FPS。
原因是 64 档重复前景流量较小，整屏背景 Copy、HUD、Present/垂直同步
已经成为主要限制。不能用 512 档阶段收益冒充普通演示 FPS 收益。

## 实现边界

- Cache 为 1024×32 bit（4096 B），整图集一次预加载，不做自动替换、
  写回或通用组相联设计。
- Sapphire 在资源长度/CRC 确认后写入基址和 3104 B 长度并触发装载；
  PC 仍只提供资源，RISC-V 仍负责协议、资源选择、游戏逻辑和 GPU 命令。
- Color Key/Alpha 的整个源矩形命中时从片上 RAM 读取；未命中、无效或
  装载失败时整条命令回退 DDR。Alpha 背景读取和全部目标写回仍走 DDR。
- APB 新增 `0x0090～0x00a4`，旧寄存器到 `0x008c` 保持不变；GPU 版本为
  `0x00010100`。软件接口为 `gpu_texture_cache_load` 和
  `gpu_texture_cache_invalidate`。
- 普通固件在网络资源成功时缓存网络图集地址，失败时缓存内容相同的本地
  后备图集；Cache 失效不会导致 Demo 无画面。

## 验证结果

### 仿真、构建与资源

- 完整 GPU 回归：72 项，71 项初次通过；唯一失败为旧 Asset DMA 测试把
  `0x008c` 固定当作永久最大寄存器。更新为同时检查旧端点、新端点
  `0x00a4` 和 Asset DMA 起点 `0x0100` 后，受影响套件 4/4 通过。未重复
  已完成的长回归。
- Efinity 2026.1：map、interface、pnr、pgm 全部通过。
- 核心 100 MHz setup/hold 余量：+0.871/+0.026 ns；SDRAM 关系：
  +0.274/+0.061 ns。
- LUT 29,815；FF 27,759；RAM10 145（基线 141，增加 4）；DSP 20。

板端短测试输出：

```text
TEXTURE_CACHE_BOARD_PASS,cached=12,fallback_rd=16
TEXTURE_CACHE_BOARD_STOP,result=0,hardware=0
```

这同时证明命中读、未命中 DDR 回退和硬件完成状态。原始记录见
[`board-correctness.log`](evidence/texture-cache-20260928/board-correctness.log)。

### 五档固定工作量

每档使用 tick 0/90/180 三个相同逻辑时刻。下表为三次最小～最大值，
不含等待垂直同步的 Present：

| 档位 | Key | Alpha | FULL | 下溢/错误 |
| ---: | ---: | ---: | ---: | ---: |
| 32 | 0.231～0.248 ms | 0.192～0.225 ms | 8.412～9.125 ms | 0/0 |
| 64 | 0.312～0.419 ms | 0.289～0.319 ms | 8.613～8.670 ms | 0/0 |
| 128 | 0.644～0.752 ms | 0.502～0.515 ms | 9.166～9.184 ms | 0/0 |
| 256 | 1.306～1.413 ms | 0.863～0.898 ms | 10.277～10.974 ms | 0/0 |
| 512 | 2.621～2.796 ms | 1.006～1.631 ms | 12.304～12.365 ms | 0/0 |

512 档的功能计数与上一半字相位候选一致：tick 0/90/180 的总命令为
584/582/583，Key 为 515/513/514，Alpha 均为 68。流量变化如下：

| tick | Key DDR 读：旧→新 | Cache 读 | FULL DDR 读：旧→新 | FULL Cache 读 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 67,424→0 B | 67,424 B | 1,144,496→1,057,488 B | 87,008 B |
| 90 | 66,480→0 B | 66,480 B | 1,143,840→1,058,064 B | 85,776 B |
| 180 | 66,672→0 B | 66,672 B | 1,143,264→1,057,104 B | 86,160 B |

减少的 FULL DDR 读字节与 Cache 读字节逐项相等，说明计数口径没有把
流量隐藏或重复计算。完整计数见
[`five-tier-profile.log`](evidence/texture-cache-20260928/five-tier-profile.log)。

### 普通 CPU/GPU 演示

CPU 路径未接入 Cache 或 GPU。干净重载 FPGA 后，CPU 十个已输出窗口均
为 2.8 FPS，渲染平均 296.95 ms；GPU 已捕获的九个完整 30 帧窗口为
40.0～58.1 FPS，渲染平均 9.301 ms。串口在第 300 个 GPU 样本摘要处
停止，因此第十个 GPU 窗口的打印行未收录，但 300 个逐帧样本已全部进入
摘要：

```text
BULLET_GPU_300,target=64,frames=300,p5_fps=30,underflows=0,errors=0,windowed_60fps=0
```

这次 PC 端 UDP 8080 服务进程已经退出，固件重试 5 次后报告
`network_result=-22`，按既定容错路径使用本地后备图集；Cache 状态有效，
但本记录不能充当一次新的以太网成功加载证明。以太网路径本身仍保留，
此前同一场景 ID 101/102 的成功加载证据在
[`bullet-board-20260928`](evidence/bullet-board-20260928/) 中。本轮普通演示
原始记录见 [`normal-cpu-gpu.log`](evidence/texture-cache-20260928/normal-cpu-gpu.log)。

## 测量纪律与复现

只用 OpenOCD `reset halt` 会复位 Sapphire CPU，不会清空 GPU 扫描、翻页
和性能计数状态。连续换固件而不重载位流会产生大量假下溢；本轮最初的
污染日志已排除。每个正式板测前都重新 JTAG 加载同一个位流，然后才加载
对应固件。没有写 Flash。

关键命令如下（路径按本机安装）：

```powershell
& D:\efinity\pgm\bin\ftdi_pgm.bat `
  D:\efinity_builds\texture_cache_20260928\outflow\efinix_2d_gpu.bit -m jtag

& D:\efinity\risc_v_gcc\openocd\bin\openocd.exe `
  -f ftdi_ti.cfg -f debug_ti.cfg `
  -c 'init; reset halt; load_image <firmware.bin> 0x1000 bin; resume 0x1000; shutdown'
```

固件由以下仓库命令产生：

```powershell
powershell -NoProfile -File scripts/build-board-hud-dma-test.ps1 -Test texture
powershell -NoProfile -File scripts/build-board-hud-dma-test.ps1 -Test texture-profile
powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Demo bullet `
  -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102
```

哈希：

| 对象 | SHA-256 |
| --- | --- |
| 候选位流 | `84B2E64670B1878B806AA6504AF0826280C3A99830FC60A1F79906662639057A` |
| 正确性固件 | `5F71D8EEA092B94E1A91304CD1A388B7DB5772F4798B602884E275F30F8B48EE` |
| 五档固件 | `4D58AE8EB67474447B117173CE0494270EE2BCA0C4F5BB25E957D2CD854E5FCA` |
| 普通演示固件 | `E84A6FEB410B3DE1248DF27CD9126F924579030F37C400A504B23193D6FFBAAB` |

对应硬件集成提交为 `b0588d9`，板测预热修正提交为 `7df4f54`。构建日志和
资源明细见 [`texture-cache-20260928`](evidence/texture-cache-20260928/)。

## 接受范围与下一瓶颈

候选满足像素/计数一致、下溢/错误为 0、时序余量非负、512 档收益可重复
四项接受条件，因此不回滚。它仍有以下边界：

- 未达到普通演示稳定 60 FPS，不能作为赛题最终性能结论。
- 本轮普通演示因 PC 服务未监听而走后备素材；下一次完整验收要先确认
  UDP 8080 正在监听，再记录 `network_result=0`。
- 只做短时固定工作量和 300 GPU 样本，不替代长时间耐久、断网切换或
  最终画质验收。
- 非 GPU 的 `SoftwareDriverSpec`、`PangoBringupSpec` 既有 SoC 固件基线
  异常仍保留，本轮没有处理，不能宣称全项目所有测试通过。

下一项性能工作应直接测量并减少全屏背景 Copy，例如双缓冲感知的脏块
恢复或静态背景分块；不能再把小图集前景读取当作 64 档首要瓶颈。CPU
基础对照保持不变，画面美化继续由另一条工作线负责。
