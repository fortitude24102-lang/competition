# SoC 集成接口冻结与后续条件

## 当前已冻结

- CPU：RV32I 五级流水，指令/数据各一个 `CoreBusIO`。
- 启动 RAM：`0x0000_0000`～`0x0000_ffff`，64 KiB，独立指令/数据端口。
- UART：`0x1000_0000`，TXDATA 写低 8 位输出一个字节；`0x1000_0004` 返回发送就绪状态。
- 视频加速器：`0x3000_0000` 寄存器窗口，CTRL/MODE/THRESHOLD/BYPASS 可写并可读回。
- 外部扩展：`0x8000_0000` 以上分别经一项寄存缓冲从外部指令和数据 `CoreBusIO` 导出，供以后接入 AXI 桥；请求、响应两向均切断组合反压路径。
- 视频 Verilog：模块名 `VideoAccelTop` 及 `docs/accel_if.md` 中的端口名称、方向和宽度不得更改；可以替换模块内部算法。

## 已验证的软件链路

`smoke.S` 依次写入 CTRL=1、MODE=2、THRESHOLD=128、BYPASS=0，读回 MODE 和 THRESHOLD，成功后向 UART 写 ASCII `P`，最后执行 EBREAK。仿真同时检查控制输出、UART 字节和异常号 3，因此不是仅对寄存器模块做孤立测试。

## Day 11～14 的真实前置条件

以下输入目前未在项目中提供，所以本里程碑不伪造 bitstream 或板上运行结论：

- 与实际 Zynq 板卡匹配的板级顶层、时钟/复位方案和 XDC 管脚约束；
- CPU 外部内存到 PS/DDR 或 AXI Interconnect 的 `CoreBusAxiBridge`；
- 实际视频输入、输出、时序和可能存在的跨时钟域设计；
- 面向板端的 C 控制程序、下载/启动方法和串口物理发送模块或 IP；
- 板上 `demo_v0.bit`、`demo_v1.bit`、连续 30 分钟运行记录及最终标签。

拿到这些输入后，应保持现有内存映射和视频端口不变，在 SoCTop 外围新增板级适配层，而不是回改 CPU 或本 Demo 的软件接口。
