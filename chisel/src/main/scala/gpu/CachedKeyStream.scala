package gpu

import chisel3._
import chisel3.util._

/** Packed, cached small sprites: fetch once, buffer following rows during W/B stalls.
  * Each destination row remains a separate strided write; optional trimming removes only
  * transparent edge words and empty rows, preserving interior zero-strobe beats.
  */
class CachedKeyStream(trimTransparentRows: Boolean = false, pipelineWrites: Boolean = false) extends Module {
  require(!trimTransparentRows || !pipelineWrites, "Measure Key pipelining without row trimming")
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val eligible = Output(Bool())
    val readRequest = Decoupled(new AxiReadRequest)
    val readData = Flipped(Decoupled(new AxiReadBeat))
    val readDone = Input(Bool())
    val readError = Input(Bool())
    val writeRequest = Decoupled(new AxiWriteRequest)
    val writeData = Decoupled(new AxiWriteBeat)
    val writeDone = Input(Bool())
    val writeError = Input(Bool())
    val wordPixelsDone = Output(UInt(2.W))
    val completion = Decoupled(new GpuCompletion)
  })
  private val idle :: active :: finish :: Nil = Enum(3)
  private val state = RegInit(idle)
  private val command = Reg(new GpuCommand)
  private val destination = Reg(UInt(32.W))
  private val rowsLeft = Reg(UInt(16.W))
  private val wordsLeft = RegInit(0.U(5.W))
  private val readIssued = RegInit(false.B)
  private val readFinished = RegInit(false.B)
  private val rowActive = RegInit(false.B)
  private val errorSeen = RegInit(false.B)
  private val pendingRows = if(pipelineWrites) Some(RegInit(0.U(2.W))) else None
  private val fifo = Module(new Queue(UInt(32.W), 16))
  private val aligner = Module(new Rgb565WordAligner)
  private val in = io.command.bits
  private val bytes = (in.widthPixels * in.heightPixels) << 1
  private val srcEnd = in.srcAddr.pad(64) + bytes.pad(64)
  private val dstEnd = in.dstAddr.pad(64) +
    ((in.heightPixels - 1.U)(15, 0) * in.dstStride).pad(64) + (in.widthPixels << 1).pad(64)
  io.eligible := in.op === GpuOpcode.ColorKey.U && in.widthPixels =/= 0.U &&
    in.widthPixels <= 16.U && !in.widthPixels(0) && in.heightPixels =/= 0.U &&
    in.heightPixels <= 16.U && in.srcAddr(1, 0) === 0.U && !in.dstAddr(0) &&
    in.srcStride === (in.widthPixels << 1) && !in.dstStride(0) &&
    in.dstStride >= (in.widthPixels << 1) &&
    (srcEnd <= in.dstAddr || dstEnd <= in.srcAddr)
  io.command.ready := state === idle && io.eligible
  when(io.command.fire) {
    command := in; destination := in.dstAddr; rowsLeft := in.heightPixels
    readIssued := false.B; readFinished := false.B; errorSeen := false.B
    rowActive := false.B; wordsLeft := 0.U; state := active
    pendingRows.foreach(_ := 0.U)
  }
  io.readRequest.valid := state === active && !readIssued
  io.readRequest.bits.address := command.srcAddr
  io.readRequest.bits.bytes := (command.widthPixels * command.heightPixels) << 1
  when(io.readRequest.fire) { readIssued := true.B }
  fifo.io.enq.valid := state === active && io.readData.valid
  fifo.io.enq.bits := io.readData.bits.data
  io.readData.ready := state === active && fifo.io.enq.ready
  private val failing = errorSeen || (io.readDone && io.readError) || (io.writeDone && io.writeError)
  // Credit a COMPLETE row before AW. A later cache error can never starve promised W.
  private val launch = state === active && !rowActive && !failing && rowsLeft =/= 0.U &&
    fifo.io.count >= (command.widthPixels >> 1) && aligner.io.start.ready
  private val rowBeats = ((command.widthPixels << 1) + destination(1, 0) + 3.U) >> 2
  aligner.io.start.bits.sourceUpper := false.B
  aligner.io.start.bits.destinationUpper := destination(1)
  aligner.io.start.bits.pixels := command.widthPixels
  aligner.io.input.valid := rowActive && wordsLeft =/= 0.U && fifo.io.deq.valid
  aligner.io.input.bits := fifo.io.deq.bits
  private val discard = state === active && failing && !rowActive
  fifo.io.deq.ready := discard || (rowActive && wordsLeft =/= 0.U && aligner.io.input.ready)
  when(aligner.io.input.fire) { wordsLeft := wordsLeft - 1.U }
  private val keyStrobe = Cat(
    Fill(2, aligner.io.output.bits.lanes(1) && aligner.io.output.bits.data(31, 16) =/= command.colorKey),
    Fill(2, aligner.io.output.bits.lanes(0) && aligner.io.output.bits.data(15, 0) =/= command.colorKey))
  private val rowDone = WireDefault(io.writeDone)
  if(pipelineWrites) {
    val outputLeft = RegInit(0.U(4.W))
    when(io.writeRequest.fire) { outputLeft := rowBeats }
    when(io.writeData.fire) { outputLeft := outputLeft - 1.U }
    rowDone := io.writeData.fire && outputLeft === 1.U
    when(state === active && (io.writeRequest.fire =/= io.writeDone)) {
      val rows = pendingRows.get
      rows := Mux(io.writeRequest.fire, rows + 1.U, rows - 1.U)
    }
  }
  if (trimTransparentRows) {
    // At most 16 pixels plus a halfword phase: reserve all 9 aligned words before AW.
    val row = Reg(Vec(9, new AxiWriteBeat))
    val collecting = RegInit(false.B)
    val requesting = RegInit(false.B)
    val sending = RegInit(false.B)
    val index = RegInit(0.U(4.W))
    val first = Reg(UInt(4.W))
    val last = Reg(UInt(4.W))
    val nonempty = RegInit(false.B)
    aligner.io.start.valid := launch
    when(aligner.io.start.fire) {
      rowActive := true.B; wordsLeft := command.widthPixels >> 1
      collecting := true.B; index := 0.U; nonempty := false.B
    }
    aligner.io.output.ready := collecting
    io.wordPixelsDone := Mux(aligner.io.output.fire, aligner.io.output.bits.pixels, 0.U)
    when(aligner.io.output.fire) {
      row(index).data := aligner.io.output.bits.data
      row(index).strb := keyStrobe
      when(keyStrobe.orR) {
        when(!nonempty) { first := index }
        last := index; nonempty := true.B
      }
      index := index + 1.U
      when(index === rowBeats - 1.U) {
        collecting := false.B
        when(failing || !(nonempty || keyStrobe.orR)) {
          rowDone := true.B
        }.otherwise { requesting := true.B }
      }
    }
    // Once offered, hold the complete span through errors and all AW/W stalls.
    io.writeRequest.valid := requesting
    io.writeRequest.bits.address := (destination & "hfffffffc".U) + (first << 2)
    io.writeRequest.bits.beats := last - first + 1.U
    when(io.writeRequest.fire) {
      requesting := false.B; sending := true.B; index := first
    }
    io.writeData.valid := sending
    io.writeData.bits := row(index)
    when(io.writeData.fire) {
      index := index + 1.U
      when(index === last) { sending := false.B }
    }
  } else {
    io.writeRequest.valid := launch
    io.writeRequest.bits.address := destination & "hfffffffc".U
    io.writeRequest.bits.beats := rowBeats
    aligner.io.start.valid := launch && io.writeRequest.ready
    when(io.writeRequest.fire) { rowActive := true.B; wordsLeft := command.widthPixels >> 1 }
    io.writeData.valid := rowActive && aligner.io.output.valid
    io.writeData.bits.data := aligner.io.output.bits.data
    io.writeData.bits.strb := keyStrobe
    aligner.io.output.ready := rowActive && io.writeData.ready
    io.wordPixelsDone := Mux(io.writeData.fire, aligner.io.output.bits.pixels, 0.U)
  }
  when(state === active) {
    when(io.readDone) { readFinished := true.B }
    errorSeen := failing
    when(rowDone) {
      rowActive := false.B; rowsLeft := rowsLeft - 1.U
      destination := destination + command.dstStride
    }
    when(readFinished && !rowActive && !fifo.io.deq.valid && pendingRows.getOrElse(0.U) === 0.U &&
      (rowsLeft === 0.U || failing)) {
      state := finish
    }
  }
  io.completion.valid := state === finish
  io.completion.bits.tag := command.tag
  io.completion.bits.error := Mux(errorSeen, GpuError.AxiResponse.U, GpuError.None.U)
  when(io.completion.fire) { state := idle }
}
