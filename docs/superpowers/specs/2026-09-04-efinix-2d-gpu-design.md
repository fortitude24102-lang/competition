# 易灵思 RISC-V + FPGA 2D 图形加速器设计规格

日期：2026-09-04  
目标分支：`codex/efinix-2d-gpu`

## 1. 项目目标

在现有 Chisel RV32I 五级流水 SoC 上实现面向 Ti60F225 开发板的 RGB565 2D 图形加速系统。RISC-V 负责游戏逻辑、资源管理和命令提交；FPGA 负责显存搬运、像素混合、显示扫描与换帧。

最终系统必须完成赛题基础要求：

- Solid Fill；
- Block Copy；
- 加速器通过 AXI4 主动访问 DDR3；
- AXI Burst 与内部 FIFO；
- 640x480@60Hz HDMI 输出；
- 双缓冲无撕裂换帧；
- 相同场景下 CPU 软件渲染与 FPGA 渲染 FPS 对比。

最终系统必须完成赛题高阶挑战：

- RGB565 Global Alpha Blend；
- Color Key；
- 大量 Sprite 的互动游戏 Demo，并测出稳定 60 FPS 的 Sprite 数量极限。

正式创新点为：

1. 显示截止时间感知的 DDR3 自适应 QoS 仲裁；
2. 带命令标签、完成中断和性能统计的非阻塞 Command FIFO；
3. 跳过透明区域的 Sparse Blit 稀疏 Sprite 传输。

## 2. 非目标

第一版不实现旋转、缩放、三角形光栅化、纹理映射、Z Buffer、乱序命令执行、缓存一致性或 RTOS。Block Copy 第一版不支持源和目的区域重叠；软件必须拒绝重叠请求。

这些功能不会进入三人的逐日计划，除非基础、高阶和三个创新点全部通过验收且仍有剩余时间。

## 3. 硬件平台

- FPGA：Efinix Ti60F225；
- 外存：MT41J128M16JT-125 DDR3，单颗 128M x 16，额定 DDR3-1600；
- 显示：板载 HDMI；
- DDR3 控制器：Efinity 生成的 AXI4 接口控制器；
- SoC 主时钟、DDR 用户时钟和 HDMI 像素时钟允许不同频率，跨时钟边界必须使用明确的异步 FIFO 或厂商控制器已提供的 CDC。

内部 GPU 数据通路以 32 位为最小传输粒度。AXI 数据宽度作为 `GpuAxiMaster` 构造参数，仿真默认使用 64 位；板级包装使用 Efinity 实际生成的 AXI 数据宽度，不把厂商宽度写死进 BitBlt 核心。

## 4. 系统结构

```text
RISC-V CPU
    | CoreBus MMIO
    v
GpuRegs + 16-entry Command FIFO
    |
    v
BitBltEngine
    |-- Rect/row address generation
    |-- Sparse stream decoding
    |-- PixelPipe ExtModule
    v
GpuAxiMaster --+
               |
CpuAxiBridge --+--> DdrQosArbiter --> Efinity DDR3 AXI4 Controller
               |
ScanoutDma ----+
    |
    v
Async pixel FIFO --> VideoTiming640x480 --> HDMI board adapter
```

现有 CPU、CSR、中断入口、UART、GPIO、启动 RAM、CoreBus 和 `0x8000_0000` 外存窗口继续保留。现有 RGB888 灰度/阈值模块仅作为 ExtModule 与 valid/ready 测试范例，不进入最终 2D 数据通路。

## 5. RGB565 与显存布局

RGB565 像素为小端 16 位：

```text
bits[15:11] R
bits[10:5]  G
bits[4:0]   B
```

二维像素地址：

```text
pixel_addr = base + y * stride_bytes + x * 2
```

640x480 一帧占 614,400 字节。默认演示布局按 1 MiB 对齐：

```text
0x8000_0000  Framebuffer A
0x8010_0000  Framebuffer B
0x8020_0000  普通 Sprite、背景和字体资源
0x8100_0000  Sparse Sprite 资源与压力测试数据
```

地址是软件默认值而不是硬件常量；驱动可传入其他合法 DDR 地址。

## 6. 命令协议

`GpuCommand` 固定包含：

| 字段 | 位宽 | 含义 |
|---|---:|---|
| `op` | 4 | 操作类型 |
| `srcAddr` | 32 | 普通源图或 Sparse 数据地址 |
| `dstAddr` | 32 | 目标矩形左上角地址或 PRESENT 帧地址 |
| `width` | 16 | 像素宽度 |
| `height` | 16 | 像素高度 |
| `srcStride` | 32 | 普通源图每行字节数 |
| `dstStride` | 32 | 目标帧每行字节数 |
| `color` | 16 | Solid Fill 颜色 |
| `colorKey` | 16 | Color Key 透明色 |
| `alpha` | 8 | 0 至 255 的全局 Alpha |
| `flags` | 16 | 中断、统计和模式控制位 |
| `tag` | 16 | 软件分配的命令标签 |

操作码固定为：

```text
0 NOP
1 SOLID_FILL
2 BLOCK_COPY
3 COLOR_KEY
4 ALPHA_BLEND
5 SPARSE_BLIT
6 PRESENT
```

CPU 先写命令影子寄存器，再写 `SUBMIT`。只有 `SUBMIT` 被接受时，完整命令才原子进入深度 16 的同步 FIFO。FIFO 满时 `SUBMIT` 返回总线错误且不得覆盖已有命令。

命令严格顺序执行。`PRESENT` 等待之前所有命令完成，在下一个垂直消隐期切换显示帧地址；切换发生后才更新完成标签并按 flags 产生中断。

状态至少包括：FIFO level、full、empty、engine busy、present pending、last completed tag、completed count、error code。

## 7. BitBlt 行为

### Solid Fill

不读取源地址，按 `width`、`height` 和 `dstStride` 将 `color` 写入目标矩形。

### Block Copy

逐行把 `srcAddr` 指向的 RGB565 矩形复制到 `dstAddr`。每行拆分为不跨 4 KiB 边界且不超过 AXI 最大 burst 的传输。源和目的区域重叠属于非法命令。

### Color Key

读取源像素；源像素等于 `colorKey` 时禁止目标写入，否则复制源像素。透明像素不需要读取目标背景。

### Alpha Blend

读取前景源像素和当前目标背景像素，对 RGB565 三个通道分别计算：

```text
out = round((foreground * alpha + background * (255 - alpha)) / 255)
```

C 黄金模型和 Verilog 必须使用相同的整数舍入规则。`alpha=0` 保留背景，`alpha=255` 输出前景。

### Sparse Blit

Sparse 数据逐行存放。每个 32 位 header 定义一个透明跳过段和有效像素段：

```text
bits[15:0]  skipPixels
bits[31:16] runPixels
```

header 后紧跟 `runPixels` 个小端 RGB565 像素，两个像素打包为一个 32 位字；奇数长度的高半字填零。`runPixels=0` 表示当前行结束。每行所有 `skipPixels + runPixels` 不得超过命令 `width`，行数必须恰好等于 `height`。

普通 Sparse Blit 直接写有效像素；带 Alpha flag 时只为有效像素读取背景并混合。透明区域既不读取普通源像素，也不访问目标背景或写目标。

## 8. Verilog PixelPipe 接口

最终外部模块名为 `PixelPipe`，文件为 `rtl/gpu/PixelPipe.v`。该 `.v` 文件只允许包含 `PixelPipe` 一个模块。

输入：

```text
clock, reset
in_valid, in_ready
op[2:0]
foreground[15:0]
background[15:0]
fill_color[15:0]
color_key[15:0]
alpha[7:0]
```

输出：

```text
out_valid, out_ready
result_pixel[15:0]
write_enable
```

模块必须满足 valid/ready 规则：输出停顿时数据和 `write_enable` 保持稳定；流水线稳态目标为每拍接收和输出一个像素。

每个 Verilog 文件只能定义一个模块。公共常量放入 `.vh` include，不通过在同一 `.v` 文件中追加辅助模块实现复用。

## 9. HDMI 与显示

`ScanoutDma` 从当前 front buffer 连续读取 RGB565，进入跨时钟 pixel FIFO。FIFO 输出接 `VideoTiming640x480`，生成 640x480@60Hz 的 active video、hsync、vsync 和 data enable。

显示链分成两个一模块一文件的 Verilog 边界：

- `rtl/video/VideoTiming640x480.v`：只生成坐标、有效区和同步时序；
- `rtl/board/efinix/HdmiOutAdapter.v`：只完成开发板 HDMI 物理输出所需的颜色映射、编码和厂商接口适配。

DDR 读取、FIFO水位、换帧寄存器和仲裁不进入上述 Verilog 文件。

发生 Scanout FIFO 欠载时输出黑色像素并增加 underflow counter；不得重复旧像素掩盖错误。

## 10. DDR3 QoS 仲裁

DDR3 有 CPU、GPU 和 Scanout 三类访问者。读写通道都必须保证事务完整性，不能在一个 burst 中间切换所有者。

Scanout FIFO 水位策略：

- 水位小于或等于低水位：Scanout 最高优先级；
- 水位大于或等于高水位：CPU、GPU、Scanout 按公平轮转；
- 位于两者之间：保持上一次策略，形成滞回，避免每拍切换。

低、高水位是可写寄存器，复位值分别为 FIFO 深度的 1/4 和 3/4。非法配置 `low >= high` 返回总线错误并保持旧值。

需要统计：每个主设备的读写字节数、等待周期、burst 数，Scanout 最低水位和欠载次数。

## 11. 错误处理

硬件必须拒绝或终止以下情况，并记录首个错误码与命令 tag：

- 未定义操作码；
- RGB565 地址非 2 字节对齐；
- `width` 或 `height` 为零；
- 普通图像 stride 小于 `width * 2`；
- 地址加法发生 32 位溢出；
- Block Copy 源和目的矩形重叠；
- Sparse 行程越过行宽、行数不足或多余；
- AXI 返回错误响应；
- 非法 FIFO 水位配置。

发生命令错误时只终止当前命令，更新错误状态和完成 tag，然后继续下一条命令。软件清除错误前保留首个错误，避免后续错误覆盖根因。

## 12. 软件接口与演示

C 驱动最终提供：

```c
gpu_fill(...);
gpu_blit(...);
gpu_blit_key(...);
gpu_blit_alpha(...);
gpu_blit_sparse(...);
gpu_submit();
gpu_wait_tag(...);
gpu_present(...);
gpu_get_stats(...);
```

演示使用固定随机种子和同一份场景数据，包含：

1. 大量移动纯色方块；
2. 多张背景和大图快速切换；
3. Color Key 与 Alpha Sprite；
4. 类幸存者或弹幕场景，自动增加 Sprite 数量并测量稳定 60 FPS 极限。

显示内容至少包括 CPU FPS、GPU 阻塞 FPS、GPU 非阻塞 FPS、Sprite 数量、FIFO level、DDR 等待周期、Scanout 最低水位和 underflow 数量。

CPU 与 GPU 测试必须使用相同命令序列、相同帧数和相同计时来源。FPS 以实际完成的垂直同步帧计数，不使用命令提交次数代替。

## 13. 三人所有权

### 负责人：Chisel 与系统集成

负责：MMIO、Command FIFO、命令检查、二维地址、Sparse解析、DMA/AXI、CPU外存桥、DDR QoS、Scanout DMA、双缓冲、垂直消隐换帧、中断、性能计数和顶层集成。

不得把像素混合重新写进 Chisel，也不得要求 Verilog 成员直接访问 DDR。

### 组员 A：Verilog

负责：`PixelPipe`、RGB565 Fill/Copy/Color Key/Alpha、valid/ready 流水线、640x480 显示时序和 HDMI 板级输出适配。

不得实现 DDR 主设备、二维地址生成、命令 FIFO 或 MMIO。每个 `.v` 文件只能包含一个 module。

### 组员 B：C

负责：GPU驱动、CPU黄金渲染器、双缓冲API、固定场景、Sprite资源、Sparse资源打包、游戏逻辑、FPS与性能界面。

不得绕过驱动直接散布裸 MMIO 写操作；寄存器地址只在 `gpu_driver.h` 中定义。

## 14. 验证策略

验证顺序固定为：

1. C 黄金模型生成目标显存；
2. Chisel 小型仿真内存逐像素比较 Fill/Copy；
3. Verilog PixelPipe 独立验证四种像素操作和随机反压；
4. Command FIFO 连续提交、满队列和 tag 顺序验证；
5. AXI RAM 模型验证 burst、4 KiB边界、随机延迟和错误响应；
6. Sparse 正常、奇数像素、空行和损坏数据验证；
7. Scanout/vblank/PRESENT 与 QoS 压力仿真；
8. DDR3 板级内存测试；
9. HDMI彩条、静态帧、双缓冲动画；
10. 高负载游戏与长时间稳定性测试。

源码改动必须至少留下一个能自动失败的对应测试。厂商综合只在接口冻结、DDR接入和最终时序三个里程碑运行，日常开发以 ChiselTest、Verilator 和内存结果比较为主。

## 15. 最终验收

- Fill、Copy、Color Key、Alpha、Sparse 与 C 黄金模型逐像素一致；
- Command FIFO 在满、空和随机反压下不丢失、不重复、不乱序；
- AXI burst 不跨 4 KiB 边界，错误响应可追溯到命令 tag；
- 640x480@60Hz 连续运行，正常负载下 underflow 为零且无撕裂；
- CPU软件、GPU阻塞、GPU非阻塞三种模式具有可复现的性能结果；
- QoS 开关前后有 Scanout 水位、欠载与 GPU吞吐对照；
- 普通 Color Key 与 Sparse Blit 有 DDR字节数和 Sprite上限对照；
- 最终报告包含资源、时序、带宽、FPS、CPU占用和稳定60 FPS最大Sprite数量。

## 16. 参考工程使用原则

参考 Xosera、PULP iDMA、verilog-axi、Project F、Efinix Edge Vision SoC 和 STM32 DMA2D 的接口与验证思路。第一阶段不直接引入大型第三方 RTL。若后续复制或修改任何外部源码，必须先确认许可证、保留版权声明，并在 `third_party/` 或板级适配目录记录来源与版本。
