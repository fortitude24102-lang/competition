# 成员2：双取指、分支预测与 I-Cache 新手实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 独立完成每周期最多输出两条指令的前端，包括2路 I-Cache、BTB、GShare、RAS、重定向冲刷和 CoreBus refill，并通过不依赖乱序后端的专项验收。

**Architecture:** Frontend 接收一个取指PC，从 I-Cache 读取32字节 Cache Line，选择其中连续两条32位指令，查询分支预测器后通过 `Decoupled[FetchGroup]` 输出。预测错误时负责人只给出新PC和恢复历史，Frontend 必须丢掉旧路径的排队指令和迟到响应。

**Tech Stack:** Chisel 7.7.0、Scala 2.13.18、ScalaTest、Verilator、现有 `CoreBusIO`

**Spec:** `docs/superpowers/specs/2026-09-02-dual-issue-ooo-contract-design.md`

## Global Constraints

- 只能修改 `chisel/src/main/scala/cpu/ooo/frontend/` 和对应 `src/test/scala/cpu/ooo/frontend/`。
- `OooTypes.scala` 是负责人冻结的接口，只能引用，不能修改或复制一份。
- 不修改 `Rv32Core.scala`、`SoCTop.scala`、后端、MulDiv、DCache。
- I-Cache 固定16KB、2路、32字节一行、256组；第一版只允许一个 miss 在途。
- BTB固定256项、2路；GShare固定1024项；RAS固定8项。
- 所有 Decoupled 接口都必须正确处理反压。
- 不调用PDS综合；独立验收只做测试、RTL生成和Verilator lint。

## 先理解四个词

1. `valid`：发送方说“我现在给出的数据是真的”。
2. `ready`：接收方说“我这一拍能收”。
3. `fire`：`valid && ready`，只有 fire 才算真正传输一次。
4. 反压：接收方把 ready 拉低。此时发送方必须保持 valid 和 bits 不变，不能偷偷换下一条数据。

如果测试里出现“数据重复、丢失或顺序错”，先检查是不是没有遵守这四条。

## 你负责什么

| 模块 | 作用 | 输入 | 输出 |
|---|---|---|---|
| `BranchTargetBuffer` | 记住见过的分支地址和目标 | 两个查询PC、分支更新 | 是否命中、目标、分支类型 |
| `GSharePredictor` | 预测条件分支跳不跳 | 分支PC、全局历史、实际结果 | taken预测、更新后的2-bit计数器 |
| `ReturnAddressStack` | 预测函数返回地址 | call/return更新 | 栈顶返回地址 |
| `BranchPredictor` | 组合BTB/GShare/RAS | 取指组基址、更新、恢复 | `BranchPrediction` |
| `ICache` | 把慢CoreBus变成整行快速取指 | `ICacheRequest`、CoreBus响应 | `ICacheResponse`、refill请求 |
| `OooFrontend` | 维护PC、取两条指令、排队、冲刷 | redirect、预测更新、imem响应 | `FetchGroup`、imem请求 |

## 固定模块端口

```scala
class BranchPredictor extends Module {
  val io = IO(new Bundle {
    val basePc = Input(UInt(32.W))
    val prediction = Output(new BranchPrediction)
    val update = Flipped(Valid(new BranchPredictUpdate))
    val restoreHistory = Flipped(Valid(UInt(OooConfig.GlobalHistoryWidth.W)))
  })
}

class ICache extends Module {
  val io = IO(new Bundle {
    val cpuReq = Flipped(Decoupled(new ICacheRequest))
    val cpuResp = Decoupled(new ICacheResponse)
    val mem = new CoreBusIO
    val busy = Output(Bool())
  })
}

class OooFrontend(resetVector: BigInt = 0) extends Module {
  val io = IO(new Bundle {
    val out = Decoupled(new FetchGroup)
    val redirect = Flipped(Valid(new FrontendRedirect))
    val predictorUpdate = Flipped(Valid(new BranchPredictUpdate))
    val halt = Input(Bool())
    val imem = new CoreBusIO
  })
}
```

端口字段不允许自行改名。需要新信号时先把原因和一个失败测试交给负责人，由负责人决定是否改共享契约。

---

### Task 1: 建立最小测试壳和 CoreBus 内存模型

**Files:**
- Create: `chisel/src/test/scala/cpu/ooo/frontend/FrontendTestMemory.scala`
- Create: `chisel/src/test/scala/cpu/ooo/frontend/FrontendInterfaceSpec.scala`

**Interfaces:**
- Consumes: `CoreBusIO` 请求。
- Produces: 延迟可配置的32位读响应；不支持写请求，写请求返回 `error=true`。

- [ ] **Step 1:** 从现有 `cpu/TestMemory.scala` 复制握手方法的写法，但新类只服务本目录测试，不修改原文件。
- [ ] **Step 2:** 内存内容使用 `Map[BigInt, BigInt]`，地址不存在时返回0；响应延迟参数只允许1、2或4周期。
- [ ] **Step 3:** 写接口测试，确认共享 `FetchGroup`、`ICacheRequest/Response` 可以 Elaborate。
- [ ] **Step 4:** 运行：

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.frontend.FrontendInterfaceSpec'"
```

预期：测试通过。若提示找不到 `OooTypes`，说明分支不是从负责人给出的契约提交建立，立即停止并重新建分支。

- [ ] **Step 5:** 提交 `test(frontend): add isolated memory model`。

### Task 2: GShare 两位计数器

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/GSharePredictor.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/GSharePredictorSpec.scala`

**Interfaces:**
- Consumes: 查询PC、10位全局历史、条件分支实际taken更新。
- Produces: 查询表项最高位，1表示预测taken，0表示not-taken。

索引公式固定为：`pc(11,2) ^ history`。计数器含义固定为 `00强不跳、01弱不跳、10弱跳、11强跳`，复位值全部为 `01`。

- [ ] **Step 1:** 写失败测试：同一个索引连续两次 taken 更新后，预测从 false 变为 true。
- [ ] **Step 2:** 写失败测试：`11` 再加不溢出，`00` 再减不下溢。
- [ ] **Step 3:** 实现1024个2-bit计数器和10位历史寄存器；更新使用请求里携带的旧 history，而不是当前 history。
- [ ] **Step 4:** 写恢复测试：`restore.valid` 后当前历史等于 `restore.bits`。
- [ ] **Step 5:** 运行 `testOnly cpu.ooo.frontend.GSharePredictorSpec`，全部通过后提交 `feat(frontend): add gshare predictor`。

### Task 3: 两路 BTB 和8项 RAS

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/BranchTargetBuffer.scala`
- Create: `chisel/src/main/scala/cpu/ooo/frontend/ReturnAddressStack.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/BranchTargetBufferSpec.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/ReturnAddressStackSpec.scala`

**Interfaces:**
- Consumes: `basePc`与`basePc+4`查询、`BranchPredictUpdate`。
- Produces: 两个PC的命中、目标、conditional/call/ret类型；RAS栈顶。

- [ ] **Step 1:** BTB使用128组×2路。有效位、tag、target和3个类型位分别保存，不能把整个结构做成一个超宽组合查找表。
- [ ] **Step 2:** 测试空BTB不命中；更新PC `0x100` 后只有对应PC命中并返回目标。
- [ ] **Step 3:** 测试同组第三个不同tag写入时只替换LRU选中的一路。
- [ ] **Step 4:** RAS在 call 时压入 `pc+4`，ret 时弹出；空栈ret不得给出有效预测；深度超过8时覆盖最老项。
- [ ] **Step 5:** 分别运行两个Spec，通过后提交 `feat(frontend): add btb and return stack`。

### Task 4: 组合分支预测器

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/BranchPredictor.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/BranchPredictorSpec.scala`

**Interfaces:**
- Consumes: `basePc`、分支更新、历史恢复。
- Produces: 一项 `BranchPrediction`，包含slot、taken、target和预测前history。

- [ ] **Step 1:** 查询 `basePc` 和 `basePc+4`，若两者都命中，必须选择 slot0。
- [ ] **Step 2:** 无条件jump和return只要BTB命中就taken；条件分支由GShare决定。
- [ ] **Step 3:** ret目标优先使用RAS栈顶；RAS无效时本次ret预测无效而不是跳到0。
- [ ] **Step 4:** 预测条件分支后投机更新当前history；重定向时用 `restoredHistory` 覆盖投机历史。
- [ ] **Step 5:** 测试 slot0 taken时以后端规则取消slot1，slot1 taken时允许两槽都有效。
- [ ] **Step 6:** 运行 `testOnly cpu.ooo.frontend.BranchPredictorSpec` 并提交 `feat(frontend): compose branch predictor`。

### Task 5: 16KB 两路 I-Cache

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/ICache.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/ICacheSpec.scala`

**Interfaces:**
- Consumes: `Decoupled[ICacheRequest]`、CoreBus 32位响应。
- Produces: `Decoupled[ICacheResponse]`、CoreBus 读请求、busy。

地址拆分固定为：低5位是行内偏移，`addr(12,5)` 是256组索引，`addr(31,13)` 是tag。每行8个32位字，共256位。

- [ ] **Step 1:** 写 miss 测试：第一次访问地址0，Cache必须依次发出地址0、4、8、12、16、20、24、28共8次CoreBus读。
- [ ] **Step 2:** 写 refill 完成测试：`cpuResp.lineAddress=0`，`lineData(31,0)`等于地址0的字，`lineData(63,32)`等于地址4的字。
- [ ] **Step 3:** 写 hit 测试：第二次访问同一行不得产生任何CoreBus请求。
- [ ] **Step 4:** 实现两路 tag/valid/data/LRU；复位只清valid和LRU，不清数据RAM。
- [ ] **Step 5:** 写冲突替换测试：三个拥有相同index、不同tag的地址依次访问，检查LRU替换。
- [ ] **Step 6:** 写 epoch 测试：响应必须原样返回请求epoch。
- [ ] **Step 7:** 写反压测试：`cpuResp.ready=false` 连续5拍，响应全部字段保持不变。
- [ ] **Step 8:** 写总线错误测试：refill任一字返回error时整行无效，CPU响应error且不能形成hit。
- [ ] **Step 9:** 运行 `testOnly cpu.ooo.frontend.ICacheSpec` 并提交 `feat(frontend): add two-way instruction cache`。

### Task 6: 双取指 Frontend 与重定向

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/OooFrontend.scala`
- Test: `chisel/src/test/scala/cpu/ooo/frontend/OooFrontendSpec.scala`

**Interfaces:**
- Consumes: redirect、predictorUpdate、halt、CoreBus响应、`out.ready`。
- Produces: `Decoupled[FetchGroup]` 和 CoreBus 请求。

- [ ] **Step 1:** 复位PC等于构造参数 `resetVector`，请求地址必须4字节对齐。
- [ ] **Step 2:** 从 Cache Line 中按 `pc(4,2)` 选择slot0，slot1选择下一字；若slot0位于行内最后一个字，slot1无效，下一拍请求下一行。
- [ ] **Step 3:** 无taken预测时下一个PC为 `pc+8`；slot0 taken时slot1无效且下一个PC为目标；slot1 taken时两个槽有效且下一个PC为目标。
- [ ] **Step 4:** 维护至少2组 Fetch Queue。`out.valid && !out.ready` 时用测试连续检查5拍输出不变。
- [ ] **Step 5:** redirect优先级最高：清Fetch Queue、增加2位epoch、设置新PC；迟到旧epoch ICache响应必须丢弃。
- [ ] **Step 6:** halt为true时停止新请求，但已经对外valid的输出仍遵守反压，不允许中途改变。
- [ ] **Step 7:** 用程序序列测试顺序取指、slot0跳转、slot1跳转、预测失败重定向和取指错误。
- [ ] **Step 8:** 运行 `testOnly cpu.ooo.frontend.OooFrontendSpec` 并提交 `feat(frontend): add dual-instruction frontend`。

### Task 7: 成员2独立验收

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/frontend/GenerateFrontend.scala`
- Create: `generated/reports/ooo/frontend-member2-acceptance.txt`

- [ ] **Step 1:** 连续运行两次：

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.frontend.*'"
```

两次都必须全部通过。

- [ ] **Step 2:** 生成 `OooFrontend.sv`，使用 Verilator lint；不得连接真实后端。
- [ ] **Step 3:** 运行 `git diff --check`。
- [ ] **Step 4:** 检查 `git diff --name-only`，只能出现本计划允许的 frontend 源文件、frontend 测试和验收报告。
- [ ] **Step 5:** 验收报告写明：测试数量、两次结果、RTL文件数、lint结果、已知限制“一个miss在途”。
- [ ] **Step 6:** 提交 `test(frontend): record independent acceptance`，把提交哈希发给负责人，此后停止修改分支。

## 出错时按这个顺序检查

1. 输出重复或丢失：检查是不是把 `valid` 当成 `fire`。
2. 反压时数据变化：给输出加寄存器，只在 fire 后换下一项。
3. redirect后出现旧指令：检查 Fetch Queue 是否清空、epoch是否增加、旧响应是否丢弃。
4. Cache Line字顺序反了：确认地址0放 `lineData(31,0)`，地址28放 `lineData(255,224)`。
5. 分支训练没有效果：更新索引必须使用请求携带的旧history。
6. 不知道该改后端还是SoC：都不要改，把失败测试和波形交给负责人。
