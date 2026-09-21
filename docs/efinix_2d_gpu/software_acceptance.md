# 组员 B 三天收尾验收记录

日期：2026-09-16

## 已完成产物

- `sparse_format.h` / `sparse_pack.c`：按冻结的 32 位 header、RGB565 双像素小端 literal、奇数 run 高半字清零和逐行结束规则编码。
- `gpu.h` / `gpu.c` / `gpu_regs.h`：新增 Sparse 异步提交、QoS 配置、八组 64 位性能快照和完整寄存器偏移。
- `assets.c`：Dense 与 Sparse 使用同一份像素源；正式 Demo 使用可压缩的 8×8 素材，原玩家和敌人素材继续保留。
- `benchmark.c`：固定轮询和自适应模式复用同一命令数组；Dense/Sparse 运行时对比记录读字节、周期、CPU 周期和 CRC。
- `hud.c` / `main.c`：HUD 显示 FPS、下溢、Render stall 和 QoS 模式；fixed/adaptive 分别重放相同固定输入、相同提交模式的 300 帧命令序列，并用命令哈希和 CRC 双重检查；wait-each/batch 仍作为独立演示维度。
- `test_sparse.c` / `test_days21_23.c`：覆盖全透明、全实色、行尾透明、奇数 run、容量不足、100 组固定种子随机往返、素材等价、QoS 非法阈值、64 位快照、Sparse 命令和 CRC 合同。

## 已执行验收

执行 `scripts/test-efinix-software.ps1`，结果通过：

- 全部旧软件回归保持通过；
- ASan/UBSan 下 Sparse 和 Day21–23 新测试通过；
- RV32IM `-Werror` 交叉编译、Sapphire 链接通过；
- 已生成 `release/gpu_demo.elf`、`release/gpu_demo.bin`、`release/gpu_demo.hex` 和 `software.sha256`；软件测试脚本每次交叉构建后自动刷新这些候选物。

可压缩 Demo 素材的 Dense 大小为 128 字节；测试断言其 Sparse token 小于 128 字节，并逐像素解码等于 Dense 原图。正式固件还对同一场景执行 Dense 和 Sparse 两次渲染，CRC 不同立即失败，并输出实际 Render 读字节和周期。小图是否获益由 run 分布决定，因此软件同时上报原玩家、敌人和专用 Demo 素材的实际字节数，不隐瞒头开销。

## 尚未伪造的板级证据

`uart_boot.log`、`benchmark.csv`、300 帧实测数值和耐久结果必须来自最终正式位流。当前 A-work 尚未提供计划要求的 `underflow_pulse_gpu` 跨时钟脉冲及其 adapter 接线，因此这些文件不创建占位假数据；依赖补齐并完成同一候选位流上板后再封版。
