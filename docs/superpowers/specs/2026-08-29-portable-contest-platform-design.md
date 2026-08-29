# 可移植 FPGA 比赛底座设计

## 目标

把现有 Chisel SoC、视频 RTL 和 bare-metal 软件合并为一套不押具体赛题的比赛底座。正式赛题公布后，主要工作应收敛为替换算法模块、接入指定板卡接口/IP、增加少量软件命令和测试数据，不重写 CPU、控制总线或验证框架。

## 设计依据

近年 FPGA 创新设计赛题覆盖图像/视频、音频、无线通信、高速采集、协议分析、RISC-V SoC 和异构计算。它们的共同部分不是某个固定算法，而是：

- CPU/MMIO 控制面；
- 支持背压的连续数据流；
- 明确的数据边界和处理完成语义；
- 可观测的吞吐、停顿和帧统计；
- 可脚本化的软件控制与自动回归；
- 与厂商 DDR、AXI、HDMI、以太网和 PCIe IP 解耦的适配边界。

## 总体结构

系统采用“窄腰型”三层结构：

1. 控制层保留现有五级 RV32I、CoreBus、Boot RAM、MMIO 和 bare-metal 驱动。
2. 数据层统一为 `ready/valid/data` 流，并携带 `startOfFrame/endOfLine/endOfFrame` 三个边界标志。
3. 平台层继续暴露外部存储窗口；AXI4、AXI4-Stream、DDR、显示、摄像头和高速通信通过适配器接入，不进入本轮通用逻辑。

## 流接口

Chisel 定义参数化 `StreamBeat(dataWidth)`：

- `data: UInt(dataWidth.W)`；
- `startOfFrame: Bool`；
- `endOfLine: Bool`；
- `endOfFrame: Bool`。

`SoCTop.video.in` 是输入 `Decoupled[StreamBeat(24)]`，`SoCTop.video.out` 是输出 `Decoupled[StreamBeat(24)]`。24 位仅是当前 RGB888 实例的宽度；通用流契约本身不固定为图像。

外部 `VideoAccelTop` 使用等价的扁平 Verilog 端口。模块包含一个输出寄存器，满足：

- 只有 `in_valid && in_ready` 时接受输入；
- 输出阻塞时保持数据、边界标志和 `out_valid` 不变；
- 输出被接受的同一拍可以接收下一输入，稳态吞吐为每拍一个 beat；
- `frame_done` 只在 `out_valid && out_ready && out_end_of_frame` 时脉冲一次；
- `busy` 表示输出缓冲中仍有未完成事务；
- `enable=0` 时不接受新输入，但已经产生的输出仍可排空。

本轮不验证边界标志序列是否合法；源端负责保证首帧、行尾和帧尾标志正确。

## 性能计数器

加速器 MMIO 区域保持基址 `0x3000_0000`，在现有寄存器后追加只读计数器：

| Offset | Name | Definition |
|---:|---|---|
| `0x14` | `PERF_CTRL` | 写 bit0=1 原子清零全部计数器，读回 0 |
| `0x18` | `CYCLE_COUNT` | 清零后经过的 SoC 时钟数 |
| `0x1C` | `INPUT_COUNT` | 接受的输入 beat 数 |
| `0x20` | `OUTPUT_COUNT` | 接受的输出 beat 数 |
| `0x24` | `FRAME_COUNT` | 接受的帧尾 beat 数 |
| `0x28` | `STALL_COUNT` | `out_valid && !out_ready` 的周期数 |
| `0x2C` | `BUSY_CYCLES` | `busy` 为 1 的周期数 |

所有计数器为 32 位自然回绕。清零优先于当拍事件累计，避免软件读取后无法建立明确测量起点。计数器位于现有 `AccelRegs`，不增加新的 MMIO 区域或总线仲裁。

## UART 接收与命令行

`MmioUart` 增加一个已解码字节的 `Decoupled` 接收口和一个字节缓冲。串行采样、波特率发生器和板级管脚属于平台适配层，不在本轮实现。

UART 寄存器扩展为：

| Offset | Name | Definition |
|---:|---|---|
| `0x00` | `TXDATA` | 写低 8 位发送一个字节 |
| `0x04` | `STATUS` | bit0 `txReady`，bit1 `rxValid` |
| `0x08` | `RXDATA` | 有数据时读取低 8 位并消费；空读返回总线错误 |

软件提供无 libc 的轮询 UART BSP，以及固定 64 字节行缓冲的轻量 CLI。CLI 支持：

- `help`
- `status`
- `mode 0|1|2`
- `threshold 0..255`
- `bypass on|off`
- `enable on|off`
- `perf`
- `perf clear`

合法命令回复 `OK` 或状态文本；未知命令、非法数字和超长输入回复 `ERR`，不得访问错误地址或越界写缓冲区。

## 自动回归

验证分三层：

1. SystemVerilog 独立测试验证 RTL 背压、数据保持、帧尾完成脉冲和一拍一 beat 吞吐。
2. Chisel/ExtModule 测试读取一份带字面期望值的 CSV 小帧，在确定性的输出停顿模式下检查无丢失、无重复和边界标志对齐。
3. SoC 软件仿真通过 UART RX 输入真实命令，检查 UART TX 回复和 MMIO 控制结果。

中间迭代只运行 Verilator 和 Chisel 仿真。所有任务完成后最多运行一次 Vivado SoCTop 检查，避免频繁调用。

## AXI 与板级边界

现有 `0x8000_0000`–`0xFFFF_FFFF` 外部 CoreBus 窗口继续作为未来 `CoreBusAxiBridge` 的控制/存储边界。通用流接口可由独立适配器映射为 AXI4-Stream；本轮不添加不完整的 AXI 信号、不实现 DMA，也不绑定某家 FPGA 的 DDR、HDMI、MIPI、以太网或 PCIe IP。

## 不在本轮范围

- 新算法库、Sobel、CNN、FFT 或编解码器；
- AXI4 主机、DMA、缓存一致性和 DDR 控制器；
- 物理 UART RX、摄像头、显示和高速串行 PHY；
- 中断控制器、RTOS、Linux、网络协议栈；
- 修改原始 CPU 参考目录中的任何文件。
