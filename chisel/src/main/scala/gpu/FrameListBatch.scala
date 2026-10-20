package gpu

import chisel3._
import chisel3.util._

/** One GPU owner. sticky done is backend retirement, NOT Reader's pulse.
  * ponytail: no local AXI timeout/reset; outstanding responses require a
  * coordinated system reset, never an unsafe reset of this client alone. */
class FrameListBatch(extendedArena: Boolean = false) extends Module {
  val io = IO(new Bundle {
    val apb = new ApbSlavePort
    val idle = Input(Bool())
    val frontendActive = Input(Bool())
    val frontendEmpty = Input(Bool())
    val frontendError = Input(UInt(8.W))
    val hardwareError = Input(UInt(8.W))
    val issued = Input(Bool())
    val begin = Valid(UInt(16.W))
    val end = Output(Bool())
    val descriptor = Decoupled(Vec(4, UInt(32.W)))
    val active = Output(Bool())
    val fetching = Output(Bool())
    val axiAr = Decoupled(new Axi4Address)
    val axiR = Flipped(Decoupled(new Axi4ReadData))
  })
  private val reader = Module(new FrameListReader(extendedArena=extendedArena))
  private val idle :: launch :: fetching :: drain :: Nil = Enum(4)
  private val state = RegInit(idle)
  private val base = RegInit(0.U(32.W))
  private val count = RegInit(0.U(16.W))
  private val tag = RegInit(0.U(16.W))
  private val epoch = RegInit(0.U(32.W))
  private val acceptedEpoch = Reg(UInt(32.W))
  private val completedEpoch = RegInit(0.U(32.W))
  private val lastTag = RegInit(0.U(16.W))
  private val issued = RegInit(0.U(16.W))
  private val done = RegInit(false.B)
  private val error = RegInit(0.U(8.W))
  private val pending = RegInit(false.B)
  private val address = Reg(UInt(16.W))
  private val write = Reg(Bool())
  private val data = Reg(UInt(32.W))
  when(io.apb.psel && !io.apb.penable) {
    pending := true.B;address := io.apb.paddr;write := io.apb.pwrite;data := io.apb.pwdata
  }
  private val transfer = io.apb.psel && io.apb.penable && pending
  when(transfer) { pending := false.B }
  private val active = state =/= idle
  private val stage = address === 0x50c.U || address === 0x510.U || address === 0x514.U || address === 0x518.U
  private val legal = !address(1,0).orR && (stage || Seq(0x500,0x504,0x508,0x51c,0x520,0x524,0x528).map(a=>address===a.U).reduce(_||_))
  private val start = data === 1.U && io.idle && !io.frontendActive && !reader.io.busy && !io.hardwareError.orR
  private val clear = data === 4.U
  private val rejected = !legal || (write && (active ||
    !(stage || (address === 0x508.U && (start || clear))) ||
    ((address===0x510.U || address===0x514.U) && data>65535.U)))
  private val begin = transfer && write && address===0x508.U && data===1.U && !rejected
  io.apb.pready := transfer
  io.apb.pslverror := transfer && rejected
  io.apb.prdata := 0.U
  switch(address) {
    is(0x500.U) { io.apb.prdata := "h464c5431".U }
    is(0x504.U) { io.apb.prdata := Cat(0.U(16.W), error,0.U(4.W), reader.io.fetching,error.orR,done,active) }
    is(0x50c.U) { io.apb.prdata := base }
    is(0x510.U) { io.apb.prdata := count }
    is(0x514.U) { io.apb.prdata := tag }
    is(0x518.U) { io.apb.prdata := epoch }
    is(0x51c.U) { io.apb.prdata := completedEpoch }
    is(0x520.U) { io.apb.prdata := lastTag }
    is(0x524.U) { io.apb.prdata := issued }
    is(0x528.U) { io.apb.prdata := reader.io.fetchedBytes }
  }
  when(transfer && write && !rejected) {
    switch(address) {
      is(0x50c.U) { base := data }
      is(0x510.U) { count := data(15,0) }
      is(0x514.U) { tag := data(15,0) }
      is(0x518.U) { epoch := data }
      is(0x508.U) { done := false.B;error := 0.U }
    }
  }
  io.begin.valid := begin;io.begin.bits := tag
  when(begin) {
    state := launch;acceptedEpoch := epoch;issued := 0.U;lastTag := tag-1.U
  }
  reader.io.request.valid := state===launch
  reader.io.request.bits.address := base;reader.io.request.bits.count := count
  when(reader.io.request.fire) { state := fetching }
  io.axiAr <> reader.io.axiAr;reader.io.axiR <> io.axiR
  io.active := active;io.fetching := reader.io.fetching
  private val fault = error.orR || io.frontendError.orR || io.hardwareError.orR
  io.descriptor.valid := reader.io.descriptor.valid && !fault
  io.descriptor.bits := reader.io.descriptor.bits
  reader.io.descriptor.ready := fault || io.descriptor.ready
  when(active && !error.orR) {
    when(io.hardwareError.orR) { error := io.hardwareError }
      .elsewhen(io.frontendError.orR) { error := io.frontendError }
      .elsewhen(reader.io.done && reader.io.error.orR) { error := reader.io.error }
  }
  when(io.issued && active) { issued := issued+1.U;lastTag := tag+issued }
  when(state===fetching && reader.io.done) { state := drain }
  io.end := state===drain && io.idle && io.frontendEmpty
  when(io.end) { state := idle;done := true.B;completedEpoch := acceptedEpoch }
}
