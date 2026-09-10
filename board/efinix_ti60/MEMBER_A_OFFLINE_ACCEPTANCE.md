# 组员 A：第 2～13 天离线交付

日期：2026-09-10。工具：WSL Ubuntu，Verilator 5.020；Efinity 2025.1。

## 接口和官方边界

`rtl/display/hdmi_tx_adapter.v` 只封装现有 `vendor/hdmi_tx/rtl/hdmi_src/dvi_tx/dvi_encoder.v`，其依赖为同目录 `encode.v`。

| 端口 | 约定 |
| --- | --- |
| `pixelclk` | 官方 `hdmi_tx_slow_clk` 像素时钟；所有 RGB、HS、VS、DE 同域，在上升沿采样 |
| `rst` | 高有效，直接连接编码器 `rstin`，异步清除输出和 disparity；不负责 PLL/reset 同步 |
| `red/green/blue[7:0]` | RGB888；与 `hs/vs/de` 同拍 |
| `hs/vs/de` | 原样传入官方编码器，不改变同步极性 |
| `tmds_data0_o[9:0]` | 官方编码器蓝通道按位取反，消隐控制码携带 HS/VS |
| `tmds_data1_o[9:0]` | 官方绿通道按位取反 |
| `tmds_data2_o[9:0]` | 官方红通道按位取反 |
| `tmds_clk_o[9:0]` | 官方 `1111100000` 按位取反，即 `0000011111` |
| 四路 `*_TX_OE` / `*_TX_RST` | 保持官方 `top.v`：分别恒为 1 / 0，独立于逻辑 `rst` |

包装不加寄存器。输入在第一个上升沿采样，对应输出在第三个上升沿后可用（两个周期后，含官方仿真延时）。官方输入流水线不复位；上层应在复位期间令 DE=0，并给足至少三拍冲刷后开始有效像素。编码器复位输出为 0，经过本适配层后数据输出为 `3ff`，时钟字保持不变。

`vendor/hdmi_tx/rtl/top.v` 已逐项核对：四个 10-bit 字均反相、0/1/2 对应蓝/绿/红、OE=1、TX_RST=0。`hdmi_tx.peri.xml` 四路 LVDS 均为 `is_serial=true`、`serial_width=10`、`is_half_rate=true`，使用 `hdmi_tx_fast_clk` 和 `hdmi_tx_slow_clk`。输出直接对接这一原有 Efinity IO/serializer 边界；本交付不重写 serializer，不使用目录中其他平台的串化实现，不改变官方管脚、时钟和 IO 参数。

`rtl/display/rgb565_to_rgb888.v` 是无时钟、无延迟寄存器的组合转换：输入 `rgb565[15:11]` 为红、`[10:5]` 为绿、`[4:0]` 为蓝；5-bit 扩展为 `{x,x[4:2]}`，6-bit 扩展为 `{x,x[5:4]}`。输出为三个 8-bit `red/green/blue`，可直接接适配器。

## 可复查的验证

在仓库工作树根目录执行：

```powershell
./scripts/test-efinix-verilog.ps1
```

或在 WSL 中运行 `bash scripts/test-efinix-verilog.sh`。脚本每次先只读核验既有 `vendor/manifest.sha256`，139 个文件全部匹配；没有重新复制或修改 vendor。编译和仿真任一失败都会返回非零；编译产物使用 `mktemp` 临时目录并自动清理，关闭 core dump。单模块测试保持警告致命；包含官方 FIFO/HDMI 源码的集成测试抑制 vendor 已知的 WIDTH、UNOPTFLAT、PINMISSING 和 TIMESCALEMOD 警告，功能仍由端到端断言检查。

测试先于功能实现编写，使用接口占位实现确认断言失败后再补实际逻辑：

| 阶段 | 实际命令及结果 |
| --- | --- |
| RGB565 红灯 | `./scripts/test-efinix-verilog.ps1`：`RGB565 f800: got 000000 expected ff0000`；仿真状态 134，PowerShell 进程状态 1 |
| RGB565 绿灯 / HDMI 红灯 | 同命令：RGB565 全 65536 值通过；`TMDS got R/G/B 000/000/000 expected 3ff/3ff/3ff`；仿真状态 134，PowerShell 进程状态 1 |
| 最终绿灯 | `./scripts/test-efinix-verilog.ps1 2>&1 \| Tee-Object -FilePath generated/verification/efinix-verilog-pass.log`：进程状态 0，两个测试均通过 |

最终原始输出保存在已忽略的 `generated/verification/efinix-verilog-pass.log`，其中可见：

```text
PASS vendor manifest
PASS RGB565: primary colors, white, black, all 65536 values
PASS HDMI: real vendor encoder, four control tokens, primaries, 256 streamed RGB samples, async reset, inversion, IO controls
```

RGB565 使用字面量检查红绿蓝白黑，以算术分解独立核对全部 65536 个输入，能捕获通道互换、零填充替代位复制等错误。HDMI 测试编译真实 vendor `dvi_encoder/encode`，没有编码器替身或第二份接线自比：四种控制码和三原色零 disparity 首字使用手工常量，连续 256 个 RGB 像素用独立 TMDS 解码恢复像素并核对通道与两周期延迟，同时验证异步复位、复位后恢复、时钟字反相和 IO 控制。该测试不声称覆盖编码器全部 running-disparity 状态或串行电气行为。

## 已完成的板级编译与仍待板上验收

Efinity 2025.1 已完成 `map/interface/pnr/pgm` 全流程，最终 setup/hold 均为正裕量。接口配置沿用官方 Demo 可实现的整数 PLL：像素时钟 148.75 MHz、高速串化时钟 743.75 MHz，对应 2200x1125 时序约 60.10 Hz；约束使用这两个实际时钟值。板卡说明书确认 HDMI 位于 1.8 V 的 3A Bank，DDR3 MT41J128M16JT-125 位于 1.5 V 的 3B/4A/4B Bank。

离线编译通过仍不代表 HDMI 已实际显示。当前没有板卡，尚需验证 PLL 锁定与复位释放、LVDS 管脚/10:1 串化位序/极性和输出电气参数，并在实物显示器上验收 GPU 帧缓冲画面、同步、稳定性和长时间运行。

## 第 9～13 天：显示通路

- `pixel_async_fifo.v` 封装官方 Efinix `efx_fifo_wrapper`，跨 100 MHz GPU 域与官方 Demo 148.75 MHz HDMI 域传送 RGB565、行末和帧末标志，并返回写域水位和 ready。
- `display_line_buffer.v` 使用两组 640 像素同步读块 RAM，提前一像素取数；显示当前行两次的同时接收下一行，行末位置错误会锁存 `protocol_error`。Efinity 映射为 4 个 RAM10，而非 20,480 个像素时钟域触发器。
- `display_scale2x_1080p.v` 生成 2200x1125 标准几何时序，把 640x480 最近邻放大为 1280x960；有效区左右各 320、上下各 60 像素黑边。使用官方 148.75 MHz 像素时钟时，实际刷新率约 60.10 Hz。
- `vblank_pulse_sync.v` 同步 vblank 电平；任一时钟域复位后先等待有效视频低电平再武装，只在下一次低到高边沿产生 GPU 域单周期脉冲，避免复位错位造成伪脉冲。
- `hdmi_subsystem.v` 连接 FIFO、行缓存、缩放、RGB565 转换和既有官方 DVI 编码适配器；`board_top.v` 已由官方色条切换为 GPU Scanout 数据。

`tb_display_scale2x_1080p.sv` 对完整一帧逐像素检查时序、边框、预取索引和 480 次双行握手；`tb_hdmi_subsystem.sv` 连续核对两帧不同内容，确认跨域反压下无整帧重复、丢失或错序；`tb_vblank_pulse_sync.sv` 独立覆盖源域/目的域复位错位与重新武装。Efinity `map/interface/pnr/pgm` 全流程通过，行缓存改造后总 FF 从 31,452 降为 11,050、HDMI 像素时钟负载从 20,700 降为 220；最终 HDMI 慢时钟 setup 最差裕量 2.611 ns、hold 最差裕量 0.071 ns，全部已分析时钟均为正裕量。无板卡，因此未执行显示器、电气、串行眼图和长时间运行验收。
