package gpu

import chisel3._
import chisel3.util._

class DenseBlitEngine(enableCopyStream: Boolean = true) extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val pixelRequest = Decoupled(new PixelTransaction)
    val pixelResult = Flipped(Decoupled(new PixelResult))
    val copyWordDone = Output(Bool())
    val wordPixelsDone = Output(UInt(2.W))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
    val textureCacheLoad = Flipped(Valid(new TextureCacheLoad))
    val textureCacheInvalidate = Input(Bool())
    val textureCachePerfClear = Input(Bool())
    val textureCacheValid = Output(Bool())
    val textureCacheBusy = Output(Bool())
    val textureCacheError = Output(Bool())
    val textureCacheHitBytes = Output(UInt(64.W))
  })

  private val rect = Module(new RectAddressGen)
  private val reader = Module(new AxiReadEngine(0))
  private val backgroundReader = Module(new AxiReadEngine(1))
  private val textureCache = Module(new TextureCache)
  private val aligner = Module(new PixelReadAligner)
  private val wordAligner = Module(new Rgb565WordAligner)
  private val backgroundAligner = Module(new PixelReadAligner)
  private val alphaForegroundBuffer = Module(new Queue(UInt(32.W), 33))
  private val alphaBackgroundBuffer = Module(new Queue(UInt(32.W), 33))
  private val packer = Module(new PixelWritePacker)
  private val writer = Module(new AxiWriteEngine)
  private val copyStream = Module(new CopyStreamEngine)
  private val readAddressArbiter = Module(new RRArbiter(new Axi4Address, 2))

  private val idle :: startRect :: startWrite :: startAligner :: startRead :: startAlphaAligners :: startAlphaReads :: waitAlphaReads :: requestPixel :: waitPixel :: waitRow :: finish :: streamCopy :: Nil = Enum(13)
  private val state = RegInit(idle)
  private val commandReg = Reg(new GpuCommand)
  private val srcRowBase = Reg(UInt(32.W))
  private val dstRowBase = Reg(UInt(32.W))
  private val alphaSrcAddress = Reg(UInt(32.W))
  private val alphaChunkDstAddress = Reg(UInt(32.W))
  private val alphaChunkBeats = Reg(UInt(32.W))
  private val pixelAddress = Reg(UInt(32.W))
  private val pixelRowLast = Reg(Bool())
  private val pixelLast = Reg(Bool())
  private val pixelChunkLast = Reg(Bool())
  private val fastWordBlit = RegInit(false.B)
  private val directWordBlit = RegInit(false.B)
  private val fastRowsLeft = Reg(UInt(16.W))
  private val rowReadDone = RegInit(false.B)
  private val rowWriteDone = RegInit(false.B)
  private val rowReadError = RegInit(false.B)
  private val backgroundReadError = RegInit(false.B)
  private val rowWriteError = RegInit(false.B)
  private val dynamicWriteOutstanding = RegInit(false.B)
  private val completionError = RegInit(GpuError.None.U(8.W))
  private val useTextureCache = RegInit(false.B)

  textureCache.io.load.valid := io.textureCacheLoad.valid
  textureCache.io.load.bits := io.textureCacheLoad.bits
  textureCache.io.invalidate := io.textureCacheInvalidate
  textureCache.io.perfClear := io.textureCachePerfClear
  io.textureCacheValid := textureCache.io.valid
  io.textureCacheBusy := textureCache.io.busy
  io.textureCacheError := textureCache.io.error
  io.textureCacheHitBytes := textureCache.io.hitBytes

  io.command.ready := state === idle && !textureCache.io.busy
  private val streamingCopy = state === streamCopy
  private val selectCopyStream = enableCopyStream.B && copyStream.io.eligible
  copyStream.io.command.valid := io.command.valid && io.command.ready && selectCopyStream
  copyStream.io.command.bits := io.command.bits
  copyStream.io.readDone := reader.io.done && streamingCopy
  copyStream.io.readError := reader.io.error
  copyStream.io.writeDone := writer.io.done && streamingCopy
  copyStream.io.writeError := writer.io.error
  private val incomingCommand = io.command.bits
  private val incomingAligned = incomingCommand.srcAddr(1, 0) === 0.U &&
    incomingCommand.dstAddr(1, 0) === 0.U && incomingCommand.srcStride(1, 0) === 0.U &&
    incomingCommand.dstStride(1, 0) === 0.U && incomingCommand.widthPixels(0) === 0.U
  private val rowsBeforeLast = (incomingCommand.heightPixels - 1.U)(15, 0)
  private val sourceEnd = incomingCommand.srcAddr.pad(49) +
    rowsBeforeLast * incomingCommand.srcStride + (incomingCommand.widthPixels << 1)
  private val destinationEnd = incomingCommand.dstAddr.pad(49) +
    rowsBeforeLast * incomingCommand.dstStride + (incomingCommand.widthPixels << 1)
  private val incomingOverlap = incomingCommand.srcAddr < destinationEnd && incomingCommand.dstAddr < sourceEnd
  private val sourceEnd64 = incomingCommand.srcAddr.pad(64) +
    (rowsBeforeLast * incomingCommand.srcStride).pad(64) +
    (incomingCommand.widthPixels << 1).pad(64)
  private val cacheEnd64 = textureCache.io.base.pad(64) + textureCache.io.bytes.pad(64)
  private val incomingCacheHit = textureCache.io.valid &&
    (incomingCommand.op === GpuOpcode.ColorKey.U || incomingCommand.op === GpuOpcode.Alpha.U) &&
    incomingCommand.srcAddr >= textureCache.io.base && sourceEnd64 <= cacheEnd64
  when(io.command.fire) {
    commandReg := io.command.bits
    // Preserve legacy overlapping Key commands; only extend the non-overlapping path.
    fastWordBlit := ((incomingCommand.op === GpuOpcode.Copy.U ||
      incomingCommand.op === GpuOpcode.ColorKey.U) && incomingAligned) ||
      (incomingCommand.op === GpuOpcode.ColorKey.U && !incomingOverlap)
    directWordBlit := incomingAligned
    fastRowsLeft := io.command.bits.heightPixels
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
    useTextureCache := incomingCacheHit
    state := Mux(selectCopyStream, streamCopy, startRect)
  }

  private val isCopy = commandReg.op === GpuOpcode.Copy.U
  private val isColorKey = commandReg.op === GpuOpcode.ColorKey.U
  private val isAlpha = commandReg.op === GpuOpcode.Alpha.U
  private val hasSource = isCopy || isColorKey || isAlpha
  private val rowBytes = Cat(0.U(15.W), commandReg.widthPixels, 0.U(1.W))
  private val rowTransferBytes = rowBytes + dstRowBase(1, 0)
  private val rowBeats = (rowTransferBytes + 3.U) >> 2

  rect.io.start.valid := state === startRect && !fastWordBlit
  rect.io.start.bits.base := commandReg.dstAddr
  rect.io.start.bits.widthPixels := commandReg.widthPixels
  rect.io.start.bits.heightPixels := commandReg.heightPixels
  rect.io.start.bits.stride := commandReg.dstStride
  when(rect.io.start.fire) {
    state := Mux(isColorKey, startAligner, Mux(isAlpha, startAlphaAligners, startWrite))
  }
  when(state === startRect && fastWordBlit) {
    state := startWrite
  }

  private val fixedWriteRequest = state === startWrite
  private val dynamicWriteRequest = isColorKey && !fastWordBlit &&
    packer.io.output.valid && !dynamicWriteOutstanding
  writer.io.request.valid := Mux(streamingCopy, copyStream.io.writeRequest.valid,
    fixedWriteRequest || dynamicWriteRequest)
  writer.io.request.bits.address := Mux(streamingCopy, copyStream.io.writeRequest.bits.address,
    Mux(dynamicWriteRequest, packer.io.output.bits.address, Mux(isAlpha, alphaChunkDstAddress, dstRowBase)))
  writer.io.request.bits.beats := Mux(streamingCopy, copyStream.io.writeRequest.bits.beats,
    Mux(dynamicWriteRequest, 1.U, Mux(isAlpha, alphaChunkBeats, rowBeats)))
  copyStream.io.writeRequest.ready := writer.io.request.ready && streamingCopy
  when(writer.io.request.fire && !streamingCopy) {
    when(dynamicWriteRequest) {
      dynamicWriteOutstanding := true.B
    }.otherwise {
      rowWriteDone := false.B
      state := Mux(fastWordBlit && directWordBlit, startRead,
        Mux(fastWordBlit || isCopy, startAligner, requestPixel))
    }
  }

  private val alphaRowProgress = ((alphaSrcAddress - srcRowBase) >> 1)(15, 0)
  private val alphaPixelsLeft = (commandReg.widthPixels - alphaRowProgress)(15, 0)
  private val alphaChunkPixels = Mux(alphaPixelsLeft > 64.U, 64.U(16.W), alphaPixelsLeft)
  private val startingSourceRow = state === startAligner && !fastWordBlit
  wordAligner.io.start.valid := state === startAligner && fastWordBlit
  wordAligner.io.start.bits.sourceUpper := srcRowBase(1)
  wordAligner.io.start.bits.destinationUpper := dstRowBase(1)
  wordAligner.io.start.bits.pixels := commandReg.widthPixels
  when(wordAligner.io.start.fire) { state := startRead }
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
    alphaChunkDstAddress := rect.io.address.bits.address
    alphaChunkBeats := ((alphaChunkPixels << 1) + rect.io.address.bits.address(1, 0) + 3.U) >> 2
    state := startAlphaReads
  }

  private val startingSourceRead = state === startRead
  private val startingAlphaReads = state === startAlphaReads
  private val sourceReadAddress = Mux(isAlpha, alphaSrcAddress, srcRowBase)
  private val sourceReadBytes = Mux(isAlpha, alphaChunkPixels << 1, rowBytes)
  private val sourceReadReady = Mux(useTextureCache,
    textureCache.io.readRequest.ready, reader.io.request.ready)
  private val sourceReadValid = startingSourceRead ||
    (startingAlphaReads && backgroundReader.io.request.ready)
  reader.io.request.valid := Mux(streamingCopy, copyStream.io.readRequest.valid,
    sourceReadValid && !useTextureCache)
  reader.io.request.bits.address := Mux(streamingCopy, copyStream.io.readRequest.bits.address, sourceReadAddress)
  reader.io.request.bits.bytes := Mux(streamingCopy, copyStream.io.readRequest.bits.bytes, sourceReadBytes)
  copyStream.io.readRequest.ready := reader.io.request.ready && streamingCopy
  textureCache.io.readRequest.valid := sourceReadValid && useTextureCache
  textureCache.io.readRequest.bits.address := sourceReadAddress
  textureCache.io.readRequest.bits.bytes := sourceReadBytes
  backgroundReader.io.request.valid := startingAlphaReads && sourceReadReady
  backgroundReader.io.request.bits.address := rect.io.address.bits.address
  backgroundReader.io.request.bits.bytes := alphaChunkPixels << 1
  private val sourceReadFire = sourceReadValid && sourceReadReady
  when(startingSourceRead && sourceReadFire) {
    rowReadDone := false.B
    rowReadError := false.B
    state := Mux(fastWordBlit, waitRow, requestPixel)
  }
  when(startingAlphaReads && sourceReadFire && backgroundReader.io.request.fire) {
    state := waitAlphaReads
  }
  when(state === waitAlphaReads && sourceReadReady && backgroundReader.io.request.ready) {
    state := startWrite
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
  packer.io.input.bits.rowLast := pixelRowLast || (isAlpha && pixelChunkLast)
  io.pixelResult.ready := state === waitPixel && packer.io.input.ready

  when(io.pixelResult.fire) {
    state := Mux(pixelRowLast, waitRow, Mux(isAlpha && pixelChunkLast, startAlphaAligners, requestPixel))
  }

  // Keep every beat in the burst, including transparent words with WSTRB=0.
  // Two RGB565 comparisons preserve background without reading it.
  private val sourceDataValid = Mux(useTextureCache,
    textureCache.io.readData.valid, reader.io.data.valid)
  private val sourceDataBits = Mux(useTextureCache,
    textureCache.io.readData.bits, reader.io.data.bits)
  private val sourceDone = Mux(useTextureCache, textureCache.io.readDone, reader.io.done)
  private val sourceError = Mux(useTextureCache, textureCache.io.readError, reader.io.error)
  private val wordData = Mux(directWordBlit, sourceDataBits.data, wordAligner.io.output.bits.data)
  private val validLanes = Mux(directWordBlit, "b11".U, wordAligner.io.output.bits.lanes)
  private val keyWordStrobe = Cat(
    Fill(2, validLanes(1) && wordData(31, 16) =/= commandReg.colorKey),
    Fill(2, validLanes(0) && wordData(15, 0) =/= commandReg.colorKey))
  writer.io.data.valid := Mux(streamingCopy, copyStream.io.writeData.valid, Mux(fastWordBlit,
    Mux(directWordBlit, sourceDataValid, wordAligner.io.output.valid), packer.io.output.valid))
  writer.io.data.bits.data := Mux(streamingCopy, copyStream.io.writeData.bits.data,
    Mux(fastWordBlit, wordData, packer.io.output.bits.data))
  writer.io.data.bits.strb := Mux(streamingCopy, copyStream.io.writeData.bits.strb,
    Mux(fastWordBlit, Mux(isColorKey, keyWordStrobe, "hf".U), packer.io.output.bits.strb))
  copyStream.io.writeData.ready := writer.io.data.ready && streamingCopy
  packer.io.output.ready := !fastWordBlit && writer.io.data.ready
  // Transparent pixels are processed too; partial first/last words count only valid lanes.
  io.copyWordDone := (fastWordBlit || streamingCopy) && writer.io.data.fire
  io.wordPixelsDone := Mux(io.copyWordDone,
    Mux(streamingCopy || directWordBlit, 2.U, wordAligner.io.output.bits.pixels), 0.U)
  wordAligner.io.output.ready := fastWordBlit && !directWordBlit && writer.io.data.ready

  when(writer.io.done) {
    rowWriteDone := true.B
    rowWriteError := rowWriteError || writer.io.error
    dynamicWriteOutstanding := false.B
  }
  when(sourceDone) {
    rowReadDone := true.B
    rowReadError := rowReadError || sourceError
  }
  when(backgroundReader.io.done) {
    backgroundReadError := backgroundReadError || backgroundReader.io.error
  }

  private val writeFinished = Mux(
    isColorKey && !fastWordBlit,
    !dynamicWriteOutstanding && !packer.io.output.valid,
    rowWriteDone || writer.io.done
  )
  private val readFinished = Mux(
    isAlpha,
    sourceReadReady && backgroundReader.io.request.ready,
    !hasSource || rowReadDone || sourceDone
  )
  private val transferError = rowWriteError || writer.io.error || rowReadError || sourceError ||
    (isAlpha && (backgroundReadError || backgroundReader.io.error))
  when(state === waitRow && writeFinished && readFinished) {
    when(transferError) {
      completionError := GpuError.AxiResponse.U
      state := finish
    }.elsewhen(Mux(fastWordBlit, fastRowsLeft === 1.U, pixelLast)) {
      state := finish
    }.otherwise {
      when(fastWordBlit) { fastRowsLeft := fastRowsLeft - 1.U }
      srcRowBase := srcRowBase + commandReg.srcStride
      dstRowBase := dstRowBase + commandReg.dstStride
      rowReadDone := false.B
      rowWriteDone := false.B
      rowReadError := false.B
      backgroundReadError := false.B
      rowWriteError := false.B
      dynamicWriteOutstanding := false.B
      when(isAlpha) { alphaSrcAddress := srcRowBase + commandReg.srcStride }
      state := Mux(isColorKey && !fastWordBlit, startAligner, Mux(isAlpha, startAlphaAligners, startWrite))
    }
  }

  io.completion.valid := Mux(streamingCopy, copyStream.io.completion.valid, state === finish)
  io.completion.bits.tag := Mux(streamingCopy, copyStream.io.completion.bits.tag, commandReg.tag)
  io.completion.bits.error := Mux(streamingCopy, copyStream.io.completion.bits.error, completionError)
  copyStream.io.completion.ready := io.completion.ready && streamingCopy
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
  private val textureCacheOwnsAxi = textureCache.io.busy
  io.axi.ar.valid := Mux(textureCacheOwnsAxi,
    textureCache.io.axi.ar.valid, readAddressArbiter.io.out.valid)
  io.axi.ar.bits := Mux(textureCacheOwnsAxi,
    textureCache.io.axi.ar.bits, readAddressArbiter.io.out.bits)
  textureCache.io.axi.ar.ready := io.axi.ar.ready && textureCacheOwnsAxi
  readAddressArbiter.io.out.ready := io.axi.ar.ready && !textureCacheOwnsAxi
  // Only Alpha issues background reads. A bad RID=1 during Copy must reach
  // the foreground reader, which drains it and reports an AXI error.
  private val backgroundResponse = isAlpha && io.axi.r.bits.id === 1.U
  textureCache.io.axi.r.valid := io.axi.r.valid && textureCacheOwnsAxi
  textureCache.io.axi.r.bits := io.axi.r.bits
  reader.io.axiR.valid := io.axi.r.valid && !textureCacheOwnsAxi && !backgroundResponse
  reader.io.axiR.bits := io.axi.r.bits
  backgroundReader.io.axiR.valid := io.axi.r.valid && !textureCacheOwnsAxi && backgroundResponse
  backgroundReader.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := Mux(textureCacheOwnsAxi, textureCache.io.axi.r.ready,
    Mux(backgroundResponse, backgroundReader.io.axiR.ready, reader.io.axiR.ready))
  textureCache.io.axi.aw.ready := false.B
  textureCache.io.axi.w.ready := false.B
  textureCache.io.axi.b.valid := false.B
  textureCache.io.axi.b.bits := 0.U.asTypeOf(new Axi4WriteResponse)

  alphaForegroundBuffer.io.enq.valid := isAlpha && sourceDataValid
  alphaForegroundBuffer.io.enq.bits := sourceDataBits.data
  private val sourceDataReady = Mux(isAlpha, alphaForegroundBuffer.io.enq.ready,
    Mux(fastWordBlit, Mux(directWordBlit, writer.io.data.ready,
      wordAligner.io.input.ready), aligner.io.input.ready))
  reader.io.data.ready := Mux(streamingCopy, copyStream.io.readData.ready, sourceDataReady && !useTextureCache)
  copyStream.io.readData.valid := reader.io.data.valid && streamingCopy
  copyStream.io.readData.bits := reader.io.data.bits
  textureCache.io.readData.ready := sourceDataReady && useTextureCache
  wordAligner.io.input.valid := fastWordBlit && !directWordBlit && sourceDataValid
  wordAligner.io.input.bits := sourceDataBits.data
  aligner.io.input.valid := Mux(isAlpha, alphaForegroundBuffer.io.deq.valid,
    sourceDataValid && !fastWordBlit)
  aligner.io.input.bits := Mux(isAlpha, alphaForegroundBuffer.io.deq.bits, sourceDataBits.data)
  alphaForegroundBuffer.io.deq.ready := isAlpha && aligner.io.input.ready
  alphaBackgroundBuffer.io.enq.valid := backgroundReader.io.data.valid
  alphaBackgroundBuffer.io.enq.bits := backgroundReader.io.data.bits.data
  backgroundReader.io.data.ready := alphaBackgroundBuffer.io.enq.ready
  backgroundAligner.io.input.valid := alphaBackgroundBuffer.io.deq.valid
  backgroundAligner.io.input.bits := alphaBackgroundBuffer.io.deq.bits
  alphaBackgroundBuffer.io.deq.ready := backgroundAligner.io.input.ready
}
