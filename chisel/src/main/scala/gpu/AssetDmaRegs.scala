package gpu

import chisel3._
import chisel3.util._

object AssetDmaError {
  val None = 0
  val Descriptor = 1
  val Session = 2
  val AssetId = 3
  val Offset = 4
  val Sequence = 5
  val Length = 6
  val AddressRange = 7
  val Stream = 8
  val AxiResponse = 9
  val Aborted = 10
}

class AssetDmaDescriptor extends Bundle {
  val session = UInt(32.W)
  val dstAddr = UInt(32.W)
  val assetId = UInt(32.W)
  val expectedOffset = UInt(32.W)
  val expectedSequence = UInt(32.W)
  val maxLength = UInt(32.W)
}

class AssetPacketMeta extends Bundle {
  val session = UInt(32.W)
  val assetId = UInt(32.W)
  val offset = UInt(32.W)
  val length = UInt(16.W)
  val flags = UInt(16.W)
  val sequence = UInt(32.W)
  val crc32 = UInt(32.W)
}

/** APB shadow registers and packet admission for the network-to-DDR DMA. */
class AssetDmaRegs extends Module {
  val io = IO(new Bundle {
    val paddr = Input(UInt(16.W))
    val psel = Input(Bool())
    val penable = Input(Bool())
    val pwrite = Input(Bool())
    val pwdata = Input(UInt(32.W))
    val prdata = Output(UInt(32.W))
    val pready = Output(Bool())
    val pslverror = Output(Bool())

    val descriptor = Output(new AssetDmaDescriptor)
    val active = Output(Bool())
    val start = Output(Bool())
    val abort = Output(Bool())
    val done = Output(Bool())
    val error = Output(Bool())
    val aborted = Output(Bool())
    val committedOffset = Output(UInt(32.W))
    val committedSequence = Output(UInt(32.W))
    val committedBytes = Output(UInt(32.W))

    val metaIn = Flipped(Decoupled(new AssetPacketMeta))
    val metaOut = Decoupled(new AssetPacketMeta)
    val dropPacket = Output(Bool())

    val packetCommitted = Input(Bool())
    val packetBytes = Input(UInt(16.W))
    val packetLast = Input(Bool())
    val packetFailed = Input(Bool())
    val packetError = Input(UInt(8.W))
    val abortDone = Input(Bool())
  })

  private val shadow = RegInit(0.U.asTypeOf(new AssetDmaDescriptor))
  private val activeDescriptor = RegInit(0.U.asTypeOf(new AssetDmaDescriptor))
  private val active = RegInit(false.B)
  private val done = RegInit(false.B)
  private val error = RegInit(false.B)
  private val aborted = RegInit(false.B)
  private val aborting = RegInit(false.B)
  private val lastError = RegInit(AssetDmaError.None.U(8.W))
  private val committedOffset = RegInit(0.U(32.W))
  private val committedSequence = RegInit(0.U(32.W))
  private val committedBytes = RegInit(0.U(32.W))
  private val packetCount = RegInit(0.U(32.W))
  private val errorCount = RegInit(0.U(32.W))
  private val duplicateCount = RegInit(0.U(32.W))
  private val packetPending = RegInit(false.B)
  private val pendingLength = RegInit(0.U(16.W))
  private val pendingLast = RegInit(false.B)
  private val startPulse = RegInit(false.B)
  private val abortPulse = RegInit(false.B)

  startPulse := false.B
  abortPulse := false.B

  private val meta = io.metaIn.bits
  private val sameSession = meta.session === activeDescriptor.session
  private val sameAsset = meta.assetId === activeDescriptor.assetId
  private val duplicate = active && !packetPending && sameSession && sameAsset &&
    meta.sequence < committedSequence
  private val offsetEnd = meta.offset +& meta.length
  private val writeStart = activeDescriptor.dstAddr +& meta.offset
  private val writeEnd = writeStart +& meta.length
  private val lengthValid = meta.length =/= 0.U && meta.length <= 1024.U &&
    offsetEnd <= activeDescriptor.maxLength && (meta.flags(0) || meta.length(1, 0) === 0.U)
  private val flagsValid = (meta.flags & "hfffc".U) === 0.U
  private val addressValid = writeStart >= GpuMemoryMap.AssetStart.U &&
    writeEnd <= GpuMemoryMap.AssetEndExclusive.U
  private val expected = active && !aborting && !packetPending && sameSession && sameAsset &&
    meta.offset === committedOffset && meta.sequence === committedSequence &&
    lengthValid && flagsValid && addressValid

  io.metaOut.valid := io.metaIn.valid && expected
  io.metaOut.bits := meta
  io.metaIn.ready := Mux(packetPending || aborting, false.B,
    Mux(expected, io.metaOut.ready, true.B))
  io.dropPacket := io.metaIn.valid && io.metaIn.ready && !expected

  when(io.metaOut.fire) {
    packetPending := true.B
    pendingLength := meta.length
    pendingLast := meta.flags(0)
  }.elsewhen(io.metaIn.fire && !expected) {
    when(duplicate) {
      duplicateCount := duplicateCount + 1.U
    }.otherwise {
      error := true.B
      errorCount := errorCount + 1.U
      when(!active) { lastError := AssetDmaError.Descriptor.U }
        .elsewhen(!sameSession) { lastError := AssetDmaError.Session.U }
        .elsewhen(!sameAsset) { lastError := AssetDmaError.AssetId.U }
        .elsewhen(meta.offset =/= committedOffset) { lastError := AssetDmaError.Offset.U }
        .elsewhen(meta.sequence =/= committedSequence) { lastError := AssetDmaError.Sequence.U }
        .elsewhen(!lengthValid || !flagsValid) { lastError := AssetDmaError.Length.U }
        .otherwise { lastError := AssetDmaError.AddressRange.U }
    }
  }

  when(io.packetCommitted && packetPending) {
    packetPending := false.B
    when(io.packetBytes =/= pendingLength) {
      error := true.B
      errorCount := errorCount + 1.U
      lastError := AssetDmaError.Stream.U
    }.otherwise {
      committedOffset := committedOffset + pendingLength
      committedSequence := committedSequence + 1.U
      committedBytes := committedBytes + pendingLength
      packetCount := packetCount + 1.U
      when(pendingLast || io.packetLast) {
        active := false.B
        done := true.B
      }
    }
  }

  when(io.packetFailed && packetPending) {
    packetPending := false.B
    aborting := true.B
    error := true.B
    errorCount := errorCount + 1.U
    lastError := Mux(io.packetError === 0.U, AssetDmaError.AxiResponse.U, io.packetError)
  }

  when(aborting && io.abortDone) {
    packetPending := false.B
    aborting := false.B
    active := false.B
    aborted := true.B
    lastError := AssetDmaError.Aborted.U
  }

  private val access = io.psel && io.penable
  private val knownAddress = AssetDmaRegisterMap.All.map(address => io.paddr === address.U).reduce(_ || _)
  private val readOnlyAddress = Seq(
    AssetDmaRegisterMap.Status, AssetDmaRegisterMap.CommittedOffset,
    AssetDmaRegisterMap.CommittedSequence, AssetDmaRegisterMap.CommittedBytes,
    AssetDmaRegisterMap.PacketCount, AssetDmaRegisterMap.ErrorCount,
    AssetDmaRegisterMap.DuplicateCount
  ).map(address => io.paddr === address.U).reduce(_ || _)
  private val descriptorEnd = shadow.dstAddr +& shadow.maxLength
  private val descriptorValid = shadow.dstAddr(1, 0) === 0.U &&
    shadow.expectedOffset(1, 0) === 0.U && shadow.maxLength =/= 0.U &&
    shadow.expectedOffset < shadow.maxLength &&
    shadow.dstAddr >= GpuMemoryMap.AssetStart.U &&
    descriptorEnd <= GpuMemoryMap.AssetEndExclusive.U
  private val controlBitsValid = (io.pwdata & "hfffffffc".U) === 0.U &&
    io.pwdata(1, 0) =/= 3.U
  private val startInvalid = io.paddr === AssetDmaRegisterMap.Control.U && io.pwdata(0) &&
    (active || !descriptorValid)
  private val abortInvalid = io.paddr === AssetDmaRegisterMap.Control.U && io.pwdata(1) && !active

  io.pready := access
  io.pslverror := access && (!knownAddress ||
    (io.pwrite && readOnlyAddress) ||
    (io.pwrite && io.paddr === AssetDmaRegisterMap.Control.U &&
      (!controlBitsValid || startInvalid || abortInvalid)))

  when(access && io.pwrite && !io.pslverror) {
    switch(io.paddr) {
      is(AssetDmaRegisterMap.Session.U) { shadow.session := io.pwdata }
      is(AssetDmaRegisterMap.DstAddr.U) { shadow.dstAddr := io.pwdata }
      is(AssetDmaRegisterMap.AssetId.U) { shadow.assetId := io.pwdata }
      is(AssetDmaRegisterMap.ExpectedOffset.U) { shadow.expectedOffset := io.pwdata }
      is(AssetDmaRegisterMap.ExpectedSequence.U) { shadow.expectedSequence := io.pwdata }
      is(AssetDmaRegisterMap.MaxLength.U) { shadow.maxLength := io.pwdata }
      is(AssetDmaRegisterMap.Control.U) {
        when(io.pwdata(0)) {
          activeDescriptor := shadow
          active := true.B
          done := false.B
          error := false.B
          aborted := false.B
          aborting := false.B
          lastError := AssetDmaError.None.U
          committedOffset := shadow.expectedOffset
          committedSequence := shadow.expectedSequence
          committedBytes := 0.U
          packetPending := false.B
          startPulse := true.B
        }.elsewhen(io.pwdata(1)) {
          aborting := true.B
          abortPulse := true.B
        }
      }
    }
  }

  io.prdata := 0.U
  switch(io.paddr) {
    is(AssetDmaRegisterMap.Session.U) { io.prdata := shadow.session }
    is(AssetDmaRegisterMap.DstAddr.U) { io.prdata := shadow.dstAddr }
    is(AssetDmaRegisterMap.AssetId.U) { io.prdata := shadow.assetId }
    is(AssetDmaRegisterMap.ExpectedOffset.U) { io.prdata := shadow.expectedOffset }
    is(AssetDmaRegisterMap.ExpectedSequence.U) { io.prdata := shadow.expectedSequence }
    is(AssetDmaRegisterMap.MaxLength.U) { io.prdata := shadow.maxLength }
    is(AssetDmaRegisterMap.Status.U) {
      io.prdata := Cat(0.U(16.W), lastError, 0.U(4.W), aborted, error, done, active)
    }
    is(AssetDmaRegisterMap.CommittedOffset.U) { io.prdata := committedOffset }
    is(AssetDmaRegisterMap.CommittedSequence.U) { io.prdata := committedSequence }
    is(AssetDmaRegisterMap.CommittedBytes.U) { io.prdata := committedBytes }
    is(AssetDmaRegisterMap.PacketCount.U) { io.prdata := packetCount }
    is(AssetDmaRegisterMap.ErrorCount.U) { io.prdata := errorCount }
    is(AssetDmaRegisterMap.DuplicateCount.U) { io.prdata := duplicateCount }
  }

  io.descriptor := activeDescriptor
  io.active := active
  io.start := startPulse
  io.abort := abortPulse
  io.done := done
  io.error := error
  io.aborted := aborted
  io.committedOffset := committedOffset
  io.committedSequence := committedSequence
  io.committedBytes := committedBytes
}
