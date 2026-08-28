package soc

import chisel3._
import chisel3.util._
import chisel3.util.experimental.loadMemoryFromFileInline

class DualPortRam(words: Int = 16384, initFile: Option[String] = None) extends Module {
  require(words > 0 && isPow2(words), "DualPortRam words must be a positive power of two")

  val io = IO(new Bundle {
    val imem = new SocBusTargetIO
    val dmem = new SocBusTargetIO
  })

  private val memory = SyncReadMem(words, Vec(4, UInt(8.W)))
  initFile.foreach(path => loadMemoryFromFileInline(memory, path))

  private def connectPort(bus: SocBusTargetIO, instruction: Boolean): Unit = {
    val requestPending = RegInit(false.B)
    val pendingRead = RegInit(false.B)
    val pendingError = RegInit(false.B)
    val responseValid = RegInit(false.B)
    val responseData = RegInit(0.U(32.W))
    val responseError = RegInit(false.B)

    val inRange = bus.req.bits.addr < (words * 4).U
    val sizeAligned = MuxLookup(bus.req.bits.size, false.B)(Seq(
      0.U -> true.B,
      1.U -> !bus.req.bits.addr(0),
      2.U -> (bus.req.bits.addr(1, 0) === 0.U)
    ))
    val accessLegal = inRange && sizeAligned && (if (instruction) !bus.req.bits.write && bus.req.bits.size === 2.U else true.B)
    val readEnable = bus.req.fire && !bus.req.bits.write && accessLegal
    val index = bus.req.bits.addr(log2Ceil(words) + 1, 2)
    val readData = memory.read(index, readEnable)

    bus.req.ready := !requestPending && !responseValid
    bus.resp.valid := responseValid
    bus.resp.bits.rdata := responseData
    bus.resp.bits.error := responseError

    when(bus.resp.fire) {
      responseValid := false.B
    }

    when(requestPending) {
      responseValid := true.B
      responseData := Mux(pendingRead && !pendingError, readData.asUInt, 0.U)
      responseError := pendingError
      requestPending := false.B
    }

    when(bus.req.fire) {
      requestPending := true.B
      pendingRead := !bus.req.bits.write
      pendingError := !accessLegal
    }

    if (!instruction) {
      val writeData = bus.req.bits.wdata.asTypeOf(Vec(4, UInt(8.W)))
      val writeMask = VecInit((0 until 4).map(bus.req.bits.wstrb(_)))
      when(bus.req.fire && bus.req.bits.write && accessLegal) {
        memory.write(index, writeData, writeMask)
      }
    }
  }

  connectPort(io.imem, instruction = true)
  connectPort(io.dmem, instruction = false)
}
