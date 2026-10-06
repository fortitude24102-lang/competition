# 16 B实例前端候选证据（2026-10-06）

阶段说明与复现：[接口、检查与取舍](../../v3_instances_20261006.md)。CPU/game/vendor/release不变；候选默认关闭。以下保留失败记录，不将工具exit0等同于时序合格。

## 初版 r1

`r1.zip` SHA256=`5858ed6291624667368ea0b80db581da9b3c1889e0a83c57177c833ec7b99852`。

八个原文件：工程XML、compile.log、最终timing.rpt、place.rpt、InstanceStream.sv、templates_16x224.sv、instance-contract-green2.log、instance-full-gpu.log。编译exit0，XLR60,054/RAM231/DSP30；最终100 MHz核心setup=−1.173 ns，hold均非负，**未上板**。前端最初3项通过，后续GPU全80项中79通过，一项新AXI测试模型不正确；详细根因与修正见阶段说明。

## 修正版 r2

`r2.zip` SHA256=`57d37be1d0add6886064c1eb933835fca3b668f5d7bb5fcefc607bada941aba0`，6个原文件逐项哈希回读一致。仅拆开模板写入/描述检查路径，并缩窄已受约束的尺寸算术，不降低频率、不改DDR/网络/CPU。受影响前端/寄存器12项和旧顶层6项通过。最终核心setup仍−1.101ns，未上板；路径变为寄存器地址解码至Sapphire APB响应寄存器。

## 响应暂存版 r3：时序通过、性能拒绝接入

`r3.zip` SHA256=`2ecc284ab4f755bee09729c0b9e642e3600657b8473ab4612397486460855e34`，72项归档哈希回读一致。

包含最终工程XML、编译/资源/时序、网络实际展开SDC和1488数据/2请求/2确认物理路径、18项受影响仿真及补充Asset/复位测试、原APB等待阶段RED、同一位流旧/新各300帧串口、短软件成本诊断、JTAG和恢复互动日志、相关Chisel/C源码与完整候选分模块RTL。C构建器/驱动此前原始日志保留在本地`.superpowers/sdd/v3_two_week_plan_20261001`；本次重复检查exit0及结果记录于阶段说明，不将本包说成包含所有历史原始日志。

XLR46,380/RAM156/DSP28，100MHz核心setup+0.513ns、全部16个setup/hold非负；CDC最大0.933/0.916/0.950ns。BIT `04c11a0737ba325b06b484a17665ce5bb49a6fa1a484b324b25f0bb7607c58b3`，BIN `fe59e2bf21b42d58bef98d5409a90540eb057232370a4a1a9fa36d05981e71d4`，原文件位于工程/测量目录，没有覆盖release。

实板四组均无下溢/错误、流量和可见计数一致，但实例路径256档60.1→30FPS、512档工作17.386→27.223ms，**净收益失败，默认关闭且不接入正式版本**。软件展开短诊断是tick0/100次函数调用，不是300帧；其继承的启动行warmup/samples字段不适用，以INSTANCE_EXPAND_COST行为准。实测入口/范围与失败边界见[完整报告](../../v3_instances_20261006.md)，不要拿第9天成绩替代该候选。

已JTAG恢复2026-10-06显示修复位流和原互动固件，资源result0/retry0、新V3_READY后60.1FPS/under0/miss0。无Flash操作；本轮无新目视确认、CPU慢回放或30分钟耐久。

`restored-control.zip` SHA256=`79e134932d9fa5e083e2fc8761e1679782556e5db2571ad009f6d704d4eaf675`，2项UART/HTTP快照逐项哈希回读一致。同build冷重载后旧观察者序号未自动丢弃，网页最初真实标为stale；既有控制测试建立真实新HELLO/ACK会话后，移动/租约松键通过，最终真实遥测stale=false/age78ms/GPU60.1FPS/under0/miss0。没有以缓存值伪造实时，没有重跑CPU比较。
