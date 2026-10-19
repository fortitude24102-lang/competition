# Alpha连续提交与灰度缩放（2026-10-19）

功能线按用户最新要求，最终只做GPU灰度与板键持续缩放；不扩展阈值、颜色映射、截图或压缩回传。性能线继续。官方Sapphire、100MHz、DDR3、HDMI、网口、CPU基础绘图、游戏/挑战工作量不变。所有候选默认关闭，只允许JTAG/RAM，不写Flash、不覆盖release。

## 实现与局部收益

Alpha在现有像素RTL前后增加两项地址/行末/块末元数据FIFO，仅候选`--alpha-pipeline`开启。计算和DDR事务不重写；最后结果进入packer后才能换块，最终B完成后才能退休。相同16×2真实像素RTL测试，旧129周期、候选114周期，减少15周期/11.63%；不是游戏FPS或极限Sprite成绩。按AXI ID分别保持读事务顺序，前景与背景的跨ID仲裁顺序不必相同。

灰度复用Transform opcode7：flags bit5，Mask51；STATUS bit18单独声明能力，bit17仍表示缩放。C命令仍32字节；旧硬件在任何MMIO写入/tag变更前拒绝灰度。RGB565位复制展开到8位后，Y8=floor((R8+2*G8+B8)/4)，再截取为RGB565灰阶；不是BT.601精确亮度。Key在灰度转换之前比较原色。缩放演示左右彩色/灰度飞机，同用KEY1缩小、KEY2放大、松开保持，不改变游戏资格负载。

## 本轮发现的两个既有错误恢复/退休问题

1. 多行Alpha第一行发生R/B错误后提前结束，RectAddressGen仍active，下一Fill卡在startRect。定向测试在旧路径2000周期只退休1/2条，读写事务已空。修正在finish中仅清地址生成器，必须已排空原像素/事务。随后旧/新路径R/B错误＋后续Fill通过，原始RED与GREEN分别保留。
2. 前一Alpha块的writer.done脉冲可与下一块writer.request.fire同拍；旧代码后面的rowWriteDone:=true覆盖新请求的false，造成仍有W拍时提前退休。独立AR/W背压的65像素测试发现，修改为done时rowWriteDone:=!writer.request.fire，等待新事务真正完成。这不是通过删除边界检查提速。

第一轮长故障仿真曾手动停止单个仿真进程，得到UnexpectedEndOfMessages；不把该停止当作恢复缺陷的有效RED，另有上面2000周期的明确失败。独立审查指出跨块事务覆盖不足，已补独立ARREADY、下一块ARVALID前尾像素消费断言、旧/新65像素逐ID读/逐拍写对照。临时故意提前换块的错误变体被退休时仍有未完成写的断言抓住；错误变体已恢复，不进入生成RTL或最终源码。

## R1位流隔离：禁止作为最终候选加载

R1在第二项退休优先级修复前生成，虽资源/时序合格，仍**未加载、不得使用**。

|配置|XLR|RAM|DSP|core setup/hold|状态|
|---|---:|---:|---:|---|---|
|首轮已验证仅Transform|51112/60800|179/256|37/160|+0.130/+0.026ns|历史可恢复版本，不含灰度|
|R1 Alpha＋灰度|51294/60800|179/256|37/160|+0.457/+0.026ns|有已知退休竞争，隔离，不加载|

R1全部16个最终setup/hold关系为正，最小setup+0.201ns、hold+0.012ns；不能因流程PASS就跳过行为门槛。R1 BIT为`D:/efinity_builds/alpha_gray_20261019_r1/outflow/efinix_2d_gpu.bit`，SHA256 `3345253880eee7aac5268660752ec1adf1232710562ea7863581b3425947b07e`。另一个R1只开灰度候选同样早于退休修复，不允许加载。

## 修复后的R2：同BIN A/B/A板测

A仅灰度/缩放、Alpha旧调度；B灰度/缩放＋Alpha连续调度，两者都含本轮退休修复、Key预取和Scanout换字，不开透明裁剪、Copy256或条带。两版最终16个setup/hold关系均为正，100MHz不变。

|R2配置|XLR/60800|RAM/256|DSP/160|core setup/hold|全局最小setup/hold|
|---|---:|---:|---:|---|---|
|A，连续调度关|51409|179|37|+0.265/+0.027ns|+0.023/+0.012ns|
|B，连续调度开|51245|179|37|+0.273/+0.026ns|+0.138/+0.020ns|

资源差异包含优化/映射变化，不能宣称元数据FIFO本身减少164个XLR。生成的56份模块源码逐文件确认一个模块。最终B BIT路径`D:/efinity_builds/alpha_gray_20261019_r2/outflow/efinix_2d_gpu.bit`，SHA256 `1d53bb5fbee641bcc086d5f62c514c39f59c2ddc27a85f74b2fbcfa3b12aa780`。A为`D:/efinity_builds/grayscale_20261019_r2/outflow/efinix_2d_gpu.bit`，SHA256 `29e3e290c56095a7c26f799e67b48384c6b9852abf3137a5e0cf812d1383ed40`。

### 普通512：可重复但很小的收益

始终使用未重编译的`dc82fae7902e1fd238a572db28e49b947535d75f876c892562b2d8c736504a0b`探针BIN，30帧预热＋3600帧连续采样，LogicCopy1/SealWords256/HudDirect1固定：

|顺序|FPS|平均/最大work μs|最大wall μs|超预算/迟到/新增下溢/错误|
|---|---:|---:|---:|---|
|A|60.1|9617 / 12743|16639|0/0/0/0|
|B|60.1|9567 / 13407|16639|0/0/0/0|
|返回A|60.1|9618 / 12781|16639|0/0/0/0|

相对两侧基线平均值，B少50.5μs、约0.525%。是小幅整帧工作时间收益，不是显示FPS增加，也不是最大耗时改善；B单次最大值反而更高。三组均可见499..504、Alpha66..67，封存状态CRC`c0ecf1df`一致，包含死亡/自动重开，不是恒定512活动精灵资格，更不是新的极限成绩。候选保留，正式默认开关与release仍不替换。

三组真实网口资源101/102/103均result0、重试0、network1。启动/离屏准备时已有下溢计数分别369360/365040/365040，由`V3_COUNTER_BASELINE`保存，表格是30帧预热后3600采样帧的**新增**计数，不声称自上电全过程下溢0，也不把第一预热窗口约57.8FPS当作稳态成绩。

### 1040全活动诊断分段

同一`9c2a1b108814ee462a4b769527fd27d51214deb6b21e3f0db8f0c5093be64f63`保存的r3分段BIN；每项tick11/22/33三次均值。显式初始化全部1040精灵、额外130Alpha，不按opcode重排FULL。

|阶段均值ms|A|B|返回A|
|---|---:|---:|---:|
|背景Copy|5.55915|5.56006|5.55370|
|Alpha|2.41399|2.30233|2.41237|
|Key|3.54329|3.54791|3.54797|
|完整有序场景|11.48922|11.36600|11.48533|

相对两侧基线，Alpha阶段约少4.59%，完整分段约少1.06%。三次各24阶段的描述符CRC、命令数、读取/有效写入/Cache字节逐项一致，新增下溢和硬件错误0。阶段中有同步、等待和串口，不能相加推正常FPS；描述符CRC不是实板帧缓冲CRC。背景与Key几乎不变，后续性能工作应先量化它们的访存等待，不继续把乘法吞吐当整机主瓶颈。

## 物理像素与演示

- A/B各通过80例Transform/灰度/镜像/Key的DDR逐像素、padding/哨兵、像素数和有效写字节读回；同一BIN，SHA256 `506608cb5a88880564d8194c16452fab0561708698a05eff9d315efca09ce5ab`。
- A/B各通过新增24例Alpha读回：1/3/16/65宽、两种半字起点、缓存/DDR、Alpha128及0/255端点，逐像素与独立C参考比较，padding/哨兵、处理数、读写/缓存字节均检查。缓存加载后故意修改DDR源，确认真正命中缓存。最终oracle BIN SHA256 `5a841aead984c26fb19b2ab8f6917a14c4b7c48a6f45fda0b6752c62a412e5e9`。
- 首版Alpha oracle在A的case22像素/哨兵通过，但测试按整行估算读量，预期528B而硬件实际544B。OpenOCD快照`0xf8100060: 00000220 00000000 00000104 00000000`证明读544B/有效写260B；65宽、半字起点2时，64＋1像素两块每行读132＋4B，边界字确实重复读取。仅修测试按块计算，硬件不变；初失败、读回日志及修正后的两版24/24保留。
- 当前保留B BIT＋双飞机Zoom BIN，SHA256 `1dc64ca838ee1b744ab23c1a14f084a350117d894c680c4ee9b33d03f92b29ab`，启动明确`color_and_gray=1`与首帧`scale_q8=256,side=16,keys=0`。同一KEY1/KEY2控制两架飞机，左右分别彩色/灰度。**不是游戏MENU，此独立固件不处理网页游戏控制；网页遥测过期不代表网口回退。**新画面人工目视尚待用户确认；上一版方向/松开保持的人工确认不冒充这一版灰度目视。
- 离屏oracle不PRESENT，HDMI缺输入次数以`under_offscreen`记录，不作为栅格失败；有显示的分段/正常512仍严格要求新增下溢0。没有以此放宽游戏验收。

## 验证进度与边界

- 首个行为RED四套11项6通过/5失败，包含停止的故障仿真；不当作全为产品缺陷。
- focused-r1四套11项10通过/1失败：灰度、能力、旧关闭路径全部通过，故障恢复失败随后定向修复。
- alpha-recovery-green三项通过，随后加强事务覆盖发现第二个竞争。完整GPU套件只运行一次；已通过套件不重复，Alpha修复用定向复测补证。
- V3软件入口、网关真实UDP/HTTP、采集身份/会话/清理保护通过；基础Sapphire软件与链接检查通过。构建仍有既有RWX LOAD segment警告。
- 完整普通游戏固件链接通过，仍32字节C命令与4KiB栈，栈区0x1dd50..0x1ed50，片上RAM末端0x20000尚余4784B；这是链接余量，不是实际栈水位。BIN SHA256 `bbdee4d00f57f354c03f84186eb697e38fdd1b8bfb38c040fb11095ac66160a0`，未拿它替换A/B测量BIN。
- 完整GPU回归仅一次，30套119项，117通过/2失败，两项都在Alpha新套件：跨ID读顺序过约束、跨块完成竞争。两者修正后`alpha-final-r2.log`最终4/4通过（含先前通过的该套两项），其余通过的套件不重复。完整首跑29分06秒、完整日志保留，不伪造一次全套GREEN；核心RTL/驱动的独立只读审查提出的跨块覆盖缺口已补，修正用例和错误变体均有证据。历史两项SoC异常、栈水位及30分钟实机耐久不在此冒称通过。

日志根目录：`generated/verification/v3/alpha-gray-20261019/`。不要把R1测试或时序自动挪给后续位流；全部烧录操作仅JTAG/RAM，没有Flash写入。

## 证据与复现入口

[证据包](evidence.zip)共1210296字节、491项（含目录），SHA256 `300a5119bc3aa0423f5707c8fc746efbcb56457bfd0f3a606958140c7e0dab11`。包内保留完整首跑失败、定向GREEN、故意错误变体日志、两组R1/R2生成RTL/资源/时序、A/B/A原始UART、最终BIN与源码快照；`identities.csv`逐文件哈希。已打开ZIP核对关键日志及三份最终诊断BIN、核心Dense源码、新Alpha oracle源码哈希。BIT本体不入库，只记录确切路径、哈希和可重建RTL。

位流R1均隔离不加载；**固件**`board-zoom-r1`与`board-transform-r1`名称中的r1只是该固件首版，不表示有位流R1的退休缺陷，两者已在R2硬件验证。`board-alpha-r1`是计数模型错误的旧诊断，最终使用`board-alpha-r2`。包内过程进度是封存时快照，不替代本页及Git后续提交记录。

生成器`gpu.GenerateEfinix2dGpu`使用新目录、`--split-verilog --instances --frame-lists --key-prefetch --scanout-word-pipeline --transform-blit`；B另加`--alpha-pipeline`，A不加。新建工程用`scripts/test-efinix-board.ps1 -GpuRtlDirectory <新RTL目录> -OutputDirectory <新编译目录> -Flow compile`，必须检查最终全部时序关系，不能只看进程退出0。独立固件入口为`scripts/build-board-hud-dma-test.ps1 -Test zoom|transform|alpha-pipeline -OutDirectory <全新目录>`，通过JTAG载入0x1000。新Zoom首帧必须从新加载/复位候选BIT开始；离屏oracle无PRESENT。不要为重现本轮证据重新跑已经通过的全套仿真。

封存时所有烧录及串口采集进程均退出，板上继续运行B＋双飞机Zoom；没有Flash写入或远端推送。新增灰度组合的人工画面确认仍待补，不因此宣称人工验收已通过。
