# Ethernet Resource Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 保留网络功能、协议和 GPU 基线，释放片内逻辑与 RAM。
**Architecture:** 头部寄存器＋同步负载 RAM；单笔在途发送用可靠跨域邮箱，其余队列不变。
**Tech Stack:** Verilog、Icarus/Verilator、Efinity、现有官方 Sapphire 和 GPU。
**Spec:** docs/efinix_2d_gpu/net_resource_design_20261006.md

## Global Constraints

- 不修改 CPU 绘图、游戏、美术、厂商源码或 release；不写 Flash，不自动推送 main。
- 接口和协议不变；输入四项队列、CRC、会话、错误保护、busy 到完成语义不变。
- 每个新 .v 只有一个模块；使用现有隔离工作区，保留已有未提交实例原型。
- parser<=2000 XLR 且 RAM>0；两发送邮箱 RAM=0；整机 XLR<90%，全部最终 setup/hold 非负才允许上板。

## Review Focus

- 同步 RAM 读首字节和连续地址跨边界不丢字节，背压时保持输出。
- 坏 CRC/截断/超时不向 DMA 输出任何部分负载。
- GPU 或 GE 单端复位请求通过共同复位清空邮箱双方，不产生幽灵/重复发送。
- 原 TX busy 单笔限制与资源会话、IP 配置快照保持。
- 网络功能通过不代表 GPU 新前端时序或 512@60 已通过。

### Task 1: Parser RAM mapping

**Files:** asset_udp_rx.v; tb_asset_udp_rx.sv; scripts/test-net-resource-report.ps1.
**Interfaces:** 原 parser meta/payload valid/ready 接口不变。
- [x] 写资源报告验收脚本，运行合格旧基线报告，观察 FAIL parser 17210>2000/RAM=0。
- [x] 添加非周期字节、确定性单拍背压与复位清空测试，保留原错误与最大包测试；随机多拍 fuzz 延后，见结果文档。
- [x] 将头部与负载分离，同步 RAM 首字节预取/每次消费预取后继，RAM 内容无需复位。
- [x] 运行 parser 和真实 MAC 资源回归 PASS；r4 综合 parser780XLR/RAM1。

### Task 2: Single-outstanding TX mailboxes

**Files:** 新 net_async_mailbox.v/tb_net_async_mailbox.sv；net_control_bridge.v、efinix_asset_network_shared.v、项目 XML/SDC。
**Interfaces:** wr_clk/reset/data/valid/ready 与 rd_clk/reset/data/valid/ready；仅替换两组单笔在途 TX FIFO。
- [x] 写 mailbox 异步背压/快照/复位/重入测试；观察缺失实现导致失败。
- [x] 实现双向两级同步请求/确认、源/目标快照和共同复位，保持 valid 直到消费。
- [x] 接入两个发送通路与工程清单，增加 req/ack/data 的 8ns 明确约束，不改其余 FIFO；r4 实网表/工具约束展开/全部1492路径验证通过。
- [x] mailbox、全部网络控制/资源六项和顶层胶合回归 PASS。

### Task 3: Qualification and evidence

**Files:** README、net_resource_progress_20261006.md、证据压缩包。
**Interfaces:** 使用原 generated/efinix_gpu、原互动 BIN 和正式素材服务；候选 fresh 输出目录。
- [x] 完整 Efinity 编译，读取资源报告及最终每条 setup/hold；r4 完整资格检查 PASS。
- [x] 一次独立整轮改动审查；修正重要问题并回归，不纳入无关 GPU 原型 RED 测试。
- [x] 全部门槛通过后 JTAG 临时加载，实际两份资源/控制/遥测验证 PASS；未写 Flash。
- [x] 更新 README/结果文档，保留失败证据与实测限制，显式提交本轮文件但不推送；提交哈希以 Git 记录为准。
