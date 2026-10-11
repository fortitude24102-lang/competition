# 整帧命令前端：直接列表与AXI预取基础（2026-10-11）

本阶段从`e9b55c4`开始，仅实现并离线验证两个基础部件。**尚未接入生产GPU Top、没有生成新位流或加载新固件，没有新板测FPS；512仍未稳定60。**下一阶段才把这两个部件接到门铃、模板展开器和像素后端。

## 为什么改前端

现有逐Sprite提交由Sapphire构建命令、写APB字段、等待队列。历史紧凑APB实例候选虽然减少构建开销，却增加提交/等待成本，已拒绝默认接入。Copy提前调度在同场景获得明显收益，但512仍约43FPS；CRC小表减少封存尖峰，没有可信平均FPS提升。原始板测见[Copy提前调度](copy_ahead_20261011.md)和[CRC](replay_crc_20261011.md)，不是本前端的成绩。

本次采用直接生成16B列表、GPU突发取数的路线，目标是后续用一次门铃代替逐Sprite软件提交。按Ponytail复用已有12个模板、四字格式和`AxiReadEngine`，不引入新的CDMA库，不改CPU绘图、不改GPU100MHz、分辨率、游戏内容或Key/Alpha。

## 已实现的接口

### 软件：直接写调用者缓冲

`sw/efinix_gpu/include/gpu_instances.h`和`src/gpu_instances.c`新增：

```c
int gpu_instances_build_into(const bullet_state *state, uint32_t dst,
    int network, int glow, int manual, unsigned hud_height,
    unsigned capacity, gpu_instance *items, gpu_instance_stats *stats);
```

不先构建旧32B命令数组再压缩，也不增加生产片内BSS列表；`items`可由下一阶段调用者指定到DDR。`state/items/stats`必须不重叠，items有capacity项可写空间。该内部C API不检测任意指针有效性/别名。

- 四字格式、模板、裁剪和Alpha→Key顺序不变；旧`gpu_instances_build`保持R7语义，以薄包装复用新实现。
- `manual=1`支持当前游戏友方kind3，失活`age=UINT16_MAX`既不绘制core也不漏出glow；`manual=0`仍拒绝R7中的kind3。
- 容量/参数错误会清零所有统计，已写的部分数组**禁止发布**。无新增CPU存储发布驱动或所有权锁。

### 硬件：完整列表预取后再消费

`chisel/src/main/scala/gpu/FrameListReader.scala`提供请求`address/count`、四字Decoupled描述符、AXI AR/R、busy/fetching/done/error/fetchedBytes。

- 32bit INCR读、最多256拍、拆4KiB边界，复用原ID6读引擎。
- 默认1024项、16B对齐，合法地址窗口`[0x02d20000,0x02d28000)`；分为两个16KiB bank，单次请求不能跨bank，末地址可正好等于bank边界。
- 完整预取到16KiB `SyncReadMem`后才输出，避免晚到的AXI错误泄漏半份列表；ID/RESP/RLAST错误由原读引擎归并为AxiResponse。非法请求零AR、AddressRange；忙时不接新请求。
- 输出持有寄存器保证背压稳定；最后描述符握手才结束运输。**done不是后端执行完成，不允许据此立即PRESENT或改写正在使用的素材/模板。**
- `fetchedBytes`包含已接收但可能出错的拍，不表示资源有效。模块没有AXI超时；无响应时由下一阶段有界软件超时及整机复位策略处理。

该模块是独立运输部件，不验证每条模板/图像地址，不新增物理DDR端口，也没有成为当前Top的AXI主设备。下游仍须沿用模板验证器/命令验证器。完整预取规避的是未来描述符与像素互等的风险，不意味着共享DDR仲裁已经证明。

默认列表容量覆盖当前512 Sprite最多585项，不等于1024 Sprite游戏支持。后者可需1161项，必须修改硬件容量/bank契约、重新综合并协商软件容量，不能只改当前允许1..1024的参数。

## 验证与证据

完整GPU回归16个套件、81项全部通过（0失败/中止/忽略）。一次全阶段只读独立审查无Critical/Important；不是作者自审或板测。以下均为本阶段离线检查。

- 新软件检查：9,600帧（四档×600tick×本地/网口×glow开关），与真实`game_build`+HUD裁剪逐字段、顺序、统计相同，源状态不变；3个完整RGB565像素样本与真实golden renderer一致。
- 原12,000帧R7与真实驱动检查仍通过；新API包含失活友军glow、字面负坐标裁剪、容量canary、参数拒绝。
- 完整软件回归：18项C＋23项实际UDP/HTTP通过。
- Reader定向仿真1项通过，内部覆盖跨4KiB、跨256拍、1024项、第二bank精确末地址、AR/R/消费者停顿、非法请求、首尾RESP及尾拍ID错误、后续批/复位。复位测试在AXI已读完、描述符背压时执行；没有验证中途AXI局部复位，也没有注入错误RLAST（只验证正确RLAST及沿用的引擎检查逻辑）。没有将1项测试说成完整整机验证。
- 先写测试，缺API/缺Reader类的编译失败是本阶段RED；这证明目标接口尚未实现，不是既有产品症状的复现。

复现：

```powershell
wsl.exe bash scripts/test-v3-instances.sh
powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble
powershell -NoProfile -File scripts/test-v3-gpu.ps1 -Suite gpu.FrameListReaderSpec
powershell -NoProfile -File scripts/test-v3-gpu.ps1
```

GPU脚本还会先执行8个C damage套件、18,000帧golden检查；GPU过滤回归不是整SoC回归，历史两项SoC固件异常仍保留，不混称解决。

原始证据在[evidence目录](evidence/frame_list_foundation_20261011)，`SHA256SUMS`覆盖原始字节（Git属性禁止换行转换）：

| 文件 | 含义 |
|---|---|
| frame-list-baseline.log / frame-list-red.log / frame-list-green.log | 原C基线、新API缺失RED、完整实例GREEN |
| frame-list-software-regression.log | 18C＋23实际UDP/HTTP完整输出 |
| reader-red.log / reader-green.log | 缺Reader类的RED、1项真实AXI定向GREEN |
| reader-green.log.software.log | 定向检查前8个damage套件18,000帧 |
| gpu-task2-final.log / gpu-task2-final.log.software.log | 最终16套件81项及damage完整输出 |
| final-review.md / progress.md / task-3-validation.log | 独立审查、全部决策/任务记录、文档证据收尾检查 |

本阶段Git差异检查确认正式Top/生成器、板级源清单、`generated/efinix_gpu`、release以及CPU绘图/互动游戏/生产入口未变；没有生成位流或加载固件，不重新测当前板卡状态，也不把此前MENU恢复的遥测当作本阶段新证据。

审查的唯一次要项：接口文档未把done脉冲、error保持、busy覆盖消费阶段的持续时间集中列为信号契约。实现和测试正确，此阶段不扩展适配器；下一阶段编写轮询寄存器/门铃时补充明确契约，不能把Reader的done直接当成软件可轮询的sticky状态。[完整审查与全部未判定边界](evidence/frame_list_foundation_20261011/final-review.md)。

## 下一阶段验收门槛

1. 加默认关闭的0500门铃/能力位和批执行适配，旧位流不探测新地址；模板/epoch/列表所有权及CPU发布栅栏明确，按实际Sapphire缓存配置核对可见性，不能假定fence替代写回缓存维护。
2. 共用原DDR AR/R：列表预取后把读通路交还像素后端，扫描DMA仍保留优先权；错误丢弃、队列排空、tag回绕和PRESENT栅栏联验。部分执行错误不能通过旧路径重放。中途AXI复位必须联验响应端共同复位/排空，不能只复位Reader再误收旧ID6响应。
3. 同当前游戏生成完整像素、等价仿真；综合检查16KiB实际RAM映射、全SoC资源和100MHz时序，超额/无收益则回退。
4. 合格后仅JTAG同场景旧→新→旧，分别测列表构建/发布、等待、GPU busy、预取字节和帧工作分布。验证512的P95/最大、迟到/下溢/错误，再做长测，不能以平均小于16.67ms或HDMI60Hz冒充稳定60。

## 开源参考及边界

[RasteriCEr](https://github.com/ToNi3141/RasteriCEr)采用Display List；其README提出按显示行组织列表、硬件流控和scatter/gather DMA作为可能改进。借鉴“列表上传减少CPU负担”的思路，**不把作者的改进建议说成已交付的DMA实现**；该工程GPL-3.0，本阶段没有复制其源码。

[verilog-axi](https://github.com/alexforencich/verilog-axi)提供AXI DMA读流、可配置突发和整突发FIFO容量思路。这里沿用本工程已有读引擎，不宣称引入CDMA或已经实现读写重叠。独立完整列表RAM是当前保守选择，若集成测量显示预取成本抵消收益，再评估小FIFO流式方案及其仲裁/死锁证明。

[Chisel memory文档](https://www.chisel-lang.org/docs/explanations/memories)用于核对Vec掩码写和同步读；实际FPGA资源/时序必须综合测量，仿真不证明RAM一定被映射为期望的片内存储。
