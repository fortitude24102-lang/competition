# 正式候选发布目录

现有 `gpu_demo.elf`、`gpu_demo.bin`、`gpu_demo.hex` 与 `software.sha256` 属于 V1 软件产物。运行 `scripts/test-efinix-software.ps1` 会重新构建它们；这些现有文件不能作为 V2 960×540/以太网方案的配套固件。

V2 GPU 核候选及冻结状态见 `docs/efinix_2d_gpu/v2_final_acceptance.md`；`v2_rc0.sha256` 仅用于核对该候选的生成 RTL 和 `filelist.f`，不覆盖 V1 固件。生成目录通过 `.gitattributes` 固定 LF 换行，避免 Windows/Linux 检出改变文件哈希。

V2 正式 `.bit`、固件、`benchmark.csv`、耐久日志和最终 `manifest.sha256` 尚未齐备。A 还需完成官方 GE/CDC/guard 与新 GPU 端口的完整板级接线；B 还需完成 V2 固件、资源包和修正后的压力向量。最终发布清单须在这些产物使用同一候选核完成板测后生成。
