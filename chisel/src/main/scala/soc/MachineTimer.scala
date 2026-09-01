package soc

import chisel3._
import chisel3.util._

class MachineTimer extends Module {
  val io = IO(new Bundle {
    val bus = new SocBusTargetIO
    val interrupt = Output(Bool())
  })

  private val mtime = RegInit(0.U(64.W))
  private val mtimecmp = RegInit("hffffffffffffffff".U(64.W))
  private val responseValid = RegInit(false.B)
  private val responseData = RegInit(0.U(32.W))
  private val responseError = RegInit(false.B)

  mtime := mtime + 1.U
  io.interrupt := mtime >= mtimecmp

  io.bus.req.ready := !responseValid
  io.bus.resp.valid := responseValid
  io.bus.resp.bits.rdata := responseData
  io.bus.resp.bits.error := responseError

  when(io.bus.resp.fire) {
    responseValid := false.B
  }

  when(io.bus.req.fire) {
    val offset = io.bus.req.bits.addr(15, 0)
    val legalWord = io.bus.req.bits.size === 2.U && io.bus.req.bits.addr(1, 0) === 0.U
    val fullWrite = io.bus.req.bits.wstrb === "b1111".U
    val mtimecmpLow = offset === MemoryMap.Timer.MtimecmpLowOffset.U
    val mtimecmpHigh = offset === MemoryMap.Timer.MtimecmpHighOffset.U
    val mtimeLow = offset === MemoryMap.Timer.MtimeLowOffset.U
    val mtimeHigh = offset === MemoryMap.Timer.MtimeHighOffset.U
    val readable = mtimecmpLow || mtimecmpHigh || mtimeLow || mtimeHigh
    val writable = mtimecmpLow || mtimecmpHigh
    val legalAccess = legalWord && Mux(io.bus.req.bits.write, writable && fullWrite, readable)

    responseValid := true.B
    responseData := MuxCase(0.U, Seq(
      (!io.bus.req.bits.write && mtimecmpLow) -> mtimecmp(31, 0),
      (!io.bus.req.bits.write && mtimecmpHigh) -> mtimecmp(63, 32),
      (!io.bus.req.bits.write && mtimeLow) -> mtime(31, 0),
      (!io.bus.req.bits.write && mtimeHigh) -> mtime(63, 32)
    ))
    responseError := !legalAccess

    when(legalWord && fullWrite && io.bus.req.bits.write && mtimecmpLow) {
      mtimecmp := Cat(mtimecmp(63, 32), io.bus.req.bits.wdata)
    }.elsewhen(legalWord && fullWrite && io.bus.req.bits.write && mtimecmpHigh) {
      mtimecmp := Cat(io.bus.req.bits.wdata, mtimecmp(31, 0))
    }
  }
}
