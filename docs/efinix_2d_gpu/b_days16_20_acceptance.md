# B 组员第 16～20 天交付与验收

本批任务沿用官方 Sapphire CPU、DDR3 与 HDMI Demo，不引入自研 CPU，也不改变已冻结的 APB 寄存器偏移。当前没有开发板，因此这里只把可离线证明的部分标为完成；画面观感、真实帧率和 HDMI 欠流仍保留为上板验收。

## 第 16 天：高级绘图 Demo

- `sw/efinix_gpu/src/assets.c`：增加 12×8 敌机素材，和原 8×8 玩家素材一次上传到稠密素材区。
- `sw/efinix_gpu/src/game.c`：`game_build_commands` 为每帧生成同一份有界命令列表，包含背景 Fill、玩家 Color Key、敌机 Alpha 和子弹 Fill。
- `sw/efinix_gpu/src/main.c`：前 150 帧逐条等待，后 150 帧批量提交，渲染内容来自同一命令列表。
- 离线验收：测试断言一帧内同时存在 `GPU_OP_COLOR_KEY` 与 `GPU_OP_ALPHA`。
- 上板验收：切换提交模式前后画面内容一致，透明色无紫边，Alpha 边缘无明显色带。

## 第 17 天：批量提交与 tag 回收

- `sw/efinix_gpu/include/gpu.h`、`sw/efinix_gpu/src/gpu.c`：增加 `gpu_try_submit`、`gpu_submit`、`gpu_poll`、批量可用的 `gpu_wait_tag`。
- 软件跟踪最多 16 条在途命令；队列满返回 `GPU_DRIVER_AGAIN`，阻塞提交可在完成进度出现后继续。
- `LAST_DONE` 只提供最新完成 tag。为保证批量期间即使跨过多个完成 tag 也不会漏掉中间错误，负责人侧 `Efinix2dGpuTop.scala` 已将现有 `ERROR` 寄存器改为“首次非零错误保持到复位”，不增加也不移动 APB 寄存器。软件稳定读取 `LAST_DONE → ERROR → LAST_DONE`；只要错误为 0，就能安全回收按序完成的整段 tag。发生错误后按现有恢复约定复位 GPU。
- 离线验收：连续接受 16 条，第 17 条返回 `AGAIN`；允许执行后第 17 条成功，最终接受数和完成数都为 17。
- 上板验收：APB 满队列压力测试中无命令丢失、乱序或重复执行。

## 第 18 天：逐条等待与批量模式对比

- `sw/efinix_gpu/include/benchmark.h`、`sw/efinix_gpu/src/benchmark.c`：`gpu_benchmark_submit_stream` 对同一命令列表运行两种提交模式，输出命令数、等待次数、每命令等待千分比、CPU 周期和软件观察到的队列高水位。该接口不把等待次数冒充 CPU 占用率；固件 HUD 的 CPU 忙碌千分比由真实 `rdcycle` 渲染周期/帧周期计算。
- 离线验收：两种模式接受的命令数相同；逐条模式每条等待一次，批量模式只等待末 tag；批量队列高水位大于 1。
- 上板验收：用真实 `rdcycle` 记录帧周期和 CPU 忙碌比例，并以 framebuffer CRC 或截图确认两种模式画面一致。

## 第 19 天：现场 HUD

- `sw/efinix_gpu/include/hud.h`、`sw/efinix_gpu/src/hud.c`：生成有界 HUD 命令列表，显示 FPS、Sprite 数、CPU 忙碌千分比、队列高水位、欠流数、错误码和提交模式颜色块。
- `main.c` 已接入 FPS、Sprite、CPU 忙碌比例、队列高水位、错误码和模式；蓝色块表示逐条等待，绿色块表示批量提交。HUD 构建接口会拒绝超出 640×480 的坐标。
- 离线验收：最坏输入仍不会超出 `HUD_MAX_COMMANDS`。
- 待负责人依赖：A 第 18～19 天已有 HDMI 域欠流计数，但尚未映射到 CPU 可读寄存器，因此 `main.c` 的欠流数当前固定为 0；负责人完成跨时钟域/APB 接入后再替换。
- 上板验收：现场可见两种模式及性能差异，制造带宽压力时欠流和错误字段同步变化。

## 第 20 天：300 帧稳定性统计

- `benchmark_summarize_run` 只接受 300 帧样本，计算第 5 百分位 FPS，累计欠流与错误。容量候选至少要在 30 帧中达到或超过该 Sprite 数，并且这些帧自己的 P5≥60；单帧偶然达到的高 Sprite 数不会被误报为稳定容量。
- `main.c` 保存完整 300 帧样本并在结束时调用统计函数；P5 不达标、欠流/错误非零时不打印 PASS。
- 离线验收：固定输入样本的 P5 与稳定判定可重复；注入一次欠流后稳定 Sprite 数归零，并保留欠流计数。
- 上板验收：用固定随机种子逐档增加 Sprite 数，每档运行 300 帧；将通过条件的最大档记录为“稳定 60 FPS 最大 Sprite 数”。失败记录必须带欠流和错误计数。

## 自动验证

运行 `scripts/test-efinix-software.ps1`。脚本会执行 sanitizer 主机测试、B 第 16～20 天专项测试、RV32 编译和完整 Sapphire ELF/BIN/HEX 链接，并用 `-Wstack-usage=2048` 防止单个函数接近官方 4 KiB 栈上限。两个大命令列表和 300 帧样本放在 BSS，而不是栈。输出中的 `not board executed` 表示只证明软件构建和离线模型，不代表已经通过板卡验收。

## 下一依赖点

B 第 21 天需要负责人完成自适应 QoS 的 CPU 可读/可控接口；B 第 22 天需要负责人完成 SparseDecoder 接口。因此本批在第 20 天停止，未提前伪造后续硬件依赖。
