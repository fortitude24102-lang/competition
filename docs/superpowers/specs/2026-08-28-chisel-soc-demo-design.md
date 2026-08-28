# Chisel SoC Demo 设计规格

## 1. 目标与范围

在现有 `Rv32Core` 五级 RV32I CPU 之外完成任务书 Day 3～14 的 SoC 主线：地址表、片上 RAM、UART 控制口、加速器寄存器、视频外部模块、SoC 顶层、测试、RTL 生成与 Vivado 集成记录。

本轮不再修改 CPU 微架构，不临时实现完整 AXI4，也不加入 Cache、DMA、操作系统或复杂参数框架。实际板级 bitstream 需要板级顶层、XDC、时钟复位和视频物理接口齐备后才能验收；这些外部文件未到位时，以可综合 SoC RTL、程序仿真和核级 OOC 综合作为独立里程碑。

## 2. 已确认约束

- CPU 使用现有 Chisel `Rv32Core`，其指令/数据端口均为 `CoreBusIO`。
- Chisel 负责 SoC 底座、地址译码、寄存器和连接；视频算法保持独立 Verilog。
- 首版使用简单 ready-valid 请求/响应，不为 Demo 重做 AXI。
- 必须预留日后 AXI 接入点；未来接 AXI 时不得修改 CPU、AccelRegs、UART 软件地址或视频控制接口。
- 所有环境与构建缓存继续位于 `D:\Chisel-environment`，项目位于 `D:\ZYNQ\smallproject`。
- 原始 LoongArch CPU 工程保持只读。

## 3. 方案选择

采用最小 SoC 互连方案：CPU 内部继续使用 `CoreBusIO`，SoC 互连按固定地址表选择 RAM、UART、AccelRegs 或外部存储窗口。每个目标最多接收一个未完成请求，并为读、写都返回一次响应。

不直接把 AXI 信号放进 CPU 或外设。预留两个外部 `CoreBusIO` 主端口（指令、数据），未来新增一个独立 `CoreBusAxiBridge`，在桥内完成双端口仲裁、AXI ID/通道状态及宽度转换。这样 AXI 的五通道反压不会进入 CPU 流水级，也不会改变软件可见寄存器。

## 4. 地址空间

| 区域 | 地址范围 | 首版用途 | 后续 AXI 关系 |
|---|---:|---|---|
| Boot RAM | `0x0000_0000`～`0x0000_FFFF` | 64 KiB 双端口指令/数据 RAM | 后续可替换为 Boot ROM + SRAM |
| UART | `0x1000_0000`～`0x1000_0FFF` | MMIO 发送与状态 | 保持片内外设，不走外部 AXI |
| Accelerator | `0x3000_0000`～`0x3000_0FFF` | 视频控制/状态寄存器 | 保持片内外设或以后挂 AXI-Lite 桥 |
| External Memory | `0x8000_0000`～`0xFFFF_FFFF` | 透传到预留外部 CoreBus 端口 | 日后连接 AXI4 Master |
| 其余地址 | — | 返回总线错误 | 不静默别名到其他设备 |

加速器寄存器：

| Offset | 名称 | 属性 | 位定义/复位值 |
|---:|---|---|---|
| `0x00` | CTRL | R/W | bit0 enable，复位 0 |
| `0x04` | STATUS | R | bit0 busy，bit1 frameDone |
| `0x08` | MODE | R/W | bits[1:0]：0 bypass，1 gray，2 threshold；复位 0 |
| `0x0C` | THRESHOLD | R/W | bits[7:0]，复位 128 |
| `0x10` | BYPASS | R/W | bit0，复位 1 |

UART 寄存器：

| Offset | 名称 | 属性 | 定义 |
|---:|---|---|---|
| `0x00` | TXDATA | W | 写低 8 位产生一个发送字节 |
| `0x04` | STATUS | R | bit0 txReady |

## 5. 模块划分

### `MemoryMap`

只保存基地址、窗口大小、offset 与地址匹配函数，不包含状态。

### `AccelRegs`

作为 `CoreBusIO` 从设备，保存 enable、mode、threshold、bypass；采样外部 busy/frameDone。写掩码必须作用到对应字节，非法 offset 返回 `error=true` 且不改变寄存器。

### `MmioUart`

作为 `CoreBusIO` 从设备，把 TXDATA 写入转换成 `Decoupled(UInt(8.W))` 字节流。首版不自行产生波特率和串行波形，由板级 UART IP 或后续串行发送器消费；这样可在仿真中直接检查软件输出，也不把板卡时钟参数写死在 SoC。

### `DualPortRam`

提供独立指令和数据 `CoreBusIO` 从端口，容量 64 KiB，支持字节写掩码。指令端只允许读；越界、未对齐或指令写请求返回错误。初始化内容通过生成参数或测试加载，RTL 不依赖测试目录临时文件。

### `SoCInterconnect`

指令端命中 Boot RAM 或 External Memory；数据端命中 Boot RAM、UART、Accelerator 或 External Memory。请求被接受后锁存目标，直到对应响应握手，禁止响应串线。未映射地址返回一次错误响应。

### `VideoAccelExt`

使用 Chisel 7 `ExtModule` 声明 `VideoAccelTop` 的显式 clock/reset、24 位像素输入输出、valid、mode、threshold、bypass、busy 与 frameDone。`rtl/video/VideoAccelTop.v` 首先提供可替换的稳定 Demo 实现：bypass、gray、threshold；后续组员可替换模块内部，但不能改端口。

### `SoCTop`

实例化 `Rv32Core`、RAM、互连、UART、AccelRegs 和 VideoAccelExt。顶层暴露视频流、UART 字节流、预留外部指令/数据 CoreBus 端口，以及 commit/trap/halted 调试信号。

## 6. 数据流

1. CPU 从 Boot RAM 取指并执行裸机 RV32I 程序。
2. 普通 load/store 访问 Boot RAM；MMIO 地址由数据互连路由到 UART 或 AccelRegs。
3. 软件写 MODE/THRESHOLD/BYPASS，AccelRegs 输出直接连接 VideoAccelExt。
4. 视频像素和 valid 穿过外部 Verilog，状态回到 AccelRegs。
5. 访问 External Memory 窗口时从 SoCTop 的预留 CoreBus 端口发出；首版测试环境可返回错误，日后接 AXI 桥。

## 7. AXI 扩展边界

后续 `CoreBusAxiBridge` 独立于本计划实现，接口定义为两个 `Flipped(new CoreBusIO)` 输入和一个 AXI4 Master 输出。桥负责：

- 指令/数据请求仲裁；
- AXI AR/R 与 AW/W/B 五通道状态；
- 32 位单拍访问与字节 strobe；
- AXI error 到 `CoreBusResp.error`；
- 最多未完成事务数量和 AXI ID 管理。

首版不创建不完整的 AXI Bundle 或空状态机。预留通过稳定地址窗口、外部 CoreBus 端口和独立桥模块边界完成。

## 8. 测试与验收

- `MemoryMapSpec`：所有窗口边界和非法空洞。
- `AccelRegsSpec`：reset、全部寄存器读写、写掩码、只读状态、非法 offset。
- `MmioUartSpec`：TXDATA 反压、STATUS、非法访问。
- `DualPortRamSpec`：取指、load/store、字节掩码、并发端口、越界错误。
- `SoCInterconnectSpec`：每个目标路由、响应锁定、外部窗口和未映射错误。
- `VideoAccelExtSpec`：验证外部 Verilog 被真实编译并覆盖 bypass、gray、threshold 三种像素模式。
- `SoCTopSmokeSpec`：编译的 RV32I 程序写加速器寄存器、读回并向 UART 输出 PASS 字节，最后 EBREAK。
- 一条命令从源代码生成 `generated/SoCTop.sv`，并让 Verilator 同时检查生成 SV 与外部 Verilog。
- Vivado 对 SoCTop 做一次 OOC 综合，记录 100 MHz WNS、逻辑级数和资源；不进行一般频率调优。

## 9. 文档与交付物

- `chisel/src/main/scala/soc/MemoryMap.scala`
- `chisel/src/main/scala/soc/AccelRegs.scala`
- `chisel/src/main/scala/soc/MmioUart.scala`
- `chisel/src/main/scala/soc/DualPortRam.scala`
- `chisel/src/main/scala/soc/SoCInterconnect.scala`
- `chisel/src/main/scala/soc/VideoAccelExt.scala`
- `chisel/src/main/scala/soc/SoCTop.scala`
- 对应 Chisel 测试与 SoC 裸机 smoke 程序
- `rtl/video/VideoAccelTop.v`
- `generated/SoCTop.sv`
- `scripts/gen-soc-rtl.ps1`、`scripts/verify-soc.ps1`
- `docs/memory_map.md`、`docs/accel_if.md`、`docs/chisel_build.md`、`docs/integration_fix.md`

板级 `demo_v0.bit`、`demo_v1.bit`、连续运行 30 分钟和 `demo-v1` 标签只有在板级工程/XDC、C 控制程序及实际视频链路具备后执行，不用伪造文件代替验收证据。

## 10. 非目标

- 本轮不实现 AXI4/AXI4-Lite 协议状态机；
- 不增加 Cache、DMA、CSR/中断或操作系统支持；
- 不修改 `Rv32Core` 五级流水微架构；
- 不为追求代码抽象而建立通用 SoC 框架；
- 不手工修改 Chisel 生成的 SystemVerilog。
