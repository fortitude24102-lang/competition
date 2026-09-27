# V2 以太网与实时性能对比实施记录

依据：已批准的一周升级计划、`v2_interface_contract.md` 和赛题原文。

目标：Sapphire 发起资源请求，PC 仅返回文件字节，资源通过官方网口与 Asset DMA 进入 DDR；屏幕持续显示同一场景的纯 CPU 与 GPU 绘制 FPS。画面沿用已有资源，工作量集中于完整链路与性能证据。

- [x] 官方 MAC 适配、GET 发送控制、包接收保护与跨域 FIFO（联调仿真通过）。
- [x] Sapphire APB 网络驱动、分块超时重试、完整资源 CRC 与就绪标志。
- [x] 板顶层网络与 GPU DMA 接线、官方网口约束、工程源文件清单；map/interface/pnr/pgm 通过。
- [x] 同一命令场景的软件绘制、CPU/GPU 交替窗口、明确标签的实时 HUD；主机测试和 RV32 构建通过。
- [ ] 覆盖坏包/背压/恢复、客户端重试、两种绘制一致性和整板结构的离线检查。
- [ ] 同一候选位流的真实以太网、HDMI 与帧率上板验收。

性能口径：CPU/GPU 分时测量，避免双方并发争抢 DDR；屏幕同时保留最近有效成绩并标注当前模式。渲染吞吐与含 PRESENT 的实际帧率分别统计；初始化和 CRC 校验不计入帧率。结果无实测时显示待测，不预填 60。高负载模式在同一帧使用 Alpha 和 Color Key。

网络口径：停等 GET/DATA，20 ms 响应超时、最多 5 次重试；GPU 只写资源区。仅完整资源 CRC 匹配才对渲染器开放。网络失败保留错误状态，并允许本地性能 Demo 继续运行；此回退不得记为网络验收通过。

## 已取得的离线证据（2026-09-26）

- `test_network_assets.c`：GET 字节序、1024+1024+3 字节尾块、丢包重试、DMA abort/restart、最大重试次数、DDR 地址边界、错误完整 CRC、最终提交与分离寄存器读取之间的竞态均通过。
- `test_v2_assets.c`：协议服务与缓存检查通过；已修复错误响应覆盖原 GET、导致重试请求字段被污染的问题，并增加回归。
- Windows 原生 C `asset_server.exe` 已构建；UDP 回环测试通过，完整读取仓库中四份正式资源并逐块验证编号、偏移、长度、sequence、LAST、CRC，最后逐字节核对完整文件。回环测试不代表板卡吞吐。
- Efinity Interface Designer 的加载与设计检查通过；官方 GE PLL 与 DDR PLL 冲突已通过移至空闲 PLL 解决。完整逻辑综合和时序验收分别记录，接口检查不替代它们。
- 板卡连接后物理“以太网 2”已为 Up、1 Gbps，地址 192.168.1.2/24；USB 串口识别 COM13、COM14。候选固件使用板卡 192.168.1.3 / PC 192.168.1.2，没有修改电脑的 IP 或防火墙。
- 官方双 MAC 联调仿真通过：ARP、非零 GET、DATA 64/1024 字节、载荷 CRC 拒收、异步时钟、背压和复位。仿真对端必须主动 ARP，发送数据时序按官方 mac_test 对齐。
- 完整 Efinity map/interface/pnr/pgm 通过，报告中的 setup/hold clock relationship 均为正裕量；候选位流已经 JTAG 临时下载，未写 Flash。构建目录为 `D:/efinity_builds/v2_ethernet_compare_20260926`。
- 软件回归通过，修正全屏填充测试残留的 640×480 常量；HUD 最坏测试使用 686/1024 条命令。固件 text=16994、data=0、bss=47496 字节（size 工具口径），未覆盖 V1 release。
- 上板读回 GPU ID `32444750`、NET ID `4e455431`。本轮先 `reset halt` 再 load/resume 后成功运行；运行中反复建立调试连接、暂停再恢复曾出现 PC 异常，后续性能采集使用连续运行的串口日志，不以暂停中的数值计成绩。

## 首轮真实上板结果

COM13，115200 baud。PC 只运行静态资源服务，不参与渲染和逐帧逻辑。

| 资源 | 字节数 | GET 次数 | 重试 | 加载及校验耗时 | 返回码 |
|---|---:|---:|---:|---:|---:|
| scene | 1036800 | 1013 | 0 | 2391 ms | 0 |
| flower | 10240 | 10 | 0 | 23 ms | 0 |
| zombie_walk1 | 10240 | 10 | 0 | 23 ms | 0 |
| zombie_walk2 | 10240 | 10 | 0 | 23 ms | 0 |

固件报告 `network_result=0`。32 Sprite、每窗口 30 帧，两轮结果：CPU `fps_x10=21`、render_us=451390/453163；GPU `fps_x10=85`、render_us=95738/95781。约为 2.1 对 8.5 FPS；这是含 HUD/PRESENT 的实际帧率，不是 60 Hz HDMI 刷新率。尚未达到 60 FPS，未取得 300 帧稳定性或 Sprite 极限结果；显示效果仍需用户现场确认。

使用入口与寄存器说明见 `v2_network_usage.md`。
