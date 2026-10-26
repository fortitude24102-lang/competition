package gpu

import chisel3._
import chisel3.util._

/** Two full-burst banks. Reset is COMMON DDR reset; GPU reset uses abort.
  * A bank remains owned until B, keeping response identity independent of R/W.
  * ponytail: fixed same-ID, two-bank pipeline; no unaligned/DRE/general DMA. */
class WideCopyDma extends Module {
  val io = IO(new Bundle {
    val request = Flipped(Decoupled(new WideCopyRequest))
    val completion = Decoupled(new GpuCompletion)
    val axi = new Axi128MasterPort
    val abort = Input(Bool())
    val busy = Output(Bool())
    val recovering = Output(Bool())
  })
  private val free :: reading :: full :: committed :: Nil = Enum(4)
  private val state = RegInit(VecInit(Seq.fill(2)(free)))
  private val beats = Reg(Vec(2,UInt(7.W)))
  private val destinations = Reg(Vec(2,UInt(32.W)))
  private val readAccepted = RegInit(VecInit(Seq.fill(2)(false.B)))
  private val writeDone = RegInit(VecInit(Seq.fill(2)(false.B)))
  private val memory = SyncReadMem(128,UInt(128.W))
  private val active = RegInit(false.B)
  private val done = RegInit(false.B)
  private val failed = RegInit(false.B)
  private val aborted = RegInit(false.B)
  private val error = RegInit(GpuError.None.U(8.W))
  private val tag = Reg(UInt(16.W))
  private val source = Reg(UInt(32.W))
  private val destination = Reg(UInt(32.W))
  private val remaining = RegInit(0.U(32.W))
  private val allocate = RegInit(false.B)
  private val readBank = RegInit(false.B)
  private val writeBank = RegInit(false.B)
  private val responseBank = RegInit(false.B)
  private val readIndex = RegInit(0.U(6.W))
  private val arPending = RegInit(false.B)
  private val arBank = Reg(Bool())
  private val arAddress = Reg(UInt(32.W))
  private val arBeats = Reg(UInt(7.W))
  private val awPending = RegInit(false.B)
  private val wBank = Reg(Bool())
  private val wActive = RegInit(false.B)
  private val fetchIndex = RegInit(0.U(7.W))
  private val sendIndex = RegInit(0.U(6.W))

  io.request.ready := !active && !done && !io.abort
  io.completion.valid := done && !io.abort && !aborted
  io.completion.bits.tag := tag
  io.completion.bits.error := error
  io.busy := active || done
  io.recovering := io.abort || (aborted && active)
  when(io.completion.fire || io.abort) { done := false.B }
  when(io.abort && active) { aborted := true.B }

  // Defense at the physical narrowing boundary, in addition to CommandValidator.
  private val req = io.request.bits
  private val srcEnd = req.srcAddr +& req.bytes
  private val dstEnd = req.dstAddr +& req.bytes
  private val legal = !req.srcAddr(3,0).orR && !req.dstAddr(3,0).orR &&
    !req.bytes(3,0).orR && req.bytes =/= 0.U &&
    req.srcAddr >= GpuMemoryMap.FramebufferA.U && req.dstAddr >= GpuMemoryMap.FramebufferA.U &&
    srcEnd <= GpuMemoryMap.DdrEndExclusive.U && dstEnd <= GpuMemoryMap.DdrEndExclusive.U &&
    (srcEnd <= req.dstAddr || dstEnd <= req.srcAddr)
  when(io.request.fire) {
    tag := req.tag;source := req.srcAddr;destination := req.dstAddr;remaining := req.bytes
    failed := false.B;aborted := false.B;error := GpuError.None.U
    allocate := false.B;readBank := false.B;writeBank := false.B;responseBank := false.B
    readIndex := 0.U
    when(legal) { active := true.B }.otherwise {
      done := true.B;error := GpuError.AddressRange.U
    }
  }

  private val srcPageBeats = (4096.U(13.W) - source(11,0)) >> 4
  private val dstPageBeats = (4096.U(13.W) - destination(11,0)) >> 4
  private val lengthBeats = remaining >> 4
  private val pageLimit = Mux(srcPageBeats < dstPageBeats,srcPageBeats,dstPageBeats)
  private val capped = Mux(pageLimit < 64.U,pageLimit,64.U)
  private val segmentBeats = Mux(lengthBeats < capped,lengthBeats,capped)(6,0)
  when(active && remaining =/= 0.U && state(allocate)===free &&
    !arPending && !failed && !aborted && !io.abort) {
    state(allocate) := reading;readAccepted(allocate) := false.B
    destinations(allocate) := destination;beats(allocate) := segmentBeats
    arBank := allocate;arAddress := source;arBeats := segmentBeats;arPending := true.B
  }
  io.axi.ar.valid := arPending
  io.axi.ar.bits := 0.U.asTypeOf(new Axi128Address)
  io.axi.ar.bits.addr := arAddress;io.axi.ar.bits.len := arBeats-1.U
  io.axi.ar.bits.size := 4.U;io.axi.ar.bits.burst := 1.U
  when(io.axi.ar.fire) {
    arPending := false.B;readAccepted(arBank) := true.B;allocate := !allocate
    source := source + (arBeats << 4);destination := destination + (arBeats << 4)
    remaining := remaining - (arBeats << 4)
  }
  io.axi.r.ready := state(readBank)===reading && readAccepted(readBank)
  private val expectedLast = readIndex +& 1.U === beats(readBank)
  when(io.axi.r.fire) {
    memory.write(Cat(readBank,readIndex),io.axi.r.bits.data)
    when(io.axi.r.bits.resp =/= 0.U || io.axi.r.bits.id =/= 0.U || io.axi.r.bits.last =/= expectedLast) {
      failed := true.B;error := GpuError.AxiResponse.U
    }
    when(expectedLast) {
      state(readBank) := full;readAccepted(readBank) := false.B
      readBank := !readBank;readIndex := 0.U
    }.otherwise { readIndex := readIndex+1.U }
  }

  // A complete read bank is a prerequisite to even PRESENT AW.
  when(active && state(writeBank)===full && !awPending && !wActive &&
    !failed && !aborted && !io.abort) {
    state(writeBank) := committed;writeDone(writeBank) := false.B
    wBank := writeBank;awPending := true.B;writeBank := !writeBank
    fetchIndex := 0.U;sendIndex := 0.U
  }
  io.axi.aw.valid := awPending
  io.axi.aw.bits := 0.U.asTypeOf(new Axi128Address)
  io.axi.aw.bits.addr := destinations(wBank);io.axi.aw.bits.len := beats(wBank)-1.U
  io.axi.aw.bits.size := 4.U;io.axi.aw.bits.burst := 1.U
  when(io.axi.aw.fire) {
    awPending := false.B;wActive := true.B
  }

  // Two-word elastic read pipeline absorbs synchronous RAM latency under W stalls.
  // Prefetch the committed bank during AW arbitration; external W still waits for AW.
  private val words = Module(new Queue(UInt(128.W),2,pipe=true))
  private val memoryPending = RegInit(false.B)
  private val fetch = (awPending || wActive) && fetchIndex < beats(wBank) &&
    ((words.io.count +& memoryPending.asUInt) < 2.U || words.io.deq.fire)
  private val data = memory.read(Cat(wBank,fetchIndex(5,0)),fetch)
  memoryPending := fetch
  words.io.enq.valid := memoryPending;words.io.enq.bits := data
  when(memoryPending) { assert(words.io.enq.ready,"wide DMA RAM pipeline overflow") }
  when(fetch) { fetchIndex := fetchIndex+1.U }
  io.axi.w.valid := wActive && words.io.deq.valid
  io.axi.w.bits.data := words.io.deq.bits;io.axi.w.bits.strb := "hffff".U
  io.axi.w.bits.last := sendIndex +& 1.U === beats(wBank)
  words.io.deq.ready := wActive && io.axi.w.ready
  when(io.axi.w.fire) {
    when(io.axi.w.bits.last) { wActive := false.B;writeDone(wBank) := true.B }
      .otherwise { sendIndex := sendIndex+1.U }
  }
  io.axi.b.ready := state(responseBank)===committed && writeDone(responseBank)
  when(io.axi.b.fire) {
    state(responseBank) := free;writeDone(responseBank) := false.B;responseBank := !responseBank
    when(io.axi.b.bits.resp =/= 0.U || io.axi.b.bits.id =/= 0.U) {
      failed := true.B;error := GpuError.AxiResponse.U
    }
  }
  for(i<-0 until 2) {
    when((failed || aborted || io.abort) && state(i)===full) { state(i) := free }
  }
  private val drained = state.map(_===free).reduce(_&&_) && !arPending && !awPending &&
    !wActive && !memoryPending && !words.io.deq.valid
  when(active && drained && (remaining===0.U || failed || aborted || io.abort)) {
    active := false.B
    when(!aborted && !io.abort) { done := true.B }
  }
}
