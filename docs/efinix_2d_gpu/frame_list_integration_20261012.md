# 整帧列表前端整机接入与实板取舍（2026-10-12）

本轮完成列表前端整机接入、软件驱动、资格检查、实板净收益验收及恢复正常菜单。保留候选，不把它称为稳定512@60或V3封版；新功能仍默认关闭，正式RTL/release不替换，没有推送main，没有写Flash。

## 设计与实际改变

Sapphire直接把GPU场景写成16B描述符到私有DDR A/B bank；沿用官方同步后，一次门铃发布地址/数量/起始tag/epoch。GPU完整AXI预取，再由原InstanceStream模板展开，经原命令队列和Copy/Key/Alpha像素后端绘制。批次只有在描述符、命令、渲染及缓存真正排空后才完成，之后才能HUD/PRESENT。不是Reader最后一拍读完就呈现。

- 复用原AXI读引擎（ID6、最多256拍、4KiB分段）、Render读端口和DDR QoS；预取期间后端必须已空，预取后端口回归原像素读取。写端口、HDMI和资源DMA不变。
- 保留之前CopyAhead：背景Copy与CPU构建重叠；列表跳过第一条已提交背景，不双Copy。
- 避免每Sprite软件完整命令展开和逐字段APB提交/信用轮询；旧APB路径仍可使用。
- 全列表运输错误拒绝整批；中途描述符错误只保留已完成前缀，不自动重放Alpha、不PRESENT。软件失败后锁住owner，必须协调复位，不能局部清AXI状态硬重试。
- 统计包含列表前端忙、读字节和停顿，不能把预取算免费；旧计数器地址不变。

沿用Alex Forencich [verilog-axi](https://github.com/alexforencich/verilog-axi)的描述符/突发/缓冲思路，但没有声称移植其CDMA。工程特色是针对现有APB/DDR/资源限制，复用读端口、整批验证隔离、复用模板展开及同版旧新对照，而非另开通用DMA或移除Alpha/Key。CPU基础绘图算法/配置没有优化，官方核、100MHz和960×540 RGB565不变；PC仍仅资源、控制及遥测。

## 软件与硬件契约

| 项目 | 契约 |
|---|---|
| bank | `02d20000..02d24000`、`02d24000..02d28000`，每bank16KiB |
| 请求 | 16B对齐，1..1024描述符，必须完整落在单bank；当前固件仍512对象容量 |
| 能力探测 | 先读旧STATUS bit15；无能力不读0500/0400新窗口 |
| 门铃 | 0500 ID=`464c5431`；0504 active/done/error/fetching；0508 START=1、CLEAR=4 |
| 参数 | 050c地址、0510数量、0514起始tag、0518 epoch；活动期间拒绝修改 |
| 完成 | 051c完成epoch、0520末issued tag、0524 issued数量、0528预取字节；完成后还核对旧LAST_DONE |
| 所有权 | 单CPU owner，列表/模板/素材在完成前不变；旧SUBMIT和管理写不能混入 |
| tags | 16bit回绕，软件uint8 outstanding不装整批数量；返回成功后原驱动提交统计继续有效 |
| 发布 | 原`gpu_platform_sync`及官方custom cache同步，不使用不存在的CSR810 |

正常构建用显式`-FrameList`；终止探针另由私有DDR `02d10004=0/1`切旧/新，`02d10000=1`固定CopyAhead。两个档位分别固定同BIN，JTAG加载前设置，不靠未初始化DDR。正常固件没有终止探针开关，启动MENU并使用检测到的列表前端。

候选不再在缺少网口管理核心时落入未用AUTO-R7备用main，节省片内RAM；正常互动CPU比较仍是原路径。默认关闭BIN与原合格CopyAhead/CRC正常BIN逐字节一致。只有这份候选失去“管理硬件缺失时跑AUTO-R7”的备用功能。

## 实测：同BIT/同BIN旧→新→旧

每组30帧预热＋600帧采样，零键盘输入。实际可见数量而非请求数量也记录；Alpha开启。预热和采样逐帧健康检查，所有组新增下溢/错误0。性能日志可能跨UART读取块，成绩取完整原始UART，不取采集器分块显示。

| 请求档 | 路径 | FPS | 工作均值ms | 最大ms | 超预算/迟到 | 可见范围 | Alpha范围 |
|---|---|---:|---:|---:|---:|---|---|
| 256 | 旧1 | 60.1 | 12.327 | 16.382 | 0/0 | 240..248 | 34..35 |
| 256 | 列表 | 60.1 | 11.686 | 15.796 | 0/0 | 240..248 | 34..35 |
| 256 | 旧2 | 60.0 | 12.328 | 16.726 | 1/1 | 240..248 | 34..35 |
| 512 | 旧1 | 30.0 | 19.423 | 27.407 | 600/600 | 496..504 | 66..67 |
| 512 | 列表1 | 59.6 | 13.989 | 21.181 | 5/5 | 497..504 | 66..67 |
| 512 | 旧2 | 30.0 | 19.421 | 27.351 | 600/600 | 496..504 | 66..67 |
| 512 | 列表重复 | 59.6 | 13.987 | 20.975 | 5/5 | 497..504 | 66..67 |

工作时间是PRESENT前完整帧成本；FPS来自完整wall，包含PRESENT等待，日志成本另外记录。游戏按实际时间更新，因此慢路径走过更多simulation tick，不能说所有样本处于逐tick相同场景。600采样内可见/Alpha范围相近；逐字段/顺序/完整像素等价由独立主机测试补证，不拿范围相近代替逐像素证明。

### 真正旧生产基线，避免夸大

候选引入额外GPU分支/代码布局、硬件APB响应等，会改变旧路径性能；“同BIN旧新旧”证明同版路径收益，却不能把旧30FPS当原合格生产水平。额外实测如下：

| 硬件/固件 | 512 FPS | 工作均值ms | 迟到/600 |
|---|---:|---:|---:|
| 原合格BIT＋新候选BIN、列表关（cap缺失） | 30.0 | 19.377 | 600 |
| 原合格BIT＋原合格CRC/CopyAhead探针BIN | 42.5 | 15.897 | 247 |
| 新BIT＋新候选BIN、列表开，两次 | 59.6 | 13.989 / 13.987 | 5 / 5 |

相对真正旧基线，帧率约提高40.2%，工作均值降低约12.0%；不是纯单门铃因果实验，也不是翻倍宣传。没有减少对象档位、Alpha或分辨率。两次新512仍有5帧迟到，最大约21ms，**不合格“稳定512@60”**。256新组600帧通过，但不能保证30分钟耐久；旧256反向组出现1帧迟到也原样保留。

## 资格与兼容性

- 完整GPU17套件82/82通过，0失败/中止/忽略；8个damage套件18,000帧。没有再跑同一份未变化RTL的第二轮完整仿真。
- 新真实Top：Copy→透明Key→Alpha正确像素`554483e0`，跨4KiB、延迟B、tag回绕、epoch、旧SUBMIT锁、尾RRESP错误零写、坏中间描述符不重放、非法bank零AR；前端计数测试经历cycles=0和read16/64两次真实RED后通过。
- C真实驱动及原实例检查通过：9600当前游戏字段/顺序/统计＋3完整像素样本、12000R7；18C＋23实际UDP/HTTP。旧cap安全、数量585不截断、同步先于START、timeout/错误拒绝重放、tag/epoch/issued核对覆盖。
- 新工程map/interface/pnr/pgm通过。XLR48021/60800（78.98%）、RAM172/256、DSP28/160；100MHz核心setup/hold为+0.339/+0.026ns；16个关系均非负，最小setup/hold+0.158/+0.006ns。
- 1488条网口CDC数据、2请求、2确认路径最大延迟1.113/0.729/0.907ns，均低于8ns；核对映射FF和工具实际约束。既有JTAG/未用端口约束警告不当作全部物理复位或MTBF资格。
- 官方软件RAM与4KiB预留栈不变；正常/512探针`_sp=1c300/1c5d0`，额外余15616/14896B。早期探针溢出528B的失败日志保留、未上板；余量不是实测栈峰值。
- 实板CPU写列表、源像素及guard，两轮同bank覆盖后读回`554483e0`、`5544040f`，guard保持、tag1/4、各预取48B；证明真实发布/像素操作，非仅CRC或寄存器反馈。
- 正常MENU固件重新加载，真实四档START/MENU ACK＋新快照通过；256实际RIGHT dx=360、UP dy=-240及租约失效释放通过。结束后fresh真实MENU、请求0、under/error0、controller=null，没有烧录进程。

新候选完整HDMI目视、自然死亡/512全输入阶段、完整CPU慢回放、实体断网重连、运行栈水位及30分钟耐久没有在本轮全部重验，不能以ACK替代目视或以短窗替代耐久。历史两项SoC固件异常和CPU比较中一键取消限制仍保留。

## 下一热点和取舍

正常四档检查的短512窗口，有效遥测build4.103..4.112ms、GPU busy12.764..12.821ms、PRESENT前14.521..14.639ms。busy现在包含前端、与CopyAhead和build重叠，不能相加；scene字段也不是可跨路径直接比较的全部GPU成本。短控制窗口约58FPS含开始过渡与网口轮询，不能拿终止探针59.6代替所有互动场景。

此次收益足够保留显式候选；下一轮重点抓5个最坏帧的逻辑/封存/HUD/网口与GPU执行时间，再决定削尖峰还是分块合成。不要把21ms直接归因于某一个模块，也不要靠去掉Alpha、降低Sprite或只改FPS显示达标。

独立审查Critical0/Important0。暂缓两项次要项：列表caller/driver重复官方cache同步；busy-START/模板与缓存并发写/末描述符错误/旧outstanding等待的直测补充。已有保护经审查，但上述具体输入不能冒称已被当前测试直接覆盖。[审查摘要](evidence/frame_list_integration_20261012/final-review.md)、[全部决策和阶段记录](evidence/frame_list_integration_20261012/progress.md)。

## 复现与恢复

```powershell
wsl.exe bash scripts/test-frame-list-driver.sh
wsl.exe bash scripts/test-v3-instances.sh
powershell -NoProfile -File scripts/test-v3-gpu.ps1
powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble
powershell -NoProfile -File scripts/build-board-hud-dma-test.ps1 -Test frame-list -OutDirectory generated/verification/v3/frame-list-oracle-fresh
powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -ReplayCrcNibble -FrameList -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/verification/v3/frame-list-normal-fresh
```

RTL生成参数`--frame-lists --legacy-copy --target-dir <独立目录> --split-verilog`，沿用候选板工程构建脚本的`-GpuRtlDirectory`。不改正式source list。测试模块各独立文件。诊断构建器旧instances重复添加`gpu_instances.c`已通过实际RED链接错误→去重复源→GREEN修复；不改生产算法。

完整身份见[identities.json](evidence/frame_list_integration_20261012/identities.json)：新BIT `D:/efinity_builds/frame_list_20261012_r1/outflow/efinix_2d_gpu.bit`，SHA256 `de8487d790dbac78e901816ed4dd46fd7cfb987b1b5e71724ff03d2aa072efea`；正常BIN `generated/verification/v3/frame-list-integration/normal-r2/gpu_demo.bin`。未将巨大的BIT/BIN目录提交仓库。

回退需成对JTAG加载原合格BIT `D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit`和default-off正常BIN（身份SHA=`6f19a9a447d217ffee2bef12e99baabfdd2eae4c48dab34fc6db1b7c9d332655`），确认新MENU快照；不写Flash，不能把terminal探针当正常游戏。当前已保留新正常候选，没有留在终止探针。

原始证据[目录](evidence/frame_list_integration_20261012)包括首失败、软件/RTL日志、九组UART、JTAG日志、真实菜单/控制、打包最终routed报告和身份。`sha256.csv`覆盖原始字节，Git禁止换行转换；归档`capture-board.ps1`为本次固定COM9/IP台架脚本，不是自动选择任意板卡的通用工具。

```powershell
powershell -NoProfile -File docs/efinix_2d_gpu/evidence/frame_list_integration_20261012/verify-evidence.ps1
```

该命令验证归档哈希、82GPU结果、像素oracle、9组600帧健康/净收益及真实菜单输入证据，不再次烧录，也不将历史SoC异常或未做的耐久补成通过。
