# 正式候选发布目录

当前已放入组员 B 经主机测试和 RV32 交叉编译生成的 `gpu_demo.elf`、`gpu_demo.bin`、`gpu_demo.hex`，其哈希记录在 `software.sha256`。运行 `scripts/test-efinix-software.ps1` 会重新构建并刷新这四个文件。

正式 `.bit`、`uart_boot.log`、`benchmark.csv`、耐久日志和最终 `manifest.sha256` 尚未生成。原因是 A-work 仍缺少 `underflow_pulse_gpu` CDC 与板级 adapter 接线；禁止用占位文件或旧位流冒充最终候选证据。
