# 负责人第 18 天离线验收

日期：2026-09-12。依据官方 Demo 复用版计划书完成“中断和 tag 状态”。当前没有开发板，本记录只证明 Chisel 仿真、生成 RTL 和离线接口合同，不代表板卡 IRQ、DDR 或帧率验收。

## 完成内容

- `GpuApbRegs.scala`：`STATUS[12:8]` 输出 16 项命令队列的历史高水位，bit13 输出 IRQ pending；`CONTROL.bit1` 产生 IRQ clear。
- `GpuApbRegs.scala`：`PERF_CONTROL.bit0` 原子锁存周期、像素、读字节、写字节和 stall 五组 64 位计数器，`bit1` 清零运行计数器与旧快照。
- `RenderEngine.scala`：把 APB clear 接入 `GpuPerfCounters`，并向寄存器侧提供全部计数值和队列高水位。
- `Efinix2dGpuTop.scala`：命令完成 IRQ 从单周期脉冲改为粘滞状态；软件清除与新完成同周期时，新完成优先，不会漏中断。
- `LAST_DONE` 沿用严格按序完成语义。B 第 17 天驱动在最多 16 条在途窗口内通过稳定读取 `LAST_DONE → ERROR → LAST_DONE`，可一次回收多个连续 tag；硬件不新增完成队列和寄存器偏移。

## 离线验收

- APB 单元测试验证五组 64 位快照在实时计数继续变化时仍保持一致，高低 32 位不会撕裂。
- 单元测试验证 IRQ clear 和性能 clear 只在对应 APB 写传输期间产生，不会误提交命令。
- 顶层 Fill 测试验证 IRQ 在完成后持续为 1，写 `CONTROL.bit1` 后清零。
- GPU 回归共 31 项通过，并重新生成 `generated/efinix_gpu/*.sv`；生成物仍使用 split-verilog。

## 下一依赖

负责人第 19 天 `SparseDecoder.scala` 必须与组员 B 第 22 天的 `sparse_format.h`、打包器及随机 token 向量使用同一格式。当前 B 仅完成到第 20 天，因此在该共享格式提交前停止，不自行另定 Sparse 边界规则。
