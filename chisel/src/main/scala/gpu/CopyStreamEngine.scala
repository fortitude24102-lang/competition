package gpu

import chisel3._
import chisel3.util._

/** Continuous Copy scheduler. Reuses DenseBlit's AXI engines and their burst limits.
  * A 16-word FIFO decouples R from W/B stalls; this is not a multi-outstanding CDMA.
  */
class CopyStreamEngine extends Module {
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
    val completion = Decoupled(new GpuCompletion)
  })
  private val idle :: active :: finish :: Nil = Enum(3)
  private val state = RegInit(idle)
  private val command = Reg(new GpuCommand)
  private val bytes = Reg(UInt(32.W))
  private val readIssued = RegInit(false.B)
  private val writeIssued = RegInit(false.B)
  private val readFinished = RegInit(false.B)
  private val writeFinished = RegInit(false.B)
  private val errorSeen = RegInit(false.B)
  private val fifo = Module(new Queue(UInt(32.W), 16))

  private val incoming = io.command.bits
  private val rowBytes = incoming.widthPixels << 1
  private val totalBytes = (incoming.widthPixels * incoming.heightPixels) << 1
  private val srcEnd = incoming.srcAddr.pad(34) + totalBytes.pad(34)
  private val dstEnd = incoming.dstAddr.pad(34) + totalBytes.pad(34)
  io.eligible := incoming.op === GpuOpcode.Copy.U &&
    incoming.widthPixels =/= 0.U && incoming.heightPixels =/= 0.U &&
    incoming.srcAddr(1, 0) === 0.U && incoming.dstAddr(1, 0) === 0.U &&
    incoming.srcStride === rowBytes && incoming.dstStride === rowBytes &&
    totalBytes(1, 0) === 0.U &&
    incoming.srcAddr >= GpuMemoryMap.FramebufferA.U && incoming.dstAddr >= GpuMemoryMap.FramebufferA.U &&
    srcEnd <= GpuMemoryMap.DdrEndExclusive.U && dstEnd <= GpuMemoryMap.DdrEndExclusive.U &&
    (srcEnd <= incoming.dstAddr || dstEnd <= incoming.srcAddr)

  io.command.ready := state === idle && io.eligible
  when(io.command.fire) {
    command := incoming
    bytes := totalBytes
    readIssued := false.B
    writeIssued := false.B
    readFinished := false.B
    writeFinished := false.B
    errorSeen := false.B
    state := active
  }
  io.readRequest.valid := state === active && !readIssued
  io.readRequest.bits.address := command.srcAddr
  io.readRequest.bits.bytes := bytes
  io.writeRequest.valid := state === active && !writeIssued
  io.writeRequest.bits.address := command.dstAddr
  io.writeRequest.bits.beats := bytes >> 2
  when(io.readRequest.fire) { readIssued := true.B }
  when(io.writeRequest.fire) { writeIssued := true.B }
  fifo.io.enq.valid := io.readData.valid && state === active
  fifo.io.enq.bits := io.readData.bits.data
  io.readData.ready := fifo.io.enq.ready && state === active
  io.writeData.valid := fifo.io.deq.valid && state === active
  io.writeData.bits.data := fifo.io.deq.bits
  io.writeData.bits.strb := "hf".U
  fifo.io.deq.ready := io.writeData.ready && state === active
  when(state === active) {
    when(io.readDone) { readFinished := true.B }
    when(io.writeDone) { writeFinished := true.B }
    errorSeen := errorSeen || (io.readDone && io.readError) || (io.writeDone && io.writeError)
    // Drain all promised data/responses even after error; never retry a partial blit.
    when(readFinished && writeFinished && !fifo.io.deq.valid) { state := finish }
  }
  io.completion.valid := state === finish
  io.completion.bits.tag := command.tag
  io.completion.bits.error := Mux(errorSeen, GpuError.AxiResponse.U, GpuError.None.U)
  when(io.completion.fire) { state := idle }
}
