# GPU 专用纹理 Cache 设计规格

日期：2026-09-28

状态：待用户书面规格复核

适用基线：`a89328d`（R6 弹幕场景＋半字相位 Color Key DMA）

## 1. 目标

在不改变画面、游戏逻辑、对象数量、CPU 软件渲染基线、GPU 命令格式、
100 MHz GPU 时钟和 PC 资源服务器职责的前提下，为 Color Key 和 Alpha
前景纹理增加 4 KiB 片上只读 Cache，减少同一 3104 字节图集被数百个
Sprite 重复读取时产生的 DDR3 小事务。

PC 仍只通过以太网提供资源；Sapphire RISC-V 仍负责资源校验、Cache
装载、游戏逻辑和 GPU 命令生成。Cache 是 GPU 内部数据通路优化，不把
游戏运算转移到 PC 或固定逻辑。

## 2. 非目标

- 不缓存背景、帧缓冲、HUD 或 Sparse 数据。
- 不实现通用组相联 Cache、自动替换、写回或跨主机一致性协议。
- 不修改 Fill、Copy、Present 和 Sparse 的现有数据路径。
- 不提高时钟、不减少 Sprite、不关闭 Alpha，也不降低分辨率。
- 本阶段不同时实施 HUD 遮挡剔除、Sprite 包围盒裁剪或 DDR 多 outstanding。
- 不预先承诺稳定 60 FPS；收益只以上板相同工作量测量为准。

## 3. 方案选择

采用“软件管理、整图集预加载”的 GPU Texture Cache，而不是自动读穿
Cache。软件管理方案没有替换冲突和首帧逐行 miss 抖动，控制状态少，
能明确证明资源来自以太网写入 DDR3 后再由 RISC-V 触发装载。

Cache 数据阵列为 1024×32 bit（4096 B），预计使用 4 个 EFX_RAM10；
标签只保存一个可编程基址和有效长度，不需要逐行 tag RAM。Ti60 提供
256 个 10-kbit RAM 块，当前候选使用 141 个；最终数量仍以 Efinity
布局布线报告为准。

## 4. 硬件结构

新增 `TextureCache.scala`，职责只有三项：

1. 接收一次预加载配置，将 4 字节对齐、最大 4096 字节的 DDR3 区域读入
   `SyncReadMem(1024, UInt(32.W))`。
2. Cache 有效时，为 Color Key/Alpha 的前景读取提供与现有
   `AxiReadEngine` 数据输出等价的 32-bit ready/valid 数据流。
3. 地址不命中、Cache 无效或命令源矩形不能完整落入有效区域时，明确
   请求调用者走原 DDR3 路径。

`TextureCache` 放在 `DenseBlitEngine` 内部。预加载复用现有 Render AXI
主接口和读引擎，不增加新的 DDR 仲裁客户端；预加载期间
`DenseBlitEngine.command.ready=0`。正常渲染时按整条命令选择数据源：

- Color Key/Alpha 的完整源矩形都在 `[cacheBase, cacheBase+cacheBytes)`：
  前景来自 Cache。
- 其他情况：整条命令走原 DDR3 前景读取路径，不允许一条命令中途混用。
- Alpha 的背景读取和目标写回始终走 DDR3。

选择整条命令命中的条件使用 64-bit 扩展地址计算：

```text
sourceEnd = srcAddr + (height-1)*srcStride + width*2
hit = valid && srcAddr >= cacheBase && sourceEnd <= cacheBase+cacheBytes
```

Color Key 的字直通、`Rgb565WordAligner`、奇偶半字相位、透明 WSTRB 和
重叠回退语义保持不变；只把它们的前景输入在 DDR 数据流与 Cache 数据流
之间切换。Alpha 继续使用现有前景 FIFO、背景 FIFO和像素乘法流水线。

## 5. 装载与一致性

Cache 上电复位后无效。装载顺序固定为：

1. PC 经以太网把背景和图集写入 DDR3。
2. RISC-V 完成长度和 CRC 校验，确定使用网络图集地址或本地回退地址。
3. RISC-V 等待 GPU 命令队列为空且渲染引擎空闲。
4. RISC-V 写 Cache 基址和字节数，再写 `LOAD`。
5. 硬件立即清除 `valid/error`、置 `busy`，完成全部 AXI 读响应后才置
   `valid`；软件轮询结束后才允许提交使用该图集的渲染命令。

约束：

- `base` 必须 4 字节对齐。
- `bytes` 必须是 4 的倍数，范围为 4～4096。
- `[base, base+bytes)` 必须位于 GPU 可读 DDR 资源地址范围内且不能溢出。
- `LOAD` 或 `INVALIDATE` 在渲染忙、队列非空或 Cache 正忙时由 APB 返回
  `PSLVERROR`，状态不改变。
- AXI 读错误使 `busy=0, valid=0, error=1`，不会留下部分有效 Cache。
- Cache 无效不是渲染错误；Color Key/Alpha 自动回退 DDR3。
- 同一 DDR 地址被网络或 CPU 重写前，软件必须先使 Cache 失效；当前
  Demo 只在启动资源加载后装载一次。
- 重新 `LOAD` 隐含先失效，不允许渲染观察到部分新数据。

## 6. APB 接口

现有 `0x0000～0x008c` GPU 寄存器保持原偏移，新增：

| 偏移 | 名称 | 访问 | 定义 |
| --- | --- | --- | --- |
| `0x0090` | `TEXTURE_CACHE_BASE` | R/W | 4 字节对齐 DDR 源基址 |
| `0x0094` | `TEXTURE_CACHE_BYTES` | R/W | 有效字节数，4～4096 且为 4 的倍数 |
| `0x0098` | `TEXTURE_CACHE_CONTROL` | W | bit0=`LOAD`，bit1=`INVALIDATE`；不得同时置位 |
| `0x009c` | `TEXTURE_CACHE_STATUS` | R | bit0=`VALID`，bit1=`BUSY`，bit2=`ERROR` |
| `0x00a0` | `PERF_CACHE_BYTES_LO` | R | 快照后的 Cache 前景读取字节数低 32 位 |
| `0x00a4` | `PERF_CACHE_BYTES_HI` | R | 快照后的 Cache 前景读取字节数高 32 位 |

`PERF_CONTROL.SNAPSHOT` 同时锁存 Cache 字节计数；`PERF_CONTROL.CLEAR`
同时清零。现有 `PERF_READ_BYTES` 继续只统计真实 DDR R beat，因此两者能
直接说明流量从 DDR 转移到片上 RAM，而不改变旧指标含义。

GPU 版本从 `0x00010000` 提升为 `0x00010100`。固件与位流版本不匹配时
继续由 `gpu_init` 拒绝，避免新固件在旧位流上静默访问不存在的寄存器。

## 7. 软件接口

在 `gpu.h/gpu.c` 增加：

```c
int gpu_texture_cache_load(gpu_device *device,
                           uint32_t base,
                           uint32_t bytes,
                           uint32_t poll_limit);
int gpu_texture_cache_invalidate(gpu_device *device);
```

`gpu_texture_cache_load` 在写寄存器前验证参数和 GPU 空闲状态，触发装载并
轮询 `BUSY`；`ERROR` 返回 `GPU_DRIVER_HARDWARE`，超时返回
`GPU_DRIVER_TIMEOUT`。函数不提交普通 GPU tag，也不改变命令队列顺序。

弹幕 Demo 在 `bullet_prepare_assets` 完成后，根据 `network_result` 选择：

```text
network_result == 0  -> BULLET_ATLAS_ADDR
network_result != 0  -> BULLET_LOCAL_ATLAS
bytes                 -> BULLET_ATLAS_BYTES (3104)
```

装载失败时打印明确状态并继续使用 DDR3 回退路径；不能因为 Cache 不可用
而让 Demo 无画面。CPU 软件渲染函数、CPU 30 帧窗口和资源内容均不改变。

## 8. 性能与资源口径

当前 512 档 Color Key 每帧从 DDR 读取约 66～67 KiB 重复图集数据，约
513 个 Key Sprite 的 8 行会形成约 4100 个源行读取。稳定 Cache 命中后，
这些前景读不再进入 DDR；目标写、透明 WSTRB beat、Alpha 背景读取和
全屏背景 Copy 均保留。

验收必须分别报告：

- Cache 有效/失效时完全相同命令和最终像素。
- `PERF_READ_BYTES`、`PERF_CACHE_BYTES`、Render AR/AW 授权和 Cache
  装载一次性字节数。
- 32/64/128/256/512 五档 Key、Alpha、FULL 和完整含 HUD/PRESENT 帧率。
- 300 个连续 GPU 样本的 P5、下溢和硬件错误。
- LUT、FF、RAM10、DSP 与 100 MHz/400 MHz 时序余量变化。

预测不是验收：512 档 Key 可能从当前 6.745～7.281 ms 降至约
3.5～5 ms，FULL 可能接近或低于 16.67 ms；低档仍可能主要受背景 Copy
和垂直同步相位限制。

## 9. 验证策略

严格按测试先行实施：

1. `TextureCacheSpec` 先在无实现状态失败，覆盖合法装载、地址边界、
   AXI 背压、4 KiB 长度、延迟响应、错误响应、失效和重新装载。
2. `TextureCacheBlitSpec` 先证明旧设计对重复 Key/Alpha 仍产生前景 AXI
   AR，再要求 Cache 命中时为零；逐像素结果必须相同。
3. 覆盖源低/高半字、奇偶宽度、独立 stride、裁剪后的源偏移、透明行、
   Color Key 重叠回退，以及 Alpha 前景命中但背景仍访问 DDR。
4. 驱动测试覆盖版本、参数检查、忙时拒绝、成功、超时、错误和失效。
5. 定向测试转绿后只运行一次完整 GPU 回归并重新生成 Verilog；不重复
   长仿真。随后执行 Efinity map/interface/pnr/pgm 和时序检查。
6. 上板先做 Cache 数据一致性短测试，再用与当前候选完全相同的五档探针
   和普通 CPU/GPU 固件测量；只临时 JTAG，不写 Flash。

## 10. 接受与停止条件

只有同时满足以下条件才接受候选：

- Cache 开/关最终帧逐像素一致，CPU 路径和游戏状态序列不变。
- Cache 命中后重复 Sprite 前景不再发 DDR AR，未命中能正确回退。
- Cache 装载/失效/错误不会死锁命令队列或污染后续命令。
- 板端下溢增量和硬件错误均为 0。
- 512 档 Key 或 FULL 时间有可重复的正收益；若收益落入测量噪声，撤回
  Cache，不再以“架构更高级”为由保留面积成本。
- Efinity 布局布线通过且核心/SDRAM 时序余量非负。

通过后再决定是否追加 HUD 遮挡剔除；两项必须保持独立测量，不能把收益
混在一次提交里。
