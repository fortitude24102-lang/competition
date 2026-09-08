# 组员 B 第 5～8 天离线验收

日期：2026-09-08。没有开发板；本记录覆盖驱动、等待协议、基准程序和 Copy 黄金模型，板上结果仍待负责人完成 GPU 顶层接线后取得。

`scripts/test-efinix-software.ps1` 现会执行三组主机 ASan/UBSan 测试，并用官方 Efinix GCC 生成 `gpu_demo.elf`、`.bin`、`.hex`。本次输出全部退出 0：

- 驱动身份/版本探测、提交字段、busy/full、超时、16 位 tag 回绕和硬件错误路径通过。驱动只允许一个 in-flight 命令；超时或硬件错误保留 pending，避免重复提交。
- `gpu_platform_sync()` 在计时区间外执行 RISC-V fence、写缓冲刷新和 D-cache invalidate；周期计数使用一致的 64 位 `rdcycle[h]` 读取。基准固定四个矩形，CPU/GPU CRC 必须一致；主机测试中的周期是合成值，不能作为加速比。
- `golden_copy()` 覆盖 1000 组种子化 stride、奇偶宽度、边界和非重叠矩形；重叠复制、越界、短 stride 等请求拒绝且不写入。生产 Copy 采用逐字节行复制，保留源/目的 padding 语义。

固件入口为 `sw/efinix_gpu/src/main.c`：无 GPU 时 ID=0 的占位 APB 会安全报告“待集成”并退出，不会因未接外设而轮询挂死。真正的 MMIO、DDR CRC、UART 和 CPU/GPU 周期比较必须在完成 `Efinix2dGpuTop` 的 APB/AXI 接线并获得 Ti60F225 后上板验证。

