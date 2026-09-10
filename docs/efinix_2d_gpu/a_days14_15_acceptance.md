# 组员 A：第 14～15 天交付

日期：2026-09-10。范围：接入 DDR Scanout（第 14 天）与实现 Color Key（第 15 天）。

## 第 14 天 接入 DDR Scanout

`board_top.v` 已把 `efinix_sapphire_adapter`（内部例化 Chisel `Efinix2dGpuTop` → `ScanoutDma`）输出的
`gpu_display_pixel / gpu_display_valid / gpu_display_line_last / gpu_display_frame_last` 接到
`hdmi_subsystem` 的像素流端口，并把 `gpu_ready / fifo_level / vblank` 回接给 GPU。数据通路为：

```text
ScanoutDma(读前台显存) -> Efinix2dGpuTop.io_display* -> efinix_sapphire_adapter
   -> board_top -> hdmi_subsystem -> pixel_async_fifo -> display_line_buffer
   -> display_scale2x_1080p -> rgb565_to_rgb888 -> hdmi_tx_adapter -> TMDS
```

`tb_hdmi_subsystem.sv` 按 ScanoutDma 的流合同（640×480 RGB565，`line_last` 每行、`frame_last` 每帧）
连续注入两帧不同内容，逐像素核对 2200×1125 时序、居中 1280×960 2×缩放、上下左右黑边、vblank 同步、
protocol_error 和官方 TMDS 串化边界。验收结果：640×480 测试图 2 倍居中显示，无错行。

## 第 15 天 实现 Color Key

- 新增 `board/efinix_ti60/rtl/pixel/gpu_pixel_color_key.v`：透明色命中（`foreground == color_key`）时
  `write_enable` 为 0，否则直通前景像素并置 `write_enable` 为 1。单 module，纯组合，与既有 Copy/Fill 一致。
- `gpu_pixel_contract.vh` 增加 `GPU_PIXEL_COLOR_KEY 3'd3`，与 `GpuOpcode.ColorKey = 3` 对齐。
- `gpu_pixel_pipe.v` 例化 `gpu_pixel_color_key` 并按 op 选择 Copy / Fill / ColorKey，保持单级弹性流水、
  反压下输出稳定、同步高复位清空。
- `tb/verilog/tb_gpu_pixel_pipe.sv` 扩展：随机 10000 组事务覆盖 Fill/Copy/ColorKey 及未知 op，
  并新增 6 组边界向量（0x0000/0xffff/0xbeef 的透明命中与 ±1 相邻非透明值）。
- `scripts/test-efinix-verilog.sh` 的像素编译列表加入 `gpu_pixel_color_key.v`。
- `chisel/src/main/scala/gpu/PixelPipeExt.scala` 的 `addPath` 加入 `gpu_pixel_color_key.v`，保持
  Chisel 黑盒接口与新增模块一致（负责人 Day 15 接入 Color Key 的依赖）。

## 验证

使用 Icarus Verilog 14（Windows，`-g2012`）：

```text
PASS self-written Verilog module structure（13 个 .v 各 1 个 module）
PASS gpu_pixel_pipe: 10000 ordered transactions (Fill/Copy/ColorKey), 9915 stalls, color-key boundaries
```

`tb_hdmi_subsystem` 的 640×480 2×居中显示验收与 vendor 清单核验在既有 `MEMBER_A_OFFLINE_ACCEPTANCE.md`
中已记录；本轮未改动任何 display/vendor 文件。

## 边界说明

`generated/efinix_gpu/` 下的像素文件副本、`filelist.f` 和 `efinix_2d_gpu.xml` 属于负责人 Chisel
split-verilog 生成物；负责人 Day 15 运行 `runMain gpu.GenerateEfinix2dGpu --split-verilog` 时会依据
已更新的 `PixelPipeExt.scala` 自动带入 `gpu_pixel_color_key.v` 并更新生成物。本轮不手工改动生成物。
