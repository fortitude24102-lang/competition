# FPGA 比赛底座移植指南

## 赛题公布后的处理顺序

1. 先确认指定 FPGA/SoC、EDA 版本、输入输出接口、数据率和评分指标。
2. 保留 `chisel/src/main/scala/cpu/`、CoreBus 地址空间和软件启动代码不变。
3. 用离线样例在通用流接口上完成算法，再接板级输入输出。
4. 复用性能计数器确认吞吐和停顿，再决定是否需要 DDR/DMA。
5. 最后加入 XDC、厂商 IP 和板级包装，并只在纯仿真通过后运行实现流程。

## 四个替换边界

### 1. 算法 RTL

当前示例位于 `rtl/video/VideoAccelTop.v`，完整端口契约见 `docs/accel_if.md`。新算法可以继续使用 Verilog/SystemVerilog，也可以由其他 HDL 生成，只要保持：

- 输入和输出采用 `valid/ready` 握手；
- 输出阻塞时保持数据和边界标志稳定；
- 稳态允许每拍接受一个 beat；
- `frame_done` 只对应实际完成的帧尾输出。

替换算法不需要修改 CPU、CoreBus、Boot RAM、UART 或软件启动文件。算法新增参数时，在 `AccelRegs.scala` 的空余 MMIO 偏移追加寄存器，并同步更新 `accel_driver.h/.c`。

### 2. AXI4-Stream 或其他流接口

Chisel 数据契约定义在 `chisel/src/main/scala/soc/StreamBeat.scala`，当前 RGB888 实例在 `SoCTop.video` 使用 24 位 `data` 和三个边界标志。

板级适配器负责映射到指定平台。对常见视频 AXI4-Stream，可将 `data/valid/ready` 对应到 `TDATA/TVALID/TREADY`，将 `startOfFrame` 对应到 `TUSER[0]`，将 `endOfLine` 对应到 `TLAST`；`endOfFrame` 应按赛题 IP 约定放入额外 `TUSER` 位或由已知分辨率计数生成。该映射必须留在适配器中，不能写死进算法。

音频、ADC、网络负载或协议采样可以实例化不同 `dataWidth` 的 `StreamBeat`，边界位按数据块/包语义使用。

### 3. 外部存储和 AXI4 Memory-Mapped

`0x8000_0000`–`0xFFFF_FFFF` 已从 `SoCTop.externalImem` 和 `SoCTop.externalDmem` 导出。两端均为稳定的 CoreBus 请求/响应接口，并由深度 1 的寄存队列切断顶层组合 ready 路径。

需要 DDR 时新增独立 `CoreBusAxiBridge`：

- 仲裁指令和数据两个 CoreBus 请求源；
- 保持每个 CoreBus 端口最多一个未完成事务的现有约束；
- 在桥内实现 AXI AR/R 与 AW/W/B 状态机；
- 将 AXI 错误响应转换为 CoreBus `error`；
- 不修改 `Rv32Core` 或 `SoCInterconnect` 的内部协议。

只有赛题明确需要连续帧缓存或高带宽块传输时才增加 DMA。DMA 应连接通用流和厂商 AXI/DDR IP，不让 CPU 逐 beat 搬运数据。

### 4. 板级包装和软件命令

`SoCTop.uartRx/uartTx` 是已解码字节流，不是 UART 管脚。板级顶层负责串行接收发送、波特率、CDC、管脚和电气约束。

软件命令位于 `sw/apps/cli.c`，寄存器访问封装位于 `sw/drivers/accel_driver.c`。新增赛题参数时：

1. 在驱动中添加一个有范围检查的读写函数；
2. 在 CLI 中增加一个短命令分支；
3. 在 `SoftwareCliSpec.scala` 输入真实字节并检查回复和寄存器结果。

## 现有自动验证

- `scripts/test-video-rtl.ps1`：独立 Verilog 背压、边界和算法回归。
- `VideoAccelExtSpec`：读取 CSV 小帧，在输出停顿下检查数据和标志不丢失、不重复。
- `AccelRegsSpec`：检查控制寄存器与周期、吞吐、帧、停顿、busy 计数器。
- `MmioUartSpec`：检查 TX/RX 单字节缓冲和空读错误。
- `SoftwareDriverSpec`：在真实 RV32I SoC 上运行 C 驱动正负测试。
- `SoftwareCliSpec`：通过 UART RX 输入命令并检查 UART TX 和 MMIO 结果。

完整交付验证使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-soc.ps1
```

该入口先完成所有纯仿真，再生成 RTL、执行 Verilator lint，最后只调用一次 Vivado。

## 2026-08-30 验证记录

- 独立 `VideoAccelTop` SystemVerilog 回归通过；
- RV32I 驱动正负镜像与交互式 CLI 镜像构建通过；
- 完整 Chisel 回归：23 个套件、48 个测试，0 失败；
- 生成 SoCTop 与外部 Verilog 的 Verilator lint 通过；
- Vivado 2019.2，`xc7z015clg485-2`，100 MHz OOC：WNS `+0.773 ns`；
- 最差路径逻辑级数：14；
- 利用率：2299 Slice LUT、2149 Slice Register、16 Block RAM Tile、0 DSP。

最差路径仍从 CPU `idEx_rs1_reg[2]` 到外部指令请求寄存缓冲，未因视频流、UART RX 或性能计数器扩展而转移到新的控制路径。

## 当前刻意保留的边界

本底座没有通用 DMA、缓存、完整 AXI 主机、中断控制器、RTOS、网络栈、视频 PHY 或摄像头驱动。这些功能依赖正式赛题和指定器件；提前实现会增加移植工作，而不会稳定降低赛后工作量。
