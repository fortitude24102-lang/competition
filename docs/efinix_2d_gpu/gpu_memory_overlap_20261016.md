# GPU读写与显示取数重叠实验（2026-10-16）

基线62fdc55，继续GPU性能优化。保持官方Sapphire、100MHz、原游戏/性能挑战、硬件Alpha和Key、网口、双缓冲及资格规则，不改CPU绘图。不推送、不写Flash、不替换release。

## 测量与选择

新增`test_board_sprite_phases.c`，复用真实`pc_build`与FrameList，将同一已初始化全活动场景分别测BACKGROUND、ALPHA、KEY、FULL；不按opcode改变最终FULL的绘制顺序。先PRESENT并预热50ms再测。阶段中间有同步/串口/等待，不能相加冒充正常固件帧率。读字节含列表描述符；总stalls也不能直接解释成B响应等待。

同一基线BIT `7898424a...c1`，固定诊断BIN SHA256 `9c2a1b108814ee462a4b769527fd27d51214deb6b21e3f0db8f0c5093be64f63`，三个tick=11/22/33：

|全活动Sprite|额外Alpha|背景ms|Alpha ms|Key ms|完整有序场景ms|
|---:|---:|---:|---:|---:|---:|
|512|64|6.705..7.449|1.587..1.608|2.041..2.203|10.367..11.155|
|1040|130|7.424..7.450|2.958..3.254|4.133..4.462|14.302..14.634|

全部24个阶段新增下溢/硬件错误0。初次未建立显示启动状态的记录出现241下溢，不能纳入性能比较；第二次固定测试仅初始化了pc_init默认64个对象，后来增大target造成非标准重叠分布，也排除。最终r3为全部对象显式初始化、边界/数量验证通过后的基线，保留先前日志但不选好看的数。

背景仍为最大单项。先试现有CopyStream的FIFO从16×32bit扩为256×32bit，即容纳一个最大AXI突发；不引入新CDMA、不修改仲裁、最大Burst、4KiB切分、在途事务数或错误退休。预期是减少R被W/B/QoS间隙阻塞，而不是认为容量增加必然加速。

## 有界候选

`CopyStreamEngine(bufferWords=16)`只允许16或256；默认保持16。顶层显式`enableCopyBurstBuffer`／生成`--copy-burst-buffer`才选256。原Key预取候选继续开启，条带关闭；命令ABI和正式固件不变。

新测试先因缺少bufferWords参数失败，再验证写端停顿时完整接收256字、满队列背压、512字顺序/掩码、延迟B、R/B错误锁存和稳定完成。现有Copy随机背压、4KiB、奇数宽/非紧密回退、错误ID/RLAST案例也用256重新运行。

接受条件：最终时序/资源通过，实板Copy字节和哨兵一致，无新增下溢/错误；同一诊断BIN测候选，再回原BIT对照，必须看到可重复收益才启用。完整正常固件只用同一95b...BIN做严格3600帧挑战及资格后观察，不以隔离测试代替FPS资格。无收益恢复原BIT与MENU，实验记录保留。

## Copy实验结果：不启用

同一Copy oracle BIN、同一有效分段r3 BIN，按原BIT→256字候选→原BIT（A/B/A）顺序：

|指标|原BIT A|候选 B|回原BIT A|
|---|---:|---:|---:|
|独立960×468 Copy ms|7.520|7.457|7.520|
|512完整场景均值ms|10.664|10.684|10.698|
|1040完整场景均值ms|14.480|14.404|14.428|
|1040背景均值ms|7.440|7.411|7.443|

各分段的列表CRC、读取/写入/Cache字节完全一致；全部阶段下溢/硬件错误0。Copy oracle四种尺寸/stride/4KiB场景逐像素、首尾哨兵和精确字节检查均通过。独立大Copy只有0.84%差异，512完整场景反而略慢，1040完整场景对两次原BIT分别仅0.52%/0.16%；不足以证明值得启用的整机收益。256字缓冲显式关闭，不把RAM容量本身当成性能来源。

14项定向＋79项其余GPU合计22套93项通过，未重复已通过的14项；后续Scanout改动另有自己的验证。独立只读审查无Critical/Important/Minor；当时尚未判断的资源/时序和Copy实板数据已补证。旧SoC异常、无关Word/临时文件仍保留。

## 继续定位：显示拆包器的字间空拍

代码可直接观察：`PixelReadAligner`在输出一个32bit字的高半字时将buffered清零，只在下一拍重新接收新字；持续供数/持续输出也只能3拍给出2像素。Scanout直接连接此拆包器，读事务归属持续到物理RLAST，所以不仅渲染的FIFO容量会影响共享DDR占用。

下一有界候选仅对Scanout启用弹性字替换：在旧字高半字被接收且本行还有像素时，同时接收下一个32bit字；结束像素、半字起点、奇数尾、暂停时稳定、错误与行/帧边界不变。其他Alpha/Copy使用的拆包器默认不改。测试先验证16像素无间隙与各相位/尾部，再用原518400像素CRC检查完整Scanout，最后相同BIN A/B/A板测。候选仍可单独回退，不因Copy实验无明显收益而强行扩大缓存。

参考的是[verilog-axi的读FIFO/事务解耦原则](https://github.com/alexforencich/verilog-axi#axi_fifo_rd-module)及本工程已有弹性流水，不复制其RTL或声称FIFO/弹性握手原创。针对本设计的具体改动是RGB565双像素拆包的尾像素同拍换字；减少共享读口占用只是待测假设，不能提前当成游戏FPS收益。

该参考仓库README现已声明由[Taxi](https://github.com/fpganinja/taxi)接替维护。本轮只参考握手/缓存原则，不引入旧仓库依赖，也未为本次小改动迁移总线IP。

## 两种候选的验证状态（不要混用）

Copy256候选：定向3套14项＋其余19套79项均通过，28套C/27项实际协议与身份保护通过。此Copy候选最终map/interface/pnr/pgm通过，XLR49704/RAM176/DSP33；全部16个最终setup/hold关系为正，核心100MHz setup0.139ns/hold0.026ns。BIT SHA256 `82a8295d119ac3e25246d322bb6851a472329e576baa43438ff01cd03b295028`，输出`generated/verification/v3/copy-burst-buffer-20261016/rtl/`；实测无明确整机收益，关闭。

Scanout换字候选：初始3项新增＋7项系统共10项通过，实际生成命令只开Key预取与Scanout换字，Copy仍16字、Alpha/Copy拆包仍旧路径。独立审查未发现RTL错误，但指出断供/末尾sentinel两处重要测试盲区：新增`ScanoutWordBoundarySpec`，把buffer错误固定为true后确实因输出未清空失败；删除末像素保护后确实因吞sentinel失败，两个错误变体都已恢复正确源码。同时新增启用路径的RRESP/RID/RLAST错误及成功两行测试。恢复后的最终三套12项全部通过（`scanout-final.log`），没有把故意失败的错误变体混作未解决缺陷。审查指出的报告归属歧义也已分开说明。候选各有独立资源/时序和板测，不能套用Copy时序结论。

原BIT＋95b...原正常BIN重新挑战在1057档VERIFY3457帧时控制会话重建，回MENU，未完成3600帧。中断前work最大16.607ms/wall最大16.643ms、可见1057/Alpha133恒定、四项异常0；这**不是资格成绩**，也不能归因于GPU性能失败。完整HTTP显示会话1223241503→4164059846→1063718926；已停止本任务的等待采集器，保留日志。先前口头提前认定通过已明确更正，历史有效1040资格仍单独保留。

原BIT＋同一95b...BIN第二次（`native-baseline-r2`）真正通过1040＋130Alpha：3600帧60.10FPS，work最大16.496ms/wall最大16.643ms，work_miss/late/新增下溢/错误0、数量恒定；资格后5秒未作废，最后实际MENU并释放owner，UART完整导出。后续Scanout候选与这次有效基线比较，不用1057未完成值。

生成/仿真/板测原始结果使用新目录`generated/verification/v3/sprite-phases-20261016/`；Scanout候选RTL输出`generated/verification/v3/scanout-word-pipeline-20261016/rtl/`，不能和Copy候选目录混用。

Scanout的最终map/interface/pnr/pgm现已通过：XLR49346/60800、RAM176/256、DSP33/160，100MHz核心setup0.541ns/hold0.026ns、DDR setup0.321ns，16个最终setup/hold关系全正。BIT SHA256 `705f1642db8dffc3bfd1ab5cb208e7645351eba141ec7f652d5ecc1ae43beb09`。无新增FIFO、行RAM或DMA；仅资源结果，不提前证明FPS收益。

## Scanout实板同固件A/B/A

同一Copy oracle四个尺寸/stride逐像素、首尾哨兵、精确字节和下溢检查通过，960×468 Copy由7.520ms降至5.766ms（减少23.3%）。同一r3分段BIN，1040完整场景均值14.428→11.481ms、背景7.443→5.556ms；列表CRC/渲染字节/Cache量均相同，24阶段下溢/错误0。阶段数据仍不是完整游戏FPS。

普通512同一终止BIN `dc82fae7902e1fd238a572db28e49b947535d75f876c892562b2d8c736504a0b`，同为30预热＋3600连续采样、HUDdirect/LogicCopy/SealWords256固定：

|硬件|FPS|work均值/最大ms|wall最大ms|work_miss/late/新增下溢/错误|
|---|---:|---:|---:|---|
|原Key预取BIT|60.1|11.527 / 15.208|16.639|0/0/0/0|
|Scanout换字BIT|60.1|9.618 / 13.191|16.639|0/0/0/0|
|回原Key预取BIT|60.1|11.528 / 15.760|16.639|0/0/0/0|

工作均值减少16.6%；本来已受刷新率限制，不能宣传普通512的显示FPS也增加16.6%。三组均包含死亡等待/重开，实际可见499..504、Alpha66..67，600输入封存状态CRC `c0ecf1df`相同。此CRC是游戏/回放状态，不是实板帧缓冲像素CRC；像素证据另由Copy oracle和完整Scanout仿真覆盖，不夸称完整游戏像素已读回。

## 测量控制连续性

首个Scanout正常BIN挑战在1576档SAMPLE425帧时会话变化、回MENU；未完成600短窗或3600长确认，不记成绩。旧采集器将串口、HTTP续租、HTTP状态和日志写盘放在同一循环，任一1秒HTTP超时都可能越过250ms租约，这是明确的结构风险，但尚不能证明每次会话中断都仅由此造成。

仅采集工具新增标准库独立心跳进程，通过私有stdin传token、只续既有中性控制，不更改网关/固件250ms租约、500ms过期规则或挑战算法。父进程遇新会话/MENU/性能模式退出立即失败，心跳HTTP失败也中止；进程管道关闭后退出，再释放owner。独立审查指出最终5秒后还需重新断言性能快照新鲜，现已补齐同会话/owner/ACK、3600帧、stage4/5和不变best的最终保护，并用过期/缺失性能等12个失败变体验证。清理异常也必须保留串口关闭与BIN身份，注入故障先红后绿。HTTP200本身可能重新获得过期owner，真正阻止错误计分的是父进程会话保护，不声称心跳单独保证会话不变。

最终软件回归：28套C（含两项条带脚本）、27项真实UDP/HTTP、3项独立心跳以及采集器身份/会话/清理检查通过；随后最终资格保护另有定向红→绿检查。心跳只改善测量可靠性，不计作GPU提速。

## 极限复测：没有新增合格纪录

两个独立正常固件挑战均使用原95b...BIN、Scanout候选BIT、原600帧短窗/3600帧长窗/随后5秒规则，且各自整个有效搜索期间保持同一控制会话：

|采集|最终目标|最终stage/best|统计frames|终态tick|迟到增量|下溢/错误|结果|
|---|---:|---|---:|---:|---:|---|---|
|native-scanout-r2|1572|6 / 0|3600|3661|1|0/0|作废，不记分|
|native-scanout-r3|1568|6 / 0|3600|3670|2|0/0|作废，不记分|

两次独立心跳正常退出0，父采集器正确返回非零、保留失败HTTP记录，未产出performance-final.json。两次此前1573/1576的长确认失败后，原算法已自动重新二分。终态frames=3600不等于保持通过：60预热＋3600采样后，在后续运行阶段仍会因迟到作废。r2终态work=16.657ms、GPUbusy=15.453ms、build=2.721ms；r3终态work=15.311ms、busy=14.271ms、build=2.686ms，只是终态遥测，不冒充整段最大值，也不把重叠build和busy相加。

因此本轮**不宣称1568/1572/1576稳定60，不把旧BIT的1040资格挪给新BIT**。1040＋130Alpha仍是原Key预取BIT/原正常BIN本轮重验的有效成绩；Scanout候选的新增极限尚未取得完整合格结果。已证明的独立收益是普通512同BIN A/B/A工作时间减少16.6%，以及同BIN背景搬运/完整分段渲染缩短。

下一轮应继续减少最坏帧开销，并单独量化资格完成后HUD状态转换与PRESENT截止之间的余量。阶段切换可能增加成本是待证假设，不能直接当根因；现有短窗搜索也可能选中几乎没有余量的边界，不以降低Sprite/Alpha或放宽60FPS门槛规避。下一GPU设计仍先看剩余5.556ms背景项及Key/Alpha访存重叠，不继续盲扩FIFO。

## 复现与收尾

从仓库根目录生成候选（示意新日志路径，不覆盖既有证据）：

```powershell
./scripts/test-v3-gpu.ps1 -Generate -KeyPrefetch -ScanoutWordPipeline `
 -Suite gpu.ScanoutWordPipelineSpec,gpu.ScanoutWordBoundarySpec,gpu.GpuSystemSpec `
 -LogPath generated/verification/v3/scanout-reproduction.log
./scripts/test-efinix-board.ps1 `
 -GpuRtlDirectory generated/verification/v3/scanout-word-pipeline-20261016/rtl `
 -OutputDirectory D:/efinity_builds/scanout_reproduction_fresh -Flow compile
```

只在板卡就绪后用CLI的`-m jtag`载入该BIT；正常BIN用官方OpenOCD配置、800kHz、0x1000地址JTAG RAM载入，不写Flash。随后用`test-game-menu-board.ps1 -PerformanceChallenge`和COM9、ExpectedBuild0x20261015、新OutDirectory运行原自动挑战。脚本默认COM13，当前设备实际为COM9，不照抄旧端口。详细BIT/BIN/工程/RTL/时序和全部正负记录见[原始证据索引](evidence/gpu_memory_overlap_20261016/README.md)。

最后已JTAG重载95b...正常BIN、保留Scanout候选BIT，四档真实START/MENU ACK与新快照通过，恢复MENU并释放owner。无Flash写入、无release替换、无远端推送。已通过的长仿真没有重复运行；93项Copy/旧GPU回归与最终12项Scanout定向验证的时点分别保留，不说98项都在最终树上重跑。CPU慢比较退出限制、历史SoC异常、30分钟实机耐久、栈水位和本轮HDMI人工目视仍不补称通过。
