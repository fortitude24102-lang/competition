# 组员 A：第 18～19 天交付

日期：2026-09-10。范围：完善换帧与下溢显示（第 18 天）、接出 QoS 水位（第 19 天）。

## 第 18 天 完善换帧与下溢显示

- `display_scale2x_1080p.v`：新增 `underflow` 输出，定义为 `scaled_active && !line_valid`，
  与既有 `rgb565 = scaled_active && line_valid ? line_pixel : 16'h0000` 同源——缺失行时
  `rgb565` 固定输出黑色背景，同时 `underflow` 置 1。
- `hdmi_subsystem.v`：新增 `underflow_event`（粘滞，复位清除）与 `underflow_count`
  （16 位，上升沿计数下溢“段”）。断流时锁存事件，恢复后下一帧由行缓存重新装载、正常显示。
- `board_top.v`：接出 `display_underflow_event` / `display_underflow_count` 内部信号，供状态观察。
- `tb_hdmi_subsystem.sv`：增加断流—下溢—恢复阶段：先喂三帧不同图案，随后切断扫描流验证
  `underflow_event` 锁存、缩放区只出现黑色/已知图案（无花屏），再恢复喂白色帧验证恢复。

## 第 19 天 接出 QoS 水位

- `pixel_async_fifo.v`：新增 `LOW_WATERMARK`/`HIGH_WATERMARK` 参数（默认 256/1536）与
  `wr_level_low`/`wr_level_high` 输出，在写时钟域对写侧水位做阈值比较。
- `hdmi_subsystem.v`：接出 `fifo_level_low`/`fifo_level_high`，与既有 `fifo_level` 一起构成
  供 Chisel `DdrQosArbiter` 使用的“level / low / high”三信号。
- `tb_hdmi_subsystem.sv`：监视 `fifo_level_low`/`fifo_level_high` 是否被观测到。

## 依赖与边界

第 18 天依赖负责人 `FrameSwapController`（Day14 已完成）、第 19 天依赖负责人 `DdrQosArbiter`
（已存在基础轮询版）。本轮只负责把水位阈值信号从显示侧接出；负责人 Day21 再把 `low`/`high`
接入自适应仲裁并（经 `Efinix2dGpuTop`）消耗。`board_top.v` 到 `efinix_sapphire_adapter`/生成
GPU 的 `low`/`high` 走线属负责人后续集成，本轮不在 `board_top.v` 中接（生成物未再生前不宜引用）。

## 验证（Icarus Verilog 14，`-g2012`）

```text
PASS self-written Verilog module structure（14 个 .v 各 1 个 module）
PASS display: ... underflow latch + black background, recovery, QoS watermarks
```
