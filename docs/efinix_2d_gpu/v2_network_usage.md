# V2 资源服务与实时性能对比

PC 保存并返回 RGB565 文件。官方 Sapphire RISC-V 决定请求的资源、目标地址、重试和场景状态，AetherGX 负责硬件绘制。加载完成后的画面不依赖 PC 的逐帧运算。

## 启动 PC 服务端

在仓库根目录运行：

```powershell
./scripts/build-v2-asset-server.ps1
./generated/verification/v2-network-software/asset_server.exe ./sw/efinix_gpu/assets/v2/manifest.csv 8080
```

构建脚本在 WSL 使用 `gcc-mingw-w64-x86-64`，产物是原生 Windows exe。服务端只接受 manifest 中列出的资源编号；GET 中不携带文件路径。

板卡默认 IP 为 `192.168.0.2`，PC 网卡需在同一网段使用 `192.168.0.3`，UDP 端口均为 `8080`。如需要更换地址，通过固件编译宏 `NETWORK_LOCAL_IP`、`NETWORK_PEER_IP` 配置；当前实现面向直连/同子网千兆网口，无 DHCP、网关和路由。Windows 防火墙需允许该服务端接收 UDP 8080。本轮脚本不会更改 PC 网卡地址或防火墙规则。

固件启动时按顺序加载 scene、flower、zombie_walk1、zombie_walk2。串口输出每个资源的编号、成功提交字节数、请求尝试数、重试数、耗时和返回码。所有文件 CRC 校验通过后，屏幕显示 `NET READY`。失败时显示 `NET FAIL FALLBACK`，以独立 DDR 地址中的本地素材继续性能演示；这不算以太网验收通过。

## 屏幕与测试口径

本机 2026-09-26 联调沿用 PC 的 `192.168.1.2`，板卡改为 `192.168.1.3`。只构建对应固件、不重复主机回归：

```powershell
./scripts/test-efinix-software.ps1 -FirmwareOnly -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102
```

JTAG 加载固件前执行 `reset halt`；加载后从 `0x1000` 开始运行。V2 位流仅临时加载，不写 Flash。

同一组 Sprite 的同一段运动序列分别由 CPU 软件和 GPU 硬件绘制。屏幕保留两种模式最近一个窗口的成绩，标出当前运行模式与 Sprite 数量。`FPS` 包含 HUD 与 PRESENT 等待，`RENDER MS` 只测量场景绘制与完成同步。初次测量之前显示 `--`。

背景和每个 Sprite 的来源、位置、尺寸及混合方式在两种模式中保持一致；每帧使用 Color Key 和 Alpha。GPIO KEY1 减少负载，KEY2 增加负载。固定的最高软件档位不代表硬件的实际极限；稳定 60 FPS 与吞吐结果须由同一候选位流实测。

## CPU 网络寄存器

基址与 GPU 相同，为 `0xF8100000`。板级适配器仅将 `0x0200` 页面分派给网络模块，原 GPU 与 Asset DMA 寄存器不变。

| 偏移 | 名称 | 语义 |
|---|---|---|
| 0x0200 | ID | 只读 `0x4E455431`，ASCII NET1 |
| 0x0204 | STATUS | bit0 正在发送；bit1 发送完成；bit2 发送错误；bit3 请求 FIFO 可用 |
| 0x0208 | CONTROL | 写 bit0 发出 32 字节 GET；要求 Asset DMA 已 START，且发送端不忙 |
| 0x020C | LOCAL_IP | 本机 IPv4 数值，如 `0xC0A80002` |
| 0x0210 | PEER_IP | PC IPv4 数值，如 `0xC0A80003` |
| 0x0214 | PORTS | 低 16 位本地端口，高 16 位 PC 端口 |
| 0x0218 | RESERVED | 保留，读 0；不将跨域未同步计数当成有效统计 |
| 0x021C | TX_COUNT | 完成发送统计 |
| 0x0220–0x023C | TX_DATA[0..7] | 32 字节 ASST 头；每字低 byte lane 为最早发送字节 |

请求头、IP、端口与活动 Asset DMA session 随 SEND 原子传递到网口时钟域。分块载荷 CRC 在解析器中通过后才输出元数据；完整资源 CRC 由 RISC-V 对 DDR 内容计算。CPU 每次只等待一块，响应超时为 20 ms，最多重试 5 次；发送阶段包含 ARP，使用独立的 100 ms 软件等待上限。每次重试先等 ABORT 完成，再从尚未确认的 offset/sequence 恢复，防止链路复位留下半包。

## 检查入口与边界

```powershell
wsl bash scripts/test-v2-network-software.sh
wsl bash scripts/test-v2-perf.sh
python sw/efinix_gpu/tests/test_asset_server_udp.py generated/verification/v2-network-software/asset_server.exe
make -C sw/efinix_gpu
```

主机协议测试、RTL 仿真、Efinity 接口设计检查和真实上板结果分开记录于 `v2_implementation_progress.md`。现有 V1 release 不会被软件构建自动替换。V2 固件位置为 `generated/verification/efinix-software/gpu_demo.elf/.bin/.hex`；它需要匹配的 V2 板级位流。
