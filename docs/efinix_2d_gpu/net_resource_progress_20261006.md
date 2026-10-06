# 以太网资源压缩（2026-10-06）

已完成[资源压缩计划](net_resource_plan_20261006.md)的实现与短窗板测，不是替换 CPU、改游戏或完成 512@60。正式 GPU 生成物、冻结互动 BIN、素材、PC 仅资源/输入/遥测中继的职责均不变。未写 Flash，release 不变；独立实例前端仍默认关闭，未纳入本候选。

## 改动及实测结果

| 项目 | 合格旧基线 integration-r3 | 本轮最终 net_resource-r4 |
|---|---:|---:|
| 整机 XLR / 60,800 | 58,503（96.22%） | 44,595（73.35%） |
| RAM / 256 | 217（84.77%） | 142（55.47%） |
| DSP / 160 | 20 | 20 |
| 网络 XLR / RAM | 27,770 / 109 | 14,213 / 34 |
| DATA 解析器 XLR / RAM | 17,210 / 0 | 780 / 1 |

净释放 13,908 XLR、75 RAM；器件剩余 16,205 XLR、114 RAM。这是资源与布局余量，不是新增 Sprite/FPS 实测，也不代表实例前端时序问题已解决。

- `asset_udp_rx.v`：32 B 头部寄存器＋1024 B 同步负载 RAM。一个共享读地址与读使能，元数据握手预取首字节，消费时预取后继，背压保持输出；整包 CRC/会话/长度合法后才交付 DMA，无额外每字节气泡。
- 新 `net_async_mailbox.v`：单模块，双向两级同步请求/确认，源与目标快照，valid 保持到消费；两域共同异步复位、各自同步释放。仅替换现有 busy 限制为单笔在途的资源 GET 与管理 TX，不改变接收四项队列、资源元数据/负载/完成 FIFO。
- `test-net-resource-report.ps1`：实测资源门槛＋实际综合 FF/SDC 覆盖检查。`-RequireRouted` 额外核对工具展开的约束、全部 1488 数据路径与两组 req/ack 布线延迟 ≤8 ns、全部最终 setup/hold。

## 失败与修正，不能跳过的门槛

1. 初轮功能检查发现最大负载第 992 字节未知值。原因是先截断接收下标再相减，数组下标表达式扩宽后越界。改为完整 11-bit 相减再明确截为 10-bit；将测试比较改为 case inequality，避免 X 被当作通过。已复现 RED，再观察 GREEN。
2. r1 虽有 RAM 属性，但两个不同读表达式被推断为不支持的多读端口，8192 个负载位仍是 FF。整机 60,805 XLR，超出容量，未上板。统一成一个读表达式后 r2 映射到 1 RAM。
3. 审查发现 SDC 的 `rd_snapshot` 目的集合匹配 0 FF。实际 1488 位被别名为 packet/length/local_ip/peer_ip/descriptor。实网表检查先失败，再收紧为这些实际数据 FF；不把 descriptor_valid 纳入数据约束。r3 在综合阶段主动中止，避免使用过宽的中间约束；未上板。
4. r2 完整编译 exit0，最终普通 setup/hold 最小 0.147/0.004 ns；但原编译的数据目的约束无效，**不作为上板资格**。修正后重开 fresh r4，通过实际约束展开、全路径延迟与最终 STA 门槛才上板。

六项网络 RTL 回归（邮箱、管理 RX/TX、仲裁、真实 MAC、DATA 解析器、真实 MAC 资源包）通过，负责人实际 APB/MAC/HELLO/会话/GE reset 胶合检查通过。r2 既有布线用工具独立报出数据最长 0.934 ns、请求 0.583 ns、确认 0.848 ns，已证实报告入口有效；不能拿它替代 r4 的资格。

## 复现入口

在仓库根目录运行：

```powershell
powershell -File scripts/test-v3-control-rtl.ps1
powershell -File scripts/test-v3-integration.ps1 -RtlOnly -IcarusRoot C:/iverilog
powershell -File scripts/test-efinix-board.ps1 -OutputDirectory D:/efinity_builds/net_resource_20261006_r4 -Flow compile
```

在候选构建目录完成编译后运行 Efinity `efx_run.bat --flow sta_tclsh --tcl_script <仓库绝对路径>/scripts/report-net-mailbox-cdc.tcl efinix_2d_gpu.xml`，随后在仓库运行 `powershell -File scripts/test-net-resource-report.ps1 -BuildDirectory D:/efinity_builds/net_resource_20261006_r4 -RequireRouted`。普通 exit0 或不带 `-RequireRouted` 的资源检查不是上板资格。

## 开源借鉴与兼容边界

参考 [LiteEth RAM 数据/元数据分离](https://github.com/enjoy-digital/liteeth/blob/master/liteeth/mac/sram.py)、[verilog-axis 同步 RAM/整帧提交](https://github.com/alexforencich/verilog-axis/blob/master/rtl/axis_fifo.v)、[PULP 两相稳定快照 CDC](https://github.com/pulp-platform/common_cells/blob/master/src/cc_cdc_2phase.sv)。未整库复制、未引入新依赖；RAM 推断按已安装 Efinity 官方属性/同步端口规则实现。verilog-axis 的后继 Taxi 许可并非 MIT，不作为无审查直接复制来源。

保留输入/元数据队列，而非进一步共享全包池，代价是仍有 26 块浅 FIFO RAM；现有功能和突发容忍比额外挤资源更优先。Windows linked worktree 用原生 Git/手动台账，未用无法解析 Windows gitdir 的 WSL Git。

## 审查范围与未覆盖项

一次独立审查完成，无 Critical；两项 Important（RAM 推断、空 CDC 目的集合）进入修正和 RED→GREEN 检查，不用第二轮重复审查代替测试。

- 资源/布线/实际约束应用由负责人测量，不能只靠审查或源代码外观；资格失败时不烧录。
- 保留共同复位契约，不宣称物理 MTBF、任意停钟、每一复位相位或 recovery/removal 已穷尽验证；不适用独立域单边保留事务的热复位。
- 错包/超时/背压是代表性回归，不是所有 malformed 序列或同拍提交/完成组合的穷举。
- 板上资源、输入、遥测需实际检验；短测不代表 30 分钟耐久/满线速吞吐。
- 无关 GPU 原型两个 APB 期待仍 RED，历史 SoC 固件两项异常保留，不修 CPU、不借本轮网络通过宣称 512@60。
- 不审查或改写厂商内部、无关脏文件和旧 release；固件/候选哈希用于明确资格边界，不等于厂商行为穷尽证明。

延后的小项：邮箱复位覆盖已捕获待消费阶段，但未扫请求/确认传播的所有相位；解析器新增背压为每第三字节停一拍，未做随机多拍 fuzz。以上是未覆盖成本，不写成已完成测试。

## 最终资格与上板结果

最终 r4 的资源同上表，map/interface/pnr/pgm 全部通过。全部 16 个最终 setup/hold 关系非负，最小 setup0.147ns、hold0.004ns；100MHz核心setup0.974ns。工具展开的三组8ns约束覆盖实际FF：数据1488对、请求2对、确认2对。所有布线路径实报最长分别0.934/0.583/0.848ns。布局阶段曾有DDR hold负值，但最终修复后为正，不把预布局报告当最终资格，也不删旧警告。继承的未匹配旧JTAG/部分未用端口约束警告保留，不宣称全部外设引脚已穷尽约束。

位流 `D:/efinity_builds/net_resource_20261006_r4/outflow/efinix_2d_gpu.bit` SHA256：`8c9e4ef648d83717cf3c9782bc48412f1b744b157ab83db990c7708c82ba9f77`。
原互动 BIN `generated/verification/v3/integration/gpu_demo.bin` SHA256：`b55d038d4d7e7973e9de2f1960087052e07bf52c4b162c3e5e7738a001562483`。
原五档诊断 BIN SHA256：`3ff9c53396ed8df8b83aa293071d7e50c9646c3e2624e15afa2529c9d1f0ea37`，与第9天相同，不重编或改游戏。

JTAG 临时加载后，背景101（1036800B）、图集102（3104B）均result0/retry0，纹理Cache加载成功、network1。真实 HTTP→UDP→FPGA→Sapphire 右移/上移改变x/y，停心跳后keys0/age−1；实际HELLO ACK，非模拟网页数据6010 FPS×100、窗口下溢/错误/呈现迟到0。CPU慢回放未重跑，新会话CPU成绩未测/不可用，保留正常固件现有的CPU/GPU屏幕对比功能，不改CPU渲染基础配置。

五档 seed7，预热30帧后每档300帧正常提交，再300帧带探针；960×540 RGB565双缓冲、100MHz GPU、1080p60 HDMI。下表只取probe0，不将带探针的成本与普通固件混用。每档下溢/硬件错误0，诊断完整结束result0/hardware0。

| 请求档 | 可见范围 | FPS | 工作平均/P95/最大（us） | 工作超预算/呈现迟到 | 严格短窗合格 |
|---|---|---:|---|---|---|
|32|30～32|60.1|9465/9579/10871|0/0|是|
|64|60～64|60.1|10223/10387/11734|0/0|是|
|128|123～128|60.1|11311/11421/12718|0/0|是|
|256|248～256|60.1|13462/13741/14862|0/0|是|
|512|501～512|30.0|17353/17629/19165|300/300|否|

512旧基线工作平均17358us，本轮17353us，差异仅5us，**不是有意义的性能提升**。构建3188us、硬件busy11600us也基本不变。本轮完成的是网络资源压缩，不宣称GPU瓶颈已经解决；余量为后续前端关键路径/批量提交优化提供空间。既有完整背景Copy仍是大项，不扩大Cache或同时塞入整套CDMA。

收尾仅加载原互动BIN，恢复资源result0/retry0、GPU60.1FPS、under/miss0；真实HELLO/ACK重新建立，最终遥测新鲜、build=20261005、epoch=00030001。网关累计软件拒收计数159，FPGA遥测control_drop_delta仍0；网关包含同build固件重启后的旧序号/会话过滤，未逐包归因，**不把网关拒收称作线上零丢包**。恢复后没有JTAG/OpenOCD烧录进程，PC服务保留，板卡继续运行。

原始日志、资源/STA/全部CDC路径及失败报告见[证据包](evidence/net-resource-20261006/README.md)。仅短测，未完成30分钟耐久或全部复位相位验收。
