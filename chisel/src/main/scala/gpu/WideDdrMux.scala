package gpu

import chisel3._
import chisel3.util._

/** Fixed two-master mux, no ID namespace assumptions. COMMON DDR reset only.
  * A direction changes owner only after its promises and responses drain. */
class WideDdrMux extends Module {
  val io = IO(new Bundle {
    val legacy = Flipped(new Axi128MasterPort)
    val native = Flipped(new Axi128MasterPort)
    val ddr = new Axi128MasterPort
    val emergency = Input(Bool())
  })
  private val readOwner = RegInit(false.B)
  private val writeOwner = RegInit(false.B)
  private val readCount = RegInit(0.U(5.W))
  private val writeCount = RegInit(0.U(5.W))
  private val dataCount = RegInit(0.U(5.W))
  private val readTurn = RegInit(0.U(2.W))
  private val writeTurn = RegInit(0.U(2.W))
  private val arHeld = RegInit(false.B)
  private val awHeld = RegInit(false.B)

  // Native errors include malformed RLAST markers. Count its advertised beats,
  // not a bad marker, so that the DMA can drain before ownership changes.
  private val nativeLengths = Module(new Queue(UInt(8.W),2,pipe=true))
  private val nativeReadIndex = RegInit(0.U(8.W))
  private val nativeLast = nativeLengths.io.deq.valid && nativeReadIndex===nativeLengths.io.deq.bits
  private val readRetire = io.ddr.r.fire && Mux(readOwner,nativeLast,io.ddr.r.bits.last)
  private val writeRetire = io.ddr.b.fire
  private val dataRetire = io.ddr.w.fire && io.ddr.w.bits.last

  io.legacy.r.valid := io.ddr.r.valid && !readOwner && readCount.orR
  io.native.r.valid := io.ddr.r.valid && readOwner && readCount.orR
  io.legacy.r.bits := io.ddr.r.bits;io.native.r.bits := io.ddr.r.bits
  io.ddr.r.ready := readCount.orR && Mux(readOwner,io.native.r.ready,io.legacy.r.ready)
  io.legacy.b.valid := io.ddr.b.valid && !writeOwner && writeCount.orR
  io.native.b.valid := io.ddr.b.valid && writeOwner && writeCount.orR
  io.legacy.b.bits := io.ddr.b.bits;io.native.b.bits := io.ddr.b.bits
  io.ddr.b.ready := writeCount.orR && Mux(writeOwner,io.native.b.ready,io.legacy.b.ready)

  private val readCurrent = Mux(readOwner,io.native.ar.valid,io.legacy.ar.valid)
  private val readOther = Mux(readOwner,io.legacy.ar.valid,io.native.ar.valid && !io.emergency)
  private val switchRead = readOther && Mux(readOwner,
    io.emergency || readTurn===2.U || !readCurrent,
    readCount.orR || readTurn.orR || !readCurrent)
  private val readCredit = readCount < Mux(readOwner,2.U,16.U) || readRetire
  private val admitRead = arHeld || (readCredit && !switchRead && (!readOwner || !io.emergency))
  io.ddr.ar.valid := readCurrent && admitRead
  io.ddr.ar.bits := Mux(readOwner,io.native.ar.bits,io.legacy.ar.bits)
  io.legacy.ar.ready := io.ddr.ar.ready && admitRead && !readOwner
  io.native.ar.ready := io.ddr.ar.ready && admitRead && readOwner
  when(io.ddr.ar.valid && !io.ddr.ar.ready) { arHeld := true.B }
  when(io.ddr.ar.fire) { arHeld := false.B;when(readTurn=/=2.U) { readTurn := readTurn+1.U } }
  private val nextReadCount = readCount + io.ddr.ar.fire.asUInt - readRetire.asUInt
  readCount := nextReadCount
  when(switchRead && nextReadCount===0.U && !arHeld && !io.ddr.ar.valid) {
    readOwner := !readOwner;readTurn := 0.U
  }
  nativeLengths.io.enq.valid := io.ddr.ar.fire && readOwner
  nativeLengths.io.enq.bits := io.ddr.ar.bits.len
  nativeLengths.io.deq.ready := readRetire && readOwner
  when(io.ddr.r.fire && readOwner) {
    nativeReadIndex := Mux(nativeLast,0.U,nativeReadIndex+1.U)
  }
  when(nativeLengths.io.enq.valid) { assert(nativeLengths.io.enq.ready) }

  private val writeCurrent = Mux(writeOwner,io.native.aw.valid,io.legacy.aw.valid)
  private val writeOther = Mux(writeOwner,io.legacy.aw.valid,io.native.aw.valid && !io.emergency)
  private val switchWrite = writeOther && Mux(writeOwner,
    io.emergency || writeTurn===2.U || !writeCurrent,
    writeCount.orR || dataCount.orR || writeTurn.orR || !writeCurrent)
  private val writeCredit = writeCount < Mux(writeOwner,2.U,16.U) || writeRetire
  private val admitWrite = awHeld || (writeCredit && !switchWrite && (!writeOwner || !io.emergency))
  io.ddr.aw.valid := writeCurrent && admitWrite
  io.ddr.aw.bits := Mux(writeOwner,io.native.aw.bits,io.legacy.aw.bits)
  io.legacy.aw.ready := io.ddr.aw.ready && admitWrite && !writeOwner
  io.native.aw.ready := io.ddr.aw.ready && admitWrite && writeOwner
  when(io.ddr.aw.valid && !io.ddr.aw.ready) { awHeld := true.B }
  when(io.ddr.aw.fire) { awHeld := false.B;when(writeTurn=/=2.U) { writeTurn := writeTurn+1.U } }
  io.ddr.w.valid := dataCount.orR && Mux(writeOwner,io.native.w.valid,io.legacy.w.valid)
  io.ddr.w.bits := Mux(writeOwner,io.native.w.bits,io.legacy.w.bits)
  io.legacy.w.ready := io.ddr.w.ready && dataCount.orR && !writeOwner
  io.native.w.ready := io.ddr.w.ready && dataCount.orR && writeOwner
  private val nextWriteCount = writeCount + io.ddr.aw.fire.asUInt - writeRetire.asUInt
  private val nextDataCount = dataCount + io.ddr.aw.fire.asUInt - dataRetire.asUInt
  writeCount := nextWriteCount;dataCount := nextDataCount
  when(switchWrite && nextWriteCount===0.U && nextDataCount===0.U && !awHeld && !io.ddr.aw.valid) {
    writeOwner := !writeOwner;writeTurn := 0.U
  }
  assert(readCount<=16.U && writeCount<=16.U && dataCount<=16.U)
  when(readRetire) { assert(readCount.orR) }
  when(writeRetire) { assert(writeCount.orR) }
  when(dataRetire) { assert(dataCount.orR) }
}
