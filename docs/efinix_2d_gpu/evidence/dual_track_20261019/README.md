# 双线首轮：Key裁剪与板键缩放验证（2026-10-19）

本轮不改CPU基础栅格算法、100MHz、游戏/挑战的精灵尺寸和数量；官方Sapphire、DDR、HDMI和以太网保留。只用JTAG/RAM，不写Flash，不覆盖release。新硬件开关默认关闭。设计/接口见[双线设计](../../gpu_dual_track_20261018.md)。

## 本轮实现

- `--key-row-trim`依赖原Key预取：整行确定非透明范围后才发AW，全透明行不写，首尾零WSTRB字不传输，内部透明孔仍保留零掩码。所有处理像素仍计数，不以少计透明像素夸大吞吐。
- `--transform-blit`：opcode7、STATUS bit17、源尺寸寄存器0x00a8；独立源/输出宽高、最近邻残差DDA、水平/垂直镜像、可选Color Key。旧opcode0..6及16B实例描述符不变。旧BIT缺能力时C帮助函数拒绝提交，不访问新寄存器。
- 独立板键演示：KEY1按住缩小、KEY2按住放大，释放保持、双键暂停；起始1x，0.25..4x，对16×16飞机给出4..64像素目标。控制器每秒0.5x，20ms消抖，单次轮询停顿最多累计250ms；GPU绘制与PRESENT期间不轮询，因此不承诺极长阻塞下的精确墙钟速度。屏幕显示实际整数像素比例。
- 按键独立输入P14/GPIOR22、N14/GPIOR21，3.3V上拉、低有效，2FF同步后送Sapphire GPIO低2位。新指南与配套官方按键Demo一致，旧原理图按键/LED标签存在冲突，原LED输出/OE引脚保留。

## 普通512同BIN实测：裁剪不推荐启用

每组30预热＋3600采样帧，原场景、原调度/封存/HUD选项，无计时中额外诊断。PC只供101/102/103资源，三组状态CRC均`c0ecf1df`。

| 位流顺序 | FPS | work均值/最大μs | 最大呈现间隔μs | 超预算/迟到/新下溢/错误 |
|---|---:|---:|---:|---|
| 旧Scanout A | 60.1 | 9618 / 12960 | 16639 | 0 / 0 / 0 / 0 |
| Key裁剪＋Transform联合候选 | 60.1 | 9784 / 12367 | 16639 | 0 / 0 / 0 / 0 |
| 旧Scanout返回 A | 60.1 | 9618 / 12388 | 16639 | 0 / 0 / 0 / 0 |
| 只开Transform，裁剪关 | 60.1 | 9618 / 12743 | 16639 | 0 / 0 / 0 / 0 |

联合候选工作均值反而增加166μs（约1.73%），不宣称性能收益，Key裁剪保持实验关闭。两侧基线均值重现，随后关闭裁剪、保留Transform的独立候选均值亦回到9618μs，支持裁剪在当前素材负载下无收益；最大值只描述本次窗口，不拿较小单次最大值抵消平均退化。不同候选仍包含映射/布局差异，不把每个周期差异过度归因。实际可见499..504、Alpha66..67，包含死亡等待/重开；不是恒定512活动精灵资格，也不是新的极限Sprite成绩。功能演示与性能路径分离。

同一探针BIN：`generated/verification/v3/rows-stripes-20261016/fw-probe512/gpu_demo.bin`，SHA256 `dc82fae7902e1fd238a572db28e49b947535d75f876c892562b2d8c736504a0b`。采集`capture-game-probe.ps1 -LogicCopy 1 -SealWords 256 -HudDirect 1 -SerialPort COM9`，三份`ordinary512-{old-a,new,old-b}.log`均有身份检查与正常STOP。

## 资源、时序门槛

| 候选 | XLR / 60800 | RAM / 256 | DSP / 160 | core setup/hold ns | 是否允许加载 |
|---|---:|---:|---:|---|---|
| 原Scanout | 49346 | 176 | 33 | +0.541 / +0.026 | 历史合格基线 |
| 裁剪＋Transform | 51818 | 179 | 37 | +0.421 / +0.026 | 本轮16个报告关系全正，已测 |
| 仅裁剪 | 50243 | 176 | 33 | **−0.290** / +0.026 | 禁止加载，本轮未加载 |
| 只开Transform，裁剪关 | 51112 | 179 | 37 | +0.130 / +0.026 | 本轮16个报告关系全正，已测 |

联合候选全局最小setup为DDR FIFO的+0.067ns，最小hold为rxc的+0.010ns，不只检查core。仅裁剪的失败路径为既有InstanceStream模板RAM→范围乘加校验→命令高度CE，54级逻辑、末端扇出218；基线已有此范围链，不在新增透明裁剪的数据路径内。联合候选同一前端有不同映射深度/末端，不能简单说裁剪修好了/破坏了时序。Efinity流程返回0也不能替代检查最终时序报告。

联合BIT：`D:/efinity_builds/dual_track_20261019_r1/outflow/efinix_2d_gpu.bit`，SHA256 `88f7629c1a1b476740ce50382586cc024643e7ddd0c5bfdd87629c8f1cd14682`。旧Scanout BIT SHA256 `705f1642db8dffc3bfd1ab5cb208e7645351eba141ec7f652d5ecc1ae43beb09`。仅裁剪BIT虽生成，仍不合格。

最终功能BIT：`D:/efinity_builds/transform_blit_20261019_r1/outflow/efinix_2d_gpu.bit`，SHA256 `4b280223c23bbc5bf2638b63e79e8ca52c5866dae278d33964ff2b4428a3df36`。它的全局最小setup为core的+0.130ns、最小hold为rxc的+0.020ns。只开Transform不代表超频或新FPS资格。

## 真正读回的像素验证

- 联合候选Transform：40个4×4源图用例，输出边长4/8/2/5/3，四种镜像组合、Key开/关，带stride、半字相位、前后哨兵。所有DDR像素、处理像素数、实际有效写字节通过，最终`TRANSFORM_BOARD_STOP,result=0,hardware=0`。
- 最终只开Transform候选亦运行相同40例、同一BIN，再次全部通过；这是不同硬件配置的验证，不是重复测同一未变候选。
- C32布局修正后，最终Transform BIN亦在同一合格功能BIT上通过40例，最终Zoom首帧绘制/PRESENT完成日志通过；只有固件变化，没有重新综合硬件。
- 联合候选缓存Key：8×4混合/全透明/全不透明，目的半字两相位共6例；加载64B缓存后故意修改DDR源，仍逐字匹配缓存原图及padding/四个哨兵。每例处理32像素、Cache64B、DDR读取0，写字节20/0/64，最终`KEY_TRIM_BOARD_STOP,result=0,hardware=0`。
- 最初离屏Transform测试将启动前HDMI缺数据计数当失败，首例像素和写量实际完全正确。停住CPU、无PRESENT时两次硬件快照下溢从`0x0045bcd2`增至`0x0045de02`，LAST_DONE=1/ERROR=0，结合显示模块`scaled_active && !line_valid`证明来源。修正仅限离屏测试：显式打印`under_offscreen`，不用于判定离屏栅格错误；正式显示/资格的零新增下溢规则未放宽，失败首证保留。
- 仿真直接AXI统计：相同8×4混合图原AW/W/B=4/18/4，裁剪3/5/3；处理像素均32。它是局部数据拍证据，不是游戏提速。

最终离屏Transform BIN为`generated/verification/v3/dual-track-20261018/board-transform-r2/test.bin`，SHA256 `999c53353a280ff86c91920260e28c36567984cf3e10acb1e765c4f671373e70`。上述缺数据诊断使用官方OpenOCD配置（debug_ti.cfg在初始化时halt），确切命令为：

```text
openocd.exe -f ftdi_ti.cfg -f debug_ti.cfg -c "init; mww 0xf810004c 1; echo [mdw 0xf8100078 2]; sleep 100; mww 0xf810004c 1; echo [mdw 0xf8100078 2]; echo [mdw 0xf8100034 2]; shutdown"
```

## 验证范围与复现

父集成曾观察2个预期RED（拒绝opcode7、缺能力位），接线后3/3 GREEN；Transform引擎3项＋校验2项合计5/5，校验器随后单独2/2，旧前端8/8及Key定向测试通过。完整GPU回归运行一次，29套件114项，113通过、1项旧`AssetDmaRegsSpec`把全寄存器最大地址锁定0xa4，与新增可选0xa8冲突。修正测试为“原地址最大值仍0xa4、新源尺寸为0xa8、无重复且未侵入0x100资产窗口”，不改硬件，随后仅定向复测该套件4/4通过，未重复全套。默认关闭对0xa8仍报错的行为另由`TransformApbSpec`通过。原始失败完整保留，不伪造一次全套GREEN日志。

软件首轮及C32布局修正后的最终回归均通过28套C、30项网关/协议检查（含本机真实UDP/HTTP）、3项独立心跳、采集身份/清理保护。C32另通过Transform与旧驱动/帧列表/12,000帧实例/3,000帧提交缓存的ASan/UBSan检查。代码集成提交`6d3a684`，C兼容修正`79c6d3b`。

### C布局与完整游戏固件兼容

补做完整游戏固件链接时发现最初C命令32→36字节导致HUD/场景数组膨胀，官方124KiB程序RAM超出1648B。最终保留原32字节及所有旧偏移：Transform源宽/高复用该操作不用的color/tag存储，实际提交tag仍由驱动独立分配、ColorKey低半字保持0。Chisel命令及APB接口不变，没有通过缩栈、减容量或删除CPU/网络功能规避。

同配置完整游戏重新链接通过，保留4KiB栈0x1dd20..0x1ed20，RAM末端0x20000尚余4832B。这是**链接余量，不是运行栈水位**。新普通固件BIN SHA256 `61ff901df312910fda5aff1c0d6cfea6ce133df8c462c536d029a073c9648bb3`，实板101/102/103资源完整加载、四档真实START/MENU ACK＋新快照通过，最后释放控制。此次短控不替代新普通BIN的长帧率资格；上方四组3600性能数据始终使用保存的旧`dc82...`探针BIN。

候选生成：`test-v3-gpu.ps1 -Generate -KeyPrefetch -ScanoutWordPipeline -TransformBlit`，不要加`-KeyRowTrim`作为默认性能路径；可选开关不改正式生成物。构建`build-board-hud-dma-test.ps1 -Test zoom|transform|key-trim -OutDirectory <全新目录>`，输出BIN加载0x1000。Transform/Key离屏用例不启动PRESENT；Zoom必须从新加载/复位的候选BIT开始，首帧完整后才PRESENT。不要把功能BIN当游戏/性能BIN。

本轮原始日志位于`generated/verification/v3/dual-track-20261018/`，可移植证据见[evidence.zip](evidence.zip)。包内保留原始失败、定向复测、四组性能数据、布局修正前/后身份、三组生成RTL和最终时序报告；BIT本体不入库，只存确切SHA256与可重建源码。`input-identities.csv`是早期身份，`input-identities-final.csv`记录C32最终身份；旧源码哈希保存在`source-identities-pre-c-layout-fix.csv`，最终源码哈希在`source-identities.csv`。

证据ZIP SHA256：`9d181fc5288b4ab366b37b9248ce24f5580e1643f46b92539e490011dd2e72f9`，841303字节、306项；已核对关键日志存在及包内三份最终BIN的哈希。全部烧录进程已退出，串口采集已关闭，仅本地提交，未推送。

当前板上运行最终功能BIT＋C32独立Zoom BIN `board-zoom-layout32/test.bin`（SHA256 `7699dae71aba3d12514af96c40995fdb0670cab9d565310d6b1d613e9b0644a6`），首帧日志`ZOOM_FRAME,scale_q8=256,side=16,keys=0`。最终C32像素oracle为`board-transform-layout32/test.bin`，SHA256 `f71d4d183ecf24aa16d0795d6d56c13df157bcb458543382b956e471c0ba00bf`。保留独立演示，**不是正常游戏MENU**，此独立固件不处理网页游戏控制，不能把网页遥测过期当成网口硬件回退。

### HDMI与物理按键人工确认（2026-10-19）

用户在上述演示运行时回复：“正常，方向与松开保持均正确”。据此记录HDMI画面与按键反应正常，KEY2放大、KEY1缩小、松开保持通过人工确认。未据此宣称精确0.5x/秒速度、上下限或双键暂停已单独完成人工测量。这条确认在证据ZIP封存后补记于本文；ZIP及上述哈希保持不变，包内不包含此次人工回复。本次仅更新记录，没有重新烧录或重复仿真。

边界：历史SoC两项异常、实际栈水位/长时间耐久未补验。工作进程曾主动停止旧完整HDMI子系统长仿真（此前六项小RTL仿真通过），不能称RTL/SoC全部套件通过。提交缓存的Transform→旧命令混合序列本轮未专门测，代码审查未发现转换错误；默认路径及旧命令缓存回归通过，缓存仍默认关闭。

## 下一步

透明裁剪不适合作为当前小而较实心Sprite的默认路径；后续按实际W空拍、Alpha读改写与B等待占比选热点。优先把既有实例前端的宽范围校验分阶段，保持完整64位边界检查后再评估资源与时序；不通过删检查提升主频。Alpha连续流水、双在途写、截图/压缩网页预览仍属后续，不宣称已完成两线所有功能。
