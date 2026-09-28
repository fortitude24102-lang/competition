package gpu

import chisel3._
import chisel3.util._

class TextureCacheLoad extends Bundle {
  val base = UInt(32.W)
  val bytes = UInt(13.W)
}

class TextureCache extends Module {
  val io = IO(new Bundle {
    val load = Flipped(Decoupled(new TextureCacheLoad))
    val invalidate = Input(Bool())
    val readRequest = Flipped(Decoupled(new AxiReadRequest))
    val readData = Decoupled(new AxiReadBeat)
    val readDone = Output(Bool())
    val readError = Output(Bool())
    val axi = new Axi4MasterPort
    val valid = Output(Bool())
    val busy = Output(Bool())
    val error = Output(Bool())
    val base = Output(UInt(32.W))
    val bytes = Output(UInt(13.W))
    val hitBytes = Output(UInt(64.W))
    val perfClear = Input(Bool())
  })

  private val memory = SyncReadMem(1024, UInt(32.W))
  private val preload = Module(new AxiReadEngine(0))
  private val baseReg = RegInit(0.U(32.W))
  private val bytesReg = RegInit(0.U(13.W))
  private val validReg = RegInit(false.B)
  private val busyReg = RegInit(false.B)
  private val errorReg = RegInit(false.B)
  private val hitBytesReg = RegInit(0.U(64.W))

  private val loadEnd = io.load.bits.base.pad(64) + io.load.bits.bytes.pad(64)
  private val loadLegal = io.load.bits.base(1, 0) === 0.U &&
    io.load.bits.bytes >= 4.U && io.load.bits.bytes <= 4096.U &&
    io.load.bits.bytes(1, 0) === 0.U &&
    io.load.bits.base >= GpuMemoryMap.AssetStart.U &&
    loadEnd <= GpuMemoryMap.AssetEndExclusive.U(64.W)

  io.load.ready := !busyReg && preload.io.request.ready
  preload.io.request.valid := io.load.valid && io.load.ready && loadLegal
  preload.io.request.bits.address := io.load.bits.base
  preload.io.request.bits.bytes := io.load.bits.bytes

  when(io.load.fire) {
    when(loadLegal) {
      baseReg := io.load.bits.base
      bytesReg := io.load.bits.bytes
      validReg := false.B
      busyReg := true.B
      errorReg := false.B
    }.otherwise {
      errorReg := true.B
    }
  }

  preload.io.data.ready := true.B
  when(preload.io.data.fire) {
    memory.write((preload.io.data.bits.address - baseReg)(11, 2), preload.io.data.bits.data)
  }

  when(preload.io.done) {
    busyReg := false.B
    validReg := !preload.io.error
    errorReg := preload.io.error
  }

  when(io.invalidate && !busyReg) {
    validReg := false.B
    errorReg := false.B
  }

  io.axi.aw.valid := false.B
  io.axi.aw.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.w.valid := false.B
  io.axi.w.bits := 0.U.asTypeOf(new Axi4WriteData)
  io.axi.b.ready := false.B
  io.axi.ar.valid := preload.io.axiAr.valid
  io.axi.ar.bits := preload.io.axiAr.bits
  preload.io.axiAr.ready := io.axi.ar.ready
  preload.io.axiR.valid := io.axi.r.valid
  preload.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := preload.io.axiR.ready

  private val readQueue = Module(new Queue(new AxiReadBeat, 2))
  private val readActive = RegInit(false.B)
  private val readAddress = Reg(UInt(32.W))
  private val readWordsLeft = Reg(UInt(32.W))
  private val pendingValid = RegInit(false.B)
  private val pendingAddress = Reg(UInt(32.W))
  private val pendingLast = Reg(Bool())
  private val readDoneReg = RegInit(false.B)
  private val readErrorReg = RegInit(false.B)

  readDoneReg := false.B
  readErrorReg := false.B

  private val requestEnd = io.readRequest.bits.address.pad(64) +
    io.readRequest.bits.bytes.pad(64)
  private val cachedEnd = baseReg.pad(64) + bytesReg.pad(64)
  private val requestInRange = io.readRequest.bits.address >= baseReg &&
    requestEnd <= cachedEnd
  private val readerIdle = !readActive && !pendingValid && readQueue.io.count === 0.U

  io.readRequest.ready := validReg && !busyReg && readerIdle
  when(io.readRequest.fire) {
    when(io.readRequest.bits.bytes === 0.U) {
      readDoneReg := true.B
    }.elsewhen(!requestInRange) {
      readDoneReg := true.B
      readErrorReg := true.B
    }.otherwise {
      val byteOffset = io.readRequest.bits.address(1, 0)
      val totalBytes = Cat(0.U(1.W), io.readRequest.bits.bytes) + byteOffset
      readAddress := Cat(io.readRequest.bits.address(31, 2), 0.U(2.W))
      readWordsLeft := (totalBytes + 3.U) >> 2
      readActive := true.B
    }
  }

  private val queueWillFree = readQueue.io.deq.fire
  private val occupied = readQueue.io.count +& pendingValid
  private val canIssue = occupied < 2.U || queueWillFree
  private val issueRead = readActive && canIssue
  private val memoryData = memory.read((readAddress - baseReg)(11, 2), issueRead)

  pendingValid := issueRead
  when(issueRead) {
    pendingAddress := readAddress
    pendingLast := readWordsLeft === 1.U
    readAddress := readAddress + 4.U
    readWordsLeft := readWordsLeft - 1.U
    when(readWordsLeft === 1.U) {
      readActive := false.B
    }
  }

  readQueue.io.enq.valid := pendingValid
  readQueue.io.enq.bits.address := pendingAddress
  readQueue.io.enq.bits.data := memoryData
  readQueue.io.enq.bits.last := pendingLast

  io.readData <> readQueue.io.deq
  when(io.readData.fire && io.readData.bits.last) {
    readDoneReg := true.B
  }

  when(io.perfClear) {
    hitBytesReg := 0.U
  }.elsewhen(io.readData.fire) {
    hitBytesReg := hitBytesReg + 4.U
  }

  io.readDone := readDoneReg
  io.readError := readErrorReg
  io.valid := validReg
  io.busy := busyReg
  io.error := errorReg
  io.base := baseReg
  io.bytes := bytesReg
  io.hitBytes := hitBytesReg
}
