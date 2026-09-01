# 盘古 MES2L676-100HP RISC-V 平台设计

## 目标

以盘古 `MES2L676-100HP + 底板一` 为最终板级目标，把现有 Chisel RV32I 五级流水线 Demo 演进为可运行 CoreMark、可接 DDR3、可继续扩展硬件加速器的比赛 CPU 平台。CPU 和通用 SoC 逻辑保持厂商无关；紫光同创专用时钟、复位、DDR3、UART 管脚和约束只放在板级适配层。

## 不可破坏约束

- 不修改 `D:/loong/CPU-5/nscscc-solo-la-soc-master/rtl/`；项目只使用已经复制到 `references/loongarch-core-v2/` 的参考文件。
- CPU 和通用 SoC 使用 Chisel 编写，交付给 PDS 的输入是 Chisel 生成的 SystemVerilog。
- 保留五级单发射结构，新增逻辑需要控制组合路径级数。
- 保留 `0x8000_0000` 以上的外部存储窗口，为后续 AXI4/DDR3 适配预留稳定边界。
- 中间迭代使用 Chisel 仿真和 Verilator；只有阶段性收口才运行一次综合，不频繁调用 Vivado。

## 分层结构

1. `Rv32Core`：五级 RV32I、旁路、冒险控制、精确异常；后续增加机器模式 CSR、中断返回、分支预测和 Cache。
2. `SoCTop`：Boot RAM、UART、GPIO、机器计时器、加速器寄存器和外部存储窗口。
3. `CoreBusAxiBridge`：后续把现有单请求 CoreBus 转换为 AXI4；CPU 与厂商 DDR 控制器之间只通过该边界耦合。
4. `PangoMes2l676Top`：后续负责盘古时钟/复位、UART 串行收发、按键/LED 和 PDS IP 连接，不包含 CPU 微架构逻辑。

## 第一阶段：上板必需基础

第一阶段只增加两个最小外设。

### GPIO

GPIO 基址为 `0x1000_1000`，窗口大小 `0x1000`：

| 偏移 | 名称 | 访问 | 定义 |
|---:|---|---|---|
| `0x00` | `OUTPUT` | R/W | 低 8 位驱动 LED 等输出，复位为 0 |
| `0x04` | `INPUT` | R | 低 8 位采样按键等输入 |

只接受对齐的 32 位访问。非法偏移、写只读寄存器或不完整写掩码返回总线错误且无副作用。

### 机器计时器

计时器使用 CLINT 兼容的地址布局，基址为 `0x0200_0000`，窗口大小 `0x1_0000`：

| 偏移 | 名称 | 访问 | 定义 |
|---:|---|---|---|
| `0x4000` | `MTIMECMP_LO` | R/W | 比较值低 32 位 |
| `0x4004` | `MTIMECMP_HI` | R/W | 比较值高 32 位 |
| `0xBFF8` | `MTIME_LO` | R | 自复位起的周期计数低 32 位 |
| `0xBFFC` | `MTIME_HI` | R | 自复位起的周期计数高 32 位 |

`mtime` 每个 SoC 时钟加一并自然回绕。`mtimecmp` 复位为全 1；当无符号 `mtime >= mtimecmp` 时 `timerInterrupt` 拉高。32 位分片访问用于兼容 RV32 软件；软件通过高-低-高重读方式获得一致的 64 位时间。第一阶段只把中断线送到 `SoCTop` 输出，CSR 阶段再接入 CPU。

## 后续阶段

1. 实现机器模式 CSR：`mstatus/mie/mtvec/mepc/mcause/mtval/mip/mscratch`、CSR 指令和 `MRET`，接入计时器中断。
2. 移植官方 CoreMark，先在仿真验证，再在真实板卡上运行至少 10 秒，报告 CoreMark、CoreMark/MHz 和 CoreMark/LUT。
3. 增加小型 BTB 与 2-bit 饱和计数器方向预测，不延长取指关键路径。
4. 增加可参数化的两路组相联 I-Cache/D-Cache，并用突发 AXI4 访问盘古 DDR3。
5. 根据盘古官方 PDS 参考工程加入器件、管脚、PLL 和 DDR3 IP 配置；在拿到官方约束前不猜测引脚号。

## 验证原则

- 每个新硬件行为先写能正确失败的 Chisel 测试，再写最小实现。
- 外设单元测试覆盖合法读写、复位值、错误访问和背压保持。
- 互连测试覆盖边界地址和响应目标锁定。
- 软件测试在真实 `Rv32Core + SoCTop` 仿真中访问 MMIO，不用主机侧假数据代替。
- 第一阶段不增加 AXI、Cache 或厂商 IP；这些功能在拥有独立测试和明确接口时再加入。
