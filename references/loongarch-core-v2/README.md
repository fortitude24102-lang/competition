# LoongArch core_v2 只读参考快照

复制日期：2026-08-27

来源：`D:\loong\CPU-5\nscscc-solo-la-soc-master\rtl`

本目录仅用于参考旧 CPU 的流水线、取指/访存接口、提交跟踪及 SoC 集成方式。后续 RISC-V CPU 使用 Chisel 在 `chisel/` 下重新实现，不直接修改或综合本目录中的 Verilog。

复制范围：

- `core_v2/`：原 `rtl/ip/myCPU/core_v2/` 全部文件；
- `integration/core_top.v`；
- `integration/AxiCrossbar_2x8.v`；
- `integration/thinpad_top.v`。

复制完成时，38 个来源文件与目标文件的 SHA-256 均一致。原始工程当时已有未提交修改，本快照保留复制时的工作区内容。
