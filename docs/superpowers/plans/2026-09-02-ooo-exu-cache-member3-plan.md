# 成员3：RV32M 执行单元与 D-Cache 新手实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 独立完成 RV32M 的8种乘除法运算和16KB两路写回式 D-Cache，通过不依赖乱序后端和前端的专项验收。

**Architecture:** `MulDivUnit` 接收已经译码好的操作和两个32位操作数，乘法走3级流水，除法走最多32轮迭代，最终带原tag返回结果。`DCache` 接收已经由负责人检查过的普通RAM请求，命中时读写Cache Line，miss时通过现有32位 CoreBus 完成8拍填充，脏行替换前完成8拍回写。

**Tech Stack:** Chisel 7.7.0、Scala 2.13.18、ScalaTest、Verilator、现有 `CoreBusIO`

**Spec:** `docs/superpowers/specs/2026-09-02-dual-issue-ooo-contract-design.md`

## Global Constraints

- 只能修改 `chisel/src/main/scala/cpu/ooo/exu/`、`cpu/ooo/cache/` 和对应测试目录。
- `OooTypes.scala` 只能引用，不能修改、复制或新增另一个 `MulDivOp`。
- 不修改旧 `Decoder.scala`；RV32M译码由负责人完成。
- 不修改 Frontend、ROB、LSQ、SoCTop 和现有 `Rv32Core`。
- D-Cache固定16KB、2路、32字节一行、256组、写回写分配、一个miss在途。
- D-Cache只处理普通RAM；MMIO、对齐检查、符号扩展和Store提交顺序由负责人处理。
- 每个 Decoupled 接口必须支持反压，响应停住时 bits 不能变化。
- 不调用PDS综合；独立验收只做测试、RTL生成和Verilator lint。

## 先理解五个词

1. `tag`：负责人给每条微操作的编号。你不解释它，只需要原样返回。
2. `MULH`：两个有符号数相乘，取64位结果的高32位。
3. `refill`：Cache miss后从内存读取整条32字节 Cache Line。
4. `dirty`：Cache里的数据被Store改过，但还没写回内存。
5. `write-back`：脏行被替换前，先把8个32位字写回内存。

遇到不认识的指令，不要修改接口猜测行为，先在本计划的运算表中查。

## 你负责什么

| 模块 | 作用 | 输入 | 输出 |
|---|---|---|---|
| `PipelinedMultiplier` | 完成4种乘法 | op、lhs、rhs、tag | 3级后结果与tag |
| `IterativeDivider` | 完成4种除法/余数 | op、lhs、rhs、tag | 最多32轮后的结果与tag |
| `MulDivUnit` | 在乘法和除法之间分流并合并响应 | `MulDivRequest` | `MulDivResponse`、busy |
| `DCacheArrays` | 保存两路tag/data/valid/dirty/LRU | index、写入控制 | 两路查找结果 |
| `DCache` | 命中、refill、回写状态机 | `CacheRequest`、CoreBus响应 | `CacheResponse`、CoreBus请求 |

## 固定模块端口

```scala
class MulDivUnit extends Module {
  val io = IO(new Bundle {
    val req = Flipped(Decoupled(new MulDivRequest))
    val resp = Decoupled(new MulDivResponse)
    val busy = Output(Bool())
  })
}

class DCache extends Module {
  val io = IO(new Bundle {
    val cpuReq = Flipped(Decoupled(new CacheRequest))
    val cpuResp = Decoupled(new CacheResponse)
    val mem = new CoreBusIO
    val busy = Output(Bool())
  })
}
```

不要增加“方便调试”的顶层输出。内部状态需要观察时，在ScalaTest中使用公开握手结果判断；确实无法判断时先交失败测试给负责人评审。

## RV32M 结果表

| op | lhs解释 | rhs解释 | 返回值 |
|---|---|---|---|
| MUL | 不区分符号 | 不区分符号 | 64位乘积低32位 |
| MULH | 有符号 | 有符号 | 乘积高32位 |
| MULHSU | 有符号 | 无符号 | 乘积高32位 |
| MULHU | 无符号 | 无符号 | 乘积高32位 |
| DIV | 有符号 | 有符号 | 向0截断的商 |
| DIVU | 无符号 | 无符号 | 无符号商 |
| REM | 有符号 | 有符号 | 余数符号跟lhs |
| REMU | 无符号 | 无符号 | 无符号余数 |

强制边界行为：除数为0时 DIV/DIVU 返回 `0xffffffff`，REM/REMU 返回 lhs；`0x80000000 / 0xffffffff` 的 DIV 返回 `0x80000000`，REM返回0。

---

### Task 1: 建立 RV32M 测试向量和接口壳

**Files:**
- Create: `chisel/src/test/scala/cpu/ooo/exu/MulDivVectors.scala`
- Create: `chisel/src/test/scala/cpu/ooo/exu/MulDivInterfaceSpec.scala`

**Interfaces:**
- Consumes: 共享 `MulDivRequest/Response`。
- Produces: 八种运算的固定输入/期望结果表。

- [ ] **Step 1:** 每种op至少写6个固定向量：0、1、最大正数、最小负数、`0xffffffff`、随机常量 `0x12345678/0x13579bdf`。
- [ ] **Step 2:** DIV/REM额外加入除零和最小负数除以-1。
- [ ] **Step 3:** 写接口 Elaborate 测试，确认tag是6位且8种枚举全部可以输入。
- [ ] **Step 4:** 运行：

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.exu.MulDivInterfaceSpec'"
```

- [ ] **Step 5:** 提交 `test(exu): define rv32m acceptance vectors`。

### Task 2: 三级流水乘法器

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/exu/PipelinedMultiplier.scala`
- Test: `chisel/src/test/scala/cpu/ooo/exu/PipelinedMultiplierSpec.scala`

**Interfaces:**
- Consumes: `Decoupled[MulDivRequest]`，只允许四种Mul操作。
- Produces: `Decoupled[MulDivResponse]`，保持输入tag。

- [ ] **Step 1:** 写失败测试：连续3拍输入3个不同tag的MUL，请求不能互相覆盖，输出顺序必须相同。
- [ ] **Step 2:** 写失败测试：`resp.ready=false`时最后一级valid/tag/data连续保持5拍。
- [ ] **Step 3:** 第1级锁存op/lhs/rhs/tag；第2级形成66位带符号扩展操作数并计算乘积；第3级按op选择低32位或高32位。
- [ ] **Step 4:** `MULHSU` 的lhs扩展为33位有符号，rhs前补0后再解释为有符号，防止最高位被误当负号。
- [ ] **Step 5:** 运行所有固定向量，再运行200组Scala随机向量与 `BigInt` 参考结果比较。
- [ ] **Step 6:** 测试通过后提交 `feat(exu): add pipelined rv32m multiplier`。

### Task 3: 32轮迭代除法器

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/exu/IterativeDivider.scala`
- Test: `chisel/src/test/scala/cpu/ooo/exu/IterativeDividerSpec.scala`

**Interfaces:**
- Consumes: `Decoupled[MulDivRequest]`，只允许Div/Divu/Rem/Remu。
- Produces: `Decoupled[MulDivResponse]`；busy期间 `req.ready=false`。

- [ ] **Step 1:** 先处理除0和有符号溢出两个特殊情况，这两个请求不进入32轮循环。
- [ ] **Step 2:** 普通有符号操作先记录商和余数需要的符号，再对绝对值执行无符号恢复除法。
- [ ] **Step 3:** 每周期只做一次移位、比较和减法，计数器从0到31；禁止一拍展开32次循环。
- [ ] **Step 4:** 输出前按DIV或REM恢复符号，tag保持不变。
- [ ] **Step 5:** 测试busy期间拒绝第二个请求；响应反压时保持稳定。
- [ ] **Step 6:** 跑固定向量和200组随机向量，通过后提交 `feat(exu): add iterative rv32m divider`。

### Task 4: MulDivUnit 仲裁

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/exu/MulDivUnit.scala`
- Test: `chisel/src/test/scala/cpu/ooo/exu/MulDivUnitSpec.scala`

**Interfaces:**
- Consumes: 八种 `MulDivRequest`。
- Produces: 单一 `MulDivResponse` 和busy。

- [ ] **Step 1:** Mul类请求进入乘法器，Div/Rem类进入除法器。
- [ ] **Step 2:** 两个子模块不会同时接收同一个请求，只有目标模块的 `req.valid=true`。
- [ ] **Step 3:** 响应仲裁固定让除法器优先，但乘法器已有有效响应时必须保持数据直到被接收。
- [ ] **Step 4:** `busy` 在除法运行或任一响应等待接收时为true。
- [ ] **Step 5:** 混合输入 `mul, div, mul`，检查tag和结果对应，运行 `testOnly cpu.ooo.exu.*`。
- [ ] **Step 6:** 提交 `feat(exu): integrate muldiv execution unit`。

### Task 5: D-Cache数组和地址拆分

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/cache/DCacheArrays.scala`
- Test: `chisel/src/test/scala/cpu/ooo/cache/DCacheArraysSpec.scala`

**Interfaces:**
- Consumes: index、tag、way选择、整行写入、单字节掩码写入。
- Produces: 两路tag/valid/dirty/data和LRU位。

地址拆分固定：`addr(4,0)` 行内偏移，`addr(12,5)` 256组index，`addr(31,13)` tag。字号是 `addr(4,2)`，字节号是 `addr(1,0)`。

- [ ] **Step 1:** 数据使用两份 `SyncReadMem(256, Vec(8, Vec(4, UInt(8.W))))`，每一路一份。
- [ ] **Step 2:** tag/valid/dirty/LRU可以使用寄存器向量；复位只清valid/dirty/LRU。
- [ ] **Step 3:** 测试整行写入后8个字顺序正确。
- [ ] **Step 4:** 测试 `wstrb=0010` 只修改选中字的第2个字节，其他31个字节不变。
- [ ] **Step 5:** 测试dirty只在Store hit或refill后重放Store时置位；普通Load hit不能置dirty。
- [ ] **Step 6:** 测试LRU命中一路后指向另一路作为下次替换目标。
- [ ] **Step 7:** 运行 `testOnly cpu.ooo.cache.DCacheArraysSpec` 并提交 `feat(cache): add data cache arrays`。

### Task 6: D-Cache hit路径

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/cache/DCache.scala`
- Test: `chisel/src/test/scala/cpu/ooo/cache/DCacheHitSpec.scala`

**Interfaces:**
- Consumes: `CacheRequest`。
- Produces: hit时的 `CacheResponse`，不访问CoreBus。

- [ ] **Step 1:** 建立状态 `Idle -> Lookup -> Respond`，Lookup单独占一拍，不能把SyncReadMem读取和tag比较放同一拍假设为组合读。
- [ ] **Step 2:** Load hit返回地址对应的完整32位字和原tag，error=false。
- [ ] **Step 3:** Store hit按wstrb更新字节，响应rdata固定0，dirty=true。
- [ ] **Step 4:** 测试cpuResp反压5拍保持稳定；响应fire后才能接收下一请求。
- [ ] **Step 5:** 测试两路都不命中时不产生错误响应，而是转入miss流程占位状态。
- [ ] **Step 6:** 提交 `feat(cache): add data cache hit path`。

### Task 7: refill流程

**Files:**
- Modify: `chisel/src/main/scala/cpu/ooo/cache/DCache.scala`
- Test: `chisel/src/test/scala/cpu/ooo/cache/DCacheRefillSpec.scala`

**Interfaces:**
- Consumes: miss请求、8个CoreBus读响应。
- Produces: 地址按4递增的8个CoreBus读请求、填充后的CPU响应。

- [ ] **Step 1:** victim优先选择invalid路，两路都valid时选择LRU路。
- [ ] **Step 2:** victim不脏时直接从行对齐地址依次读取8个字；每次必须等当前CoreBus响应fire后才能请求下一个字。
- [ ] **Step 3:** 用256位 refillBuffer 收集8个字，地址0对应最低32位。
- [ ] **Step 4:** 收满后写入victim way，设置tag/valid，清dirty，更新LRU，然后重放原CPU请求。
- [ ] **Step 5:** 任一refill响应error时不设置valid，返回原tag、rdata=0、error=true。
- [ ] **Step 6:** 测试Load miss、Store miss写分配、CoreBus随机1～4拍延迟和CPU响应反压。
- [ ] **Step 7:** 提交 `feat(cache): add data cache refill`。

### Task 8: 脏行回写

**Files:**
- Modify: `chisel/src/main/scala/cpu/ooo/cache/DCache.scala`
- Test: `chisel/src/test/scala/cpu/ooo/cache/DCacheWritebackSpec.scala`

**Interfaces:**
- Consumes: dirty victim行。
- Produces: 8个CoreBus word Store，完成后进入refill。

- [ ] **Step 1:** 回写基地址由 `victimTag ## requestIndex ## 00000` 拼接，不能使用新请求tag。
- [ ] **Step 2:** 依次写8个字，`size=2`、`wstrb=1111`、地址每次加4。
- [ ] **Step 3:** 每个写请求都等待对应响应；任一写响应error时终止替换并给CPU返回error。
- [ ] **Step 4:** 8个写响应全部成功后才允许清victim dirty并开始refill。
- [ ] **Step 5:** 测试内存最终包含被替换的修改后数据，而不是refill前旧数据。
- [ ] **Step 6:** 运行全部 cache Spec 并提交 `feat(cache): add dirty line writeback`。

### Task 9: 成员3独立验收

**Files:**
- Create: `chisel/src/main/scala/cpu/ooo/exu/GenerateMulDiv.scala`
- Create: `chisel/src/main/scala/cpu/ooo/cache/GenerateDCache.scala`
- Create: `generated/reports/ooo/memory-member3-acceptance.txt`

- [ ] **Step 1:** 连续运行两次：

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /mnt/d/ZYNQ/smallproject/.worktrees/pango-riscv-cpu/chisel && /mnt/d/Chisel-environment/sbt/bin/sbt 'testOnly cpu.ooo.exu.* cpu.ooo.cache.*'"
```

- [ ] **Step 2:** 生成 `MulDivUnit.sv` 和 `DCache.sv`，分别运行Verilator lint。
- [ ] **Step 3:** 运行 `git diff --check`。
- [ ] **Step 4:** `git diff --name-only` 只能出现 exu/cache源文件、对应测试、生成入口和验收报告。
- [ ] **Step 5:** 报告写明：固定/随机RV32M向量数量、Cache测试数量、两次结果、lint结果、限制“一个miss在途”。
- [ ] **Step 6:** 提交 `test(memory): record independent acceptance`，把提交哈希发给负责人，此后停止修改分支。

## 出错时按这个顺序检查

1. MULH符号错：检查两个操作数分别是有符号还是无符号，特别是MULHSU。
2. DIV负数结果错：先对绝对值做无符号除法，最后分别恢复商和余数符号。
3. tag错位：每一级流水寄存器都必须同时保存valid、tag和data。
4. Cache字顺序错：低地址放在256位行数据的低位。
5. 脏行写回地址错：使用旧victim tag，不使用新请求tag。
6. 重复CoreBus请求：只在 `mem.req.fire` 后进入等待响应状态。
7. 想修改LSQ、MMIO或符号扩展：不要改，那些属于负责人。
