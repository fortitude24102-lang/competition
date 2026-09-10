package gpu

import chisel3._
import chisel3.util._

class GpuApbRegs extends Module {
  val io = IO(new Bundle {
    val paddr = Input(UInt(16.W))
    val psel = Input(Bool())
    val penable = Input(Bool())
    val pwrite = Input(Bool())
    val pwdata = Input(UInt(32.W))
    val prdata = Output(UInt(32.W))
    val pready = Output(Bool())
    val pslverror = Output(Bool())

    val command = Decoupled(new GpuCommand)
    val queueLevel = Input(UInt(5.W))
    val queueFull = Input(Bool())
    val queueEmpty = Input(Bool())
    val engineBusy = Input(Bool())
    val lastDoneTag = Input(UInt(16.W))
    val lastError = Input(UInt(8.W))
    val frontBuffer = Input(UInt(32.W))
    val backBuffer = Input(UInt(32.W))
  })

  private val shadow = RegInit(0.U.asTypeOf(new GpuCommand))
  private val transfer = io.psel && io.penable
  private val submit = transfer && io.pwrite && io.paddr === GpuRegisterMap.Control.U && io.pwdata(0)
  private val legalOffset = VecInit(GpuRegisterMap.All.map(offset => io.paddr === offset.U)).asUInt.orR

  io.pready := true.B
  io.command.valid := submit
  io.command.bits := shadow
  io.pslverror := transfer && (!legalOffset || (submit && !io.command.ready))

  when(transfer && io.pwrite && legalOffset) {
    switch(io.paddr) {
      is(GpuRegisterMap.Op.U) { shadow.op := io.pwdata(3, 0) }
      is(GpuRegisterMap.SrcAddr.U) { shadow.srcAddr := io.pwdata }
      is(GpuRegisterMap.DstAddr.U) { shadow.dstAddr := io.pwdata }
      is(GpuRegisterMap.Size.U) {
        shadow.widthPixels := io.pwdata(15, 0)
        shadow.heightPixels := io.pwdata(31, 16)
      }
      is(GpuRegisterMap.SrcStride.U) { shadow.srcStride := io.pwdata }
      is(GpuRegisterMap.DstStride.U) { shadow.dstStride := io.pwdata }
      is(GpuRegisterMap.ColorKey.U) {
        shadow.color := io.pwdata(15, 0)
        shadow.colorKey := io.pwdata(31, 16)
      }
      is(GpuRegisterMap.AlphaFlags.U) {
        shadow.alpha := io.pwdata(7, 0)
        shadow.flags := io.pwdata(31, 16)
      }
      is(GpuRegisterMap.Tag.U) { shadow.tag := io.pwdata(15, 0) }
    }
  }

  io.prdata := 0.U
  switch(io.paddr) {
    is(GpuRegisterMap.Id.U) { io.prdata := "h32444750".U }
    is(GpuRegisterMap.Version.U) { io.prdata := "h00010000".U }
    is(GpuRegisterMap.Status.U) {
      io.prdata := Cat(0.U(24.W), io.engineBusy, io.queueFull, io.queueEmpty, io.queueLevel)
    }
    is(GpuRegisterMap.Op.U) { io.prdata := shadow.op }
    is(GpuRegisterMap.SrcAddr.U) { io.prdata := shadow.srcAddr }
    is(GpuRegisterMap.DstAddr.U) { io.prdata := shadow.dstAddr }
    is(GpuRegisterMap.Size.U) { io.prdata := Cat(shadow.heightPixels, shadow.widthPixels) }
    is(GpuRegisterMap.SrcStride.U) { io.prdata := shadow.srcStride }
    is(GpuRegisterMap.DstStride.U) { io.prdata := shadow.dstStride }
    is(GpuRegisterMap.ColorKey.U) { io.prdata := Cat(shadow.colorKey, shadow.color) }
    is(GpuRegisterMap.AlphaFlags.U) { io.prdata := Cat(shadow.flags, 0.U(8.W), shadow.alpha) }
    is(GpuRegisterMap.Tag.U) { io.prdata := shadow.tag }
    is(GpuRegisterMap.LastDone.U) { io.prdata := io.lastDoneTag }
    is(GpuRegisterMap.Error.U) { io.prdata := io.lastError }
    is(GpuRegisterMap.QueueLevel.U) { io.prdata := io.queueLevel }
    is(GpuRegisterMap.FrontBuffer.U) { io.prdata := io.frontBuffer }
    is(GpuRegisterMap.BackBuffer.U) { io.prdata := io.backBuffer }
  }
}
