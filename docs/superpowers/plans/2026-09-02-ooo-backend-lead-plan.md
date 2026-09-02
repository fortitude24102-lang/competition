# 负责人：双发射乱序后端与最终集成实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成双译码、寄存器重命名、ROB、双发射、LSQ、精确异常和最终 SoC 集成，并把成员2与成员3的独立模块汇总成可运行 CoreMark 的 `OoORv32Core`。

**Architecture:** 新乱序核与现有 `Rv32Core` 并存。后端每周期接收最多两条前端指令，使用64个物理寄存器、32项ROB、两个小型发射队列乱序执行，最终严格按程序顺序每周期提交最多两条。前端、MulDiv、DCache 通过冻结接口接入，后端独立开发期间全部使用 Mock。

**Tech Stack:** Chisel 7.7.0、Scala 2.13.18、ScalaTest、Verilator、RV32IM_Zicsr GCC、CoreMark v1.0

**Spec:** `docs/superpowers/specs/2026-09-02-dual-issue-ooo-contract-design.md`

## Global Constraints

- 只修改 `cpu/ooo/OooTypes.scala`、`cpu/ooo/backend/`、`cpu/ooo/OoORv32Core.scala`、对应测试和最终 SoC 集成文件。
- 不修改成员2的 `cpu/ooo/frontend/`，不修改成员3的 `cpu/ooo/exu/` 与 `cpu/ooo/cache/`。
- 保留现有 `Rv32Core` 和全部59项回归测试。
- 32项ROB、64个物理寄存器、双派发、双提交；MMIO和CSR必须串行化。
- 异常和中断只能在ROB头进入，Store只能提交后对外可见。
- 在成员模块合入前，后端测试必须使用 Mock 独立通过。
- 不在本阶段直接实现 AXI；保留 `CoreBusIO` 边界。

## 你负责什么

| 模块 | 内容 | 主要输入 | 主要输出 |
|---|---|---|---|
| `OooTypes` | 三人唯一共享 Bundle 与常量 | 无 | 所有人引用的固定类型 |
| `Decode2` | 同时译码两条 RV32IM_Zicsr 指令 | `FetchGroup` | 两个 `DecodedUop` |
| `RenameMap` | 架构寄存器到物理寄存器映射 | 两条译码指令、提交释放、恢复 | 新旧物理寄存器号 |
| `PhysicalRegFile` | 64×32、4读2写寄存器堆 | 4个读地址、2个写端口 | 4个操作数 |
| `ReorderBuffer` | 32项顺序退休与精确异常 | 两条派发、执行完成、Store完成 | 两条提交、恢复请求 |
| `IssueQueueA/B` | 就绪跟踪和双通道选择 | 微操作、写回tag | 最多两条执行请求 |
| `LoadStoreQueue` | 访存顺序、Store转发、MMIO旁路 | 访存微操作、DCache响应、提交 | DCache/MMIO请求、Load写回 |
| `OooBackend` | 连接上述模块 | 前端指令、执行/Cache结果 | 重定向、预测更新、提交 |
| `OoORv32Core` | 实例化三人模块 | CoreBus、中断 | 双提交、陷阱、halt |
| SoC集成 | 在旧核和新核之间选择 | 构造参数 | 保持外设和视频模块不变 |

---

### Task 1: 建立契约提交和三条分支基线

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/OooTypes.scala`
- Test: `chisel/src/test/scala/cpu/ooo/OooTypesSpec.scala`

**Interfaces:**
- Consumes: 共用接口设计文档中所有 Bundle 定义。
- Produces: `OooConfig`、`FetchGroup`、`FrontendRedirect`、`BranchPredictUpdate`、`MulDivRequest/Response`、`CacheRequest/Response`。

- [ ] **Step 1:** 按设计文档逐字建立共享类型，不能改字段名或位宽。
- [ ] **Step 2:** 写 Elaborate 测试，实例化一个只把每种 Bundle 接到 IO 的 `TypesHarness`。
- [ ] **Step 3:** 运行：

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.OooTypesSpec'"
```

预期：测试通过，Chisel 没有未连接端口。

- [ ] **Step 4:** 提交 `feat(ooo): freeze shared cpu interfaces`，记录提交哈希；三条开发分支都从这个哈希建立。

### Task 2: 双译码与 RV32M 控制信息

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/DecodedUop.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/Decode2.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/Decode2Spec.scala`

**Interfaces:**
- Consumes: `Decoupled[FetchGroup]`。
- Produces: `Decoupled[Vec[DecodedUop]]`，槽0年老，槽1年轻。

`DecodedUop` 必须保存 `pc/inst/fetchError/predictedTaken/predictedTarget/predictorHistory/rs1/rs2/rd/immediate/control/mulDivOp`。普通 RV32I 复用现有 `Decoder`；当 `opcode=0110011` 且 `funct7=0000001` 时产生八种 `MulDivOp`。

- [ ] **Step 1:** 写失败测试：同周期输入 `addi x1,x0,1` 和 `mul x2,x1,x1`，断言两个槽都合法且第二槽是 `Mul`。
- [ ] **Step 2:** 运行 `testOnly cpu.ooo.backend.Decode2Spec`，确认因为模块不存在而失败。
- [ ] **Step 3:** 用两个现有 `Decoder` 实例完成双译码，只在 `Decode2` 外层补 RV32M 识别，不修改旧 `Decoder.scala`。
- [ ] **Step 4:** 增加非法 `funct3`、Fetch fault、槽0无效时槽1不得单独前进的测试。
- [ ] **Step 5:** 专项测试通过后提交 `feat(ooo): add dual rv32im decode`。

### Task 3: 物理寄存器、RAT和空闲表

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/PhysicalRegFile.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/RenameMap.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/FreeList.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/RenameSpec.scala`

**Interfaces:**
- Consumes: 两条指令的 `rs1/rs2/rd/regWrite`、两个提交释放物理寄存器、恢复请求、两个写回端口。
- Produces: 每条指令的两个源物理号、新目的物理号、旧目的物理号和源就绪状态。

- [ ] **Step 1:** 测试初始映射 `xN -> pN`，空闲队列初始只包含 `p32..p63`。
- [ ] **Step 2:** 测试同组 RAW：槽0写 `x5`、槽1读 `x5` 时，槽1必须读槽0刚分配的新物理号。
- [ ] **Step 3:** 测试同组 WAW：两槽都写 `x5`，槽1旧物理号必须是槽0新物理号。
- [ ] **Step 4:** 实现双分配和双释放。`x0` 永远映射到 `p0`，不得分配新物理寄存器。
- [ ] **Step 5:** `PhysicalRegFile` 使用寄存器向量、4个同步流水读地址寄存器和2个写端口；同周期写后读必须旁路最新值。
- [ ] **Step 6:** 测试分支检查点恢复 RAT 和空闲队列头指针。
- [ ] **Step 7:** 运行 `testOnly cpu.ooo.backend.RenameSpec` 并提交 `feat(ooo): add physical register renaming`。

### Task 4: 32项 ROB 和双提交

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/ReorderBuffer.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/ReorderBufferSpec.scala`

**Interfaces:**
- Consumes: 最多两条派发、两个写回完成、Store完成、分支恢复、异常信息。
- Produces: 两个ROB索引、最多两条提交、提交释放的旧物理号、精确陷阱或全局恢复。

每个 ROB entry 保存：valid、complete、pc、inst、rd、newPhys、oldPhys、regWrite、store、csr、fence、exceptionValid、exceptionCause、exceptionValue、预测元数据。

- [ ] **Step 1:** 写测试：ROB空时同时分配两个索引0和1，tail前进2。
- [ ] **Step 2:** 写测试：索引1先完成、索引0未完成时不能提交。
- [ ] **Step 3:** 写测试：0和1均完成且无串行条件时同周期提交两条。
- [ ] **Step 4:** 实现环形 head/tail/count，使用额外计数器区分满和空。
- [ ] **Step 5:** 写测试：槽0是异常时不提交槽0和槽1，输出槽0精确异常；槽1异常时允许槽0先提交。
- [ ] **Step 6:** 写测试：Store只有 `storeCompleted=true` 才能提交；CSR/Fence在槽0提交时禁止同周期槽1提交。
- [ ] **Step 7:** 测试通过后提交 `feat(ooo): add precise dual-commit reorder buffer`。

### Task 5: 两个小型发射队列与执行通道A

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/IssueEntry.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/IssueQueue.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/IntegerLane.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/IssueQueueSpec.scala`

**Interfaces:**
- Consumes: 最多两条已重命名微操作、两个写回tag、flush、执行端 ready。
- Produces: Queue A 一条 ALU/Branch/CSR 请求，Queue B 一条 ALU/MulDiv/Memory 请求。

- [ ] **Step 1:** 测试操作数未就绪的项不会发射，匹配写回tag后下一周期可发射。
- [ ] **Step 2:** 测试队列选择最老就绪项，不允许年轻指令长期饿死年老指令。
- [ ] **Step 3:** 实现两个8项队列；普通ALU派到空位更多的一边，Branch/CSR固定A，MulDiv/Memory固定B。
- [ ] **Step 4:** 把 wakeup、select 和寄存器读取分级，禁止在同一周期形成 `writeback -> compare -> priority -> PRF mux -> ALU` 长路径。
- [ ] **Step 5:** `IntegerLane` 复用现有 `Execute` 的运算定义，输出结果、分支真实方向和目标。
- [ ] **Step 6:** 测试 flush 精确删除分支之后的项，保留更老项。
- [ ] **Step 7:** 测试通过后提交 `feat(ooo): add split issue queues`。

### Task 6: LSQ、Store转发和MMIO串行化

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/LoadStoreQueue.scala`
- Create: `chisel/src/main/scala/cpu/ooo/backend/MemoryRouter.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/LoadStoreQueueSpec.scala`

**Interfaces:**
- Consumes: Lane B 访存地址/数据、ROB年龄、提交Store许可、`CacheResponse`、MMIO CoreBus响应。
- Produces: `CacheRequest`、MMIO CoreBus请求、Load写回、Store完成。

- [ ] **Step 1:** 测试 Load 在更老 Store 地址未知时等待。
- [ ] **Step 2:** 测试同地址更老 Store 已知时，从最年轻的匹配 Store 转发字节。
- [ ] **Step 3:** 测试普通 Store 在 ROB 头允许后才产生 DCache 请求。
- [ ] **Step 4:** 实现8项 Load Queue、8项 Store Queue；第一版不做内存依赖预测。
- [ ] **Step 5:** 地址落入 `0x1000_0000` 外设区或计时器区时绕过 DCache，并要求该微操作位于ROB头且其他访存已经排空。
- [ ] **Step 6:** 使用现有 `LoadStoreUnit` 完成 byte/half/word 对齐、写掩码和符号扩展。
- [ ] **Step 7:** 覆盖误对齐、总线错误和反压测试，提交 `feat(ooo): add ordered load store queue`。

### Task 7: 后端闭环和精确恢复

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/OooBackend.scala`
- Create: `chisel/src/test/scala/cpu/ooo/backend/FakeFrontend.scala`
- Create: `chisel/src/test/scala/cpu/ooo/backend/FakeMulDiv.scala`
- Create: `chisel/src/test/scala/cpu/ooo/backend/FakeDCache.scala`
- Test: `chisel/src/test/scala/cpu/ooo/backend/OooBackendSpec.scala`

**Interfaces:**
- Consumes: Fake Frontend 指令、Fake MulDiv/DCache响应、中断。
- Produces: Frontend redirect/update、双提交 trace、精确 trap。

- [ ] **Step 1:** 用 FakeFrontend 注入独立ALU程序，验证至少出现一次同周期双提交。
- [ ] **Step 2:** 注入 RAW、WAW、WAR 组合，核对最终架构寄存器结果。
- [ ] **Step 3:** 注入预测错误分支，验证年轻指令不提交、RAT恢复、正确目标重新取指。
- [ ] **Step 4:** 注入非法指令、ECALL、EBREAK、访存错误和计时器中断，验证精确PC和cause。
- [ ] **Step 5:** CSR、MRET、Fence 和 MMIO 设为串行微操作，只能在ROB头执行。
- [ ] **Step 6:** 专项测试连续运行两次并提交 `feat(ooo): close precise out-of-order backend`。

### Task 8: 与成员3模块集成

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/OoORv32Core.scala`
- Test: `chisel/src/test/scala/cpu/ooo/OoOCoreRv32mSpec.scala`
- Test: `chisel/src/test/scala/cpu/ooo/OoOCoreMemorySpec.scala`

**Interfaces:**
- Consumes: 成员3验收通过的 `MulDivUnit` 和 `DCache`。
- Produces: 能运行 RV32M 和缓存访存程序的半集成 CPU。

- [ ] **Step 1:** 先查看成员3验收报告和分支 diff，只合入其所有权目录。
- [ ] **Step 2:** 删除测试里的 FakeMulDiv/FakeDCache 实例连接，源文件可以保留供后端单测使用。
- [ ] **Step 3:** 运行 RV32M 指令程序集，覆盖8种运算和除零边界。
- [ ] **Step 4:** 运行 Load/Store、脏行替换和总线错误程序集。
- [ ] **Step 5:** 确认成员3专项测试仍通过，提交 `feat(ooo): integrate muldiv and data cache`。

### Task 9: 与成员2前端和SoC集成

**Files:**
- Modify: `chisel/src/main/scala/cpu/ooo/OoORv32Core.scala`
- Modify: `chisel/src/main/scala/soc/SoCTop.scala`
- Modify: `chisel/src/main/scala/Generate.scala`
- Test: `chisel/src/test/scala/cpu/ooo/OoOCoreProgramSpec.scala`
- Test: `chisel/src/test/scala/soc/OooSoCTopSpec.scala`

**Interfaces:**
- Consumes: 成员2验收通过的 `OooFrontend`。
- Produces: 完整双发射乱序 SoC 和独立 RTL 生成入口。

- [ ] **Step 1:** 查看成员2验收报告和 diff，只合入 `frontend/` 所有权目录。
- [ ] **Step 2:** 连接 redirect、predictorUpdate 和 imem；halt后禁止新取指。
- [ ] **Step 3:** 给 `SoCTop` 增加构造参数 `useOooCore: Boolean = false`，默认仍使用旧核，避免破坏当前Demo。
- [ ] **Step 4:** 新增 `Generate ooo-soc` 和 `Generate ooo-core`，不要改变现有生成命令。
- [ ] **Step 5:** 跑 RV32I、RV32M、CSR、异常、中断和 SoC UART 软件测试。
- [ ] **Step 6:** 生成 RTL 并执行 Verilator lint，提交 `feat(soc): integrate dual-issue out-of-order core`。

### Task 10: 性能计数器、CoreMark和150 MHz验收

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/backend/PerformanceCounters.scala`
- Modify: `sw/coremark/core_portme.c`
- Create: `scripts/run-ooo-coremark-baseline.ps1`
- Create: `generated/reports/ooo/integration-acceptance.txt`

**Interfaces:**
- Consumes: cycle、commit0/1、branch、mispredict、I/D miss、ROB full、issue0/1事件。
- Produces: `mcycle/minstret` 和仿真报告中的 IPC、miss率、预测准确率。

- [ ] **Step 1:** 增加64位 `mcycle/minstret`，只有有效提交才增加 minstret；双提交加2。
- [ ] **Step 2:** 增加自定义只读计数器：双提交周期、分支总数、预测失败、I$ miss、D$ miss、ROB满周期。
- [ ] **Step 3:** CoreMark 改用 `-march=rv32im_zicsr -mabi=ilp32 -O2`，官方算法源码保持哈希不变。
- [ ] **Step 4:** 运行至少10轮 RTL CoreMark，要求三组标准CRC正确，计算 `IPC=minstret/mcycle`。
- [ ] **Step 5:** 运行全部旧核和新核测试；旧核59项必须继续全过。
- [ ] **Step 6:** 第一次 PDS 只检查 `OoORv32Core` OOC 的6.667 ns约束；记录WNS、最差路径、LUT/FF/BRAM/DSP。
- [ ] **Step 7:** 若WNS小于0，只对报告中的真实最差路径加流水寄存；每次改动必须重跑相应专项测试。
- [ ] **Step 8:** 报告至少包含 CoreMark/MHz、IPC、预测准确率、I/D命中率和资源，提交 `test(ooo): record integrated performance baseline`。

## 负责人独立验收命令

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.backend.*'"
git diff --check
```

在合入组员代码之前，这两个命令必须通过。未通过时不得要求组员修改其已经验收成功的模块来掩盖后端问题。
