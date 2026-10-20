# 四块列表容量与786/1024游戏档位（2026-10-20）

实现提交`10634c518556eb35f9a0f10635d189b9d209c7ec`，前序基线`3900bb4`。本轮扩容，不把增加容量宣传成硬件渲染提速；只JTAG/RAM，不改Flash、release、CPU基础栅格算法或100MHz。

## 实现结果

- 原64/128/256/512四档保留，新增的是**786、1024**，不是768。HDMI为两列三行卡片，网页新增两个档位；键盘、死亡回菜单及一键重选沿用原逻辑。
- DDR列表由2048项/32KiB扩到4096项/64KiB，性能挑战软件上限由1819扩到**3640个活动Sprite＋455个额外Alpha光晕＋1条背景=4096项**。这不是3640个Sprite稳定60FPS的成绩。
- 每次仍只预取1024项，跨块先执行退休再继续，片上预取RAM不翻倍。完整span在第一次START前检查，保留错误锁定、tag回绕和失败后不重放。
- 默认关闭`enableExtendedListArena` / `--extended-list-arena`，要求frame-lists。GPU STATUS bit20表示新容量；新C驱动遇到旧BIT只使用2048项，挑战上限仍1819。旧BIN可在新BIT使用前两块。
- 网络保持32/128字节/version1，status bit14表示六档能力，mask为`0x007f7fff`、bit15仍保留。网关/网页限制旧固件5/6；合法但不支持的档位由旧512运行时非致命拒绝。真实网口硬件接收层也改为允许1..6，7仍拒绝。

## DDR和链接边界

|用途|范围（末端不含）|
|---|---|
|四块列表，每块16KiB|`0x02d20000..0x02d30000`|
|性能挑战私有状态|从`0x02d30000`，静态约束末端不超过`0x02d40000`|
|既有实验条带scene/bins|保留原区域，bins末端`0x02d70000`|
|1024配置HUD命令临时区|从`0x02d80000`，静态约束末端不超过`0x02e00000`|
|实验条带表面|仍从`0x02e00000`开始，本候选不开条带|

1024配置首次链接BSS超出24176字节，未上板。仅把该配置的HUD命令临时区搬到DDR，CPU场景命令缓存仍在片上BSS；4KiB栈不缩。最终正常固件链接`_end=0x1ce60`、`_sp=0x1de60`，到128KiB末端剩8608字节。这是静态链接余量，**没有实测栈水位**。中间r2临时地址与实验条带别名，在离线检查中已纠正，未加载。

## 验证与实际结果

受影响Chisel三套五项通过：旧/新arena、第三/第四块、1024项上限、16KiB拆分、末端越界、Top bit20，以及原Reader/Batch。当前软件完整回归28个C入口、31项Python、3项独立心跳、Node及采集器保护通过；1024真实32字节RX→运行时→ACK另行通过。实际浏览器六按钮、786/1024映射、键盘、重选、失焦释放、旧能力隔离、过期状态和移动布局通过。模拟网页测试不提供板卡FPS。

硬件网口遗漏曾使5/6在C之前被丢弃：新增真实router/CRC/CDC/APB测试先得到`valid six-tier START 5 lost`，再将硬件边界从4改6，保留7及其他非法字段拒绝。六套网络RTL和实际APB/MAC子系统回归通过。初次源码只读审查未发现该问题，后由主任务补查；不把审查结论当作完整路径证明。

旧Key流水BIT＋本轮oracle实板2048/2047项通过；中间r1新BIT＋同oracle4096/4095项通过。四块末端使用不同Alpha值，实际最终像素、哨兵、tag回绕均正确，防止把重复前两块误判成扩容。oracle不PRESENT，启动下溢不能冒充显示资格。

最终r2 BIT的4096/4095项像素、哨兵、tag回绕也已通过。普通游戏终止探针各30帧预热＋3600采样，网络101/102/103完整加载、重试0：

|请求档位|FPS|work均值/最大ms|超预算/迟到帧|新增下溢/错误|实际可见 / Alpha|
|---|---:|---:|---:|---:|---|
|786|60.0|11.713 / 17.299|1 / 1|0 / 0|771..778 / 101..102|
|1024|55.3|14.370 / 21.793|307 / 308|0 / 0|1006..1016 / 130..131|

两组wall最大均33.277ms，状态封存CRC分别`b7d1fd1a`、`a7bd652f`；这不是全帧像素CRC。**两个普通新档均不能称稳定60FPS。**不通过重跑挑选零迟到结果，也不拿中间r1零迟到替代最终r2的失败。容量正确不等于帧预算合格，独立性能挑战也不能代替普通游戏结果。

最终r2 BIT＋旧512正常BIN四档真实START/MENU通过；随后最终r2＋normal-r4六档真实START/MENU ACK与新快照全部通过，5/6实际请求数量分别786/1024，未依赖软件模拟。挑战租约切换、新session和R清分保护通过。

### 自动挑战：2007未保留资格

搜索已突破原1819的软件容量，2007个全活动Sprite＋251个额外Alpha光晕完成3600帧采样后很快变为stage6/best0，采集器正确报不合格。**本轮没有新增有效60FPS极限成绩，不能把2007或3640写成通过，也不把旧BIN的1819直接迁移到本版。**

结束后只读回PC私有DDR统计120字节（随后CPU继续MENU，未改数据）确认：maximum3640、target2007、frames3600、work_misses/cadence_misses/underflows/errors全0，visible_min/max2007、Alpha_min/max251，work累计5613960761ticks、wall累计5989915967ticks，最大work1659867ticks、wall1664199ticks。按100MHz计，采样期60.101FPS、最大work16.59867ms，但最终stage6/best0。

结合`pc_record`状态路径，3600帧统计合格后被持续检查作废，而不是软件又碰到1819容量。导致作废的后续单帧work/wall没有留在采样统计，不能仅凭这份读回数据宣称已定位到某个GPU阶段或HUD。缺少失败后的串口总结：采集器报失败后关闭串口早于租约失效后的汇总输出，故额外保存原始HTTP阶段记录和DDR读回；没有虚构PERF_RESULT或有利的5秒保持成绩。后续应优先补捉“资格完成后的帧预算”，不通过放松持续检查来保留成绩。

已自动返回正常六档MENU、释放控制权；末态遥测新鲜、新增下溢/错误0。JTAG和串口采集已结束。HDMI人工目视、手动飞行/死亡/CPU比较未新增实板验收，不冒称通过。

### 中间产物与排除组

- `normal-r1`链接失败；`normal-r2`HUD临时地址冲突；均未加载。
- `normal-r3`及第一组探针误用了历史192.168.0.*构建参数，不匹配当前网络，不能作为最终固件。首轮786因此用备用素材，3600帧60.0FPS，work最大16.864ms、1帧超预算/迟到；保留失败记录，不删除。
- 已核对实际网卡192.168.1.2、网口1Gbps、资源服务8080、网关8090；正确候选使用板端`0xc0a80103`、PC端`0xc0a80102`。纠正构建参数后资源101/102/103完整CRC加载成功、重试0；不是靠延长超时或削弱CRC。
- 中间r1 BIT＋正确IP的786探针3600帧60.1FPS，work平均11.712ms/最大16.545ms、wall最大16.641ms，超预算/迟到/新增下溢/错误全0，可见771..778、Alpha101..102。仅证明该中间组合，最终r2需独立验证。

## 构建和复现

RTL生成在原Key流水配置上再加`-ExtendedListArena`。生成目录`generated/verification/v3/capacity-six-levels-20261020/rtl-5971eb20f49b410ebb3856ac32c3c341`，60个单模块HDL；`.vh`仅为共享定义。最终候选工程`D:/efinity_builds/capacity_six_levels_20261020_r2/`；r1仅为中间身份，不作最终部署。

```powershell
scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -FrameList -PerformanceChallenge -HudDirect -ObjectCapacity 1024 -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory <新目录>
scripts/test-game-menu-board.ps1 -Bin <正常BIN> -Bit <最终BIT> -LoadBit -LevelCount 6 -PerformanceChallenge -ExpectedBuild 0x20261015 -SerialPort COM9 -Python C:/Users/fortiutde/AppData/Local/Programs/Python/Python39/python.exe -OutDirectory <新采集目录>
```

普通786/1024终止探针使用同配置但不加`-PerformanceChallenge`，改为`-StartCount <786或1024> -ProbeFrames 3600`。以`capture-game-probe.ps1 -LogicCopy 1 -SealWords 256 -HudDirect 1`采集，每次完整JTAG重载BIT后再载BIN，避免旧显示相位状态。所有正式/中间BIN有不同SHA，build ID相同不能单独辨认；按实际BIN哈希、新HELLO/session和原始UART判断。

最终正常BIN：`generated/verification/v3/capacity-six-levels-20261020/normal-r4/gpu_demo.bin`，SHA256`33aac5fa90d290c3820d9e3c537fe7c8c51785e9409c668410744bf27d42311e`。
786探针：`probe786-r2/gpu_demo.bin`，SHA256`dd8b6833385cd972dbcaf391ada4462538e07f6587a1174c93b5156a0bad436d`。
1024探针：`probe1024-r2/gpu_demo.bin`，SHA256`bd5489d8a8e39fca40dbbdeed357be035b619204b44a4422fa96bd95d39d77b7`。

最终r2 BIT：`D:/efinity_builds/capacity_six_levels_20261020_r2/outflow/efinix_2d_gpu.bit`，SHA256`a476bfaae3c7f1d384ddcd9a7ce78c24498f0e64493be40ad66874989c1cc945`。编译map/interface/pnr/pgm通过，无错误；最终16项setup/hold全部为正，100MHz核心setup+0.093ns/hold+0.026ns，全局最小setup+0.093ns/hold+0.007ns。保留既有警告，不把微小正裕量宣传为超频余量。
资源XLR52738/60800、RAM179/256、DSP37/160，预取RAM未增加；与前序Key流水候选XLR52301相比仍有逻辑增量，不能称“完全零资源开销”。

原始证据目录`generated/verification/v3/capacity-six-levels-20261020/`。本轮不重复已通过且未改变的35套136项旧GPU全量回归，不将其计为本轮新增测试；历史SoC异常、30分钟耐久、人工HDMI目视和栈水位未补称通过。CPU慢速栅格绘图期间网口处理仍可能延后，未擅自改变CPU比较路径；运行时收到MENU仍能中止Replay。

[本轮证据封存](evidence.zip)，SHA256`06b415b79a0a84b8dbf700ba418aafe76291c8b0d50f94a0123011923bbc3fc5`。211项条目，含最终BIT、三个安全BIN/ELF、列表oracle、生成RTL、源码快照、正负日志、原始HTTP和失败DDR统计；最终BIT哈希已在包内复核。未打包不安全/错误网段的中间固件，排除组只保留原始日志，防止误烧。包内README/计划为封包时快照，不含封包后才得到的本段ZIP哈希。未改任何既有证据ZIP，未推送main或替换release/Flash。
