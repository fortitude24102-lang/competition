package gpu

import chisel3._
import chisel3.util._

/** Optional small-blit writer: ordered W, bounded bursts, retirement at final B. */
class AxiWritePipeline(writeCredits: Int = 2) extends Module {
  require(writeCredits == 2 || writeCredits == 4, "Small-blit write credits must be 2 or 4")
  val io = IO(new Bundle {
    val request = Flipped(Decoupled(new AxiWriteRequest))
    val data = Flipped(Decoupled(new AxiWriteBeat))
    val axiAw = Decoupled(new Axi4Address)
    val axiW = Decoupled(new Axi4WriteData)
    val axiB = Flipped(Decoupled(new Axi4WriteResponse))
    val done = Output(Bool())
    val error = Output(Bool())
  })
  private val idle :: sendAddress :: sendData :: Nil = Enum(3)
  private val state = RegInit(idle)
  private val address = Reg(UInt(32.W))
  private val remaining = Reg(UInt(32.W))
  private val burstLeft = Reg(UInt(9.W))
  private val responses = Module(new Queue(Bool(), writeCredits)) // Final burst of a request.
  private val responseError = io.axiB.bits.resp =/= Axi4.Okay.U || io.axiB.bits.id =/= 0.U
  private val requestError = RegInit(false.B)
  private val haltNewRequests = RegInit(false.B)
  private val done = RegInit(false.B)
  private val error = RegInit(false.B)
  done := false.B; error := false.B
  io.done := done; io.error := error
  responses.io.deq.ready := io.axiB.valid
  io.axiB.ready := responses.io.deq.valid
  private val badResponse = io.axiB.fire && responseError
  private val finishingWrite = io.axiW.fire && burstLeft === 1.U && remaining === 1.U
  io.request.ready := (state === idle || finishingWrite) && responses.io.enq.ready && !haltNewRequests && !badResponse &&
    (io.request.bits.beats =/= 0.U || responses.io.count === 0.U)
  private val toBoundary = (4096.U(13.W) - address(11, 0)) >> 2
  private val capped = Mux(remaining > 256.U, 256.U, remaining)
  private val burst = Mux(capped > toBoundary, toBoundary, capped)
  io.axiAw.valid := state === sendAddress && responses.io.enq.ready
  io.axiAw.bits := 0.U.asTypeOf(new Axi4Address)
  io.axiAw.bits.addr := address; io.axiAw.bits.id := 0.U
  io.axiAw.bits.len := (burst - 1.U)(7, 0)
  io.axiAw.bits.size := Axi4.WordSize.U; io.axiAw.bits.burst := Axi4.Incrementing.U
  responses.io.enq.valid := io.axiAw.fire
  responses.io.enq.bits := remaining === burst
  io.axiW.valid := state === sendData && io.data.valid
  io.axiW.bits.data := io.data.bits.data; io.axiW.bits.strb := io.data.bits.strb
  io.axiW.bits.last := burstLeft === 1.U
  io.data.ready := state === sendData && io.axiW.ready
  when(io.axiAw.fire) { burstLeft := burst(8, 0); state := sendData }
  when(io.axiW.fire) {
    address := address + 4.U; remaining := remaining - 1.U
    burstLeft := burstLeft - 1.U
    when(burstLeft === 1.U) { state := Mux(remaining === 1.U, idle, sendAddress) }
  }
  // A new row may share the old final W; its initialization must win.
  when(io.request.fire) {
    address := Cat(io.request.bits.address(31, 2), 0.U(2.W)); remaining := io.request.bits.beats
    when(io.request.bits.beats === 0.U) { done := true.B }.otherwise { state := sendAddress }
  }
  when(io.axiB.fire) {
    when(responses.io.deq.bits) {
      done := true.B; error := requestError || responseError; requestError := false.B
    }.otherwise { requestError := requestError || responseError }
    when(responseError) { haltNewRequests := true.B }
  }
  // An already accepted row must finish all of its W/B, even after its first B fails.
  when(haltNewRequests && state === idle && responses.io.count === 0.U) { haltNewRequests := false.B }
}
