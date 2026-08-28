# RV32I 五级流水核验证记录

## 验证范围

- ISA：RV32I，ABI 为 ILP32。
- 微架构：IF、ID、EX、MEM、WB 五级顺序流水。
- 数据相关：EX/MEM 与 MEM/WB 前递，load-use 精确暂停。
- 控制相关：分支、JAL、JALR 重定向与错误路径冲刷。
- 存储接口：独立指令/数据 ready-valid 总线，支持可变请求及响应延迟。
- 异常：非法指令、ECALL、EBREAK、取指/数据访问错误、控制流及访存地址错位；trap 后保持 halted 至复位。

## 自动验证入口

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify-rv32i-core.ps1
```

该命令依次验证工具链、编译程序、全部 Chisel 测试、37 个上游 `rv32ui` 程序、RTL 生成与 Verilator 静态检查，并执行最终一次 Vivado 核级时序检查。

## 上游兼容性来源

- `riscv-tests` 固定提交：`2ebecad997fa58cd9e5724340ba75aa4b59bd1d0`。
- `riscv-test-env` 固定提交：`6de71edb142be36319e380ce782c3d1830c65d68`。
- 构建前校验整个上游 `isa/` 源码树摘要：`02edf74107518fa84c63c5a1547e3aa7272f558229b4814b90e6d653f292b7be`。
- 上游源码和构建产物均位于 `D:\Chisel-environment`，没有复制进项目仓库。
- 适配层仅替换特权启动与 PASS/FAIL 通道；指令测试主体及上游 `test_macros.h` 保持不变。

选择的用例为：`add`、`addi`、`and`、`andi`、`auipc`、`beq`、`bge`、`bgeu`、`blt`、`bltu`、`bne`、`jal`、`jalr`、`lb`、`lbu`、`lh`、`lhu`、`lui`、`lw`、`or`、`ori`、`sb`、`sh`、`sll`、`slli`、`slt`、`slti`、`sltiu`、`sltu`、`sra`、`srai`、`srl`、`srli`、`sub`、`sw`、`xor`、`xori`。

## 最终结果

- 统一验证命令：通过，退出码为 0。
- Chisel/Verilator：14 个套件、37 个测试全部通过；Verilator 5.050 RTL 静态检查通过。
- 上游 RV32UI：37/37 个选定二进制通过。
- Vivado 目标：`xc7z015clg485-2`，核级 OOC 综合，100 MHz（10.000 ns）约束。
- 最差建立时间裕量（WNS）：`+1.157 ns`，0 个失败端点。
- 最差数据路径延迟：`8.603 ns`，其中逻辑 `2.581 ns`、布线 `6.022 ns`。
- 最差路径逻辑级数：14（`CARRY4=3`、`LUT4=2`、`LUT5=4`、`LUT6=5`）。
- 最差路径起点：`idEx_rs1_reg[2]/C`。
- 最差路径终点：`ifId_fetchError_reg/CE`。
- 综合资源：1829 个 Slice LUT（3.96%）、1598 个 Slice Register（1.73%）、0 个 DSP、0 个 Block RAM Tile。

最差路径从 ID/EX 源操作数进入执行/重定向控制，再到 IF/ID 写使能。路径只包含一条进位链，没有串联两个主要 32 位运算，也没有经过指令或数据总线的 `ready` 反馈链，因此按照计划不做额外频率调优或第三次 Vivado 运行。

本报告是核级 OOC 里程碑，只对内部寄存器路径施加 10 ns 时钟约束；核外 ready-valid 接口没有板级 input/output delay，不能替代 SoC 集成后的接口时序收敛。当前脚本和环境路径也按本 Demo 的固定位置 `D:\ZYNQ\smallproject` 与 `D:\Chisel-environment` 配置，不作为可搬移发布包。

第一阶段 Vivado 检查为 WNS `+3.386 ns`、12 级逻辑；最终加入完整访存和精确异常后仍满足 100 MHz 目标。最终报告位于 `generated/reports/rv32core-final/`。

## 仓库与原始 CPU 完整性

- 编译产生的 ELF/bin 文件保持在忽略列表或 `D:\Chisel-environment`，没有作为未跟踪文件进入仓库。
- `references/loongarch-core-v2/core_v2` 与原始 `rtl/ip/myCPU/core_v2` 共 35 个文件逐一进行 SHA-256 比较，差异为 0。
- 原始 LoongArch CPU 目录未被本项目的构建和验证脚本写入。
