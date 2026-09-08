package gpu

import chisel3._
import chisel3.util._

class ScanoutPixel extends Bundle {
  val pixel = UInt(16.W)
  val lineLast = Bool()
  val frameLast = Bool()
}

/** Reads one RGB565 framebuffer in display order, one AXI request per row. */
class ScanoutDma(
    frameWidth: Int = GpuMemoryMap.FrameWidth,
    frameHeight: Int = GpuMemoryMap.FrameHeight,
    strideBytes: Int = GpuMemoryMap.FrameWidth * GpuMemoryMap.BytesPerPixel,
    lowWatermark: Int = 256
) extends Module {
  require(frameWidth > 0 && frameHeight > 0)
  require(strideBytes >= frameWidth * GpuMemoryMap.BytesPerPixel)

  val io = IO(new Bundle {
    val enable = Input(Bool())
    val frontBase = Input(UInt(32.W))
    val fifoLevel = Input(UInt(12.W))
    val pixel = Decoupled(new ScanoutPixel)
    val axi = new Axi4MasterPort
    val busy = Output(Bool())
    val frameDone = Output(Bool())
    val error = Output(Bool())
  })

  private val reader = Module(new AxiReadEngine)
  private val aligner = Module(new PixelReadAligner)
  private val idle :: waitDemand :: startAligner :: startRead :: stream :: waitRead :: Nil = Enum(6)
  private val state = RegInit(idle)
  private val rowBase = Reg(UInt(32.W))
  private val row = RegInit(0.U(log2Ceil(frameHeight max 2).W))
  private val readDone = RegInit(false.B)
  private val readError = RegInit(false.B)
  private val frameDone = RegInit(false.B)
  private val error = RegInit(false.B)

  frameDone := false.B
  error := false.B
  io.frameDone := frameDone
  io.error := error
  io.busy := state =/= idle

  when(state === idle && io.enable) {
    rowBase := io.frontBase
    row := 0.U
    state := waitDemand
  }

  when(state === waitDemand && io.fifoLevel <= lowWatermark.U) {
    state := startAligner
  }

  aligner.io.start.valid := state === startAligner
  aligner.io.start.bits.upperFirst := rowBase(1)
  aligner.io.start.bits.pixels := frameWidth.U
  when(aligner.io.start.fire) {
    state := startRead
  }

  reader.io.request.valid := state === startRead
  reader.io.request.bits.address := rowBase
  reader.io.request.bits.bytes := (frameWidth * GpuMemoryMap.BytesPerPixel).U
  when(reader.io.request.fire) {
    readDone := false.B
    readError := false.B
    state := stream
  }

  aligner.io.input.valid := reader.io.data.valid
  aligner.io.input.bits := reader.io.data.bits.data
  reader.io.data.ready := aligner.io.input.ready

  io.pixel.valid := state === stream && aligner.io.output.valid
  io.pixel.bits.pixel := aligner.io.output.bits.pixel
  io.pixel.bits.lineLast := aligner.io.output.bits.last
  io.pixel.bits.frameLast := aligner.io.output.bits.last && row === (frameHeight - 1).U
  aligner.io.output.ready := state === stream && io.pixel.ready

  when(reader.io.done) {
    readDone := true.B
    readError := reader.io.error
  }
  when(io.pixel.fire && io.pixel.bits.lineLast) {
    state := waitRead
  }

  private val rowReadFinished = readDone || reader.io.done
  private val rowReadFailed = readError || reader.io.error
  when(state === waitRead && rowReadFinished) {
    when(rowReadFailed) {
      error := true.B
      state := idle
    }.elsewhen(row === (frameHeight - 1).U) {
      frameDone := true.B
      state := idle
    }.otherwise {
      row := row + 1.U
      rowBase := rowBase + strideBytes.U
      state := waitDemand
    }
  }

  io.axi.ar.valid := reader.io.axiAr.valid
  io.axi.ar.bits := reader.io.axiAr.bits
  reader.io.axiAr.ready := io.axi.ar.ready
  reader.io.axiR.valid := io.axi.r.valid
  reader.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := reader.io.axiR.ready

  io.axi.aw.valid := false.B
  io.axi.aw.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.w.valid := false.B
  io.axi.w.bits := 0.U.asTypeOf(new Axi4WriteData)
  io.axi.b.ready := false.B
}
