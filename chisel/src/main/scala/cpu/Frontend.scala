package cpu

import chisel3._
import chisel3.util._

class FetchPacket extends Bundle {
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val error = Bool()
}

class Frontend(resetVector: BigInt = 0) extends Module {
  val io = IO(new Bundle {
    val imem = new CoreBusIO
    val output = Decoupled(new FetchPacket)
    val redirectValid = Input(Bool())
    val redirectPc = Input(UInt(32.W))
  })

  val nextPc = RegInit(resetVector.U(32.W))
  val requestPending = RegInit(false.B)
  val requestPc = Reg(UInt(32.W))
  val dropResponse = RegInit(false.B)
  val queue = Module(new Queue(new FetchPacket, 2, hasFlush = true))

  queue.io.flush.get := io.redirectValid
  io.output <> queue.io.deq

  io.imem.req.valid := !requestPending && !io.redirectValid && queue.io.enq.ready
  io.imem.req.bits.addr := nextPc
  io.imem.req.bits.write := false.B
  io.imem.req.bits.size := 2.U
  io.imem.req.bits.wdata := 0.U
  io.imem.req.bits.wstrb := 0.U

  queue.io.enq.valid := io.imem.resp.valid && requestPending && !dropResponse && !io.redirectValid
  queue.io.enq.bits.pc := requestPc
  queue.io.enq.bits.inst := io.imem.resp.bits.rdata
  queue.io.enq.bits.error := io.imem.resp.bits.error
  io.imem.resp.ready := requestPending && (dropResponse || io.redirectValid || queue.io.enq.ready)

  when(io.imem.req.fire) {
    requestPending := true.B
    requestPc := nextPc
    nextPc := nextPc + 4.U
  }

  when(io.imem.resp.fire) {
    requestPending := false.B
    dropResponse := false.B
  }

  when(io.redirectValid) {
    nextPc := io.redirectPc
    when(requestPending && !io.imem.resp.fire) {
      dropResponse := true.B
    }
  }
}
