# 组员 A：第 16～17 天交付

日期：2026-09-10。范围：实现精确 Alpha（第 16 天）与四模式压力测试（第 17 天）。

## 第 16 天 实现精确 Alpha

- 新增 `board/efinix_ti60/rtl/pixel/gpu_pixel_alpha_blend.v`：在 RGB565 原生 5/6/5 通道上分别计算
  冻结公式 `out = (fg*alpha + bg*(255-alpha) + 127) / 255`，与 `sw/efinix_gpu/src/rgb565.c` 的
  `rgb565_global_alpha` 一致。除以 255 用恒等式 `(x + (x>>8) + 1) >> 8` 精确实现（对 x < 65280 精确，
  本模块分子上限 16192）。乘加结构可由 Efinity 推断为 DSP。单 module，纯组合。
- `gpu_pixel_contract.vh` 增加 `GPU_PIXEL_ALPHA 3'd4`，与 `GpuOpcode.Alpha = 4` 对齐。
- `gpu_pixel_pipe.v` 例化 `gpu_pixel_alpha_blend` 并按 op 选择 Copy / Fill / ColorKey / Alpha；
  Alpha 恒置 `write_enable=1`，其余流水、反压、复位行为不变。
- `scripts/test-efinix-verilog.sh` 像素编译列表加入 `gpu_pixel_alpha_blend.v`。
- `chisel/src/main/scala/gpu/PixelPipeExt.scala` 的 `addPath` 加入 `gpu_pixel_alpha_blend.v`。

## 第 17 天 四模式压力测试

`tb/verilog/tb_gpu_pixel_pipe.sv` 扩展为四模式：

- 随机 10000 组事务覆盖 Fill / Copy / ColorKey / Alpha 及未知 op，随机反压（stall）下无丢失、重复或乱序；
- Alpha 期望值由与 `rgb565.c` 相同的参考模型 `alpha_ref` 计算，alpha/背景/前景均随机变化；
- 新增 Alpha 边界向量：`alpha=0` 保留背景、`alpha=255` 保留前景、`alpha=128` 中点混合
  （`0xf800/0x001f/128 -> 0x800f`、`0xffff/0x0000/128 -> 0x8410`，与 C 向量一致）。

## 验证（Icarus Verilog 14，`-g2012`）

```text
PASS gpu_pixel_pipe: 10000 ordered transactions (Fill/Copy/ColorKey/Alpha), 9915 stalls, color-key and alpha boundaries
PASS self-written Verilog module structure（14 个 .v 各 1 个 module）
```

除以 255 恒等式对 [0,65280] 逐值核对为 0 差异，覆盖本模块全部中间值范围。

## 依赖与边界

Alpha 公式依赖组员 B `rgb565.c::rgb565_global_alpha`（已存在）与冻结合同
`docs/gpu_interface.md`；二者均已对齐。`generated/efinix_gpu/` 副本、`filelist.f`、
`efinix_2d_gpu.xml` 仍属负责人 Chisel split-verilog 生成物，由负责人 Day16 接入 Alpha 时一并再生。
