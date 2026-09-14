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
    val queueHighWater = Input(UInt(5.W))
    val queueFull = Input(Bool())
    val queueEmpty = Input(Bool())
    val engineBusy = Input(Bool())
    val irqPending = Input(Bool())
    val lastDoneTag = Input(UInt(16.W))
    val lastError = Input(UInt(8.W))
    val frontBuffer = Input(UInt(32.W))
    val backBuffer = Input(UInt(32.W))
    val perfCycles = Input(UInt(64.W))
    val perfPixels = Input(UInt(64.W))
    val perfReadBytes = Input(UInt(64.W))
    val perfWriteBytes = Input(UInt(64.W))
    val perfStalls = Input(UInt(64.W))
    val perfUnderflows = Input(UInt(64.W))
    val perfRenderGrants = Input(UInt(64.W))
    val perfScanoutGrants = Input(UInt(64.W))
    val irqClear = Output(Bool())
    val perfClear = Output(Bool())
    val qosLowWatermark = Output(UInt(12.W))
    val qosHighWatermark = Output(UInt(12.W))
    val qosAdaptiveEnable = Output(Bool())
  })

  private val shadow = RegInit(0.U.asTypeOf(new GpuCommand))
  private val pending = RegInit(false.B)
  private val address = RegInit(0.U(16.W))
  private val write = RegInit(false.B)
  private val writeData = RegInit(0.U(32.W))
  private val setup = io.psel && !io.penable
  private val transfer = io.psel && io.penable && pending
  private val submit = transfer && write && address === GpuRegisterMap.Control.U && writeData(0)
  private val perfCapture = transfer && write &&
    address === GpuRegisterMap.PerfControl.U && writeData(0)
  private val legalOffset = VecInit(GpuRegisterMap.All.map(offset => address === offset.U)).asUInt.orR
  private val perfCycles = RegInit(0.U(64.W))
  private val perfPixels = RegInit(0.U(64.W))
  private val perfReadBytes = RegInit(0.U(64.W))
  private val perfWriteBytes = RegInit(0.U(64.W))
  private val perfStalls = RegInit(0.U(64.W))
  private val perfUnderflows = RegInit(0.U(64.W))
  private val perfRenderGrants = RegInit(0.U(64.W))
  private val perfScanoutGrants = RegInit(0.U(64.W))
  private val qosLowWatermark = RegInit(256.U(12.W))
  private val qosHighWatermark = RegInit(1536.U(12.W))
  private val qosAdaptiveEnable = RegInit(true.B)
  private val qosWrite = transfer && write && address === GpuRegisterMap.QosWatermarks.U
  private val qosWriteValid = writeData(30, 28) === 0.U && writeData(15, 12) === 0.U &&
    writeData(11, 0) < writeData(27, 16)

  when(setup) {
    pending := true.B
    address := io.paddr
    write := io.pwrite
    writeData := io.pwdata
  }.elsewhen(transfer) {
    pending := false.B
  }

  io.pready := transfer
  io.command.valid := submit
  io.command.bits := shadow
  io.irqClear := transfer && write && address === GpuRegisterMap.Control.U && writeData(1)
  io.perfClear := transfer && write && address === GpuRegisterMap.PerfControl.U && writeData(1)
  io.pslverror := transfer && (!legalOffset || (submit && !io.command.ready) ||
    (qosWrite && !qosWriteValid))
  io.qosLowWatermark := qosLowWatermark
  io.qosHighWatermark := qosHighWatermark
  io.qosAdaptiveEnable := qosAdaptiveEnable

  when(perfCapture) {
    perfCycles := io.perfCycles
    perfPixels := io.perfPixels
    perfReadBytes := io.perfReadBytes
    perfWriteBytes := io.perfWriteBytes
    perfStalls := io.perfStalls
    perfUnderflows := io.perfUnderflows
    perfRenderGrants := io.perfRenderGrants
    perfScanoutGrants := io.perfScanoutGrants
  }.elsewhen(io.perfClear) {
    perfCycles := 0.U
    perfPixels := 0.U
    perfReadBytes := 0.U
    perfWriteBytes := 0.U
    perfStalls := 0.U
    perfUnderflows := 0.U
    perfRenderGrants := 0.U
    perfScanoutGrants := 0.U
  }

  when(transfer && write && legalOffset) {
    switch(address) {
      is(GpuRegisterMap.Op.U) { shadow.op := writeData(3, 0) }
      is(GpuRegisterMap.SrcAddr.U) { shadow.srcAddr := writeData }
      is(GpuRegisterMap.DstAddr.U) { shadow.dstAddr := writeData }
      is(GpuRegisterMap.Size.U) {
        shadow.widthPixels := writeData(15, 0)
        shadow.heightPixels := writeData(31, 16)
      }
      is(GpuRegisterMap.SrcStride.U) { shadow.srcStride := writeData }
      is(GpuRegisterMap.DstStride.U) { shadow.dstStride := writeData }
      is(GpuRegisterMap.ColorKey.U) {
        shadow.color := writeData(15, 0)
        shadow.colorKey := writeData(31, 16)
      }
      is(GpuRegisterMap.AlphaFlags.U) {
        shadow.alpha := writeData(7, 0)
        shadow.flags := writeData(31, 16)
      }
      is(GpuRegisterMap.Tag.U) { shadow.tag := writeData(15, 0) }
      is(GpuRegisterMap.QosWatermarks.U) {
        when(qosWriteValid) {
          qosLowWatermark := writeData(11, 0)
          qosHighWatermark := writeData(27, 16)
          qosAdaptiveEnable := writeData(31)
        }
      }
    }
  }

  io.prdata := 0.U
  switch(address) {
    is(GpuRegisterMap.Id.U) { io.prdata := "h32444750".U }
    is(GpuRegisterMap.Version.U) { io.prdata := "h00010000".U }
    is(GpuRegisterMap.Status.U) {
      io.prdata := Cat(
        0.U(18.W), io.irqPending, io.queueHighWater,
        io.engineBusy, io.queueFull, io.queueEmpty, io.queueLevel
      )
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
    is(GpuRegisterMap.QosWatermarks.U) {
      io.prdata := Cat(qosAdaptiveEnable, 0.U(3.W), qosHighWatermark, 0.U(4.W), qosLowWatermark)
    }
    is(GpuRegisterMap.PerfCyclesLo.U) { io.prdata := perfCycles(31, 0) }
    is(GpuRegisterMap.PerfCyclesHi.U) { io.prdata := perfCycles(63, 32) }
    is(GpuRegisterMap.PerfPixelsLo.U) { io.prdata := perfPixels(31, 0) }
    is(GpuRegisterMap.PerfPixelsHi.U) { io.prdata := perfPixels(63, 32) }
    is(GpuRegisterMap.PerfReadBytesLo.U) { io.prdata := perfReadBytes(31, 0) }
    is(GpuRegisterMap.PerfReadBytesHi.U) { io.prdata := perfReadBytes(63, 32) }
    is(GpuRegisterMap.PerfWriteBytesLo.U) { io.prdata := perfWriteBytes(31, 0) }
    is(GpuRegisterMap.PerfWriteBytesHi.U) { io.prdata := perfWriteBytes(63, 32) }
    is(GpuRegisterMap.PerfStallsLo.U) { io.prdata := perfStalls(31, 0) }
    is(GpuRegisterMap.PerfStallsHi.U) { io.prdata := perfStalls(63, 32) }
    is(GpuRegisterMap.PerfUnderflowsLo.U) { io.prdata := perfUnderflows(31, 0) }
    is(GpuRegisterMap.PerfUnderflowsHi.U) { io.prdata := perfUnderflows(63, 32) }
    is(GpuRegisterMap.PerfRenderGrantsLo.U) { io.prdata := perfRenderGrants(31, 0) }
    is(GpuRegisterMap.PerfRenderGrantsHi.U) { io.prdata := perfRenderGrants(63, 32) }
    is(GpuRegisterMap.PerfScanoutGrantsLo.U) { io.prdata := perfScanoutGrants(31, 0) }
    is(GpuRegisterMap.PerfScanoutGrantsHi.U) { io.prdata := perfScanoutGrants(63, 32) }
  }
}
