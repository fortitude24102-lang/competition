# 组员 A：三天收尾离线验收

日期：2026-09-14。分支：`A-work`。本记录只证明 Windows Icarus 仿真和
Efinity 静态实现结果；当前没有开发板，因此不把离线证据写成上板结论。

## 2026-09-15 主线增量收尾

已把主线 `3032c45`（Sparse 渲染和自适应 DDR QoS）合入 `A-work`，并完成该版本
对组员 A 接口的新依赖：

- 用锁定的 Chisel 7.7.0 / Scala 2.13.18 / sbt 1.12.4 重新生成
  `generated/efinix_gpu/`。生成物新增 `SparseDecoder.sv`、
  `SparseBlitEngine.sv`、`Arbiter4_GpuCompletion.sv` 和顶层
  `io_underflow_pulse_gpu`，同时更新 QoS 与性能计数器 RTL；旧的三路 completion
  仲裁文件已从生成物和 Efinity 清单移除。
- `gpu_underflow_pulse` 现在经 `efinix_sapphire_adapter` 接入
  `Efinix2dGpuTop.io_underflow_pulse_gpu`，由 GPU 域 64 位 underflow 性能计数器消费；
  已移除板级悬空交接阶段的临时 `syn_keep`。既有
  `gpu_scanout_level -> io_scanoutLevel` 水位通路保持不变。
- `scripts/test-task2-board-integration.ps1` 现在同时检查 CDC、完整端口路径、
  split-verilog 与 Efinity 清单顺序一致，以及每个生成的 `.sv/.v` 恰含一个 module。
  静态检查、Icarus 欠流 CDC 波形测试，以及 64 位 GPU underflow 计数器的精确递增、
  清零优先级和无旁路计数器污染检查均通过。
- 本机没有 WSL/Verilator；GPU Scala 测试源码可以完整编译，39 项中 2 项纯合同测试
  通过，其余 37 项在断言执行前统一因 Chisel Windows 仿真后端找不到 Unix
  `which` 而停止。因此本次不把这些环境失败计作 RTL 回归通过，也没有以重复安装
  仿真环境替代用户指定的 Icarus 验证。

增量最终候选命令：

```powershell
./scripts/test-efinix-board.ps1 `
  -EfinityHome C:/efinity/efinity `
  -OutputDirectory D:/efinity_builds/efinix_2d_gpu_member_a_main3032c45_20260915_r1 `
  -Flow compile
```

Efinity 2026.1.132 的 `map/interface/pnr/pgm` 全部 PASS，生成位流
`outflow/efinix_2d_gpu.bit`，大小 2,129,658 字节，SHA-256：
`8866f2748e9941b8a06a9d9d859b62561180285768a2f90bb73933eb57c6060f`。
CDC 报告为 `No Synchronizer warnings to report`；映射网表保留 16/16 个注册 Gray
源位，且 `gpu_underflow_pulse` 直接作为 GPU underflow 计数器寄存器的时钟使能。

增量候选静态时序均为正裕量：

| 时钟 | Setup 裕量 (ns) | Hold 裕量 (ns) |
|---|---:|---:|
| `core_clk` 100 MHz | 1.730 | 0.026 |
| `sdram_clk` 400 MHz | 0.276 | 0.097 |
| `rx_cal_clk` 400 MHz | 0.297 | 0.027 |
| `tx_cal_clk` 400 MHz | 0.354 | 0.091 |
| `tx_cal_clk_90edge` 400 MHz | 0.249 | 0.072 |
| `hdmi_tx_slow_clk` 148.743 MHz | 2.521 | 0.012 |

顶层映射估算为 13,869 FF、749 SRL、2,948 ADD、14,276 LUT、95 RAM、
16 DSP/MULT。当前仍无开发板，故下载、真实 DDR/HDMI、Sparse/Dense 实屏一致性、
QoS 收益和耐久运行仍属于现场验收，不由上述离线结果替代。组员 B 的 C 资源与寄存器
定义不参与本次 A 的 RTL 生成和时序收敛，因此未越界代做。

## 交付结果

- `underflow_pulse_cdc.v` 将显示域欠流“段”通过 16 位注册 Gray 事件计数器送到
  GPU 时钟域。连续高电平只产生一个事件；来得比 GPU 时钟更密的独立事件会排队，
  输出每个事件一个 GPU 周期高脉冲，队列脉冲之间强制一个低周期。
- 两个时钟域都采用异步置位、同步释放的本地复位。启动高电平、跨复位保持高电平、
  1 ns 短复位和释放窗口内真实新事件均有专项测试。
- 在 2026-09-14 交接阶段，`hdmi_subsystem.underflow_pulse_gpu` 在 `board_top`
  接为内部信号 `gpu_underflow_pulse`，并用 Efinity `syn_keep` 临时保留整个 CDC 锥；
  该临时状态已被上面的 2026-09-15 主线增量接线取代。
- 既有 12 位 `fifo_level -> gpu_scanout_level -> io_scanoutLevel` 通路保持不变。
  2026-09-14 交接阶段未修改 Chisel、生成 GPU RTL、APB 地址、Sapphire 适配器端口或
  组员 B 软件；生成 RTL 与适配器现已由上面的 2026-09-15 增量接线取代。
- Efinity 工程 XML 已按依赖顺序加入 CDC 文件；SDC 用 Efinity 2026.1 支持的
  `get_cells` 把注册 Gray 源到第一同步级的最大延迟限制为一个像素周期
  `6.722689076 ns`，没有添加宽泛 false path。

## 最终 Icarus 回归

命令：

```powershell
./scripts/test-efinix-verilog.ps1 -IcarusHome D:/FPGA/iverilog
```

工具：Icarus Verilog 14.0 (devel)，`-g2012`。一次最终回归结果为 7/7 通过：

| 用例 | 覆盖内容 | 结果 |
|---|---|---|
| `tb_rgb565_to_rgb888` | 主色、黑白和全部 65,536 个 RGB565 输入 | PASS |
| `tb_hdmi_tx_adapter` | 官方编码器四种控制码、三原色、256 个连续 RGB 样本、复位及 IO 控制 | PASS |
| `tb_gpu_pixel_pipe` | Fill/Copy/Color Key/Alpha 共 10,000 个有序随机事务、反压和边界值 | PASS |
| `tb_vblank_pulse_sync` | 两域独立复位、无启动伪脉冲、重新武装 | PASS |
| `tb_underflow_pulse_cdc` | 密集事件排队、两域复位、1 ns 短复位、释放窗口事件 | PASS |
| `tb_display_scale2x_1080p` | 2200×1125 时序、1280×960 居中、黑边、480 次双行握手 | PASS |
| `tb_hdmi_subsystem` | FIFO CDC、双行缓存、完整缩放帧、vblank、TMDS、断流黑屏与白帧恢复、水位 | PASS |

完整 HDMI 仿真仅出现官方 `efx_fifo_wrapper.v` 既有的 generate 语法警告。
15 个自写 `.v` 文件均检查为一文件一个 `module`。

最终波形为 [member_a_underflow_final.vcd](evidence/member_a_underflow_final.vcd)，
大小 45,623 字节，SHA-256：
`39d5dc4168dfa6dad2f4839e0695c6bd0347067e98ed2d6b4ee4543bea8b548a`。
从 VCD 直接统计：共 12 个输出脉冲；每个高电平恰为 100 ns（一个 GPU 周期）；
最小上升沿间隔 200 ns，满足脉冲间强制低周期；像素或 GPU 复位期间上升沿为 0。
两个相距 28 ns、早于一次 GPU 采样的源事件最终仍形成两个独立输出脉冲。

## 最终 Efinity 候选

命令（未设置 `EFX_HIFTDI_ENABLE`）：

```powershell
./scripts/test-efinix-board.ps1 `
  -EfinityHome C:/efinity/efinity `
  -OutputDirectory D:/efinity_builds/efinix_2d_gpu_member_a_final_20260914_r1 `
  -Flow compile
```

Efinity 2026.1.132，Titanium `Ti60F225`，I3 timing model：`map`、`interface`、
`pnr`、`pgm` 全部 PASS，并生成未下载的候选位流：
`D:/efinity_builds/efinix_2d_gpu_member_a_final_20260914_r1/outflow/efinix_2d_gpu.bit`。
位流大小 2,096,988 字节，SHA-256：
`6ac6e1f2d26de36b19d10d51c0c722a0d401b819d116610a9abf307e04a9663f`。

最终映射网表中 `u_underflow_sync` 保留 16/16 个 `pixel_event_gray` 源寄存器，
16/16 个第一同步级输入均直接来自对应注册 Gray 位；新增 `set_max_delay` 无空匹配或
执行失败警告，CDC 报告为 `No Synchronizer warnings to report`。异步复位同步器由常量复位源
驱动的提示属于既有工具分类，不是 Gray 数据路径告警。

静态时序全部为正裕量：

| 时钟 | Setup 裕量 (ns) | Hold 裕量 (ns) |
|---|---:|---:|
| `core_clk` 100 MHz | 2.218 | 0.026 |
| `sdram_clk` 400 MHz | 0.391 | 0.063 |
| `rx_cal_clk` 400 MHz | 0.533 | 0.030 |
| `tx_cal_clk` 400 MHz | 0.444 | 0.097 |
| `tx_cal_clk_90edge` 400 MHz | 0.351 | 0.072 |
| `hdmi_tx_slow_clk` 148.743 MHz | 2.915 | 0.012 |

顶层映射估算：12,890 FF、749 SRL、2,392 ADD、13,174 LUT、95 RAM、14 DSP/MULT。
显示子系统估算为 818 XLR、8 RAM；`u_underflow_sync` 单独估算为 121.5 XLR、42 FF。

第一次诊断构建发现未消费的交接线使 CDC 被综合删除；第二次诊断构建保留 CDC 后又发现
通用 `keep` 只保留部分 Gray 源寄存器。最终候选把板级交接线和源 Gray 寄存器都改为
Efinity 官方 `syn_keep`，上述网表、CDC 和时序结果均来自修正后的最终目录。诊断构建不作为候选。

## 负责人集成合同

- 信号：`board_top.gpu_underflow_pulse`，经
  `efinix_sapphire_adapter.gpu_underflow_pulse_gpu` 接到
  `Efinix2dGpuTop.io_underflow_pulse_gpu`。
- 时钟域：`gpu_stream_clk`；高有效；每个已交付欠流事件一个 GPU 周期。
- 排队规则：相邻输出脉冲之间至少一个低周期；16 位模计数最多允许 65,535 个未消费事件，
  环境不得让待处理数回绕。
- 复位规则：任一外部复位有效时输出为低；复位期间保持高的源电平不会在恢复后重放，
  释放窗口内真实新上升沿会保留。
- 负责人操作：无需再补接端口或保留板级 `syn_keep`；合入本次生成 RTL、适配器、
  `board_top` 与 Efinity XML 即可。映射网表已证明该脉冲被 64 位性能计数器消费。

## 仍需开发板验证

- 实际下载、启动、DDR3 校准和 DDR 实读写；
- UART/LED 现场状态、HDMI 显示器锁定、物理画面与电气接口；
- 真实高负载下的欠流计数、性能计数器消费、最大稳定 Sprite 数和 300 帧无撕裂；
- 复位按钮/掉电重启、温度/电压条件以及 30 分钟连续运行。

这些项目不能由当前仿真、静态时序或生成位流代替。
