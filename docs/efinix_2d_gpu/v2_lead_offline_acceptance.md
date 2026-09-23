# V2 主负责人离线交付与接线边界

记录日期：2026-09-23。依据 `v2_interface_contract.md` 和复用官方 Sapphire / DDR3 / HDMI Demo 的 V2 计划。本记录覆盖主负责人第 5～6 天的 Chisel 子系统和第 7 天 GPU 核候选冻结；不代表以太网链路或开发板验收。

## 已完成

- 内部 framebuffer 改为 960×540 RGB565、stride 1920 字节；A/B 每块仍保留 0x200000 字节槽位。Scanout 整帧仿真输出 518400 像素、540 个行尾和 1 个帧尾，固定像素流 CRC32 为 `0x954A2475`。
- DDR 仲裁扩展为 Render 读写、Scanout 只读、Asset 只写。低/高水位滞回保留；紧急态停止新 Render/Asset 地址，非紧急态按完整事务轮询，并把同拍获准的两笔其他事务分别计入 Render 等待上界。地址选择后再次检查紧急态；此前已经呈现且被反压的 AXI VALID 属于在途地址，继续保持到握手。
- Render 响应 FIFO 可容纳完整 256 拍 burst，保存 DATA/ID/RESP/LAST；仅 FIFO 空时准入下一笔 Render AR。这样 Render 写反压不会一直占住物理读通道，Scanout 可以在物理 RLAST 入缓冲后继续读取。客户端自身未取旧响应期间的新 AR 不参与可服务请求的等待计数。
- 首次实际启用显示前不把空 FIFO 误判为紧急态；后续 PRESENT 等待期间仍保持显示优先级。Scanout 在紧急态持续补行直到达到高水位，避免“256 低水位加一行 960 像素仍达不到 1536”造成永久暂停。输出 ready/valid 继续限制 FIFO 容量。
- GPU 顶层 APB 的 `0x0100` 页接入 Asset DMA 寄存器，保留 V1 寄存器偏移；受保护元数据和 payload 经完整包缓存、第三路 AXI 写入 DDR。3 字节尾拍的 `WSTRB=0x7` 已由顶层测试确认。
- 接入 guard 的 `stream_error`：接收中途截断会在任何 DDR 地址发出前报告 STREAM 错误。AXI B 失败后已提交 offset/sequence/bytes 不推进，活动描述符保留到软件 ABORT，随后可用同一 offset/sequence 重新 START。ABORT 与最后一笔写完成同拍时优先完成取消，不再误报 committed。
- 分模块 RTL 位于 `generated/efinix_gpu/`；A 必须按最终 `filelist.f` 全量更新工程清单，包括 Asset DMA、包缓存和 Render 响应 FIFO，不能继续沿用 A-work 中的旧生成模块列表。最终回归、生成物检查与 RC0 状态见 `v2_final_acceptance.md`。

## 顶层对 A 组的固定交接

生成端口与合同第 4.2 节的对照：

| A 的 guard / parser 信号 | GPU 顶层端口 |
|---|---|
| `meta_valid` / `meta_ready` | `io_assetMeta_valid` / `io_assetMeta_ready` |
| `meta_session`, `meta_asset_id`, `meta_offset`, `meta_length`, `meta_flags`, `meta_sequence`, `meta_crc32` | `io_assetMeta_bits_session`, `io_assetMeta_bits_assetId`, `io_assetMeta_bits_offset`, `io_assetMeta_bits_length`, `io_assetMeta_bits_flags`, `io_assetMeta_bits_sequence`, `io_assetMeta_bits_crc32` |
| `payload_valid` / `payload_ready` / `payload_data` / `payload_last` | `io_assetPayload_valid` / `io_assetPayload_ready` / `io_assetPayload_bits_data` / `io_assetPayload_bits_last` |
| `stream_error` | `io_assetStreamError` |
| `dma_abort` | `io_assetDropPacket` 与 `io_assetAbort` 逻辑或 |
| parser `current_session` | `io_assetSession`（另用 `io_assetActive` 指示有效期） |

`assetDropPacket` 是元数据被 DMA 拒绝后的丢包请求；`assetAbort` 是软件 ABORT 或 writer 失败。跨 GE RX 与 GPU 时钟域传递 session 时必须采用稳定多周期采样或握手，不能逐 bit 独立同步。

## 验证范围

- 边界测试覆盖首次显示、后续待换帧、紧急态地址入口、AXI VALID 保持、256 拍完整响应缓存与 ABORT/完成同拍。
- 三路仲裁模型限定每两周期最多传输一个共享 DDR 数据拍，并加入地址反压及 B 延迟；Render 读写、Scanout 读和 Asset 写均实际获得服务，非紧急态等待不超过 8 笔事务，模拟显示 FIFO 无欠流。
- 完整顶层模型由 APB 发起 PRESENT、Asset START 和 COPY，接入 1024 字节资源流与 2048 像素显示 FIFO。模型使用共享 DDR 数据带宽和地址反压，核对 1024 字节 Asset 写入、512 字节 COPY 结果、256 个渲染像素计数及 Scanout 像素/行尾。显示模型预填至 1536 后每 4 个 GPU 周期消费一个像素；该设定用于功能与竞争验收，不推导实板帧率。
- 最终完整 GPU 回归及生成检查结果记录于 `v2_final_acceptance.md`。
- 上述测试是仿真和 RTL lint，不是板上 HDMI、网口或 FPS 结论。

## 尚需 A/B 交付后才能进行

截至 `competition/A-work@6de10a3`，A 有 ASST 接收解析器和 960×540 显示参数化，但尚无官方 GE UDP wrapper、RX/TX 跨时钟 FIFO、`asset_stream_guard`、session CDC 握手和将上述新顶层端口接入 `efinix_sapphire_adapter.v` / `board_top.v` 的完整板级链路。Efinity XML 也需按新 `filelist.f` 纳入完整模块，随后才能做有效的板级构建及网口/HDMI 联调。

B 的协议、资源服务/缓存与 SVEC 文件已有 A-work 更新。`stress_vectors.bin` 的长度、记录边界和 CRC 正确，但语义未通过：全部 346 条命令目的地址为 0，PRESENT 为 0×0，每档预期像素少算一条 FILL 的 256 像素。详细证据与修正要求见 `v1_gap_acceptance.md`。收到修正版后才能执行该文件的真实命令交叉回归。

该分支的 `sw/efinix_gpu/include/gpu_regs.h` 仍是 640×480 / 614400 字节，必须改为 960×540 / 1036800 字节。B 已有 `asset_server_handle_get`、回调式 `asset_fetch` 和事务缓存，应继续复用；尚需把它们接入 PC 实际文件/UDP 服务和 Sapphire 真实设备接口，再完成正式资源包及 main 接线、CPU/GPU HUD 对比和逐档 300 帧压力流程。已有缓存/协议文件不等于这条可执行链路已经完成。板上性能结论仍待 A/B 集成。

在这些文件交付前，主负责人不修改或伪造 A/B 的 GE/游戏实现，也不声称板上完成。
