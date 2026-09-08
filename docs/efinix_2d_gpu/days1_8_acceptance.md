# 组员 A 与 B 前八天交付及验收

更新日期：2026-09-08。依据官方 Demo 版原计划继续实施；后期交互绘图与共享碰撞不在本批次范围。

## 验收口径

本机没有开发板。实现、离线验证、板上验收分列；“离线通过”不等于该日所有板上要求完成。既有官方 Demo 及 vendor 副本只读，负责人已有 `PixelReadAligner.scala`、`RenderEngineSpec.scala` 草稿保持不变。

现有 `Efinix2dGpuTop.scala` 为占位接口；APB、命令队列、Fill 和完成状态尚未接成可运行的顶层。A 第四、五天工程目标为官方 Sapphire／DDR 与 HDMI 彩条共存，不是完整 GPU。B 的 GPU 固件还依赖负责人完成正式 APB／AXI 接线、完成 tag／错误反馈及缓存一致性验收。

## A 每日状态

| 天 | 原计划交付 | 离线验证 | 板上验收 |
|---|---|---|---|
| 1 | 官方 HDMI 基线 | 已有完整官方 HDMI compile 日志 | 彩条、下载及十分钟稳定显示待验收 |
| 2 | vendor 清单、HDMI 适配器 | 139 项哈希及真实编码器仿真已通过 | IO 电气与串化仍待板测 |
| 3 | RGB565 输出边界 | 全 65536 输入已通过 | 实际显示颜色待板测 |
| 4 | 官方 Sapphire／DDR 派生工程 | 已生成；Efinity map 通过，Interface Designer 未通过 | memTest、UART 待验收 |
| 5 | DDR 与 HDMI 共存工程 | 已生成；同一板级流程在 Interface Designer 阶段停止 | DDR 校准后彩条待验收 |
| 6 | Copy、Fill 像素模块 | Verilator 回归通过 | 通过后用于后续 GPU 集成 |
| 7 | 统一 PixelPipe | 10000 笔事务、9915 次 stall 回归通过 | 通过后用于后续 GPU 集成 |
| 8 | 冻结接口与 Chisel 黑盒 | Chisel 黑盒 1 项测试通过 | 单独模块通过不表示 GPU 顶层已接通 |

## B 每日状态

| 天 | 原计划交付 | 离线验证 | 板上验收 |
|---|---|---|---|
| 1 | 官方 BSP UART／memTest | 已有官方 GCC 固件编译日志 | UART 和 DDR 实际读写待验收 |
| 2 | 寄存器与命令合同 | 布局断言及官方 soc.h 编译已通过 | 实际寄存器访问待验收 |
| 3 | RGB565 与 Alpha 黄金模型 | 主机数学检查已通过 | 后续与像素 RTL 对比 |
| 4 | CPU Fill 与 CRC | 主机内存检查已通过，参考帧 CRC 77def323 | 纯软件板上运行待验收 |
| 5 | MMIO 驱动、身份探测 | 驱动行为测试通过（无 GPU 时安全返回）；官方 BSP 交叉编译通过 | GPU 接线及实板读取待验收 |
| 6 | 异步 Fill 与 tag 等待 | Fill/tag/超时/硬件错误行为测试通过；生成 ELF/BIN/HEX | 实际 GPU 写 DDR、与 CPU CRC 比较待验收 |
| 7 | CPU／GPU 周期基准 | 基准驱动与独立内存模型测试通过；主机周期为合成值 | 无真实加速比；须完成 GPU 集成后上板测量 |
| 8 | 非重叠 Copy 黄金模型 | 1000 组种子化 stride/边界/奇偶 Copy 通过 | 本日参考算法可独立离线验收 |

## 验证入口

继续使用 `scripts/test-efinix-verilog.ps1`、`scripts/test-efinix-software.ps1` 和 `scripts/test-efinix-pixel-chisel.ps1`。板级派生工程入口为 `scripts/test-efinix-board.ps1`；本次运行 map 通过但 Interface Designer 失败，日志位于本机 `D:/efinity_builds/efinix_2d_gpu_day5/compile.log`，未计作板级通过。

本次离线回归结果：Verilog 入口退出 0（vendor manifest、RGB565 全量、HDMI、PixelPipe）；软件入口退出 0（ASan/UBSan、生产驱动/模型/benchmark/Copy、官方 RV32 ELF/BIN/HEX）；Chisel 黑盒入口退出 0（`PixelPipeExtSpec` 1 项）。板级流程只得到 map PASS，Interface Designer FAIL，因此没有可报告的布局布线或时序裕量。WSL 的本机 localhost 代理提示不影响离线工具运行。

任何板上 FPS、UART、DDR CRC 或加速比必须来自真实板卡运行，不使用主机行为模型输出替代。模拟器仅证明被覆盖的逻辑与驱动协议。
