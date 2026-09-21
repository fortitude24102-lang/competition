# Ti60F225 2D GPU V2 接口合同

状态：冻结于 2026-09-21。本文是 V2 网络资源、Asset DMA、960×540 显示和压力向量的唯一接口依据。V1 GPU 命令与寄存器仍以 `docs/gpu_interface.md` 为准；本文只定义 V2 新增项和明确覆盖项。

## 1. 不变边界与时钟域

- Sapphire RISC-V、GPU APB、AetherGX 和 DDR AXI 工作在 100 MHz。
- 官方 GE Demo 的 GMII RX/TX 数据宽度均为 8 bit，千兆模式标称 125 MHz；板级 RGMII 为每边沿 4 bit。RX、TX 与 GPU 时钟域均按异步时钟域处理。
- HDMI 像素时钟为 148.5 MHz，10:1 串化时钟为 742.5 MHz。
- 网络到 GPU 的多位数据只通过异步 FIFO；单周期状态只通过脉冲同步器。禁止直接同步多位总线。
- GPU APB 基址仍为 `0xF8100000`，窗口仍为 64 KiB；V1 的 `0x0000`～`0x008C` 偏移、字段和行为不变。
- GPU DDR AXI 地址宽度 32 bit、数据宽度 32 bit、ID 宽度 4 bit、LEN 宽度 8 bit。

官方 GE RX RAM 的 `udp_rec_data_length` 是包含 8 字节 UDP 头的 UDP 长度，RAM 地址 0 对应第一个 UDP 应用字节。`efinix_ge_mac_wrapper` 必须先检查长度不小于 8，再向下游输出 `rx_length = udp_rec_data_length - 8`；不得把 UDP 头计入 ASST 包长度。

## 2. V2 显存与显示常量

| 项目 | 冻结值 |
|---|---:|
| 内部宽度 | 960 像素 |
| 内部高度 | 540 像素 |
| 像素格式 | RGB565，小端 |
| 每像素字节数 | 2 |
| 行步长 | 1920 字节（`0x780`） |
| 单帧有效字节数 | 1,036,800 字节（`0x0FD200`） |
| Framebuffer A | `0x02000000` |
| Framebuffer B | `0x02200000` |
| Dense 资源区 | `0x02400000`～`0x05FFFFFF` |
| Sparse 资源区 | `0x06000000`～`0x0FFFFFFF` |
| DDR 上界 | `0x10000000`，不包含 |
| 显示 FIFO | 2048 个 RGB565 像素 |
| FIFO 低水位 | 256 像素 |
| FIFO 高水位 | 1536 像素 |

Scanout 每行只读取 960 个有效像素，每第 960 个输出置 `lineLast`，第 540 行末尾同时置 `frameLast`。显示侧对每个输入像素做 2×2 最近邻复制，恰好铺满 1920×1080，不再产生 V1 的居中黑边。

Framebuffer A/B 各保留 `0x200000` 字节地址槽。所有资源和 DMA 目标区间使用半开区间 `[address, address + length)`；加法溢出、目标小于 `0x02400000` 或末地址大于 `0x10000000` 均为越界。Asset DMA 不得写入两个 framebuffer。

## 3. ASST UDP 应用协议

V2 使用停等式 UDP 分块协议。所有头字段使用网络字节序（大端），单个 DATA 载荷为 1～1024 字节，应用包总长为 33～1056 字节。固定头为 32 字节：

| 字节偏移 | 字段 | 宽度 | 冻结值或语义 |
|---:|---|---:|---|
| 0 | `magic` | 32 | `0x41535354`，ASCII `ASST` |
| 4 | `version` | 16 | `1` |
| 6 | `type` | 16 | `1=GET`，`2=DATA`，`3=ERROR` |
| 8 | `session` | 32 | RISC-V 每次启动资源会话时生成 |
| 12 | `asset_id` | 32 | manifest 中的资源编号 |
| 16 | `offset` | 32 | 资源内字节偏移，必须 4 字节对齐 |
| 20 | `payload_len` | 16 | GET 请求长度或 DATA 实际长度，最大 1024 |
| 22 | `flags` | 16 | bit0 `LAST`；bit1 `RETRY`；其余位必须为 0 |
| 24 | `sequence` | 32 | 同一资源从 0 开始逐块递增 |
| 28 | `payload_crc32` | 32 | DATA 载荷 CRC32；GET 固定为 0 |

CRC 使用 CRC-32/ISO-HDLC：反射多项式 `0xEDB88320`、初值 `0xFFFFFFFF`、最终异或 `0xFFFFFFFF`，只覆盖 DATA 载荷，不覆盖 32 字节头。空 DATA、未知 type、保留 flags 非零、长度不符、未对齐 offset 或应用包超过 1056 字节均拒绝。

GET 没有载荷，`payload_len` 表示请求字节数。DATA 必须回显 GET 的 `session/asset_id/offset/payload_len/sequence`；最后一块置 `LAST`。超时重发同一个 GET 时置 `RETRY`，其余字段不变。重复 DATA 可以被识别和计数，但不得第二次写 DDR 或推进 committed 状态。ERROR 没有载荷，具体错误由软件按请求失败处理，不进入 DMA 数据通路。

Sapphire 的职责是选择 `asset_id`、DDR 目标地址和请求时机，执行 20 ms 超时与最多 5 次重试，核对分块 CRC 和完整资源 CRC，并在全部通过后提交缓存。PC 只读取资源文件并响应 GET；FPGA 不解释地图、植物、敌人或动画语义。

## 4. 网络流接口

### 4.1 官方 UDP RAM 到解析器的原始流

以下信号位于 GE RX 时钟域：

| 信号 | 方向（wrapper 视角） | 含义 |
|---|---|---|
| `rx_byte[7:0]` | output | UDP 应用数据字节，按线上顺序输出 |
| `rx_valid` | output | `rx_byte/rx_last/rx_length` 有效 |
| `rx_ready` | input | 下游可接收当前字节 |
| `rx_last` | output | 当前字节是本应用包最后一个字节 |
| `rx_length[15:0]` | output | 应用包总长，已排除 8 字节 UDP 头 |

`rx_valid && !rx_ready` 时，所有输出必须保持稳定。一次包传输从首个 `rx_valid && rx_ready` 开始，到带 `rx_last` 的握手结束；`rx_length` 在整个包内保持不变。wrapper 最多读取官方 2048 字节 RAM 中声明的有效范围。

### 4.2 解析和跨域后的受保护流

`asset_udp_rx` 解析 ASST 头、只接受版本 1 的 DATA，并经异步 FIFO 送到 100 MHz GPU 域。`asset_stream_guard` 输出以下接口：

| 信号 | 方向（guard 视角） | 位宽 | 含义 |
|---|---|---:|---|
| `meta_valid` | output | 1 | 元数据有效 |
| `meta_ready` | input | 1 | DMA 可接收元数据 |
| `meta_session` | output | 32 | 包 session |
| `meta_asset_id` | output | 32 | 包 asset_id |
| `meta_offset` | output | 32 | 包 offset |
| `meta_length` | output | 16 | DATA 载荷字节数 |
| `meta_flags` | output | 16 | ASST flags |
| `meta_sequence` | output | 32 | 包 sequence |
| `meta_crc32` | output | 32 | 头中声明的 payload CRC32 |
| `payload_valid` | output | 1 | 载荷字节有效 |
| `payload_ready` | input | 1 | DMA 可接收载荷字节 |
| `payload_data` | output | 8 | 载荷字节 |
| `payload_last` | output | 1 | 当前字节是该 DATA 载荷最后一字节 |
| `dma_abort` | input | 1 | 放弃当前包并丢弃至包尾 |
| `stream_error` | output | 1 | 当前包长度、last 或超时错误的单周期脉冲 |

握手规则：

1. `meta_valid` 必须保持到 `meta_ready`；反压期间所有 meta 字段稳定。
2. 元数据握手完成后才能输出该包 payload；一个包的 payload 完成前不得输出下一包 meta。
3. `payload_valid && !payload_ready` 时，`payload_data/payload_last` 保持稳定。
4. 恰好传输 `meta_length` 个字节，且只在最后一个字节置 `payload_last`。
5. 截断、超长、错误 last、FIFO 溢出、超时或 `dma_abort` 时，guard 丢弃到当前 UDP 包尾，只产生一次错误；后续合法包必须可继续接收。
6. `meta_length` 的合法范围为 1～1024。payload 不要求 4 字节整长，DMA 通过 AXI `WSTRB` 处理尾部 1～3 字节。

`asset_udp_rx` 还接收 `current_session[31:0]` 并在输出 meta 前完成 session 检查。该值来自 `ASSET_SESSION` 的活动描述符：START 后到 done/abort 前保持稳定，由 A 的网络模块通过稳定多周期采样或请求/应答握手同步到 GE RX 时钟域；禁止逐 bit 独立同步后直接使用。DMA 仍再次比较 `meta_session`，形成跨模块的第二道保护。

## 5. Asset DMA APB 控制面

以下寄存器新增在现有 GPU APB 窗口，不改变 V1 偏移：

| 偏移 | 名称 | 访问 | 内容 |
|---:|---|---|---|
| `0x0100` | `ASSET_SESSION` | RW | 当前会话 |
| `0x0104` | `ASSET_DST_ADDR` | RW | 当前资源在 DDR 的基地址，4 字节对齐 |
| `0x0108` | `ASSET_ID` | RW | 期望 asset_id |
| `0x010C` | `ASSET_EXPECTED_OFFSET` | RW | 期望资源内 offset，4 字节对齐 |
| `0x0110` | `ASSET_EXPECTED_SEQUENCE` | RW | 期望 sequence |
| `0x0114` | `ASSET_MAX_LENGTH` | RW | 本描述符最多可提交的总字节数 |
| `0x0118` | `ASSET_CONTROL` | W | bit0 `START`；bit1 `ABORT` |
| `0x011C` | `ASSET_STATUS` | R | bit0 busy；bit1 done；bit2 error；bit3 aborted；`[15:8]` last_error |
| `0x0120` | `ASSET_COMMITTED_OFFSET` | R | 已成功写入并提交的资源内下一 offset |
| `0x0124` | `ASSET_COMMITTED_SEQUENCE` | R | 下一期望 sequence |
| `0x0128` | `ASSET_COMMITTED_BYTES` | R | 当前描述符累计提交字节数 |
| `0x012C` | `ASSET_PACKET_COUNT` | R | 成功提交包数，32 bit 自然回绕 |
| `0x0130` | `ASSET_ERROR_COUNT` | R | 拒绝或 AXI 失败包数，32 bit 自然回绕 |
| `0x0134` | `ASSET_DUPLICATE_COUNT` | R | 重复包数，32 bit 自然回绕 |

软件先写六个影子字段，再写 `START`。START 原子锁存描述符；busy 时再次 START 返回 `PSLVERROR`，不得覆盖活动描述符。以下任一条件使包在写 DDR 前被拒绝：session、asset_id、offset 或 sequence 不匹配；长度为 0/大于 1024；`meta_offset + meta_length > max_length`；目标越界或地址计算溢出。

START 时，`committed_offset` 初始化为 `expected_offset`，`committed_sequence` 初始化为 `expected_sequence`，`committed_bytes` 清零。包写地址固定为 `dst_addr + meta_offset`，并要求 `meta_offset + meta_length <= max_length`；因此 `dst_addr` 始终表示完整资源的 DDR 基址，而不是当前分块地址。带 `LAST` 的合法包提交成功后置 done 并清 busy。

完整包的所有 AXI B 响应成功后，才一次性更新 committed offset、sequence、bytes 和 packet count。相同 session/asset_id 且 sequence 小于当前期望值的包记为 duplicate，不写 DDR、不置致命 error。sequence 大于期望值为乱序错误。ABORT 阻止新 burst；已发出的 AXI 事务完成响应后置 aborted 并清 busy。

`last_error` 冻结为：`0=NONE`、`1=DESCRIPTOR`、`2=SESSION`、`3=ASSET_ID`、`4=OFFSET`、`5=SEQUENCE`、`6=LENGTH`、`7=ADDRESS_RANGE`、`8=STREAM`、`9=AXI_RESPONSE`、`10=ABORTED`。

## 6. Asset DMA AXI 写规则

- Asset DMA 只发 AXI 写，不发读。
- AXI 数据为 32 bit；首地址 4 字节对齐。offset 已固定 4 字节对齐，因此每包首拍 `WSTRB` 从 bit0 开始。
- burst 类型固定 INCR；单个 burst 不得跨 4 KiB 边界，也不得超过 AXI LEN 可表达的 256 beat。
- 非整字尾用 `WSTRB=0001/0011/0111`，线上先到的字节写入低地址、低有效 byte lane。
- 元数据未握手、描述符未 START 或任何保护检查失败时不得产生 AW/W。
- 任一 B 响应错误使当前包失败；不得推进 committed 状态。软件可 ABORT 后用同一 offset/sequence 重试。

## 7. 三路 DDR QoS

三个客户端固定为：Render（读写）、Scanout（只读）、Asset（只写）。AXI 事务一旦获准，所有地址、数据和响应通道必须保持同一 owner 到事务结束，禁止拍间切换 owner。

1. 当 `scanoutLevel <= 256` 时进入显示紧急态；直到 `scanoutLevel >= 1536` 才退出，形成滞回。
2. 紧急态中，Scanout 读具有最高优先级；在途事务可完成，但不得新发 Render 读或 Render/Asset 写地址。
3. 非紧急态中，Render 与 Scanout 读按事务轮询；Render 与 Asset 写按事务轮询。
4. 非紧急态内，持续请求的 Render 最迟在 8 个其他已完成事务后获准；持续请求的 Asset 最迟在 8 个其他已完成写事务后获准。
5. 紧急态可暂停第 4 条等待上界；退出紧急态后等待计数继续并优先偿还。任何有限等待保证都不能以引入显示下溢为代价。
6. `QOS_WATERMARKS` 原有字段、合法性检查和默认值不变；关闭 adaptive 时不进入紧急态，使用事务级轮询。

## 8. 性能计数器语义

V1 八个 64 位计数器和 `0x004C`～`0x008C` 偏移保持不变。运行计数器按无符号 64 bit 自然回绕，低 32 bit 溢出必须进位到高 32 bit。

- `PERF_CONTROL.bit0=SNAPSHOT`：同一周期锁存全部八个运行计数器，软件随后从低/高寄存器读取一致快照。
- `PERF_CONTROL.bit1=CLEAR`：清零全部运行计数器和旧快照。
- 同一周期内部事件与 CLEAR 同时发生时，CLEAR 优先，该周期事件不计数；下一周期立即恢复计数。
- 同一次 APB 写同时置 SNAPSHOT 和 CLEAR 时，先锁存清零前值，再清运行计数器。

V2 第 1 天不增加没有软件或验收消费者的新计数器。Asset 包成功、错误和重复统计使用第 5 节已有寄存器。

## 9. Sprite stress vector 二进制格式

`tb/vectors/stress_vectors.bin` 使用小端，文件由 32 字节文件头、若干 16 字节 tier 描述符及其命令记录组成。文件头：

| 偏移 | 类型 | 字段 | 值 |
|---:|---|---|---|
| 0 | char[4] | magic | `SVEC` |
| 4 | u16 | version | 1 |
| 6 | u16 | header_bytes | 32 |
| 8 | u16 | tier_desc_bytes | 16 |
| 10 | u16 | command_record_bytes | 32 |
| 12 | u32 | tier_count | tier 数 |
| 16 | u32 | random_seed | 固定种子 |
| 20 | u32 | total_command_records | 全文件命令记录数 |
| 24 | u32 | body_crc32 | 第 32 字节至文件末尾的 CRC-32/ISO-HDLC |
| 28 | u32 | reserved | 0 |

每个 tier 先写 16 字节描述符，随后紧跟 `command_count` 个命令：

| 偏移 | 类型 | 字段 |
|---:|---|---|
| 0 | u32 | sprite_count（16、32、64、96、128……） |
| 4 | u32 | command_count（包含该代表帧的背景、Sprite 和 PRESENT） |
| 8 | u16 | first_tag |
| 10 | u16 | last_tag |
| 12 | u32 | expected_pixels |

每个 32 字节命令记录直接映射 `GpuCommand`：

| 偏移 | 类型 | 字段 |
|---:|---|---|
| 0 | u8 | op |
| 1 | u8 | alpha |
| 2 | u16 | flags |
| 4 | u16 | tag |
| 6 | u16 | reserved=0 |
| 8 | u32 | src_addr |
| 12 | u32 | dst_addr |
| 16 | u16 | width_pixels |
| 18 | u16 | height_pixels |
| 20 | u32 | src_stride |
| 24 | u32 | dst_stride |
| 28 | u16 | color |
| 30 | u16 | color_key |

`command_count` 必须至少为 1，tag 在 tier 内按 16 bit 模运算连续，描述符 last_tag 必须等于最后一条命令 tag。负责人仿真检查队列顺序、完成 tag、像素数和错误码；B 的 300 帧/p5 FPS 算法使用同一 tier 和种子，但仿真结果不得表述为板上 FPS。

## 10. 验收与变更规则

- A 的 wrapper 必须用 64 字节与 1024 字节 UDP 载荷验证，并证明坏校验包不产生 `rx_valid`。
- A 的 parser/guard 必须覆盖坏 magic、坏版本、超长、截断、错误 last、重复、乱序、FIFO 满、随机反压和异步复位。
- 负责人 Asset DMA 必须覆盖 1/2/3/1023/1024 字节、非整字尾、4 KiB 边界、B 响应错误、ABORT 和随机反压。
- 三路 QoS 必须证明各事务 owner 锁定、非紧急态等待上界及 Asset 压力下 Scanout 无下溢。
- V2 帧测试必须恰好输出 518,400 个内部像素、540 个行尾和 1 个帧尾。

修改本文中的任何地址、位宽、字段、字节序、时钟域、握手规则或仲裁上界，必须同时修改负责人 Chisel、A 的 Verilog、B 的 C/PC 工具和对应测试；只改其中一方视为接口破坏。
