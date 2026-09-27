# V2 性能瓶颈定位（2026-09-27，真实开发板）

## 口径与结论

使用 `release/v2/efinix_2d_gpu.bit`，只把同版 Sapphire 固件编译为 `V2_PROFILE` 诊断模式并通过 JTAG 临时加载；未写 Flash，未更改 RTL、素材或正式 V2 发布包。PC 只运行静态 UDP 素材服务器。四份素材在本轮均由板端完整加载、CRC 校验成功，重试次数为 0，`network_result=0`。

本轮在同一 32 Sprite 场景中分别测量完整背景拷贝、24 个 Color Key、8 个 Alpha、完整 33 条命令及 PRESENT。前一轮在显示扫描尚未稳定时，`scan_grants=0` 且存在下溢，不纳入稳态结论。以下取后两轮，均 `under=0`。

| 阶段 | 工作量 | 耗时范围 | DDR 读/写量 | 渲染授权次数 | 说明 |
|---|---:|---:|---:|---:|---|
| 背景 Copy | 518,400 像素，1 条命令 | 22.02–22.05 ms | 1,036,800 / 1,036,800 B | 2,566 | 单独已超过 60 FPS 的 16.67 ms 帧预算 |
| Color Key | 122,880 像素，24 条命令 | 16.21–16.34 ms | 245,760 / 117,392 B | 32,235–32,309 | 透明像素减少写入，但写事务仍较碎 |
| Alpha | 40,960 像素，8 条命令 | 53.03–61.69 ms | 225,280–266,240 / 81,920 B | 77,040–87,440 | 像素仅为背景的 7.9%，却是最慢阶段 |
| 完整 GPU 命令 | 682,240 像素，33 条命令 | 91.45–100.73 ms | 1,507,840–1,548,800 / 1,236,112 B | 111,841–122,315 | 不含 HUD、软件游戏逻辑及 PRESENT |
| PRESENT | 一次翻页 | 14.40–15.90 ms | — | — | 等待显示时序；不是单独的渲染吞吐指标 |

稳态完整命令阶段按耗时折算约 9.9–10.9 次/秒；正式 V2 的含 HUD/PRESENT 交替测试为 CPU 2.1 FPS、GPU 8.5 FPS。两种口径不同，不能直接拿阶段耗时相加或把 HDMI 的 60 Hz 刷新率当作 60 FPS 游戏帧率。当前版本未达到赛题的 60 FPS 高负载挑战。

## 根因（代码与板上计数互相印证）

1. **Alpha 的事务粒度过小，是首要瓶颈。** `DenseBlitEngine.scala` 的 `alphaChunkPixels` 每次仅取 1–2 像素；前景和背景各启动一次 `AxiReadEngine`，Color Key/Alpha 的 `dynamicWriteRequest` 固定 `beats=1`。`AxiWriteEngine` 每笔写在 `waitResponse` 等 B 响应后才能接下一笔。Alpha 阶段平均每像素约 1.88–2.13 次渲染授权，说明大量地址/响应开销压过像素乘法本身。现有数据不支持将 DSP 计算定为主瓶颈。
2. **Color Key 写回也碎片化。** 它同样走单 beat 动态写，但无需背景读，因此明显快于 Alpha；优化时应保留透明像素跳过语义，合并相邻有效写入。
3. **全屏背景搬运是第二道 60 FPS 门槛。** 960×540 RGB565 每帧至少搬运约 1.04 MB 读加 1.04 MB 写，稳态实测约 22 ms。即使 Alpha 完全消失，当前全屏 Copy 本身仍超帧预算。应在同一场景正确性下评估脏矩形恢复/静态背景，或提升 Copy 的有效 DDR 吞吐。
4. **扫描输出与渲染共享 DDR。** 稳态每阶段均出现 `scan_grants>0`，当前首轮显示尚未稳定的数据明显更快，但它同时发生下溢，不能当成严格的“关闭扫描对照实验”。需要独立受控对照才能量化扫描争用占比。

计数器定义须按 RTL 解读：`render_grants` 是渲染端 AXI AR/AW 地址握手次数，不是像素数、beat 数或 DDR 字节数；`stalls` 只统计 GPU 忙时 AXI/像素流出现 `valid && !ready` 的周期，并**不**涵盖所有等待 B 响应的空等周期。`under` 是显示 FIFO 下溢事件。不能仅按 `stalls` 推算 DDR 带宽占用。

## 下一步性能线顺序

1. 保持同一 32 Sprite、同一素材和 CPU/GPU 口径；先让 Alpha 按行/连续片段读取前景及背景，利用 FIFO 流式混合，并合并连续写事务，目标是显著降低 `render_grants/pixel`。先仿真验证透明、错位地址、行尾和双缓冲正确性，再上板复测。
2. 对 Color Key 合并连续有效写入；实测 `render_grants`、阶段耗时和画面一致性，避免为了总线效率破坏透明跳过。
3. 优化全屏背景恢复或改为脏矩形，同时继续检查扫描下溢；确保画面组的新场景在 CPU/GPU 两种模式一致后重新建立基线。
4. 最后统计含 HUD、输入和 PRESENT 的真实帧率，并做赛题要求的 60 FPS 活动 Sprite 极限测试；当前数据不得宣称达标。

复现诊断固件：`./scripts/test-efinix-software.ps1 -FirmwareOnly -Profile -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102`。编译结果在 `generated/verification/efinix-software/`；`-Profile` 不修改 `release/v2/` 的正式固件。串口为 COM13、115200 baud，日志行以 `PROFILE,` 开头。
