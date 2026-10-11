# 回放CRC尖峰优化：第一阶段交付

代码基点`9ec513f`。用户批准“完整校验尖峰 → 整帧命令前端 → 必要时片内分块合成”，并免除中间审批。本次只完成CRC阶段，不宣称架构前端、512@60或V3封版完成。

## 改了什么

`sw/efinix_gpu/src/replay_input.c`的共用`crc_word`增加64B、16项的反射CRC小表，每个32位逻辑字执行8次半字节更新，替代4×8次逐位更新。参考[作者的half-byte方法说明](https://create.stephan-brumme.com/crc32/)，表由原多项式`0xedb88320`推导，不增加库。`REPLAY_CRC_NIBBLE`默认0，1为候选；除内部字更新算法外，字段顺序、符号扩展、记录结构、公开API、完整600tick/epoch/seed检查、重新校验和篡改拒绝均不改。未使用增量CRC或省略校验。

官方Sapphire、CPU绘图算法和配置、GPU/SoC100MHz、现有合格RTL、960×540 RGB565、Key/Alpha、网口和游戏均不改。CRC是回放维护，不是CPU像素渲染优化，不能把探针成本当CPU/GPU游戏帧率。只重载JTAG固件，未加载新BIT、未写Flash、未替换release。

## 等价和构建检查

- 改动前17项C＋23项真实UDP/HTTP通过。新增测试包含真实生产`replay_input.c`，对照独立逐位算法和独立字段序列，覆盖固定初值/字、10,000组确定性随机字、负坐标/速度、600输入、完整CRC、恢复状态及末对象/末输入篡改。另测1024容量等价，不等于1024完整固件可上板。
- TDD成本RED：未优化生产路径与参考分别8330/8383主机ticks，无2倍节约，断言失败；改后3098/8263通过。主机时间仅是算法检查，且`REPLAY_CRC_COST_CHECK`显式开启才执行，避免主机调度影响普通功能回归。最终候选18项C＋23项实际UDP/HTTP通过。
- `-ReplayCrcNibble`缺Interactive、缺独立输出、与PublishRelease组合均在构建启动前拒绝。正常/终止候选成功链接；工具链原有LOAD段RWX告警保留，没有借此修改官方BSP。
- 正常候选`text=43152,data=0,bss=78956`，加4096B预留后126204/126976B，余772B。600帧终止探针`43912+0+78956+4096=126964B`，**仅余12B**。这是静态预算，不是实测栈水位，后续不能往该探针继续塞统计代码。

## 同BIN软核算法测量

独立RV32探针一个BIN内运行两种算法，私有DDR地址`0x02e00000/0x02e10000/0x02e20000`，不访问显存/GPU。实际CRC相等，末输入篡改拒绝，STOP明确PASS。

| 对象数 | 规范逐位参考（µs，3次） | 实际小表seal（µs） | 实际小表begin含复制（µs） |
| --- | --- | --- | --- |
| 256 | 12082 / 12100 / 12100 | 3547 / 3549 / 3547 | 3724 / 3722 / 3723 |
| 512 | 21386 / 21385 / 21386 | 6258 / 6260 / 6259 | 6456 / 6454 / 6453 |

10,000字连续更新：逐位参考44699µs，小表12400µs，成本减少约72.3%，相同CRC。**规范参考序列不是旧生产seal的完全相同汇编**，不能把21.39→6.26ms称为旧seal精确A/B；begin还含memcpy。私有DDR位置/布局与正常游戏不同，不推导其端到端FPS。

首次探针输出损坏并超时，根因为官方轻量`bsp_printf`不支持`%u`，会继续扫描后续格式符。检查实际vendor `print.h`后只把诊断格式改成`%d/%x`，未改BSP。失败原始日志保存为`algorithm-r1-failed.log`，不从它提取成绩；第二次清晰PASS。

## 真实512游戏：旧 → 新 → 旧

保持同一合格BIT、CopyAhead=1、seed7、相同网口IP及资源101/102/103；加载零重试，atlas3104像素。两种分别编译的终止固件，每组30帧预热＋600采样，跨600逻辑tick封存。三组无网页输入控制/心跳，`keys=0,age=-1`。实际可见496～504、Alpha66～67，不将请求512误写成每帧512全可见。

| 组别 | FPS | 工作均值µs | 最大工作µs | 最大墙钟µs | 超预算 / 迟到 | 采样新增下溢 / 错误 |
| --- | --- | --- | --- | --- | --- | --- |
| 旧A | 43.0 | 15882 | 39048 | 49916 | 237 / 237 | 0 / 0 |
| 小表 | 43.4 | 15875 | 24076 | 33278 | 230 / 230 | 0 / 0 |
| 旧B | 43.9 | 15851 | 39176 | 49915 | 219 / 219 | 0 / 0 |

结论：最大工作明显降低，与独立CRC收益相符；但未给每个最大帧打seal标签，不能精确归因全部最大值差异。平均FPS落在两个旧组之间，工作均值也无可信改善，**不声称平均提速，不保证512@60**。场景随实际逻辑时间推进，三组不是完全相同600状态，固件布局也不同；控制输入策略与前一轮CopyAhead心跳组不同，只在本轮三组内比较。采样下溢0不抹去日志中基线前启动累计下溢，未做30分钟耐久。

保留默认关闭的候选用于减轻尖峰，下一步不继续堆CRC表。普通帧开销仍需针对命令构建、提交/执行重叠和DDR访问处理。

## 身份和原始证据

完整SHA256见[文件身份清单](evidence/replay_crc_20261011/identities.json)；原始日志哈希见[证据清单](evidence/replay_crc_20261011/sha256.csv)。不把BIN/ELF或巨大的生成目录提交仓库。

| 用途 | BIN SHA256 |
| --- | --- |
| 正常候选 | `6f19a9a447d217ffee2bef12e99baabfdd2eae4c48dab34fc6db1b7c9d332655` |
| 新512终止候选 | `a7950317566bf89eb2c5cea40b87acee297b33ba0bdbcda75e42c877de422c78` |
| 旧512终止基线 | `6c218c99346f59a6b8b33184041eb16597268c49449431d3d242c3dcbbfaaf70` |
| 独立算法r2 | `32a688d2457558c1598d716f749d186270a6c286d812343aab899817e6b2e4c1` |
| 默认关闭的正常CopyAhead | `a03d805ad7236f0ab1da4b0c5732776067840b325a52203f9f8d94fec93e883c` |

默认关闭BIN与先前正常CopyAhead BIN哈希一致，逐字节回退成立。BIT为`D:/efinity_builds/game_menu_20261008_r1/outflow/efinix_2d_gpu.bit`，SHA256 `202d2b40ba1b919394a2cc920055a810e56c07fbd725fdb4185385124f894cf3`。

证据目录包含首失败/最终算法日志、三组完整游戏串口、真实菜单UART/HTTP/转换记录，以及前后完整软件套件输出。正常候选恢复后，四档64/128/256/512的真实START/MENU ACK＋同session新快照全部通过，最后MENU，控制权已释放。网页/资源服务保留运行；没有新目视确认，不冒称死亡全流程、CPU600tick慢比较或实体断网长测均验收。

## 复现与回退

在仓库根目录运行；实际串口本轮为COM9，不能盲用旧COM13。服务使用板卡192.168.1.3、PC192.168.1.2；改变IP需同时改变服务/固件。

```powershell
# 功能回归；额外测试用例始终覆盖小表，其他回放用例用候选开关。
powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble
# 正常候选（必须新输出；不覆盖release）
powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -ReplayCrcNibble -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/verification/v3/crc-new-run
# 独立算法，不是游戏成绩
powershell -NoProfile -File scripts/build-board-hud-dma-test.ps1 -Test replay-crc -OutDirectory generated/verification/v3/crc-probe-new-run
powershell -NoProfile -File scripts/measure-hud-glyphs-board.ps1 -Bin generated/verification/v3/crc-probe-new-run/test.bin -Log generated/verification/v3/crc-probe-new-run/board.log -SerialPort COM9 -StopPattern 'REPLAY_CRC_BOARD_STOP|REPLAY_CRC_BOARD_FAIL' -Seconds 20
```

采集工具碰到STOP/FAIL正则都会停止，**必须再检查输出为`REPLAY_CRC_BOARD_STOP,result=PASS`且没有FAIL**，不能仅凭工具退出0称通过。游戏候选在正常构建参数上加`-StartCount 512 -ProbeFrames 600`，使用独立输出，并在JTAG resume前用采集器`-CopyAheadProbe 1`选择重叠路径；不可使用诊断终止BIN作为正常游戏。测后用`test-game-menu-board.ps1`重载正常候选并验证新快照。

回退省略`-ReplayCrcNibble`；连CopyAhead也需回退时同时省略`-CopyAhead`。当前正常候选只经JTAG，断电后不保证保留，Flash没改。

## 后续取舍

优先复用当前模板描述符和像素后端，实现GPU直接取整帧列表，CPU从游戏状态直接构建，不先创建全部旧命令再压缩。必须覆盖kind3友军失活跳过、全部glow→core的Alpha顺序、边界裁剪、资源epoch、发布/执行完成栅栏和旧路径回退。现有命令数组在CPU片内RAM，不在GPU AXI可读范围，列表应放经检查的私有DDR区。先测这一变化，若后端DDR确实成为主瓶颈再做分块合成，不同时叠CDMA、缓存、主频改动。

已知两项历史SoC固件失败及CPU比较超过控制租约的限制保留。本阶段没有修它们，也没有依靠削减Sprite、关闭Alpha、PC参与计算或降低分辨率取得数字。
