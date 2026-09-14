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
  private val reader = Module(new AxiReadEngine(0))
  private val backgroundReader = Module(new AxiReadEngine(1))
  private val aligner = Module(new PixelReadAligner)
  private val backgroundAligner = Module(new PixelReadAligner)
  private val packer = Module(new PixelWritePacker)
  private val writer = Module(new AxiWriteEngine)
  private val readAddressArbiter = Module(new RRArbiter(new Axi4Address, 2))

  private val idle :: startRect :: startWrite :: startAligner :: startRead :: startAlphaAligners :: startAlphaReads :: requestPixel :: waitPixel :: waitRow :: finish :: Nil = Enum(11)
  private val state = RegInit(idle)
  private val commandReg = Reg(new GpuCommand)
  private val srcRowBase = Reg(UInt(32.W))
  private val dstRowBase = Reg(UInt(32.W))
  private val alphaSrcAddress = Reg(UInt(32.W))
  private val pixelAddress = Reg(UInt(32.W))
  private val pixelRowLast = Reg(Bool())
  private val pixelLast = Reg(Bool())
  private val pixelChunkLast = Reg(Bool())
  private val rowReadDone = RegInit(false.B)
  private val rowWriteDone = RegInit(false.B)
  private val rowReadError = RegInit(false.B)
  private val backgroundReadError = RegInit(false.B)
  private val rowWriteError = RegInit(false.B)
  private val dynamicWriteOutstanding = RegInit(false.B)
  private val completionError = RegInit(GpuError.None.U(8.W))

  io.command.ready := state === idle
  when(io.command.fire) {
    commandReg := io.command.bits
    srcRowBase := io.command.bits.srcAddr
    dstRowBase := io.command.bits.dstAddr
    alphaSrcAddress := io.command.bits.srcAddr
    rowReadDone := false.B
    rowWriteDone := false.B
    rowReadError := false.B
    backgroundReadError := false.B
    rowWriteError := false.B
    dynamicWriteOutstanding := false.B
    completionError := GpuError.None.U
    state := startRect
  }

  private val isCopy = commandReg.op === GpuOpcode.Copy.U
  private val isColorKey = commandReg.op === GpuOpcode.ColorKey.U
  private val isAlpha = commandReg.op === GpuOpcode.Alpha.U
  private val hasSource = isCopy || isColorKey || isAlpha
  private val rowBytes = Cat(0.U(15.W), commandReg.widthPixels, 0.U(1.W))
  private val rowTransferBytes = rowBytes + dstRowBase(1, 0)
  private val rowBeats = (rowTransferBytes + 3.U) >> 2

  rect.io.start.valid := state === startRect
  rect.io.start.bits.base := commandReg.dstAddr
  rect.io.start.bits.widthPixels := commandReg.widthPixels
  rect.io.start.bits.heightPixels := commandReg.heightPixels
  rect.io.start.bits.stride := commandReg.dstStride
  when(rect.io.start.fire) {
    state := Mux(isColorKey, startAligner, Mux(isAlpha, startAlphaAligners, startWrite))
  }

  private val fixedWriteRequest = state === startWrite
  private val dynamicWriteRequest = (isColorKey || isAlpha) &&
    packer.io.output.valid && !dynamicWriteOutstanding
  writer.io.request.valid := fixedWriteRequest || dynamicWriteRequest
  writer.io.request.bits.address := Mux(dynamicWriteRequest, packer.io.output.bits.address, dstRowBase)
  writer.io.request.bits.beats := Mux(dynamicWriteRequest, 1.U, rowBeats)
  when(writer.io.request.fire) {
    when(dynamicWriteRequest) {
      dynamicWriteOutstanding := true.B
    }.otherwise {
      rowWriteDone := false.B
      rowWriteError := false.B
      state := Mux(isCopy, startAligner, requestPixel)
    }
  }

  private val alphaChunkPixels = Mux(
    !alphaSrcAddress(1) && !rect.io.address.bits.address(1) && !rect.io.address.bits.rowLast,
    2.U,
    1.U
  )
  private val startingSourceRow = state === startAligner
  private val startingAlphaPair = state === startAlphaAligners
  aligner.io.start.valid := startingSourceRow || (startingAlphaPair && backgroundAligner.io.start.ready)
  aligner.io.start.bits.upperFirst := Mux(isAlpha, alphaSrcAddress(1), srcRowBase(1))
  aligner.io.start.bits.pixels := Mux(isAlpha, alphaChunkPixels, commandReg.widthPixels)
  backgroundAligner.io.start.valid := startingAlphaPair && aligner.io.start.ready
  backgroundAligner.io.start.bits.upperFirst := rect.io.address.bits.address(1)
  backgroundAligner.io.start.bits.pixels := alphaChunkPixels
  when(startingSourceRow && aligner.io.start.fire) {
    when(isColorKey) {
      rowWriteDone := false.B
      rowWriteError := false.B
      dynamicWriteOutstanding := false.B
    }
    state := startRead
  }
  when(startingAlphaPair && aligner.io.start.fire && backgroundAligner.io.start.fire) {
    state := startAlphaReads
  }

  private val startingSourceRead = state === startRead
  private val startingAlphaReads = state === startAlphaReads
  reader.io.request.valid := startingSourceRead || (startingAlphaReads && backgroundReader.io.request.ready)
  reader.io.request.bits.address := Mux(isAlpha, alphaSrcAddress, srcRowBase)
  reader.io.request.bits.bytes := Mux(isAlpha, alphaChunkPixels << 1, rowBytes)
  backgroundReader.io.request.valid := startingAlphaReads && reader.io.request.ready
  backgroundReader.io.request.bits.address := rect.io.address.bits.address
  backgroundReader.io.request.bits.bytes := alphaChunkPixels << 1
  when(startingSourceRead && reader.io.request.fire) {
    rowReadDone := false.B
    rowReadError := false.B
    state := requestPixel
  }
  when(startingAlphaReads && reader.io.request.fire && backgroundReader.io.request.fire) {
    state := requestPixel
  }

  private val sourceValid = !hasSource ||
    (aligner.io.output.valid && (!isAlpha || backgroundAligner.io.output.valid))
  io.pixelRequest.valid := state === requestPixel && rect.io.address.valid && sourceValid
  io.pixelRequest.bits.op := commandReg.op(2, 0)
  io.pixelRequest.bits.foreground := aligner.io.output.bits.pixel
  io.pixelRequest.bits.background := Mux(isAlpha, backgroundAligner.io.output.bits.pixel, 0.U)
  io.pixelRequest.bits.fillColor := commandReg.color
  io.pixelRequest.bits.colorKey := commandReg.colorKey
  io.pixelRequest.bits.alpha := commandReg.alpha
  rect.io.address.ready := state === requestPixel && io.pixelRequest.ready && sourceValid
  aligner.io.output.ready := state === requestPixel && hasSource && rect.io.address.valid && io.pixelRequest.ready &&
    (!isAlpha || backgroundAligner.io.output.valid)
  backgroundAligner.io.output.ready := state === requestPixel && isAlpha && rect.io.address.valid &&
    io.pixelRequest.ready && aligner.io.output.valid

  when(io.pixelRequest.fire) {
    pixelAddress := rect.io.address.bits.address
    pixelRowLast := rect.io.address.bits.rowLast
    pixelLast := rect.io.address.bits.last
    pixelChunkLast := aligner.io.output.bits.last
    when(isAlpha) { alphaSrcAddress := alphaSrcAddress + 2.U }
    state := waitPixel
  }

  packer.io.input.valid := state === waitPixel && io.pixelResult.valid
  packer.io.input.bits.address := pixelAddress
  packer.io.input.bits.pixel := io.pixelResult.bits.pixel
  packer.io.input.bits.writeEnable := io.pixelResult.bits.writeEnable
  packer.io.input.bits.rowLast := pixelRowLast
  io.pixelResult.ready := state === waitPixel && packer.io.input.ready

  when(io.pixelResult.fire) {
    state := Mux(pixelRowLast, waitRow, Mux(isAlpha && pixelChunkLast, startAlphaAligners, requestPixel))
  }

  writer.io.data.valid := packer.io.output.valid
  writer.io.data.bits.data := packer.io.output.bits.data
  writer.io.data.bits.strb := packer.io.output.bits.strb
  packer.io.output.ready := writer.io.data.ready

  when(writer.io.done) {
    rowWriteDone := true.B
    rowWriteError := rowWriteError || writer.io.error
    dynamicWriteOutstanding := false.B
  }
  when(reader.io.done) {
    rowReadDone := true.B
    rowReadError := rowReadError || reader.io.error
  }
  when(backgroundReader.io.done) {
    backgroundReadError := backgroundReadError || backgroundReader.io.error
  }

  private val writeFinished = Mux(
    isColorKey || isAlpha,
    !dynamicWriteOutstanding && !packer.io.output.valid,
    rowWriteDone || writer.io.done
  )
  private val readFinished = Mux(
    isAlpha,
    reader.io.request.ready && backgroundReader.io.request.ready,
    !hasSource || rowReadDone || reader.io.done
  )
  private val transferError = rowWriteError || writer.io.error || rowReadError || reader.io.error ||
    (isAlpha && (backgroundReadError || backgroundReader.io.error))
  when(state === waitRow && writeFinished && readFinished) {
    when(transferError) {
      completionError := GpuError.AxiResponse.U
      state := finish
    }.elsewhen(pixelLast) {
      state := finish
    }.otherwise {
      srcRowBase := srcRowBase + commandReg.srcStride
      dstRowBase := dstRowBase + commandReg.dstStride
      rowReadDone := false.B
      rowWriteDone := false.B
      rowReadError := false.B
      backgroundReadError := false.B
      rowWriteError := false.B
      dynamicWriteOutstanding := false.B
      when(isAlpha) { alphaSrcAddress := srcRowBase + commandReg.srcStride }
      state := Mux(isColorKey, startAligner, Mux(isAlpha, startAlphaAligners, startWrite))
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

  readAddressArbiter.io.in(0) <> reader.io.axiAr
  readAddressArbiter.io.in(1) <> backgroundReader.io.axiAr
  io.axi.ar.valid := readAddressArbiter.io.out.valid
  io.axi.ar.bits := readAddressArbiter.io.out.bits
  readAddressArbiter.io.out.ready := io.axi.ar.ready
  private val backgroundResponse = io.axi.r.bits.id === 1.U
  reader.io.axiR.valid := io.axi.r.valid && !backgroundResponse
  reader.io.axiR.bits := io.axi.r.bits
  backgroundReader.io.axiR.valid := io.axi.r.valid && backgroundResponse
  backgroundReader.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := Mux(backgroundResponse, backgroundReader.io.axiR.ready, reader.io.axiR.ready)

  aligner.io.input.valid := reader.io.data.valid
  aligner.io.input.bits := reader.io.data.bits.data
  reader.io.data.ready := aligner.io.input.ready
  backgroundAligner.io.input.valid := backgroundReader.io.data.valid
  backgroundAligner.io.input.bits := backgroundReader.io.data.bits.data
  backgroundReader.io.data.ready := backgroundAligner.io.input.ready
}
