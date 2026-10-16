package gpu

import chisel3._
import chisel3.util._

/** Packed, cached small sprites: fetch once, buffer following rows during W/B stalls.
  * Each destination row remains a separate strided write, including zero-strobe beats.
  */
class CachedKeyStream extends Module {
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
  io.writeRequest.valid := launch
  io.writeRequest.bits.address := destination & "hfffffffc".U
  io.writeRequest.bits.beats := ((command.widthPixels << 1) + destination(1, 0) + 3.U) >> 2
  aligner.io.start.valid := launch && io.writeRequest.ready
  aligner.io.start.bits.sourceUpper := false.B
  aligner.io.start.bits.destinationUpper := destination(1)
  aligner.io.start.bits.pixels := command.widthPixels
  when(io.writeRequest.fire) { rowActive := true.B; wordsLeft := command.widthPixels >> 1 }
  aligner.io.input.valid := rowActive && wordsLeft =/= 0.U && fifo.io.deq.valid
  aligner.io.input.bits := fifo.io.deq.bits
  private val discard = state === active && failing && !rowActive
  fifo.io.deq.ready := discard || (rowActive && wordsLeft =/= 0.U && aligner.io.input.ready)
  when(aligner.io.input.fire) { wordsLeft := wordsLeft - 1.U }
  io.writeData.valid := rowActive && aligner.io.output.valid
  io.writeData.bits.data := aligner.io.output.bits.data
  io.writeData.bits.strb := Cat(
    Fill(2, aligner.io.output.bits.lanes(1) && aligner.io.output.bits.data(31, 16) =/= command.colorKey),
    Fill(2, aligner.io.output.bits.lanes(0) && aligner.io.output.bits.data(15, 0) =/= command.colorKey))
  aligner.io.output.ready := rowActive && io.writeData.ready
  io.wordPixelsDone := Mux(io.writeData.fire, aligner.io.output.bits.pixels, 0.U)
  when(state === active) {
    when(io.readDone) { readFinished := true.B }
    errorSeen := failing
    when(io.writeDone) {
      rowActive := false.B; rowsLeft := rowsLeft - 1.U
      destination := destination + command.dstStride
    }
    when(readFinished && !rowActive && !fifo.io.deq.valid && (rowsLeft === 0.U || failing)) {
      state := finish
    }
  }
  io.completion.valid := state === finish
  io.completion.bits.tag := command.tag
  io.completion.bits.error := Mux(errorSeen, GpuError.AxiResponse.U, GpuError.None.U)
  when(io.completion.fire) { state := idle }
}
