package gpu

import chisel3._
import chisel3.util._

class DenseBlitEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val pixelRequest = Decoupled(new PixelTransaction)
    val pixelResult = Flipped(Decoupled(new PixelResult))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
  })

  private val rect = Module(new RectAddressGen)
  private val reader = Module(new AxiReadEngine)
  private val aligner = Module(new PixelReadAligner)
  private val packer = Module(new PixelWritePacker)
  private val writer = Module(new AxiWriteEngine)

  private val idle :: startRect :: startWrite :: startAligner :: startRead :: requestPixel :: waitPixel :: waitRow :: finish :: Nil = Enum(9)
  private val state = RegInit(idle)
  private val commandReg = Reg(new GpuCommand)
  private val srcRowBase = Reg(UInt(32.W))
  private val dstRowBase = Reg(UInt(32.W))
  private val pixelAddress = Reg(UInt(32.W))
  private val pixelRowLast = Reg(Bool())
  private val pixelLast = Reg(Bool())
  private val rowReadDone = RegInit(false.B)
  private val rowWriteDone = RegInit(false.B)
  private val rowReadError = RegInit(false.B)
  private val rowWriteError = RegInit(false.B)
  private val keyedWriteOutstanding = RegInit(false.B)
  private val completionError = RegInit(GpuError.None.U(8.W))

  io.command.ready := state === idle
  when(io.command.fire) {
    commandReg := io.command.bits
    srcRowBase := io.command.bits.srcAddr
    dstRowBase := io.command.bits.dstAddr
    keyedWriteOutstanding := false.B
    completionError := GpuError.None.U
    state := startRect
  }

  private val isCopy = commandReg.op === GpuOpcode.Copy.U
  private val isColorKey = commandReg.op === GpuOpcode.ColorKey.U
  private val hasSource = isCopy || isColorKey
  private val rowBytes = Cat(0.U(15.W), commandReg.widthPixels, 0.U(1.W))
  private val rowTransferBytes = rowBytes + dstRowBase(1, 0)
  private val rowBeats = (rowTransferBytes + 3.U) >> 2

  rect.io.start.valid := state === startRect
  rect.io.start.bits.base := commandReg.dstAddr
  rect.io.start.bits.widthPixels := commandReg.widthPixels
  rect.io.start.bits.heightPixels := commandReg.heightPixels
  rect.io.start.bits.stride := commandReg.dstStride
  when(rect.io.start.fire) {
    state := Mux(isColorKey, startAligner, startWrite)
  }

  private val fixedWriteRequest = state === startWrite
  private val keyedWriteRequest = isColorKey &&
    (state === requestPixel || state === waitPixel || state === waitRow) &&
    packer.io.output.valid && !keyedWriteOutstanding
  writer.io.request.valid := fixedWriteRequest || keyedWriteRequest
  writer.io.request.bits.address := Mux(keyedWriteRequest, packer.io.output.bits.address, dstRowBase)
  writer.io.request.bits.beats := Mux(keyedWriteRequest, 1.U, rowBeats)
  when(writer.io.request.fire) {
    when(keyedWriteRequest) {
      keyedWriteOutstanding := true.B
    }.otherwise {
      rowWriteDone := false.B
      rowWriteError := false.B
      state := Mux(isCopy, startAligner, requestPixel)
    }
  }

  aligner.io.start.valid := state === startAligner
  aligner.io.start.bits.upperFirst := srcRowBase(1)
  aligner.io.start.bits.pixels := commandReg.widthPixels
  when(aligner.io.start.fire) {
    when(isColorKey) {
      rowWriteDone := false.B
      rowWriteError := false.B
      keyedWriteOutstanding := false.B
    }
    state := startRead
  }

  reader.io.request.valid := state === startRead
  reader.io.request.bits.address := srcRowBase
  reader.io.request.bits.bytes := rowBytes
  when(reader.io.request.fire) {
    rowReadDone := false.B
    rowReadError := false.B
    state := requestPixel
  }

  private val sourceValid = !hasSource || aligner.io.output.valid
  io.pixelRequest.valid := state === requestPixel && rect.io.address.valid && sourceValid
  io.pixelRequest.bits.op := commandReg.op(2, 0)
  io.pixelRequest.bits.foreground := aligner.io.output.bits.pixel
  io.pixelRequest.bits.background := 0.U
  io.pixelRequest.bits.fillColor := commandReg.color
  io.pixelRequest.bits.colorKey := commandReg.colorKey
  io.pixelRequest.bits.alpha := commandReg.alpha
  rect.io.address.ready := state === requestPixel && io.pixelRequest.ready && sourceValid
  aligner.io.output.ready := state === requestPixel && hasSource && rect.io.address.valid && io.pixelRequest.ready

  when(io.pixelRequest.fire) {
    pixelAddress := rect.io.address.bits.address
    pixelRowLast := rect.io.address.bits.rowLast
    pixelLast := rect.io.address.bits.last
    state := waitPixel
  }

  packer.io.input.valid := state === waitPixel && io.pixelResult.valid
  packer.io.input.bits.address := pixelAddress
  packer.io.input.bits.pixel := io.pixelResult.bits.pixel
  packer.io.input.bits.writeEnable := io.pixelResult.bits.writeEnable
  packer.io.input.bits.rowLast := pixelRowLast
  io.pixelResult.ready := state === waitPixel && packer.io.input.ready

  when(io.pixelResult.fire) {
    state := Mux(pixelRowLast, waitRow, requestPixel)
  }

  writer.io.data.valid := packer.io.output.valid
  writer.io.data.bits.data := packer.io.output.bits.data
  writer.io.data.bits.strb := packer.io.output.bits.strb
  packer.io.output.ready := writer.io.data.ready

  when(writer.io.done) {
    rowWriteDone := true.B
    rowWriteError := rowWriteError || writer.io.error
    keyedWriteOutstanding := false.B
  }
  when(reader.io.done) {
    rowReadDone := true.B
    rowReadError := reader.io.error
  }

  private val writeFinished = Mux(
    isColorKey,
    !keyedWriteOutstanding && !packer.io.output.valid,
    rowWriteDone || writer.io.done
  )
  private val readFinished = !hasSource || rowReadDone || reader.io.done
  private val transferError = rowWriteError || writer.io.error || rowReadError || reader.io.error
  when(state === waitRow && writeFinished && readFinished) {
    when(transferError) {
      completionError := GpuError.AxiResponse.U
      state := finish
    }.elsewhen(pixelLast) {
      state := finish
    }.otherwise {
      srcRowBase := srcRowBase + commandReg.srcStride
      dstRowBase := dstRowBase + commandReg.dstStride
      state := Mux(isColorKey, startAligner, startWrite)
    }
  }

  io.completion.valid := state === finish
  io.completion.bits.tag := commandReg.tag
  io.completion.bits.error := completionError
  when(io.completion.fire) {
    state := idle
  }

  io.axi.aw.valid := writer.io.axiAw.valid
  io.axi.aw.bits := writer.io.axiAw.bits
  writer.io.axiAw.ready := io.axi.aw.ready
  io.axi.w.valid := writer.io.axiW.valid
  io.axi.w.bits := writer.io.axiW.bits
  writer.io.axiW.ready := io.axi.w.ready
  writer.io.axiB.valid := io.axi.b.valid
  writer.io.axiB.bits := io.axi.b.bits
  io.axi.b.ready := writer.io.axiB.ready

  io.axi.ar.valid := reader.io.axiAr.valid
  io.axi.ar.bits := reader.io.axiAr.bits
  reader.io.axiAr.ready := io.axi.ar.ready
  reader.io.axiR.valid := io.axi.r.valid
  reader.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := reader.io.axiR.ready

  aligner.io.input.valid := reader.io.data.valid
  aligner.io.input.bits := reader.io.data.bits.data
  reader.io.data.ready := aligner.io.input.ready
}
