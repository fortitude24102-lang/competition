# Ti60F225 2D GPU 接口合同

状态：冻结于 2026-09-05。硬件、Verilog 和 C 软件必须共同使用本合同；修改字段、地址或舍入规则需要三人共同评审。

## 官方边界

- Sapphire 主频：100 MHz。
- APB Slave 0：CPU 地址 `0xF8100000`，窗口 64 KiB；GPU 端接收 16 位 `PADDR` 偏移。
- GPU DDR 入口：Sapphire `io_ddrMasters_0`，AXI4 地址 32 位、数据 32 位、ID 4 位、LEN 8 位。
- DDR3：板载 MT41J128M16JT-125，软件可用窗口按 256 MiB 管理。
- 中断：Sapphire USER 0 interrupt，官方配置 ID 16。

## 显存布局

| 地址 | 用途 |
|---:|---|
| `0x02000000` | Framebuffer A，640×480 RGB565 |
| `0x02200000` | Framebuffer B，640×480 RGB565 |
| `0x02400000` | Dense Sprite 和字体资源 |
| `0x06000000` | Sparse Sprite token 流 |
| `0x10000000` | GPU 可访问 DDR 窗口末端，不包含此地址 |

RGB565 为小端 16 位，地址公式为 `base + y * stride_bytes + x * 2`。地址至少 2 字节对齐，普通图像 stride 不小于 `width * 2`。

## 命令

| 字段 | 位宽 | 含义 |
|---|---:|---|
| `op` | 4 | 0 NOP，1 FILL，2 COPY，3 COLOR_KEY，4 ALPHA，5 SPARSE，6 PRESENT |
| `srcAddr` | 32 | 源图或 Sparse token 地址 |
| `dstAddr` | 32 | 目标矩形或 PRESENT 帧地址 |
| `width` `height` | 16+16 | 像素尺寸 |
| `srcStride` `dstStride` | 32+32 | 每行字节数 |
| `color` `colorKey` | 16+16 | 填充色和透明色 |
| `alpha` | 8 | 0–255 全局 Alpha |
| `flags` | 16 | 中断和模式控制 |
| `tag` | 16 | 软件分配的顺序完成标签 |

Alpha 每个颜色通道使用整数公式 `(fg * alpha + bg * (255 - alpha) + 127) / 255`。`alpha=0` 保留背景，`alpha=255` 输出前景。

## APB 寄存器

| 偏移 | 名称 | 访问 | 内容 |
|---:|---|---|---|
| `0x0000` | ID | R | `0x32444750` |
| `0x0004` | VERSION | R | `0x00010000` |
| `0x0008` | STATUS | R | busy、full、empty、queue level |
| `0x000C` | CONTROL | W | bit0 SUBMIT；后续位用于 IRQ/计数器控制 |
| `0x0010` | OP | RW | 命令操作码 |
| `0x0014` | SRC_ADDR | RW | 源地址 |
| `0x0018` | DST_ADDR | RW | 目标地址 |
| `0x001C` | SIZE | RW | `[31:16] height`、`[15:0] width` |
| `0x0020` | SRC_STRIDE | RW | 源步长 |
| `0x0024` | DST_STRIDE | RW | 目标步长 |
| `0x0028` | COLOR_KEY | RW | `[31:16] color_key`、`[15:0] color` |
| `0x002C` | ALPHA_FLAGS | RW | `[31:16] flags`、`[7:0] alpha` |
| `0x0030` | TAG | RW | `[15:0] tag` |
| `0x0034` | LAST_DONE | R | 最近完成 tag |
| `0x0038` | ERROR | R | 最近错误码 |
| `0x003C` | QUEUE_LEVEL | R | 当前队列水位 |
| `0x0040` | FRONT_BUFFER | R | 当前前台帧地址 |
| `0x0044` | BACK_BUFFER | R | 当前后台帧地址 |
| `0x0048` | QOS_WATERMARKS | RW | 高低水位 |
| `0x004C` | PERF_CONTROL | RW | 计数器快照/清零 |
| `0x0050`–`0x0074` | PERF_* | R | 64 位周期、像素、读写字节和 stall |

APB 合法访问单周期完成。写 CONTROL.SUBMIT 时，完整影子命令原子进入 16 项 FIFO；FIFO 满时返回 `PSLVERROR`，不能覆盖或丢弃旧命令。

## 错误码

| 值 | 含义 |
|---:|---|
| 0 | 无错误 |
| 1 | 非法操作码 |
| 2 | 宽或高为零 |
| 3 | 地址未按 RGB565 对齐 |
| 4 | stride 小于行字节数 |
| 5 | 地址超出 GPU DDR 窗口或计算溢出 |
| 6 | COPY 源和目标区域重叠 |
| 7 | 命令队列满 |
| 8 | Sparse 格式错误 |
| 9 | AXI 响应错误 |

## Sparse token

每个 32 位 token 的 `[15:0]` 为 `skipPixels`，`[31:16]` 为 `runPixels`。token 后跟 `runPixels` 个小端 RGB565 literal 像素，两个像素装入一个 32 位字；奇数 run 的高半字填零。`runPixels=0` 表示行结束。

## PixelPipe

输入为 `valid/ready`、`op[2:0]`、`foreground[15:0]`、`background[15:0]`、`fill_color[15:0]`、`color_key[15:0]`、`alpha[7:0]`。输出为 `valid/ready`、`result_pixel[15:0]` 和 `write_enable`。输出被反压时，像素和写使能必须保持稳定。
