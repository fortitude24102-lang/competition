# 外部视频加速器检查说明

`rtl/video/VideoAccelTop.v` 是可替换的 Verilog 实现，`VideoAccelExt` 仅冻结其端口并把源码交给 Chisel 构建流程。后续替换算法时不得修改模块名、端口名、方向或位宽。

当前 Demo 是单级寄存实现：输入像素在一次时钟后输出，支持直通、灰度和阈值二值化。`enable=0` 时不产生有效输出；`bypass=1` 时忽略模式并直通。`frame_done` 在每个被接受像素的输出周期拉高一次，供寄存器状态路径验证。

定向测试会真实编译该 Verilog 文件，并验证：

- RGB `0x336699` 直通仍为 `0x336699`；
- 灰度结果为 `0x666666`；
- 阈值高于灰度时输出黑色，低于灰度时输出白色；
- `pixel_out_valid` 相对输入精确延迟一个周期。

运行：

```powershell
cd D:\ZYNQ\smallproject\chisel
sbt "testOnly soc.VideoAccelExtSpec"
```
