# V2 候选版：2026-09-26

此目录保存**同一轮板测**的 `efinix_2d_gpu.bit`、Sapphire 固件 `gpu_demo.elf/.bin/.hex` 和 Windows `asset_server.exe`。源文件位于 `board/efinix_ti60/`、`chisel/`、`sw/efinix_gpu/`；逐文件哈希见 `manifest.sha256`。素材在 `sw/efinix_gpu/assets/v2/`，运行服务端时从仓库根目录传入其 `manifest.csv`。

板测网络地址：板卡 `192.168.1.3`，PC `192.168.1.2`，UDP `8080`。换网段应重新编译固件；见 `docs/efinix_2d_gpu/v2_network_usage.md`。先在 PC 启动资源服务器，再经 JTAG 临时加载 `.bit`。Sapphire 固件须先 `reset halt`、加载 `.bin` 至 `0x1000`，然后 `resume 0x1000`。本包**没有写入 Flash**；上电后需重新加载。切勿与根目录 V1 固件混用。

本轮串口实测：四份资源 CRC 全通过、零重试；32 Sprite 的 CPU/GPU 成绩约 2.1/8.5 FPS。尚缺稳定 60 FPS、高负载 Sprite 极限与长时间耐久证明。详细记录见 `docs/efinix_2d_gpu/v2_implementation_progress.md`。
