# 易灵思 2D 图像渲染工程目录

本目录是计划书对应的正式开发主线，所在工作树为 `codex/efinix-2d-gpu`。官方 Demo 位于项目根目录的 `Ti60F225_DemoBoard_v4/`，只作为只读参考；不要直接在官方目录内改文件。

```text
pango-riscv-cpu/
├─ chisel/
│  ├─ src/main/scala/soc/gpu/          # 负责人：Chisel GPU/总线/DDR/显示 DMA
│  │  ├─ GpuTypes.scala
│  │  ├─ GpuRegisterMap.scala
│  │  ├─ GpuRegs.scala
│  │  ├─ GpuCommandValidator.scala
│  │  ├─ GpuMem.scala
│  │  ├─ BitBltEngine.scala
│  │  ├─ SparseBlitDecoder.scala
│  │  ├─ PixelPipeExt.scala
│  │  ├─ GpuPerf.scala
│  │  ├─ Axi4.scala
│  │  ├─ GpuAxiMaster.scala
│  │  ├─ CoreBusAxiBridge.scala
│  │  ├─ ScanoutDma.scala
│  │  ├─ FramePresenter.scala
│  │  ├─ DdrQosArbiter.scala
│  │  └─ GpuSubsystem.scala
│  ├─ src/main/scala/board/efinix/       # 负责人：易灵思厂商黑盒和板级顶层
│  │  ├─ EfinixDdrExt.scala
│  │  └─ EfinixGpuTop.scala
│  └─ src/test/scala/soc/gpu/            # 负责人：ChiselTest、AXI RAM 和集成测试
├─ rtl/
│  ├─ gpu/                               # 组员 A：像素流水线
│  │  ├─ gpu_defs.vh                    # 只放常量/宏，不放 module
│  │  └─ PixelPipe.v                     # 只包含 PixelPipe 一个 module
│  ├─ video/                             # 组员 A：通用显示链
│  │  ├─ VideoTiming640x480.v            # 只包含 VideoTiming640x480
│  │  ├─ VideoTestPattern.v              # 只包含 VideoTestPattern
│  │  ├─ TmdsEncoder.v                   # 只包含 TmdsEncoder
│  │  └─ TmdsSerializer10to1.v           # 只包含 TmdsSerializer10to1
│  └─ board/efinix/                      # 组员 A：易灵思时钟和 HDMI 适配
│     ├─ HdmiClockAdapter.v              # 只包含 HdmiClockAdapter
│     └─ HdmiOutAdapter.v                # 只包含 HdmiOutAdapter
├─ sw/
│  ├─ drivers/gpu/                       # 组员 B：MMIO 驱动和公开 API
│  │  ├─ gpu_driver.h
│  │  └─ gpu_driver.c
│  ├─ gpu/                               # 组员 B：RGB565、黄金模型和 Sparse 格式
│  │  ├─ rgb565.h
│  │  ├─ sparse_format.h
│  │  ├─ gpu_model.h
│  │  └─ gpu_model.c
│  ├─ assets/                            # 组员 B：Sprite、字体和生成资源
│  │  ├─ gpu_demo_assets.h
│  │  └─ gpu_demo_assets.c
│  ├─ tools/                             # 组员 B：Sparse 资源打包器
│  │  └─ sparse_packer.c
│  ├─ apps/                              # 组员 B：游戏 Demo、HUD、FPS 对比
│  │  └─ gpu_demo.c
│  └─ bsp/                               # 原有 Sapphire/RV32 BSP，保持兼容
├─ tb/
│  ├─ tb_pixel_pipe.sv                   # PixelPipe 定向/随机反压
│  ├─ tb_video_timing_640x480.sv         # 完整帧时序
│  ├─ tb_video_test_pattern.sv            # 彩条/网格边界
│  ├─ tb_tmds_encoder.sv                  # TMDS 控制/数据编码
│  ├─ tb_tmds_serializer.sv               # 10:1 串行化
│  ├─ tb_hdmi_out_adapter.sv              # HDMI 端到端
│  ├─ gpu_tb_tasks.svh                    # 公共任务，无 module
│  └─ vectors/                            # 三人共用：固定种子、CRC、Sparse 向量
├─ generated/
│  ├─ gpu/                               # Chisel split-verilog 生成物
│  └─ reports/efinix_2d_gpu/             # 资源、时序、带宽、FPS 报告
├─ scripts/                              # 生成、仿真、软件构建和板级验收
├─ references/official/ti60f225/         # 官方工程路径、版本、SHA256 索引
├─ docs/efinix_2d_gpu/                   # 接口合同、验收记录和本目录说明
└─ third_party/                          # 经过许可证确认的外部参考代码
```

## 三个人的文件边界

- 负责人：只写 `chisel/src/main/scala/soc/gpu/`、`chisel/src/main/scala/board/efinix/` 及对应测试；生成 RTL 进入 `generated/gpu/`。
- 组员 A：只写 `rtl/gpu/`、`rtl/video/`、`rtl/board/efinix/` 和 `tb/` 中对应的 Verilog testbench。每个 `.v` 文件只能有一个 `module`。
- 组员 B：只写 `sw/drivers/gpu/`、`sw/gpu/`、`sw/assets/`、`sw/tools/`、`sw/apps/` 以及软件测试；应用不得直接散布裸 MMIO。
- 官方 Demo 和 `references/official/ti60f225/` 只读。需要复用的文件复制到对应板级适配目录，并登记来源和版本。

原有 `chisel/src/main/scala/cpu`、`chisel/src/main/scala/soc`、`rtl/video/VideoAccelTop.v`、`sw/drivers/accel_driver.*` 等旧工程文件不删除、不强行搬迁；它们继续作为已有 SoC/视频验证基线。新比赛代码从上述新目录开始。
