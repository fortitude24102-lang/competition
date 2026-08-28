package soc

import chisel3._
import chisel3.util._

class MmioUart extends Module {
  val io = IO(new Bundle {
    val bus = new SocBusTargetIO
    val tx = Decoupled(UInt(8.W))
  })

  private val txData = RegInit(0.U(8.W))
  private val txValid = RegInit(false.B)
  private val responseValid = RegInit(false.B)
  private val responseData = RegInit(0.U(32.W))
  private val responseError = RegInit(false.B)

  io.tx.valid := txValid
  io.tx.bits := txData
  when(io.tx.fire) {
    txValid := false.B
  }

  io.bus.req.ready := !responseValid
  io.bus.resp.valid := responseValid
  io.bus.resp.bits.rdata := responseData
  io.bus.resp.bits.error := responseError

  when(io.bus.resp.fire) {
    responseValid := false.B
  }

  when(io.bus.req.fire) {
    val offset = io.bus.req.bits.addr(11, 0)
    val legalWord = io.bus.req.bits.size === 2.U && io.bus.req.bits.addr(1, 0) === 0.U
    val statusRead = !io.bus.req.bits.write && offset === MemoryMap.Uart.StatusOffset.U
    val txWrite = io.bus.req.bits.write && offset === MemoryMap.Uart.TxDataOffset.U &&
      io.bus.req.bits.wstrb(0) && !txValid
    val accessError = !legalWord || !(statusRead || txWrite)

    responseValid := true.B
    responseData := Mux(statusRead && legalWord, !txValid, 0.U)
    responseError := accessError

    when(txWrite && legalWord) {
      txData := io.bus.req.bits.wdata(7, 0)
      txValid := true.B
    }
  }
}
