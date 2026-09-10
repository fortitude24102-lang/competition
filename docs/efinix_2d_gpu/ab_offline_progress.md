# 组员 A 与 B 离线推进记录

日期：2026-09-10。依据 `docs/word/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx`，本轮继续执行原计划，不启动交互绘图与共享碰撞后期扩展。

## 本轮范围

| 负责人 | 原计划日期 | 交付 | 验证方式 | 状态 |
|---|---|---|---|---|
| A | 第 2 天 | 官方文件哈希核验、HDMI TX 适配器 | 清单完整性、单模块检查、真实官方编码器仿真 | 已完成（离线） |
| A | 第 3 天 | RGB565 转 RGB888 | 基础颜色和全输入空间检查 | 已完成（离线） |
| B | 第 2 天 | gpu_regs.h 与 gpu.h | 编译期布局断言、Chisel 合同核对、官方 soc.h 交叉编译 | 已完成（离线） |
| B | 第 3 天 | RGB565 转换与 Alpha 参考运算 | 边界值、独立黄金值和随机输入 | 已完成（离线） |
| B | 第 4 天 | CPU Fill 黄金模型与 CRC | 奇数宽度、stride、边界、非法输入与内存保护测试 | 已完成（离线） |
| A | 第 9～13 天 | 官方 FIFO CDC、同步块 RAM 双行缓存、2×居中缩放、复位安全 vblank 同步、HDMI 子系统 | 完整 2200x1125 帧仿真、两帧不同内容逐像素日志、独立复位测试、Efinity 全流程及时序 | 已完成（离线） |
| B | 第 9～10 天 | Copy API/Sprite、双缓冲布局与链接保护 | 假设备实际 Copy、独立黄金整帧 CRC/字节比较、地址/stride/tag、ELF map | 已完成（离线） |
| B | 第 11 天 | PRESENT 软件合同 | 假设备 vblank 完成合同 | 已与负责人 Day14 RTL 接通（离线） |
| B | 第 12～13 天 | HUD、300 帧基础动画、固定对象池游戏 | ASan/UBSan、Sapphire ELF/BIN/HEX | 已完成（离线） |

## 实施约束与决策

- 正式工作树为 `.worktrees/pango-riscv-cpu`，分支 `codex/efinix-2d-gpu`。本轮不修改负责人已有的 `PixelReadAligner.scala` 和 `RenderEngineSpec.scala` 草稿。
- 官方 Demo 原目录、`vendor/` 内容及其已有清单保持不变。只核验已有副本，不重复复制。
- HDMI 适配边界沿用官方顶层四路 TMDS 按位取反，以及原 OE／TX_RST 约定。串化与引脚电气行为留待板级验证。
- 软件 Alpha 使用现有 `docs/gpu_interface.md` 公式：每个 RGB565 分量 `(fg * alpha + bg * (255 - alpha) + 127) / 255`。
- C 头文件区分已经实现的 APB 寄存器行为与已预留但尚未实现的 QoS／性能控制。不声称已完成 MMIO 驱动或硬件交互。
- 离线结果不能替代 A 第 1 天显示耐久、B 第 1 天 UART／DDR，以及其他板上验收。上述项目继续待完成。

## 下一阶段

负责人 Day14 已把 A 的 `vblank_pulse_sync.v` 接入 `FrameSwapController`，B 的 PRESENT 命令现在只在 vblank 更新前后台地址并完成 tag。负责人 Day15 依赖的组员 A `gpu_pixel_color_key.v` 尚未提交，因此后续 Color Key/Alpha 集成在该依赖处暂停。开发板到位后仍需补做 DDR 实读写、UART、HDMI 显示器和 300 帧无撕裂验收。

## 本轮实际结果

- A：`./scripts/test-efinix-verilog.ps1` 返回 0；139 项 vendor 哈希匹配，RGB565 全 65,536 个输入、复位安全 vblank CDC、完整缩放帧与连续两帧不同内容均通过。真实官方 HDMI 编码器通过四种控制码、三原色、256 个连续 RGB 样本、复位、反相和 IO 控制。Efinity `map/interface/pnr/pgm` 全流程通过；双行缓存映射为 4 个 RAM10，HDMI 时钟域 FF 负载为 220，官方 148.75/743.75 MHz HDMI 时钟约束下 setup/hold 均为正裕量。
- B：`./scripts/test-efinix-software.ps1` 返回 0；主机 ASan／UBSan、Sprite COPY 整帧黄金比较、显式 fake-vblank PRESENT 等待测试均通过，参考帧为 614400 字节、CRC32 `77def323`，官方 Sapphire RV32 三个编译探针通过（`MARCH=rv32im_zicsr`）。
- 负责人 Day14：`FrameSwapController.scala` 已接入命令队列、APB 动态前后台寄存器和 Scanout。随机时刻提交后地址在 vblank 前保持不变，vblank 后完成对应 tag；25 项 GPU 回归全部通过。Efinity `map/interface/pnr/pgm` 全流程通过，100 MHz 核心 setup 裕量 0.373 ns，HDMI 慢时钟 setup/hold 裕量 2.581/0.012 ns。
- 本轮未完成：开发板下载、DDR 实读写、UART 交互、HDMI 显示器出图和耐久测试。
- 依赖：A 使用 WSL Ubuntu／Verilator 5.020；B 使用 WSL GCC 主机检查与 `D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe` 官方工具链探针。详细 A 过程见 `board/efinix_ti60/MEMBER_A_OFFLINE_ACCEPTANCE.md`。
- 当前阻塞：负责人 Day15 必须使用组员 A 的 `gpu_pixel_color_key.v`；该文件和相应合同宏当前均不存在，不能用负责人自写替代组员交付。
