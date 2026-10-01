# V3 负责人第一阶段：连续 Copy 离线候选

状态：负责人第1～4天的Copy专项完成离线检查；第5天仅完成独立候选RTL生成，尚未综合/时序/上板。不是V3封版，不是512@60已达标。A/B功能线、背景恢复和条件实例前端仍按两周计划推进。

## 做了什么

- CopyStreamEngine.scala只调度已有AxiReadEngine/AxiWriteEngine，不另开DDR端口、不更改DdrQosArbiter，也不移植整套CDMA。
- 仅在Copy、源/目的字对齐、两边stride=width×2、总长度为4的倍数、合法非重叠区域时，展开为一个连续任务。奇数宽×偶数高也可以连续展开；不能满足条件的合法描述符走原Dense通路，非法描述符仍由原验证器拒绝。
- 增加16字（64 B）FIFO，解耦读数据与写/响应停顿；读、写各最多一个未完成突发。仍按256 beat和4 KiB边界切分，不宣称增加多在途窗口。
- 等待所有读数据、写响应和FIFO排空后才给出tag；错误粘滞到本次完成，不自动重放部分命令。后续Alpha必须等前Copy完成。
- 修正非Alpha操作收到错误RID=1时被送往空闲背景读引擎的问题；现在由前景读引擎排空并报告AxiResponse。
- Dense、Render、Top提供构建期enableCopyStream开关；生成器的`--legacy-copy`用于关闭新通路，原APB及C固件不变。

CPU绘图、R7画面/逻辑、分辨率、Alpha比例、官方vendor和release/v2均未修改。

## 可核验结果

生产RTL源码包含于`02c9005`，Windows PowerShell运行入口修正包含于`4314c96`；后续阶段记录提交只增加证据和测试打印的空洞计数。测试文件SHA256：3836bc64c361e6853efe818e43ca7462af05f6ea4dd644792d9b94519ddbe93e。

2026-10-01最终GPU回归：**14套件，76/76通过，0失败/取消/忽略/待定**。CopyStreamSpec为4项测试，单项内包含连续/跨界/非连续回退、读写反压、RRESP/BRESP/RID/BID/RLAST错误、后续正常命令、非法地址、占用FIFO时整机复位、Copy→Alpha顺序及像素/计数验证。半字错位Copy/Key仍由现有RenderEngineSpec和WordKeyDmaSpec覆盖。

| 定向用例 | AR/AW次数 | 本地FIFO峰值 | 结果 |
| --- | --- | --- | --- |
| 8×8，stride16，新通路 | 1/1 | 16字 | 像素一致 |
| 相同8×8，关闭新通路 | 8/8 | 0（原直连） | 像素一致 |
| 514×3，stride1028，源/目的4 KiB边界不同 | 5/4 | 16字 | 独立读写切分正确 |
| 3×2，stride6，连续奇数宽 | 1/1 | 3字 | 跨行字拼接正确 |
| 8×3，stride24，非连续 | 3/3 | 0（原直连） | 保留逐行回退 |

第一项受控仿真155周期、关闭通路313周期；同seed，含前80周期写停顿与每突发19周期B响应延迟。这不是DDR实测加速比，也不是FPS。r_gap/w_gap只计存在读/写突发期间未握手的周期，包含测试端注入的空洞，不代表板上QoS占比。

RED记录：首次期望连续32字一突发，旧通路返回8个4字突发；新增错误RID1测试曾超时，修正后通过。独立审查无Critical/Important问题；小项建议见下方。完整日志压缩保存在[evidence/v3/copy](evidence/v3/copy/)，包括失败到通过和最终回归，保留原始编码/告警，不删失败证据。

## 如何复现，哪些工件不是正式版

仓库根目录执行：

```powershell
powershell -File scripts/test-v3-gpu.ps1
powershell -File scripts/test-v3-gpu.ps1 -Suite gpu.CopyStreamSpec -Generate
```

默认运行全部GPU测试；Suite只运行选定套件，不能把选定通过写成全部通过。Generate生成到`generated/verification/v3/copy/rtl/`，44个设计.v/.sv各一模块；CopyStreamEngine.sv SHA256为1df613ac50b672f74cb6780d06e7077e4770f8041d9ab1b8201a71a2b5a4134e。候选目录被Git忽略，可按入口重建。

关闭新通路生成时，在相同GPU限定编译环境运行：

```text
runMain gpu.GenerateEfinix2dGpu --legacy-copy --target-dir ../generated/verification/v3/copy/rtl-legacy --split-verilog
```

此轮不覆盖`generated/efinix_gpu/`、板级工程XML或实测位流。板级默认清单仍指向旧生成RTL；要编译V3候选，下一阶段必须把独立候选的完整filelist接入独立工程，不能直接运行旧板级构建脚本后声称得到新硬件。不要在未更新正式生成物时把本地源码候选当作已集成主线。

开启/关闭通路的独立生成均已成功，各44个设计文件、一模块一文件；关闭通路的Dense行为检查已在76项回归中通过。生成成功不代替Efinity综合/布局布线与正式源清单集成。

## 执行取舍与已知边界

1. 技能工作目录使用Windows原生Git Bash：WSL Git不能解析本机工作树绝对gitdir；若判断错误，只影响记录路径，需纠正。
2. 批准计划采用中文按天清单，没有工具要求的Task N标题：使用独立阶段brief/ledger，不改原计划；代价是人工核对日任务。
3. 新模块复用原AXI引擎的请求/数据接口而不是复制引擎：减少结构和资源改动；若接口不足需后续适配，当前不会因此获得多在途能力。
4. 资源/100MHz时序、下溢和FPS留到第5天：仿真正确不保证时序合格或板上净收益。
5. 复位测试是GPU与AXI对端共同复位，不承诺GPU单独复位能取消旧事务；单独复位可能需要整机复位恢复。
6. 错误RLAST测试仍提供全部约定拍数；永久遗漏R/B的坏从设备延续原引擎等待行为，可能阻塞至整机复位，不声称新增超时恢复。
7. SoftwareDriverSpec/PangoBringupSpec历史异常、A/B、背景恢复、条件实例尚未在此阶段解决；GPU定向通过不等于全SoC或整机通过，后续集成仍可能发现问题。

独立审查小项（暂缓）：补显式断言，逐周期核对反压期间WVALID/WDATA/WSTRB/WLAST与完成valid/tag/error保持不变。目前已经核对握手数据、最终像素、完成顺序/背压和原AXI引擎回归；未用“审查通过”代替这项补强。

Windows PowerShell5曾把WSL代理配置的stderr提示视为NativeCommandError；入口现在保存告警并根据退出码与实际测试结果判定。该环境提示不是GPU测试失败，原始日志仍保留。

## 下一步

按计划第5天建立独立板级候选，检查100MHz综合/时序和资源，再用相同R7正常固件测背景/HUD Copy、完整帧及下溢；没有净收益不能替换基线。随后第6～7天做物理双缓冲背景恢复及实测成本选型。暂无组员依赖，不需要为了功能线延迟Copy验证。
