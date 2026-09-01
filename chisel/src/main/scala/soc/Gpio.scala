package soc

import chisel3._

class Gpio extends Module {
  val io = IO(new Bundle {
    val bus = new SocBusTargetIO
    val input = Input(UInt(8.W))
    val output = Output(UInt(8.W))
  })

  private val outputRegister = RegInit(0.U(8.W))
  private val responseValid = RegInit(false.B)
  private val responseData = RegInit(0.U(32.W))
  private val responseError = RegInit(false.B)

  io.output := outputRegister
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
    val outputRead = !io.bus.req.bits.write && offset === MemoryMap.Gpio.OutputOffset.U
    val inputRead = !io.bus.req.bits.write && offset === MemoryMap.Gpio.InputOffset.U
    val outputWrite = io.bus.req.bits.write && offset === MemoryMap.Gpio.OutputOffset.U &&
      io.bus.req.bits.wstrb === "b1111".U
    val legalAccess = legalWord && (outputRead || inputRead || outputWrite)

    responseValid := true.B
    responseData := Mux(outputRead && legalWord, outputRegister,
      Mux(inputRead && legalWord, io.input, 0.U))
    responseError := !legalAccess

    when(outputWrite && legalWord) {
      outputRegister := io.bus.req.bits.wdata(7, 0)
    }
  }
}
