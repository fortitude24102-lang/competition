package gpu

import chisel3._
import chisel3.util._

class AssetPayloadByte extends Bundle {
  val data = UInt(8.W)
  val last = Bool()
}

/** Buffers one protected DATA payload, then writes it through bounded AXI bursts. */
class AssetDmaWriter extends Module {
  val io = IO(new Bundle {
    val descriptor = Input(new AssetDmaDescriptor)
    val meta = Flipped(Decoupled(new AssetPacketMeta))
    val payload = Flipped(Decoupled(new AssetPayloadByte))
    val abort = Input(Bool())
    val streamError = Input(Bool())
    val axi = new Axi4MasterPort
    val busy = Output(Bool())
    val packetCommitted = Output(Bool())
    val packetBytes = Output(UInt(16.W))
    val packetLast = Output(Bool())
    val packetFailed = Output(Bool())
    val packetError = Output(UInt(8.W))
    val abortDone = Output(Bool())
  })

  private val writer = Module(new AxiWriteEngine)
  private val wordBuffer = Mem(256, UInt(32.W))
  private val strobeBuffer = Mem(256, UInt(4.W))
  private val idle :: receive :: request :: writeData :: waitBurst :: Nil = Enum(5)
  private val state = RegInit(idle)
  private val packetLength = RegInit(0.U(16.W))
  private val packetLast = RegInit(false.B)
  private val receivedBytes = RegInit(0.U(16.W))
  private val writeIndex = RegInit(0.U(8.W))
  private val readIndex = RegInit(0.U(8.W))
  private val lane = RegInit(0.U(2.W))
  private val packedWord = RegInit(0.U(32.W))
  private val packedStrobe = RegInit(0.U(4.W))
  private val currentAddress = RegInit(0.U(32.W))
  private val remainingBeats = RegInit(0.U(9.W))
  private val burstBeatsLeft = RegInit(0.U(9.W))
  private val abortRequested = RegInit(false.B)
  private val committedPulse = RegInit(false.B)
  private val failedPulse = RegInit(false.B)
  private val abortDonePulse = RegInit(false.B)
  private val packetError = RegInit(AssetDmaError.None.U(8.W))

  committedPulse := false.B
  failedPulse := false.B
  abortDonePulse := false.B

  io.meta.ready := state === idle && !io.abort
  io.payload.ready := state === receive && !io.abort && !io.streamError

  when(io.meta.fire) {
    packetLength := io.meta.bits.length
    packetLast := io.meta.bits.flags(0)
    receivedBytes := 0.U
    writeIndex := 0.U
    readIndex := 0.U
    lane := 0.U
    packedWord := 0.U
    packedStrobe := 0.U
    currentAddress := io.descriptor.dstAddr + io.meta.bits.offset
    remainingBeats := (io.meta.bits.length + 3.U) >> 2
    abortRequested := false.B
    when(io.meta.bits.length === 0.U || io.meta.bits.length > 1024.U) {
      failedPulse := true.B
      packetError := AssetDmaError.Length.U
    }.otherwise {
      state := receive
    }
  }

  private val shiftedByte = (io.payload.bits.data << (lane << 3))(31, 0)
  private val nextWord = packedWord | shiftedByte
  private val nextStrobe = packedStrobe | (1.U(4.W) << lane)
  private val expectedLast = receivedBytes === packetLength - 1.U

  when(io.abort) {
    when(state === idle || state === receive || state === request) {
      state := idle
      abortRequested := false.B
      abortDonePulse := true.B
    }.otherwise {
      abortRequested := true.B
    }
  }.elsewhen(io.streamError && (state === receive || state === request)) {
    state := idle
    failedPulse := true.B
    packetError := AssetDmaError.Stream.U
  }.elsewhen(state === receive && io.payload.fire) {
    when(io.payload.bits.last =/= expectedLast) {
      state := idle
      failedPulse := true.B
      packetError := AssetDmaError.Stream.U
    }.otherwise {
      receivedBytes := receivedBytes + 1.U
      when(lane === 3.U || expectedLast) {
        wordBuffer.write(writeIndex, nextWord)
        strobeBuffer.write(writeIndex, nextStrobe)
        writeIndex := writeIndex + 1.U
        lane := 0.U
        packedWord := 0.U
        packedStrobe := 0.U
      }.otherwise {
        lane := lane + 1.U
        packedWord := nextWord
        packedStrobe := nextStrobe
      }
      when(expectedLast) { state := request }
    }
  }

  private val wordsToBoundary = (4096.U(13.W) - currentAddress(11, 0)) >> 2
  private val cappedBeats = Mux(remainingBeats > 256.U, 256.U, remainingBeats)
  private val nextBurstBeats = Mux(cappedBeats > wordsToBoundary, wordsToBoundary, cappedBeats)

  writer.io.request.valid := state === request && !abortRequested && !io.abort && !io.streamError
  writer.io.request.bits.address := currentAddress
  writer.io.request.bits.beats := nextBurstBeats
  when(writer.io.request.fire) {
    burstBeatsLeft := nextBurstBeats
    state := writeData
  }
  when(state === request && abortRequested) {
    state := idle
    abortRequested := false.B
    abortDonePulse := true.B
  }

  writer.io.data.valid := state === writeData && burstBeatsLeft =/= 0.U
  writer.io.data.bits.data := wordBuffer(readIndex)
  writer.io.data.bits.strb := strobeBuffer(readIndex)
  when(writer.io.data.fire) {
    readIndex := readIndex + 1.U
    currentAddress := currentAddress + 4.U
    remainingBeats := remainingBeats - 1.U
    burstBeatsLeft := burstBeatsLeft - 1.U
    when(burstBeatsLeft === 1.U) { state := waitBurst }
  }

  when(state === waitBurst && writer.io.done) {
    when(abortRequested || io.abort) {
      state := idle
      abortRequested := false.B
      abortDonePulse := true.B
    }.elsewhen(writer.io.error) {
      state := idle
      abortRequested := false.B
      failedPulse := true.B
      packetError := AssetDmaError.AxiResponse.U
    }.elsewhen(remainingBeats === 0.U) {
      state := idle
      committedPulse := true.B
      packetError := AssetDmaError.None.U
    }.otherwise {
      state := request
    }
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
  io.axi.ar.valid := false.B
  io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.r.ready := false.B

  io.busy := state =/= idle
  io.packetCommitted := committedPulse
  io.packetBytes := packetLength
  io.packetLast := packetLast
  io.packetFailed := failedPulse
  io.packetError := packetError
  io.abortDone := abortDonePulse
}
