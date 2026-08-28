# Chisel SoC 构建与验证

## 固定环境

- Chisel：7.7.0，Scala：2.13.18，sbt：1.12.4
- Java：Temurin OpenJDK 17.0.20.1
- Verilator：5.050
- Vivado：2019.2，器件 `xc7z015clg485-2`
- RISC-V：`riscv64-unknown-elf-gcc`，目标参数 `-march=rv32i -mabi=ilp32`

所有工具和缓存位于 `D:\Chisel-environment`。项目不会修改原始 CPU 参考目录。

## 一键验证

在项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-soc.ps1
```

脚本依次重建裸机镜像、运行完整 Chisel/Verilator 测试、生成 SystemVerilog、联合检查外部视频 Verilog，并且只调用一次 Vivado 做 100 MHz OOC 综合。

只重新生成 RTL：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gen-soc-rtl.ps1
```

等价的生成入口是 `Generate soc --target-dir ../generated`。`rv32` 和默认 Blink 入口保持不变。

## Vivado 源文件顺序

先读取 `generated/*.sv`，再读取 `rtl/video/VideoAccelTop.v`，顶层指定为 `SoCTop`。`generated/soc-filelist.f` 由验证脚本生成并传给 `scripts/vivado-soc.tcl`，不需要手工维护源文件列表。

## 100 MHz OOC 检查点

2026-08-28 的 Vivado 2019.2 OOC 实测结果：

- 时钟：100 MHz（10.000 ns）
- WNS：`+1.138 ns`
- 数据路径延迟：`8.622 ns`，其中逻辑 `2.581 ns`、未布局布线估算 `6.041 ns`
- 逻辑级数：14（3 个 CARRY4 与 11 个 LUT）
- 最差路径：`core/idEx_rs1_reg[2]/C` → `core/frontend/nextPc_reg[0]/CE`
- 原语计数：2288 LUT、1739 FF、16 RAMB36E1、0 DSP
- `report_utilization` 口径：2115 Slice LUT、1739 Slice Register、16 Block RAM Tile、0 DSP

该路径位于原 CPU 的执行/重定向控制链，不经过 SoC 外设 `ready` 串联，也没有连续两个 32 位算术器；同时满足 100 MHz 且有 1.138 ns 余量，因此按 Demo 计划不再为频率做架构改动。OOC 报告中路径延迟约 70% 来自未布局布线估算，后续板级实现仍需用真实布局布线结果重新确认。

报告位于 `generated/reports/soc-demo/`，包括时序、利用率和 `SoCTop_ooc.dcp`。

## AXI 扩展边界

当前 `0x8000_0000`～`0xffff_ffff` 从 `externalImem`、`externalDmem` 两个稳定 `CoreBusIO` 主端口导出。后续新增独立 `CoreBusAxiBridge`，在桥内完成两端口仲裁以及 AXI AR/R、AW/W/B 通道状态机；本里程碑没有放置不完整的 AXI 协议信号或空状态机。
