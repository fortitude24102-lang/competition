package gpu

import chisel3._
import chisel3.util._

/** Render-only 960x8 RGB565 scratch window. All other masters still use DDR.
  * One owner per AXI direction through B/RLAST; reserved64KiB never leaks to DDR.
  */
class StripeScratchpad extends Module {
  val io = IO(new Bundle {
    val in = Flipped(new Axi4MasterPort)
    val ddr = new Axi4MasterPort
  })
  private val base = BigInt("02e00000", 16)
  private val bytes = 15360
  private val memory = SyncReadMem(bytes / 4, Vec(4, UInt(8.W)))
  private def local(a: Axi4Address): Bool = a.addr(31, 16) === (base >> 16).U
  private def bad(a: Axi4Address): Bool = {
    val length = (a.len +& 1.U) << 2
    a.addr(1, 0).orR || a.size =/= 2.U || a.burst =/= 1.U || a.lock ||
      (a.addr.pad(33) + length) > (base + bytes).U ||
      (a.addr(11, 0) +& length) > 4096.U
  }
  private val wb = RegInit(false.B)
  private val wl = Reg(Bool())
  private val we = Reg(Bool())
  private val wa = Reg(UInt(32.W))
  private val wn = Reg(UInt(9.W))
  private val wi = Reg(UInt(4.W))
  private val response = RegInit(false.B)
  io.ddr.aw.valid := !wb && io.in.aw.valid && !local(io.in.aw.bits)
  io.ddr.aw.bits := io.in.aw.bits
  io.in.aw.ready := !wb && (local(io.in.aw.bits) || io.ddr.aw.ready)
  when(io.in.aw.fire) {
    wb := true.B; wl := local(io.in.aw.bits); we := bad(io.in.aw.bits)
    wa := io.in.aw.bits.addr; wn := io.in.aw.bits.len +& 1.U; wi := io.in.aw.bits.id
    response := false.B
  }
  io.ddr.w.valid := wb && !wl && io.in.w.valid
  io.ddr.w.bits := io.in.w.bits
  io.in.w.ready := wb && Mux(wl, !response, io.ddr.w.ready)
  when(io.in.w.fire && wl) {
    when(!we) {
      memory.write(((wa - base.U) >> 2)(11, 0), io.in.w.bits.data.asTypeOf(Vec(4, UInt(8.W))),
        io.in.w.bits.strb.asBools)
    }
    we := we || (io.in.w.bits.last =/= (wn === 1.U))
    wa := wa + 4.U; wn := wn - 1.U
    when(wn === 1.U) { response := true.B }
  }
  io.in.b.valid := wb && Mux(wl, response, io.ddr.b.valid)
  io.in.b.bits := io.ddr.b.bits
  when(wl) {io.in.b.bits.id := wi; io.in.b.bits.resp := Mux(we, 2.U, 0.U)}
  io.ddr.b.ready := wb && !wl && io.in.b.ready
  when(io.in.b.fire) {wb := false.B; response := false.B}

  private val rb = RegInit(false.B)
  private val rl = Reg(Bool())
  private val re = Reg(Bool())
  private val ra = Reg(UInt(32.W))
  private val rn = RegInit(0.U(9.W))
  private val ri = Reg(UInt(4.W))
  private val queue = Module(new Queue(new Axi4ReadData, 2))
  private val pending = RegInit(false.B)
  private val pendingLast = Reg(Bool())
  io.ddr.ar.valid := !rb && io.in.ar.valid && !local(io.in.ar.bits)
  io.ddr.ar.bits := io.in.ar.bits
  io.in.ar.ready := !rb && (local(io.in.ar.bits) || io.ddr.ar.ready)
  when(io.in.ar.fire) {
    rb := true.B; rl := local(io.in.ar.bits); re := bad(io.in.ar.bits)
    ra := io.in.ar.bits.addr; rn := io.in.ar.bits.len +& 1.U; ri := io.in.ar.bits.id
  }
  private val canIssue = (queue.io.count +& pending) < 2.U || queue.io.deq.fire
  private val issue = rb && rl && rn =/= 0.U && canIssue
  private val data = memory.read(((ra - base.U) >> 2)(11, 0), issue && !re)
  pending := issue
  when(issue) {ra := ra + 4.U; rn := rn - 1.U; pendingLast := rn === 1.U}
  queue.io.enq.valid := pending
  queue.io.enq.bits.data := Mux(re, 0.U, data.asUInt)
  queue.io.enq.bits.id := ri
  queue.io.enq.bits.last := pendingLast
  queue.io.enq.bits.resp := Mux(re, 2.U, 0.U)
  io.in.r.valid := rb && Mux(rl, queue.io.deq.valid, io.ddr.r.valid)
  io.in.r.bits := Mux(rl, queue.io.deq.bits, io.ddr.r.bits)
  queue.io.deq.ready := rb && rl && io.in.r.ready
  io.ddr.r.ready := rb && !rl && io.in.r.ready
  when(io.in.r.fire && io.in.r.bits.last) {rb := false.B}
}
