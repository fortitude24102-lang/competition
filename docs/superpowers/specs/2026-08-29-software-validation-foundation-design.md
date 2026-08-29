# 软件与验证基础设计

## 目标

建立项目内第一条可执行的 bare-metal C 验证链：C 程序通过 MMIO driver 配置加速器寄存器、读回比较，并在现有 RV32I SoC 仿真中自动给出 PASS/FAIL。这样后续 CLI 只调用 driver，不再散落裸地址。

## 范围

- 建立最小 `sw/` 目录，包含 MMIO 基础函数、加速器 driver、启动代码、链接脚本和寄存器测试。
- 使用现有 `riscv64-unknown-elf-gcc`，固定 `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`。
- 新增一个构建脚本生成 ELF、BIN 和供 Chisel RAM 初始化使用的 HEX。
- 新增 SoC 仿真用例，执行 C 程序并检查 UART 字节、EBREAK 和最终控制寄存器值。

当前 `MmioUart` 只有发送通道，没有 RX 寄存器或输入端口，因此本轮不伪造 UART CLI、echo 或命令解析。它们必须等 SoC UART RX 接口定义后再做。本轮也不包含板卡下载、串口波特率和真实画面验证。

## 软件接口

`mmio.h` 只提供 volatile 32 位读写。加速器 driver 集中定义 `0x3000_0000` 基地址和寄存器 offset，并提供：

- 设置 enable、mode、threshold、bypass；
- 读取 status 和软件可读回的控制寄存器；
- 拒绝超出已定义模式范围的 mode；
- threshold 使用 8 位类型，调用边界天然限制为 0～255。

测试程序写入 enable=1、mode=threshold、threshold=128、bypass=0，逐项读回。全部一致时向 UART TXDATA 写入 ASCII `P`，否则写入 `F`，随后执行 EBREAK。

## 构建与验证

构建脚本不依赖 `target/` 或手工修改的 generated 文件。SoC 测试加载生成的 HEX，要求：

- UART 只出现一个 `P`；
- trap cause 为 EBREAK；
- enable、mode、threshold、bypass 输出与 C 写入一致；
- 失败路径会输出 `F`，不会静默通过。

现有汇编 smoke test 保留，C 验证作为独立用例加入，便于区分 CPU/互连回归与软件 driver 回归。
