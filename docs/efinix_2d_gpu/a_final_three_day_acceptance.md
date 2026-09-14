# 组员 A：三天收尾离线验收

日期：2026-09-14。分支：`A-work`。本记录只证明 Windows Icarus 仿真和
Efinity 静态实现结果；当前没有开发板，因此不把离线证据写成上板结论。

## 交付结果

- `underflow_pulse_cdc.v` 将显示域欠流“段”通过 16 位注册 Gray 事件计数器送到
  GPU 时钟域。连续高电平只产生一个事件；来得比 GPU 时钟更密的独立事件会排队，
  输出每个事件一个 GPU 周期高脉冲，队列脉冲之间强制一个低周期。
- 两个时钟域都采用异步置位、同步释放的本地复位。启动高电平、跨复位保持高电平、
  1 ns 短复位和释放窗口内真实新事件均有专项测试。
- `hdmi_subsystem.underflow_pulse_gpu` 在 `board_top` 接为内部信号
  `gpu_underflow_pulse`。在负责人加入性能计数器输入前，该线用 Efinity
  `syn_keep` 保留整个 CDC 锥；负责人接入 GPU 时钟域计数器后可移除该临时保留属性。
- 既有 12 位 `fifo_level -> gpu_scanout_level -> io_scanoutLevel` 通路保持不变。
  未修改 Chisel、生成 GPU RTL、APB 地址、Sapphire 适配器端口或组员 B 软件。
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

- 信号：`board_top.gpu_underflow_pulse`。
- 时钟域：`gpu_stream_clk`；高有效；每个已交付欠流事件一个 GPU 周期。
- 排队规则：相邻输出脉冲之间至少一个低周期；16 位模计数最多允许 65,535 个未消费事件，
  环境不得让待处理数回绕。
- 复位规则：任一外部复位有效时输出为低；复位期间保持高的源电平不会在恢复后重放，
  释放窗口内真实新上升沿会保留。
- 负责人操作：在生成核心提供 GPU 时钟域欠流计数器增量输入后，直接消费该内部信号；
  不应把它绕经 `efinix_sapphire_adapter`。接线完成且确认不再被优化后可移除板级 `syn_keep`。

## 仍需开发板验证

- 实际下载、启动、DDR3 校准和 DDR 实读写；
- UART/LED 现场状态、HDMI 显示器锁定、物理画面与电气接口；
- 真实高负载下的欠流计数、性能计数器消费、最大稳定 Sprite 数和 300 帧无撕裂；
- 复位按钮/掉电重启、温度/电压条件以及 30 分钟连续运行。

这些项目不能由当前仿真、静态时序或生成位流代替。
