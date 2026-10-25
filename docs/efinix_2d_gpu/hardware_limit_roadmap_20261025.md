# 向硬件极限推进的工作账本（2026-10-25）

目标保留为“继续优化到硬件极限，广泛借鉴开源实现思路、算法等”。上一轮属于进展：提交04ea86d/bd32855及七组板测，普通1024均值11.5735ms、两次各1迟到。该结果尚未证明目标完成。

## 保持的约束与完成证据

- 保持当前工作量、游戏/碰撞语义、原序像素/Alpha/Key、CPU基础绘图、100MHz及严格资格门槛；任何架构变化单独建立同配置控制。
- 普通游戏需要逐帧work与呈现间隔均达标、零下溢/错误，并重复和长期验证，不能用均值或四舍五入FPS代替。
- 全活动挑战需要实际搜索、3600帧资格、同session新快照；容量封顶要区分描述符地址限制与真正计算/带宽极限。
- 对CPU计算、列表构建/发布、GPU执行、DDR与显示竞争逐项取得计时/字节/等待证据，建立可核算的上界与剩余差距。没有这些证据就不能声称达到极限。
- RTL候选必须功能/像素/顺序/错误/背压/复位验证，实际资源<54720XLR、最终setup/hold及实际CDC通过，再上板公平对照。
- 保留用户既有修改、可回退BIT/BIN及每次失败证据；只作本地提交，不擅自推送、发布或写Flash。

## 当前路线

1. 修复完整挑战采集器的实际启动故障，取得当前宽口＋精确碰撞表＋寿命计数的全活动基准。
2. 针对已确认的重复CPU运算，先做逐对象算法等价及溢出边界检查，再测普通场景和全活动挑战。保留确有收益的版本。
3. 对原始分项与AXI等待作归因；重新评估列表重叠、突发合并、W通路气泡、显示预算。只有指向该路径的证据成立才增加硬件。
4. 将新候选放入完整搜索、像素与长期运行，必要时突破纯软件容量上限；目标保持active，直至各项证据充分。

## 开源机制对照

|来源|已核对的机制|适用条件/本板差异|
|---|---|---|
|Pygame bitmask_convolve，85fda3f|固定掩码预卷积|已独立生成精确接触表并板测保留|
|[ridiculousfish/libdivide，53b36fc](https://github.com/ridiculousfish/libdivide/blob/53b36fcacfd031ec0a0837db759f057eb03bacbe/constant_fast_div.h)|乘高位/移位代替重复除法|这里连续形状索引更适合直接消掉循环内除法；保持完整uint32语义，未引入整库|
|[ToNi3141/RasterIX，ba65b998](https://github.com/ToNi3141/RasterIX/blob/ba65b9989bce0e4e9815e7580502f5f1de8810c5/rtl/RasterIX/CoalesceAddrGen.v)|外存像素事务合并，CoalesceAddrGen|原模块只接收单拍匹配宽度事务，输出属性固定且未转发多ID，不能直接替换本板多主路径；仅取边界/超时/合并机制|
|[gmcnaught/mister-fpga-blitter，c4407e41](https://github.com/gmcnaught/mister-fpga-blitter/blob/c4407e41e8566fe094adac4da71448db7b1ef5f6/README.md)|驻留源图、双行缓冲、片上RMW与显示分离|本板960×540完整RGB565帧1,036,800字节，超过Ti60全部BRAM；既有条带路径有实测负收益，不能直接套全帧缓存|
|Project F hardware-sprites，dd212c2e|逐行可见性与精灵状态机|更换渲染架构需证明原序Alpha/Key及现有功能等价|
|PULP AXI / verilog-axi（前轮核对）|锁定AW/W归属、决策FIFO、流水与突发|固定8位ID和共同复位约束，不能直接扩大ID或撤掉归属保护|

## 本轮观察

完整挑战重复触发Python子进程启动失败。实际Get-Command返回Python39与WindowsApps两个Application；原代码把两条Source转换为单个FileName，Start抛出找不到文件。finally对未启动Process调用WaitForExit又覆盖原异常。实际函数的离线进程回归已先失败再通过：选首个Application，成功启动后才登记待清理进程；资格、租约和计分不变。修复后的板上基准正在运行，句柄以当前执行状态为准，不能仅据日志/计划认为进程存活。

原始证据目录：generated/verification/v3/hardware-limit-20261025/。本账本将在后续真实结果产生时更新，不预填“完成”。

基准完整挑战已完成：2615全活动、3600帧，work最大16.594ms、wall最大16.642ms、超预算/迟到/下溢/错误均0。候选形状递增保留uint32回绕语义，独立36组seed/tick边界×3640对象及完整软件回归通过；第一次完整搜索资格为2768全活动，work最大16.609ms、wall最大16.645ms、各项失败计数0，尚需回切与长验证。候选曾在2769长验证被淘汰，不能仅取600帧候选当成绩。

同数量2048的唯一、新鲜、同session遥测窗口中位数：基准work13.087ms、build2.144ms、busy8.936ms；候选work12.4755ms、build2.146ms、busy8.9585ms。它们是窗口统计，不是逐帧最大值；raw字节字段在挑战中为0，不能当成实际零流量。既有performance_trace.h仅测试辅助，当前v3_demo实走pc_record，没有接入其失败冻结功能。

采集器新增QualifiedHoldSeconds（默认原5秒）以复用同一资格/租约/实时失效逻辑做长验证；计划1800秒，不预先宣称耐久通过。回切和长验证句柄必须逐次从工具确认。

[Efinix官方Ti60资料](https://www.efinixinc.com/docs/titanium60-ds-v3.7.pdf)资源表为256个10Kbit RAM、共2.6Mbit。完整960×540×16bit帧需8.2944Mbit，故即使腾空全部BRAM也放不下；该边界排除了照搬MiSTer320×240完整片上WORK缓冲，但不证明其他流水/局部缓存已到极限。实际Sapphire netlist存在Axi4ReadOnlyUpsizer/WriteOnlyUpsizer，不能仅从32位前端推断DDR每拍只用四分之一。

回切A2完成2606全活动/3600帧、work最大16.600ms、wall最大16.642ms，各项失败0。A1/B1/A2阶段证据已封存到`evidence/shape_phase_20261025/`。实现本地提交e3230c7；新版第二次搜索＋1800秒资格后持有正在执行，exec句柄35835（记录仅供定位，必须重新poll确认），不允许并发其他板写者。下一阶段在等待该真实句柄期间继续研究GPU/DDR短事务与逐帧失败归因，保留完整目标为active。
