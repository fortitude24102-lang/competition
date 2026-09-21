# 主负责人三天收尾验收记录

日期：2026-09-16

## 已完成

- Chisel 源已包含 SparseDecoder、SparseBlitEngine、自适应 DDR QoS、下溢/Render grant/Scanout grant 性能计数和 APB 快照寄存器。
- 已重新生成 `generated/efinix_gpu/` 拆分 RTL；每个生成 `.sv` 文件一个 module，`filelist.f` 已加入 Sparse 模块和四路完成仲裁器。
- `scripts/test-efinix-gpu.ps1` 单轮执行通过：8 个 suite、39 个 test 全部成功，覆盖 Sparse 格式错误、Dense/Sparse 等价与读字节下降、QoS 迟滞和防饿死、64 位计数以及顶层混合事务。
- `scripts/test-efinix-verilog.ps1` 单轮执行通过：真实 HDMI 编码、10000 笔四模式像素事务、vblank CDC、1080p 2× 缩放、FIFO/下溢恢复均通过。
- B 软件 Sanitizer 回归及 RV32 ELF/BIN/HEX 构建通过，生成 RTL 与 Chisel 源同步。

## 当前精确依赖点

正式生成顶层 `Efinix2dGpuTop` 现在要求输入 `io_underflow_pulse_gpu`。当前 `competition/A-work` 最新版本的 `hdmi_subsystem.v` 只有像素域粘滞 `underflow_event` 和 16 位 `underflow_count`，`efinix_sapphire_adapter.v` 也未连接该新输入。

因此以下负责人任务必须等待 A 的文件，当前不擅自修改 A 所有权目录：

1. 将像素域下溢上升沿安全同步为 GPU 时钟域单周期 `underflow_pulse_gpu`；
2. 从 `hdmi_subsystem.v` 经 `board_top.v` / `efinix_sapphire_adapter.v` 接到生成 GPU 顶层；
3. 执行 Efinity map/interface/pnr/pgm、时序检查和正式位流生成；
4. 用同一位流采集 300 帧、Dense/Sparse、fixed/adaptive、30 分钟耐久、UART 与 HDMI 证据；
5. 生成最终完整 `release/manifest.sha256`。

未连接输入在普通 Verilog 语法检查中可以悬空，因此“Verilog 回归通过”不等于板级依赖已经完成。本记录明确区分二者。
