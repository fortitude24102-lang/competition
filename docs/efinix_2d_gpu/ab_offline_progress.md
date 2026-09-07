# 组员 A 与 B 离线推进记录

日期：2026-09-08。依据 `docs/word/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx`，本轮执行原计划中的一个离线批次，不启动交互绘图与共享碰撞后期扩展。

## 本轮范围

| 负责人 | 原计划日期 | 交付 | 验证方式 | 状态 |
|---|---|---|---|---|
| A | 第 2 天 | 官方文件哈希核验、HDMI TX 适配器 | 清单完整性、单模块检查、真实官方编码器仿真 | 已完成（离线） |
| A | 第 3 天 | RGB565 转 RGB888 | 基础颜色和全输入空间检查 | 已完成（离线） |
| B | 第 2 天 | gpu_regs.h 与 gpu.h | 编译期布局断言、Chisel 合同核对、官方 soc.h 交叉编译 | 已完成（离线） |
| B | 第 3 天 | RGB565 转换与 Alpha 参考运算 | 边界值、独立黄金值和随机输入 | 已完成（离线） |
| B | 第 4 天 | CPU Fill 黄金模型与 CRC | 奇数宽度、stride、边界、非法输入与内存保护测试 | 已完成（离线） |

## 实施约束与决策

- 正式工作树为 `.worktrees/pango-riscv-cpu`，分支 `codex/efinix-2d-gpu`。本轮不修改负责人已有的 `PixelReadAligner.scala` 和 `RenderEngineSpec.scala` 草稿。
- 官方 Demo 原目录、`vendor/` 内容及其已有清单保持不变。只核验已有副本，不重复复制。
- HDMI 适配边界沿用官方顶层四路 TMDS 按位取反，以及原 OE／TX_RST 约定。串化与引脚电气行为留待板级验证。
- 软件 Alpha 使用现有 `docs/gpu_interface.md` 公式：每个 RGB565 分量 `(fg * alpha + bg * (255 - alpha) + 127) / 255`。
- C 头文件区分已经实现的 APB 寄存器行为与已预留但尚未实现的 QoS／性能控制。不声称已完成 MMIO 驱动或硬件交互。
- 离线结果不能替代 A 第 1 天显示耐久、B 第 1 天 UART／DDR，以及其他板上验收。上述项目继续待完成。

## 下一阶段

A 第 4 天为建立官方主工程副本，其板上 memTest／UART 验收仍依赖板卡；B 第 5 天为 MMIO 驱动骨架，其 ID／VERSION／错误寄存器实机读取同样依赖板卡。后续可继续准备离线内容，但必须单列待板测事项。

## 本轮实际结果

- A：`./scripts/test-efinix-verilog.ps1` 返回 0；139 项 vendor 哈希匹配，RGB565 全 65,536 个输入通过，真实官方 HDMI 编码器测试通过四种控制码、三原色、256 个连续 RGB 样本、复位、反相和 IO 控制。
- B：`./scripts/test-efinix-software.ps1` 返回 0；主机 ASan／UBSan 测试通过，参考帧为 614400 字节、CRC32 `77def323`，官方 Sapphire RV32 三个编译探针通过（`MARCH=rv32im_zicsr`）。
- 本轮未完成：开发板下载、DDR 实读写、UART 交互、HDMI 显示器出图、Efinity 板级最终时序和耐久测试。
- 依赖：A 使用 WSL Ubuntu／Verilator 5.020；B 使用 WSL GCC 主机检查与 `D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe` 官方工具链探针。详细 A 过程见 `board/efinix_ti60/MEMBER_A_OFFLINE_ACCEPTANCE.md`。
