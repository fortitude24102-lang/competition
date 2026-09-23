# A、B 接下来怎么做

更新：2026-09-23。这是现有 V2 一周计划的接续说明，不替换计划、不改变最终目标。

## 先同步，别重复做

先把最新 main 合入自己的 A-work / B-work，保留各自尚未合入 main 的工作，不要用旧文件整目录覆盖 main。遇到冲突逐项处理；GPU 生成文件以 main 的 RC0 为准，不手改 `generated/efinix_gpu/`。

负责人已完成 GPU RC0；A 的 960×540 → 1920×1080 全屏显示、欠流 CDC、显示接线及 GPU 工程文件清单已接入，相关 8 项仿真通过，这些不用重做。当前还不是可直接上板的完整 V2，旧 V1 固件/位流不能冒充 V2。

接口统一看 `docs/efinix_2d_gpu/v2_interface_contract.md`；GPU 端口接线看 `v2_lead_offline_acceptance.md`。继续复用官方 Sapphire CPU，不恢复自研 CPU。

## A：优先把网口到 GPU 的硬件通路补齐

1. 补齐官方 GE 源码依赖和 SHA256 清单，放在 `board/efinix_ti60/vendor/ge_udp/`，官方文件保持原样。当前交付只有部分文件：工程引用的 `mac/rx/*`、`mac/tx/*`、`gmii_rx_buffer.v`、`gmii_tx_buffer.v` 等还缺，不能只交一个 demo 顶层。
2. 在 `board/efinix_ti60/rtl/net/` 完成 MAC/UDP 封装、RX/TX 跨时钟通路、`asset_stream_guard`、活动 session 同步。接收通路要输出合同规定的 meta/payload 受保护流；发送通路要能把 Sapphire 的 GET 请求发给 PC。session 多位值不能逐 bit 独立同步后直接使用。
3. 补 `board_top.v`、`efinix_sapphire_adapter.v` 中网络与 GPU Asset DMA 的完整接线，包括 ready/valid、abort、stream_error、活动 session；补 GE 工程源文件、管脚和时钟/CDC 约束。不要另造一份 GPU DMA。
4. 如果 CPU 访问网络发送/状态接口尚未定稿，先交一份寄存器/驱动接口说明给负责人和 B，写清地址、读写语义、时钟、发送完成与错误行为；不得占用已冻结的 GPU 寄存器。这个接口先定，B 才能接真实设备。
5. 提交可运行的网口/跨域/板级测试：64/1024 字节、坏包、长度不符、截断、错误 last、反压、FIFO 满、超时、ABORT 和复位后恢复。不能仅凭一个合法包测试说网络完成。先用测试台发包，不必等 B 的游戏或 PC 服务。

交到 A-work：上述 RTL、完整 vendor/来源与哈希、工程/约束、接口说明、测试台和运行命令/结果。自研每个 `.v` 文件只放一个 module。负责人拿到后做网络 → Asset DMA → DDR 联合验收，再安排整板构建。

## B：软件和资源先独立推进，再接 A 的真实接口

1. 统一固件为 960×540、RGB565、stride=1920、单帧 1036800 字节。帧缓存 A/B 为 `0x02000000` / `0x02200000`，资源区从 `0x02400000` 开始；检查 `gpu_regs.h`、缓存分配、绘图/HUD、资源转换和所有旧 640×480 假设。
2. 修 `tools/generate_stress_vectors.py`，重新生成 `tb/vectors/stress_vectors.bin`：目标地址不能为 0；PRESENT 要有合法帧地址、非零尺寸和 stride；`expected_pixels` 要计入实际背景绘制；重算 CRC，保持冻结的 SVEC 格式和连续 tag。详细失败证据在 `v1_gap_acceptance.md`。
3. 复用已有 `asset_fetch`、协议解析、资源缓存和服务器处理函数，不重新写一套。PC 端补实际 UDP socket、文件读取、资源 manifest 和启动方法；Sapphire 端补真实网口驱动、Asset DMA 寄存器操作，并接入 main。A 的硬件接口未到时先用现有回调/测试替身验证超时、重试、CRC、重复包和缓存失败回滚，不能把替身测试当成实机完成。
4. 接上游戏、HUD 和基准流程：PC 只存资源并响应 GET；资源选择/校验、缓存、输入、游戏逻辑和 GPU 命令必须在 Sapphire 上执行。优先复用许可清楚的游戏逻辑，提交资源包、转换方法、来源和许可证，不导入未经授权的原版素材。
5. 补齐 CPU 纯软件 / GPU 渲染帧率及加速比展示；压力测试按 16/32/64/96/128…分档、每档 300 帧、固定种子输出 CSV，统计 p5 FPS、欠流和硬件错误。真实稳定 60 FPS 上限必须上板实测；离线阶段只交程序和测试，不填假数据。

交到 B-work：C 源码/头文件、PC 服务及运行说明、修正的向量生成器和二进制、资源包/许可清单、构建方法和测试结果。若复用的 B 文件目前只在 A-work，先按文件带入自己的分支，别把 A 整套板级工程一起覆盖过来。

## 怎么配合，避免互相等

A 用合同和测试台推进网络硬件；B 用合同和回调测试推进软件与资源，两边可同时做。A 先交 CPU 网络访问接口，B 再接真实驱动；负责人收到修正向量即可先验向量，不用等完整游戏。

每次提交附一句“完成了什么、怎么运行、哪些还没做”，并提供 commit ID。最终使用同一套核、固件和资源联合验收：资源 CRC、CPU/GPU 对比、稳定 Sprite 上限、断网后已加载场景继续运行、30 分钟耐久。没有实际跑过的上板/时序/吞吐结果标为待测。
