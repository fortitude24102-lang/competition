# 2026-10-27 最终演示文件

本目录为新增交付包，既有 V1/V2 release 未覆盖。BIT：Ti60F225 官方 Sapphire/DDR/HDMI 基础上的二维 GPU，提交 `0c47970` 的行交接候选；BIN/HEX：六档游戏与独立 15 秒 CPU/GPU 同屏展示。

板 IP 192.168.1.3，PC 192.168.1.2；管理 UDP8090，资源 UDP8080，网页 http://127.0.0.1:8765/#game 。只用 JTAG 加载 BIT 与 RAM 固件；未写 Flash。不要把原生六档游戏与 480×270 同屏展示成绩混算。

身份见 `SHA256SUMS.txt`；构建、实测和限制见[根 README](../../README.md)与[同屏证据](../../docs/efinix_2d_gpu/evidence/split_comparison_20261027/README.md)。
