# V2 GPU 核候选与最终验收状态

日期：2026-09-23。

## 当前边界

主负责人第 5～6 天已完成 960×540 Scanout、Asset DMA 顶层接线和三路 DDR QoS。最终全套 GPU 回归 60/60 通过，拆分 RTL 与 lint 均通过，GPU RC0 已冻结。

RC0 只冻结 GPU 生成 RTL 和寄存器合同。V2 系统尚未封版，`release/` 中已有的 V1 固件不属于此候选。

RC0 哈希清单为 `release/v2_rc0.sha256`，记录 35 个引用文件加 `filelist.f`，共 36 个文件的 SHA256。35 个引用文件包含 34 个 RTL module 和 1 个头文件；每个 `.v` / `.sv` 恰好一个 module，文件路径及模块名均无重复。生成后统一 CRLF/CR 为 LF，此步骤已加入 `scripts/test-efinix-gpu.ps1`，Git 检出也固定 LF。

## 固定接口

- 顶层：`Efinix2dGpuTop`；GPU/APB/DDR AXI 时钟 100 MHz。
- 内部图像：960×540 RGB565，stride=1920，单帧 1036800 字节。
- Framebuffer A/B：`0x02000000` / `0x02200000`；Asset 写入范围 `[0x02400000, 0x10000000)`。
- APB 基址：`0xF8100000`；V1 偏移不变，Asset DMA 使用 `0x0100`～`0x0134`。
- ID=`0x32444750`，兼容版本寄存器仍为 `0x00010000`；候选身份以生成物哈希清单为准。
- 显示 FIFO=2048 像素；默认低/高水位=256/1536。紧急态继续补行，像素 ready/valid 控制容量。
- 网络/GPU 顶层接线表见 `v2_lead_offline_acceptance.md`；时钟域、协议和软件控制语义以 `v2_interface_contract.md` 为准。

## 验证记录

- 定向：完整 Render burst 反压、事务 owner 保持、三路完整顶层联合测试，3/3 通过。
- 受限 DDR 带宽仲裁测试通过，覆盖三路竞争、紧急态进入/退出、等待上界和模拟 FIFO 无欠流。
- 最终全套 GPU 回归：`testOnly gpu.*`，10 suites、60 tests，全部通过（2026-09-23 10:52）；同一轮紧接执行 `GenerateEfinix2dGpu --split-verilog` 成功。
- 最终 split RTL、单文件单 module、filelist 完整性及模块名唯一性检查通过。
- 以 `Efinix2dGpuTop` 为顶层、按 `filelist.f` 执行 Verilator lint 通过；仅关闭已有混合 timescale 警告。
- RC0 新增 `AssetDmaRegs.sv`、`AssetDmaWriter.sv`、两个包缓存模块，以及 `Queue256_Axi4ReadData.sv` / `ram_256x39.sv`。A 的 Efinity 文件清单须完整同步。

这些记录不证明以太网实际吞吐、1920×1080 HDMI 板测、60 FPS 上限或 30 分钟耐久。

## 继续推进所需交付

### 2026-09-23：A-work `96f46c8` 显示增量接收

负责人按文件接入 A 的 960×540 行缓存、1920×1080 全屏 2×缩放、欠流事件 CDC、board_top/adapter 欠流接线、Efinity GPU 文件清单和对应约束；未整分支合并，未替换 GPU RC0 生成物或导入 B 的未验收代码。

- 验证方式：先把 A 的全屏测试用于旧缩放器，得到 `prefetch mapping mismatch`；接入新实现后通过。修正测试成功提示中的 270 为 540，不改变断言。
- `scripts/test-efinix-verilog.sh` 的前 7 项通过；随后新增并单独运行 `tb_gpu_perf_underflow` 通过，共 8 项。本次不重复运行已通过的 60 项 Chisel 回归。
- HDMI 联合测试核验正常供流时两帧完整 1920×1080 像素、960×540 源坐标，以及断流欠流计数、恢复后出现白像素；不证明断流后重新对齐至完整帧边界。独立 CDC 测试覆盖密集事件、两域复位、短复位和释放窗口；GPU 计数测试覆盖三次精确递增和 CLEAR 优先。
- `scripts/test-v2-display-integration.ps1` 通过：工程源文件存在、GPU filelist 顺序一致、36 个 RC0 文件 SHA256 不变、欠流链路静态接线正确。该检查不代表整个 board_top 完整 elaboration 或网络已接通。
- 使用本机现有 WSL Verilator；未导入 A 脚本中本机不存在的 `D:/FPGA/iverilog` 依赖。未生成新的波形、位流或 Efinity 时序报告，未上板。

本次仍不能接收以太网通路：A-work 仅提交 13 个 GE vendor 文件，`led_demo.xml` 引用的 `mac/rx/*`、`mac/tx/*`、`gmii_rx_buffer.v`、`gmii_tx_buffer.v` 等未随交付，且没有 GE 哈希清单；网络自研目录只有 `asset_protocol.vh` 和 `asset_udp_rx.v`，未见 MAC wrapper、RX/TX CDC、guard、session 同步及板顶层网络接线。合法包解析测试不能代替冻结合同中的坏包、长度、CRC/恢复和跨域验收。GE 部分暂留 A-work，不作为可构建主线导入。

下表为本次核对后的依赖；A 的显示接线和完整 GPU 工程文件清单已收到，不再作为缺失项催交。A 旧验收文档里的 V1 分辨率、位流和时序数据不适用于本次 V2 集成。

| 负责人 | 所需文件/结果 | 收到后的步骤 |
|---|---|---|
| A | 官方 GE vendor/manifest、MAC wrapper、RX/TX CDC、stream guard、session CDC | 核对受保护流，完成网络到 DDR 联合验收 |
| A | board_top/adapter 的网络到 Asset DMA 接线、GE 管脚/时钟约束、完整板级联合 testbench（显示接线与 GPU filelist 已接收） | 构建同一 RC0 并取得时序/CDC/HDMI/网口报告 |
| B | 修正后的 stress_vectors.bin 及生成器 | 按真实命令核验 tag、像素计数和错误码；现有失败证据见 v1_gap_acceptance.md |
| B | 960×540 固件常量，将已有 asset_fetch/服务处理函数接入真实设备/PC UDP，main/HUD/压力测试接线、资源包与许可清单 | 生成匹配 RC0 的固件和资源服务产物 |
| A+B | 同一核/固件的 CSV、CRC、稳定 Sprite 上限、断网继续与耐久证据 | 负责人审核计数，生成完整最终 manifest.sha256 并封版 |

PC 的职责继续限定为资源存储和 GET 响应；资源选择、校验、游戏状态和 GPU 命令由官方 Sapphire RISC-V 负责。
