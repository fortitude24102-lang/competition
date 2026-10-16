# 短行预取与片上条带合成（2026-10-16）

基线53bcd61，依次落实短行预取和条带合成。复用官方Sapphire、DDR3、HDMI、网口、原Alpha/Key像素引擎；CPU基础绘图、游戏负载、图形尺寸、Alpha比例和100MHz不变。两个方向都有显式回退开关，尚未改正式release或Flash。

## 已实现的路径

### 2：缓存命中小精灵的连续预取

`CachedKeyStream`针对非重叠、源4B对齐、紧密源行、偶数宽≤16和高≤16的缓存Key精灵，一次请求完整源图，通过16个32bit字FIFO预取后续行。目标仍按实际stride逐行写，不把不连续显存伪装成连续Burst。复用原写引擎和RGB565半字对齐器；透明像素只关闭WSTRB，仍排空每个已承诺的Beat。

每一行在完整源数据就绪后才承诺写请求。发生缓存读错误或B错误时，停止后续行，完成已承诺写并排空缓存/FIFO，仅完成一次，不重放半帧。裁剪后的非紧密源行、未命中Cache和重叠Key在任何issue前选择原路径。

生成开关`--key-prefetch`，默认关；不改软件命令ABI。没有顺手扩大DDR仲裁器的在途事务数量，也没有新移植一套CDMA。现有AXI写引擎仍逐行等待B，这不是多在途写入的实现。

### 3：复用原BitBlt像素引擎的条带合成

`StripeScratchpad`在Render主机与DDR仲裁之间截获`0x02e00000..0x02e03c00`，提供960×8×RGB565的15,360B片上条带；整个64KiB别名区都不透传DDR，越界/非法32bit INCR Burst返回SLVERR。读写分别保持owner到RLAST/B，支持字节写掩码和背压。Scanout、网络资源DMA和列表读取仍走原DDR通路。

Sapphire先产生完全相同的原场景，再用两遍Y分桶生成稳定有序的裁剪描述符：每条带背景装入→按原顺序Alpha/Key→长Copy写回真实back framebuffer。每段真实退休后才复用列表bank；最后才HUD/PRESENT。没有把游戏运算移到PC。

原场景DDR `0x02d40000..0x02d48000`，分桶DDR `0x02d50000..0x02d70000`；使用现有bankA/B执行，不扩大列表读取白名单。生成`--stripe-scratchpad`声明STATUS bit16；固件`-StripeRender`必须同时使用FrameList并检测能力位，旧BIT拒绝启用，不允许部分执行后回退。MENU/WIN及CPU比较仍走原相应路径。

独立审查发现并修复StripeRender+HudList的MENU/WIN临时地址泄漏：恢复HUD bank的代码移到所有场景公共出口。真实V3循环回归先看到错误bank `02d40000`失败，再确认MENU/WIN都传入原bank通过；没有放宽HUD地址检查。

## 实测，不把局部提速等同于整机提速

同一仿真AXI环境，缓存8×8、目标半字相位、stride1920的Key命令：原125周期，新100周期；写出数据/掩码顺序一致。这个20%仅属于该单命令，不是全游戏FPS提升20%。

普通512终止探针：同一BIN SHA256 `dc82fae7902e1fd238a572db28e49b947535d75f876c892562b2d8c736504a0b`，HUD直接更新，30预热＋3600采样，包含死亡等待/自动重开。

|硬件|FPS|work均值/最大ms|超预算/迟到/新增下溢/错误|
|---|---:|---:|---|
|原BIT|60.1|11.552 / 14.964|0 / 0 / 0 / 0|
|预取＋条带硬件，软件仍直绘DDR|60.1|11.526 / 15.884|0 / 0 / 0 / 0|
|仅预取硬件，软件直绘DDR|60.1|11.527 / 14.445|0 / 0 / 0 / 0|

三组可见499..504、Alpha66..67、封存CRC `c0ecf1df`一致。均值差25..26us太小，不能据此声称可信的全游戏提升；最大值也有波动，不作为单点提速证明。普通512请求数量不等于恒定512活动Sprite。

### 条带的负结果

实板隔离场景同一BIT/同一测试BIN，原顺序DDR场景与条带路径完整帧CRC逐个相同，目标尾哨兵保持，硬件错误0：

|活动Sprite（额外Alpha）|CRC|原DDR路径ms|8行条带ms|
|---|---|---:|---:|
|64（8）|119ffda2|3.85625|6.43496|
|512（64）|519af8e6|5.80020|10.88503|
|1024（128）|317493db|8.03564|15.89329|
|1819（228）|dede561f|11.50152|23.19732|

这是无Scanout/游戏循环的隔离渲染测试，不是可宣称的游戏帧率或1819@60。条带需要额外的背景装入、写回、本地读写和跨条带描述符；当前低覆盖率的小精灵场景收益不足。Render写计数也从512档948,548B变成1,847,108B，**其中包含片上写入，不等于实际DDR带宽翻倍**。据结果条带路径保持实验关闭，普通场景继续直绘DDR；将来只有重叠层数/目标读改写确实占主导时才值得重测，不因“像现代GPU”就强制启用。

首次板测将性能场景Y设为79，被原`pc_build`的Y≥80检查在任何GPU命令之前拒绝（LAST_DONE0/ERROR0）。修正测试数据到80后通过；Alpha从78开始仍跨条带。首失败原始日志保留，没有放宽生产校验。

## 资源与时序

|配置|XLR/60800|RAM/256|DSP/160|核心100MHz setup/hold ns|
|---|---:|---:|---:|---:|
|原已验证BIT|47560|172|28|0.651 / 0.026|
|短行预取＋条带|49923|192|33|1.022 / 0.026|
|仅短行预取|49738|176|33|0.411 / 0.026|

两新候选最终全部16个setup/hold关系均为正，生成、interface、map、route及PGM通过。只看最终route报告，不把placement阶段未修复的hold报告混作最终结果。生成源每个`.sv/.v`只有一个module；`.vh`为原接口头文件，不计module文件。

联合BIT SHA256 `4e9001a4c346dda1eb5ddfd5600d8b03a4be7f96af2a7910c4ddc15fca1c0d94`。
仅预取BIT SHA256 `7898424a3bb6e1a26528ecbd83e474f6673252e976bf18d4967e5f3191bf66c1`。
原BIT SHA256 `a374b64c071e9a36d88f2fe7d09817be9b6f35f951a1bc0bc72a6b35303cf0d4`。

条带完整固件BIN SHA256 `adc0abeffc6288a3b559de50e0e31bd07995393d737b9ffaa990a6453c5c981a`，已实际JTAG运行：网口资源加载、四档START/MENU真实ACK＋新快照通过，没有V3_FAIL或新增下溢/硬件错误；实际低档也出现30FPS/迟到，进一步确认不适合当前实时场景，不能把“能操作/像素正确”写成性能合格。完整CPU比较/人工新画面未补验。

## 复现入口

以下都在项目根目录运行，生成/构建使用新输出目录；CLI下载只能`-m jtag`，不写Flash。

```powershell
# 预取候选；不传开关生成的仍是原路径。
scripts/test-v3-gpu.ps1 -Generate -KeyPrefetch
# 额外包含片上条带候选。
scripts/test-v3-gpu.ps1 -Generate -KeyPrefetch -StripeScratchpad
# 条带完整固件；原固件不加StripeRender即可回原软件路径。
scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -FrameList -PerformanceChallenge -HudDirect -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -StripeRender -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory <新目录>
```

RTL分别在`generated/verification/v3/rows-stripes-20261016/rtl-key`和`rtl`。实际板卡工程使用`scripts/test-efinix-board.ps1 -GpuRtlDirectory <上述RTL目录> -OutputDirectory <新目录>`。像素实板对照用`build-board-hud-dma-test.ps1 -Test stripes`构建，串口采集器已增加STRIPE_BOARD_FAIL快速退出。

## 验证边界与收尾状态

完整GPU回归21套件91项通过；28套C、27项实际UDP/HTTP及身份保护通过，另8套damage/18000黄金帧、12000旧实例/9600当前游戏列表字段与3完整像素样本通过。新测试覆盖半字相位/stride相位交替、预取满FIFO后B错误排空、缓存读错误、局部/外部AXI读写独立、背压、非法边界、完整Alpha/Key结果及MENU/WIN+列表HUD。

仅预取BIT＋原正常菜单BIN `95b463d62c444b1d1c2a3ecec71812df6a3b85f331741884e46c48599fe091f1` 独立挑战已确认 **1040个全活动Sprite＋130个硬件Alpha光晕**：3600帧60.10FPS，work最大16.451ms/wall最大16.639ms，超预算/迟到/新增下溢/错误0，可见与Alpha数量始终固定；随后5秒未作废，真实MENU退出后串口导出完整统计。1047短窗候选长确认失败、回退再搜索才确认1040，失败原始HTTP仍保留，不把1047称为成绩。

这是同一原正常BIN更换GPU硬件的有效新窗口，不是所有画面/长期极限。上轮993属于另一个中间BIN，不能把993→1040百分比全部归因于预取；上轮该95b...BIN的1015资格后作废也没有被抹掉。本轮联合BIT搜索在1048档控制会话重建后回MENU，没有3600资格成绩；控制会话中断与GPU性能失败分开保留，未修改250ms租约、成绩作废规则或剔除慢帧。

最终已JTAG恢复仅预取BIT＋原95b...正常菜单BIN，四档START/MENU真实ACK与新快照再次通过。为从条带build20261016返回build20261015，只重启本任务自启的网关清除退休build历史，未放宽防回退/租约检查。最终API记录MENU、requested0、ownedfalse、遥测新鲜、新增下溢/错误0，无烧录/OpenOCD进程残留。网关与资源服务器留开；只用JTAG，未写Flash或替换正式release，未推送远端。

原始成功/失败、协议快照、两个候选的最终时序、精确测试BIN/ELF及逐文件SHA清单在[`raw-evidence.zip`](evidence/row_stream_and_stripes_20261016/raw-evidence.zip)，包含首次无效测试坐标、1047未合格及联合搜索中断，不只保留成功摘要。当前工作目录生成物仍在`generated/verification/v3/rows-stripes-20261016/`，不将其默认当发布版本。执行取舍：复用原像素/列表后端；无收益条带不启用，当前只保留预取作为已测候选；Windows/WSL路径兼容仅用于执行记录，不改变硬件。

条带固件静态链接text55512B/BSS66808B、`_end=0x1ddd0`/`_sp=0x1edd0`，保留官方4KiB栈，位于124KiB程序RAM内；尚不是运行栈水位证明。CPU慢比较中一键取消限制、旧SoC异常、30分钟实机耐久及人工新HDMI外观仍保留，不宣称项目整体封版。
