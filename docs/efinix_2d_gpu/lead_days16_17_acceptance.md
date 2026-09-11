# 负责人第 16～17 天离线验收

日期：2026-09-11。依据官方 Demo 版三人计划书执行；无开发板，本记录只覆盖仿真、生成与 Efinity 工程检查。

## 第 16 天：Alpha 双读与配对

- `AxiReadEngine.scala` 支持固定 4 位 AXI ID，并把响应 ID 不匹配计入 AXI 错误。
- `DenseBlitEngine.scala` 为前景和目标背景分别使用 ID 0、1；两个读地址经轮询仲裁后共用官方 32 位 AXI 入口，R 通道按 ID 分发。
- 每个 Alpha 小块限制为同一 AXI beat 内的 1～2 个 RGB565 像素，避免两个读流因交错响应和反压互相等待。
- Alpha 先完成当前小块读取和混合，再按打包地址发单拍写事务；保守 AXI 从机在 AW 后暂停 AR 的测试也能完成，不存在读改写循环等待。
- Validator 拒绝非完全同表面的 Alpha 重叠；命令和行边界统一清理读写错误，失败命令不会污染后续命令。
- `RenderEngineSpec.scala` 使用随机 AR/R、写响应和 PixelPipe 延迟，逐像素检查前景/背景配对及 3×2 跨行写回。

## 第 17 天：完整 Alpha 与性能事件

- `RenderEngine.scala` 正式接受 Alpha 命令并接入 A 的 `gpu_pixel_alpha_blend.v`。
- 队头命令先锁存 Validator 结果，再进入渲染器；保持 16 项队列容量和完成顺序，同时切断地址范围乘法到执行寄存器的长组合路径。
- `GpuPerfCounters.scala` 记录渲染活动周期、完成像素、AXI 读字节、有效写字节和阻塞周期；单元测试覆盖独立增量和同步清零。
- Alpha 使用冻结的 RGB565 通道公式；Chisel 黑盒测试覆盖 alpha=0 和 128，A 的 10000 组真实 Verilog 压力测试覆盖 0、128、255 边界及随机反压。
- APB 计数器快照/清零和任意 tag 完成查询属于第 18 天，尚未修改冻结的寄存器合同。

## 自动验证

- `scripts/test-efinix-gpu.ps1`：29/29 通过并生成 split Verilog。
- `scripts/test-efinix-pixel-chisel.ps1`：真实 Alpha 黑盒与反压测试通过。
- `scripts/test-efinix-verilog.ps1`：通过；包括 10000 组 Fill/Copy/ColorKey/Alpha 随机事务与完整两帧 HDMI 检查。
- `scripts/test-efinix-software.ps1`：通过；包括 Alpha 穷举、1000 组 Copy、ASan/UBSan 和官方 Sapphire RV32 构建。
- Efinity `map/interface/pnr/pgm`：全部通过并生成 bitstream。100 MHz core setup/hold 最差裕量为 1.849/0.026 ns；148.743 MHz HDMI 慢时钟 setup/hold 为 2.725/0.012 ns。所有已分析时钟裕量为正。

## 下一依赖

第 18 天需要组员 B Day17 提供 `gpu_wait_tag`、完成回收与 IRQ 清除的 C 侧合同/测试。当前 main 仅到 B Day15；在三人冻结字段评审前，负责人不自定义新的完成队列寄存器。
