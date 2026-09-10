# 组员 B 第 5～13 天离线验收

日期：2026-09-09。没有开发板；本记录覆盖驱动、等待协议、基准程序、Copy 黄金模型和第 9～13 天应用层，板上结果仍待负责人完成 GPU 顶层接线后取得。

`scripts/test-efinix-software.ps1` 现会执行五组主机 ASan/UBSan 测试，并用官方 Efinix GCC 生成 `gpu_demo.elf`、`.bin`、`.hex`。本次输出全部退出 0：

- 驱动身份/版本探测、提交字段、busy/full、超时、16 位 tag 回绕和硬件错误路径通过。驱动只允许一个 in-flight 命令；超时或硬件错误保留 pending，避免重复提交。
- `gpu_platform_sync()` 在计时区间外执行 RISC-V fence、写缓冲刷新和 D-cache invalidate；周期计数使用一致的 64 位 `rdcycle[h]` 读取。基准固定四个矩形，CPU/GPU CRC 必须一致；主机测试中的周期是合成值，不能作为加速比。
- `golden_copy()` 覆盖 1000 组种子化 stride、奇偶宽度、边界和非重叠矩形；重叠复制、越界、短 stride 等请求拒绝且不写入。生产 Copy 采用逐字节行复制，保留源/目的 padding 语义。

固件入口为 `sw/efinix_gpu/src/main.c`：无 GPU 时 ID=0 的占位 APB 会安全报告“待集成”并退出，不会因未接外设而轮询挂死。真正的 MMIO、DDR CRC、UART 和 CPU/GPU 周期比较必须在完成 `Efinix2dGpuTop` 的 APB/AXI 接线并获得 Ti60F225 后上板验证。

## 第 9～13 天

- `gpu_copy_async()` 已按 Copy 命令合同提交源地址、目标地址、双 stride 和 tag，并在软件侧拒绝零尺寸、奇地址、短 stride、越界和重叠区域。
- `assets.c` 提供固定 8x8 RGB565 Sprite 与无动态分配的 DDR 上传函数；主机假设备执行 Copy，独立 `golden_copy()` 生成期望整帧，再比较整帧 CRC 和全部字节（含未写区域），并覆盖零尺寸、奇地址、短 stride、重叠和地址端点。
- `framebuffer.c` 固定 A=`0x02000000`、B=`0x02200000`，`linker.ld` 同时断言 `_end` 和最终 `_sp` 不进入显存保留区。PRESENT 假设备保持 busy，只有显式 fake vblank 后才更新 FRONT/LAST_DONE；软件等 tag 完成后才交换 front/back。
- `hud.c` 用 Fill 绘制 3x5 FPS 数字；`game.c` 使用 32 发子弹、16 个敌人的固定对象池。测试运行 300 帧并由 ASan/UBSan 检查越界和未定义行为。
- `main.c` 已接入官方 Sapphire GPIO、Sprite、Fill/Copy、HUD、双缓冲和 300 帧基础游戏入口，固件可生成 ELF/BIN/Intel HEX。

PRESENT 软件合同已经完成，但当前负责人 RTL 只做到 Day13，尚未实现计划中的 Day14 `FrameSwapController`；因此真实硬件会拒绝 PRESENT，这一项必须在负责人 Day14 合入后才能完成板上“只在 vblank 换前台地址”的验收。
