# 开源思路借鉴与计算热点优化（2026-10-25）

本轮最终1024档候选两次3600帧的平均work为11.574/11.573ms，比本轮旧版11.802ms减少1.936%。迟到两次均为1帧，旧版两次为4/6帧；这只是本组观测，仍不是严格稳定60或耐久证明。实现提交`bd32855`，已加载正常六档固件并回到MENU。

## 借鉴及实现

- 阅读[Pygame的bitmask_convolve](https://github.com/pygame/pygame/blob/85fda3f719d437cf27106afae8c890e6b88ba5f5/src_c/bitmask.c)及同提交的`include/bitmask.h`。借鉴固定形状与判定区域预先卷积的思路，独立使用本工程六种8×8形状生成命中半径3、擦弹半径12的精确位表；没有导入上游源码或依赖。
- 表大小1536字节，在既有`V3_SHAPE_LUT=1`候选内替代附近弹幕最多64个texel的逐点计算。原粗筛和形状验证先限制索引，使用无符号32位移位；命中优先于擦弹，无敌期行为保持。
- 另从实际RV32反汇编确认每个活动对象寿命判断都执行`240+i%120`的REMU。以240..359的循环计数代替余数，所有continue路径仍推进；该小优化同时用于解析和查表路径，没有新开关或状态字段。
- 同时阅读[Project F的sprite_inline](https://github.com/projf/projf-explore/blob/dd212c2e5e0e0d8bdcf93ba077630dbfd49ae708/graphics/hardware-sprites/sprite_inline.sv)。逐扫描行精灵架构需要重做渲染与混合路径，本轮未采用。

对象、逻辑步数、碰撞/擦弹、像素、Alpha/Key、日志字段与频率保持；没有更改CPU基础绘图算法、硬件时钟、GPU RTL、网口或预算判定。没有用减工作量换取成绩。

## 板上对照

所有行使用相同已验证宽口BIT、普通1024场景、3600帧、原日志、原计时与构建选项；A为前轮形状查表，B增加碰撞表，C再增加寿命计数。

|轮次|work均值ms|work最大ms|work超预算|迟到|
|---|---:|---:|---:|---:|
|A1 旧形状查表|11.802|18.647|4|4|
|B1 精确碰撞表|11.662|17.180|4|4|
|A2 回切旧版|11.802|18.064|6|6|
|B2 碰撞表重复|11.664|17.131|4|4|
|C1 碰撞表＋寿命计数|11.574|17.587|1|1|
|B3 回切碰撞表|11.664|17.140|4|4|
|C2 最终重复|11.573|16.634|0|1|

所有行FPS报告60.0、wall最大33.277ms、under/error均0，状态封存CRC均`a7bd652f`，可见1006..1016、Alpha130..131。末轮work没有超预算仍发生1次迟到，两项不能混为一谈。日志均值25us，最大789..792us。C1最大work高于B组，不能声称每个尾部指标都改善。

相对最初同源窄口均值13.405ms，当前宽口＋软件优化累计均值减少约13.66%；窄口基准来自前轮封存，本轮只重测A/B/C。均值降低不是FPS同比提高，也不是1024全活动极限或长期耐久结论。

## 验证及限制

- 先对旧实现运行独立解析公式的38400组相对位置、无敌期、已擦弹及命中优先级测试，再对新实现核对；覆盖全部表位及粗筛外边界。
- 所有512/1024对象索引均检查寿命到期前与到期时、前缀对象全部inactive的情况；原余数实现和计数实现均通过。
- LUT关闭/开启的常规instance及形状/碰撞检查通过；1024容量、`-Os`、UBSan下12000帧字段/裁剪/容量/标签、驱动错误路径及9600帧命令等价、3个完整像素样本通过。
- 完整`test-v3-integration.ps1 -SoftwareOnly`入口及新增`-ShapeLut`共享C用例通过，最终计数版本再次运行后通过。子脚本采用其自身选项，未把它们全部宣传为LUT开启；硬件不变，复用前轮RTL/CDC/时序验证。
- 缺失/过期生成表检查先失败，生成后通过；新增测试可通过原解析公式发现错误表位。独立只读审查确认边界、移位、判定优先级、循环计数和测试入口没有必须修复项。
- 首个临时1024主机脚本因CRLF空行在三个PASS后返回失败，已改为LF并完整重跑通过，保留失败日志。首次额外自动挑战采集出现`WaitForExit`过程对象异常，未将它计为通过；后续正常六档START/MENU真实ACK与新快照检查通过，不宣称自动挑战、人工移动/死亡/HDMI外观或30分钟耐久通过。
- 会话初始心跳过期、首次JTAG CPU等待暂停超时；重新加载同一份已验证BIT后恢复。未修改网关/资源服务器，服务持续运行。

## 当前板态与复现

最终板上为宽口BIT＋C版正常BIN，六档菜单确认后返回MENU，真实网关状态fresh、owned=false；没有Flash、远端推送或release替换。

|身份|SHA256|
|---|---|
|宽口BIT|`4f19579ced2d8d08a2281292847d56d08c8bc767cc7253a9623c2c389aa81f3a`|
|C版正常BIN，当前板上|`09f5d6d99230281f1bb5fd46a2a00dd0ee163c8c1c48ee40e7b068bd455ad0bb`|
|C版3600帧探针BIN|`55f548350de70e38cbd5ce48f0b72b1654930564910db35bb7ca0b92615c4e36`|

正常固件text57040字节（A版55544），BSS62708字节保持；4KiB栈保留，正常`_sp=0x1e3d0`、探针`_sp=0x1da40`。这是链接布局，没有实测栈高水位。碰撞表只在LUT开启时进入固件；寿命计数为公共优化，因此最终关闭LUT的BIN会改变。证据中早期`default-off-probe`逐字节匹配旧冻结BIN的记录只适用于加入寿命计数之前。

```powershell
scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -ObjectCapacity 1024 -CopyAhead -LogicCopy -ReplayCrcNibble -ReplaySealBudget -FrameList -HudDirect -PerformanceChallenge -ShapeLut -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory <全新目录>
```

3600帧探针去掉`-PerformanceChallenge`并加入`-StartCount 1024 -ProbeFrames 3600`。生成表检查为`python tools/build_bullet_contact_masks.py --check`。完整软件入口加`-SoftwareOnly -ShapeLut`，常规实例测试为`wsl bash scripts/test-v3-instances.sh`。

原始数据在`generated/verification/v3/contact-mask-20261025/`。前轮A版正常BIN作为回退副本随本轮证据封存；完整宽口硬件身份、时序与BIT位于前轮`wide_copy_fair_20261024`封存。用户既有修改继续保留。

## 封存身份

`evidence.zip`为1,608,638字节，72条目（71份载荷＋逐文件SHA256清单），已逐条回读验证长度与摘要。SHA256：`08645a0f2d2ec4e83d3a53d0e21c30a76fee4a3d897b9357f0ea2107e5516499`，另存于`SHA256SUMS`。

包内含提交`bd328552980cd4f9e3587f8ab76b87bbfa1c0fbf`的软件/脚本源码、A版控制探针与正常回退BIN、B/C固件、全部对照日志、失败记录、测试与审查记录、最终板态；排除HTTP交互记录与网关凭据。用户既有四个工作文件再次核对摘要均未改动。本轮仅本地提交，未推送或替换release。
