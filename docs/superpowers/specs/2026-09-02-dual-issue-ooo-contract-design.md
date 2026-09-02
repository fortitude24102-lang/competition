# 双发射乱序 CPU 共用接口与分工契约

## 目标

在保留现有 `Rv32Core` 作为正确性参考和应急回退版本的前提下，新增一颗 Chisel 编写的 `RV32IM_Zicsr`、双取指、双译码、双发射、乱序执行、顺序双提交 CPU。目标是在盘古 MES2L676-100HP 上完成布局布线后达到 150 MHz，并在 CoreMark 计时区争取 IPC 不低于 1.5。

IPC 定义为 CoreMark 的 `minstret / mcycle`，计时区包含 Cache miss 和分支预测失败损失，但不包含复位、程序装载和 UART 打印。IPC 1.5 是目标而不是对所有程序的保证。

## 三人所有权

| 人员 | 唯一负责目录 | 交付物 | 禁止修改 |
|---|---|---|---|
| 负责人（成员1） | `cpu/ooo/backend/`、`cpu/ooo/OoORv32Core.scala`、SoC 集成文件 | 共享接口、译码、重命名、ROB、物理寄存器、双发射、LSQ、精确异常、最终集成 | 不替组员重写 Predictor、ICache、MulDiv、DCache |
| 成员2 | `cpu/ooo/frontend/` | BranchPredictor、ICache、双取指 Frontend | 不修改后端、DCache、SoCTop、现有 `Rv32Core` |
| 成员3 | `cpu/ooo/exu/`、`cpu/ooo/cache/` | RV32M MulDiv、DCache | 不修改前端、后端、SoCTop、现有 `Decoder` |

测试目录采用同样边界：负责人拥有 `src/test/scala/cpu/ooo/backend/` 和集成测试；成员2拥有 `.../frontend/`；成员3拥有 `.../exu/` 与 `.../cache/`。任何人都不得修改别人目录里的文件。

## 分支规则

1. 负责人先在 `codex/ooo-contracts` 提交本契约与 `OooTypes.scala`。
2. 三条开发分支必须从同一个契约提交建立：
   - `codex/ooo-backend-lead`
   - `codex/ooo-frontend-member2`
   - `codex/ooo-memory-member3`
3. 两名组员只在自己的分支工作，独立验收通过后停止修改并提交验收记录。
4. 最终只由负责人将两个组员分支合入 `codex/ooo-integration`。
5. 不得把三个人的未完成代码提前互相复制；测试需要邻接模块时使用计划规定的 Mock。

## 固定参数

```scala
object OooConfig {
  val Width = 2
  val RobEntries = 32
  val RobIndexWidth = 5
  val PhysicalRegisters = 64
  val PhysicalRegisterWidth = 6
  val UopTagWidth = 6
  val GlobalHistoryWidth = 10
  val CacheLineBytes = 32
  val CacheLineBits = 256
  val ICacheBytes = 16 * 1024
  val DCacheBytes = 16 * 1024
  val CacheWays = 2
}
```

第一版不允许随意改这些数字。只有独立功能验收和首次 PDS 报告完成后，负责人才能根据资源或时序统一调整。

## 冻结的共享数据类型

共享类型只允许放在 `chisel/src/main/scala/cpu/ooo/OooTypes.scala`，只由负责人维护。组员发现接口缺项时写清楚缺少什么，由负责人修改契约提交；组员不能自行增加同名 Bundle。

### 前端输出

```scala
class FetchSlot extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val fetchError = Bool()
  val predictedTaken = Bool()
  val predictedTarget = UInt(32.W)
  val predictorHistory = UInt(OooConfig.GlobalHistoryWidth.W)
}

class FetchGroup extends Bundle {
  val slots = Vec(OooConfig.Width, new FetchSlot)
}

class FrontendRedirect extends Bundle {
  val target = UInt(32.W)
  val restoredHistory = UInt(OooConfig.GlobalHistoryWidth.W)
}

class BranchPredictUpdate extends Bundle {
  val pc = UInt(32.W)
  val target = UInt(32.W)
  val taken = Bool()
  val conditional = Bool()
  val call = Bool()
  val ret = Bool()
  val history = UInt(OooConfig.GlobalHistoryWidth.W)
}
```

`FetchGroup.slots(0)` 永远比 `slots(1)` 年老。若第一条预测跳转，则第二条必须 `valid=false`。当 `out.valid && !out.ready` 时，全部输出位必须保持不变。

### I-Cache 请求与响应

```scala
class ICacheRequest extends Bundle {
  val addr = UInt(32.W)
  val epoch = UInt(2.W)
}

class ICacheResponse extends Bundle {
  val lineAddress = UInt(32.W)
  val lineData = UInt(OooConfig.CacheLineBits.W)
  val error = Bool()
  val epoch = UInt(2.W)
}
```

`addr` 可以是任意4字节对齐取指地址；`lineAddress` 必须低5位为0。重定向时 Frontend 增加 epoch，旧 epoch 响应只能丢弃，不能变成指令。

### 分支预测查询

```scala
class BranchPrediction extends Bundle {
  val valid = Bool()
  val slot = UInt(1.W)
  val taken = Bool()
  val target = UInt(32.W)
  val history = UInt(OooConfig.GlobalHistoryWidth.W)
}
```

`slot=0` 对应 `basePc`，`slot=1` 对应 `basePc+4`。一次取指组最多预测一个跳转，选择地址更小的那一条。

### RV32M 执行接口

```scala
object MulDivOp extends ChiselEnum {
  val Mul, Mulh, Mulhsu, Mulhu, Div, Divu, Rem, Remu = Value
}

class MulDivRequest extends Bundle {
  val tag = UInt(OooConfig.UopTagWidth.W)
  val op = MulDivOp()
  val lhs = UInt(32.W)
  val rhs = UInt(32.W)
}

class MulDivResponse extends Bundle {
  val tag = UInt(OooConfig.UopTagWidth.W)
  val data = UInt(32.W)
}
```

请求和响应都使用 Decoupled。`tag` 必须原样返回，用于后端识别结果属于哪条微操作。响应被反压时 `valid/tag/data` 必须保持不变。

### D-Cache 处理器侧接口

```scala
class CacheRequest extends Bundle {
  val tag = UInt(OooConfig.UopTagWidth.W)
  val addr = UInt(32.W)
  val write = Bool()
  val wdata = UInt(32.W)
  val wstrb = UInt(4.W)
}

class CacheResponse extends Bundle {
  val tag = UInt(OooConfig.UopTagWidth.W)
  val rdata = UInt(32.W)
  val error = Bool()
}
```

后端保证请求地址已完成对齐和权限判断。D-Cache 对 Load 返回地址所在的32位字；符号扩展、Byte/Half抽取由负责人拥有的 LSQ 完成。MMIO 不进入 D-Cache，负责人在 LSQ 外旁路到现有 `CoreBusIO`。

### 外部存储接口

ICache 与 DCache 的下游都继续使用现有 `cpu.CoreBusIO`：

```scala
class CoreBusReq extends Bundle {
  val addr = UInt(32.W)
  val write = Bool()
  val size = UInt(2.W)
  val wdata = UInt(32.W)
  val wstrb = UInt(4.W)
}
```

Cache refill/回写以8次32位 CoreBus 事务完成一个32字节 Cache Line。AXI 不放进 CPU 内部；最终在 SoC 外增加 CoreBus-to-AXI 适配器，因此当前分工不会封死 AXI。

## 模块接口

### 成员2交付的 `OooFrontend`

```scala
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

输入：重定向、预测器更新、停止取指、CoreBus 返回。输出：最多两条指令、CoreBus refill 请求。Frontend 不译码、不访问ROB、不产生异常入口。

### 成员3交付的 `MulDivUnit`

```scala
class MulDivUnit extends Module {
  val io = IO(new Bundle {
    val req = Flipped(Decoupled(new MulDivRequest))
    val resp = Decoupled(new MulDivResponse)
    val busy = Output(Bool())
  })
}
```

输入：已经译码并读出操作数的 RV32M 请求。输出：带原 tag 的结果。模块不读写寄存器、不修改CSR、不处理异常。

### 成员3交付的 `DCache`

```scala
class DCache extends Module {
  val io = IO(new Bundle {
    val cpuReq = Flipped(Decoupled(new CacheRequest))
    val cpuResp = Decoupled(new CacheResponse)
    val mem = new CoreBusIO
    val busy = Output(Bool())
  })
}
```

输入：仅普通RAM访问和下游 CoreBus 响应。输出：命中/填充后的数据、错误、refill/回写请求。第一版只允许一个 miss 在途。

### 负责人交付的 `OoORv32Core`

外部端口保持现有 CPU 边界，仅把提交跟踪扩展成两槽：

```scala
class OoORv32Core(resetVector: BigInt = 0, haltOnEbreak: Boolean = true)
    extends Module {
  val io = IO(new Bundle {
    val imem = new CoreBusIO
    val dmem = new CoreBusIO
    val timerInterrupt = Input(Bool())
    val commit = Output(Vec(2, new CommitTrace))
    val trap = Output(new TrapTrace)
    val halted = Output(Bool())
  })
}
```

负责人实例化两个组员模块并负责所有连接、仲裁、流水冲刷和 SoC 顶层适配。

## 独立验收边界

成员2的测试只能实例化 Frontend/ICache/Predictor 和内存 Mock；成员3的测试只能实例化 MulDiv/DCache 和 CoreBus Mock；负责人的后端测试用 FakeFrontend、FakeMulDiv、FakeDCache，不等待组员代码。

独立验收必须满足：

- 分支内只有本人所有权范围内的源代码和测试发生变化。
- 专项测试连续运行两次通过。
- `git diff --check` 通过。
- 生成对应模块 SystemVerilog 后，Verilator lint 通过。
- 提交一份 `generated/reports/ooo/<role>-acceptance.txt`，报告可以提交 Git，但 ELF/BIN/HEX 不提交。

## 最终验收

合并后依次要求：RV32I、RV32M、CSR、异常、中断、Cache、分支回滚、CoreMark CRC、双提交 trace 全部通过。最后才运行 PDS，检查 6.667 ns 约束下 WNS 不小于0；如果时序失败，优先给发射选择、物理寄存器读取、Cache tag/data 和 flush 扇出增加寄存级，不能删除精确异常或接口反压逻辑换取主频。
