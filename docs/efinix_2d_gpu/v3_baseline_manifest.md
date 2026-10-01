# V3 起点冻结清单（2026-10-01）

V3计划提交：`0c0dd613abb1c59bef5da14245a7f29d9d0f45d9`；V2性能基点：`85b7dc0`。本清单是候选开发前的实物对应关系，不表示V3已验收。release/v2仍为9/26冻结包。

| 项目 | 文件 | SHA256 |
| --- | --- | --- |
| 实测位流 | D:/efinity_builds/texture_cache_20260928/outflow/efinix_2d_gpu.bit | 84b2e64670b1878b806aa6504af0826280c3a99830fc60a1f79906662639057a |
| 正常R7固件 | generated/verification/hud-glyphs/entry/normal.bin | 8fef6f0c54ba4f10aa1c562e2bc80e671d49bb38f145c078e0c64cda9e5d3ffb |
| 背景 | sw/efinix_gpu/assets/bullet/background.rgb565 | efd775574d23578fe2d7c7d01ad39c7f9b42f21336342f957ff1826d1e21858e |
| 图集 | sw/efinix_gpu/assets/bullet/atlas.rgb565 | c27a2d3d02f35af807874bfb3903a308c797ac16b522c1419ad8dc4aa9d8b0e4 |

位流/正常固件为机器本地诊断工件，不保证新克隆包含；资源为仓库文件。上板候选必须单独登记源码、生成RTL、位流、固件哈希，不能与此表混用。

固定条件：官方Sapphire RV32IM_Zicsr及GPU均100 MHz；960×540 RGB565，HDMI1080p60；A/B=0x02000000/0x02200000，stride1920；合法DDR `[0x02000000,0x10000000)`。不改CPU绘图、场景和光晕比例。

R7入口为sw/efinix_gpu/src/main.c的弹幕比较路径（seed7、32/64/128/256/512档），调用bullet_demo.c生成场景；perf_demo.c保留旧性能辅助函数，不是R7主循环。正常、逐命令探针、隔离背景诊断入口和9/30原始记录见v3_research_20260930.md，复测使用相同入口而不是网页新游戏。512档无探针PRESENT前平均19.263 ms、最大20.855 ms；背景约7.6 ms，构建约3.101 ms。提交阻塞与GPU执行重叠，不能直接相加。

离线固件入口检查：`powershell -File scripts/test-hud-glyph-entry.ps1`（会重新生成诊断目录，不用于保持旧二进制不变）。专项诊断构建：`powershell -File scripts/build-board-hud-dma-test.ps1 -Test render-phases`。历史采集脚本measure-hud-glyphs-board.ps1的`-LoadBit`固定加载旧Cache位流；V3候选不能盲目使用该开关，应先明确候选位流及哈希。以上采集会访问板卡，本轮均未执行。

## 新地址解码检查（未改生产连接）

- board/efinix_ti60/rtl/efinix_sapphire_adapter.v只把高字节02分给网络，其余给GPU顶层。
- Efinix2dGpuTop.scala只把高字节01分给Asset DMA，其余给GpuApbRegs。
- 所以0300管理和0400可选实例当前未接入，不能只添加模块就宣称地址可用。第8天必须显式选择管理块；实例仅条件原型入选时接入。此轮Copy不增加APB地址。

## 保留异常和本轮边界

SoftwareDriverSpec、PangoBringupSpec历史异常仍单独保留；热重载下溢没有根治证明。专项GPU测试通过不等于全SoC/整机通过。首次连续Copy候选仅离线仿真，不烧录、不写Flash，也不把突发数量降幅写成FPS提升。
