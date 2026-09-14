package gpu

import chisel3._
import chisel3.util._

/** Transaction-level round-robin with scanout-watermark hysteresis. */
class DdrQosArbiter(maxRenderWait: Int = 8) extends Module {
  require(maxRenderWait > 0)
  val io = IO(new Bundle {
    val render = Flipped(new Axi4MasterPort)
    val scanout = Flipped(new Axi4MasterPort)
    val axi = new Axi4MasterPort
    val scanoutLevel = Input(UInt(12.W))
    val lowWatermark = Input(UInt(12.W))
    val highWatermark = Input(UInt(12.W))
    val adaptiveEnable = Input(Bool())
    val scanoutPriority = Output(Bool())
    val renderGrant = Output(UInt(2.W))
    val scanoutGrant = Output(UInt(2.W))
  })

  private val readIdle :: readAddress :: readData :: Nil = Enum(3)
  private val writeIdle :: writeAddress :: writeData :: writeResponse :: Nil = Enum(4)
  private val readState = RegInit(readIdle)
  private val writeState = RegInit(writeIdle)
  private val readOwner = RegInit(false.B)
  private val writeOwner = RegInit(false.B)
  private val nextReadOwner = RegInit(false.B)
  private val nextWriteOwner = RegInit(false.B)
  private val scanoutPriority = RegInit(false.B)
  private val renderWait = RegInit(0.U(log2Ceil(maxRenderWait + 1).W))

  when(!io.adaptiveEnable) {
    scanoutPriority := false.B
  }.elsewhen(io.scanoutLevel <= io.lowWatermark) {
    scanoutPriority := true.B
  }.elsewhen(io.scanoutLevel >= io.highWatermark) {
    scanoutPriority := false.B
  }
  io.scanoutPriority := scanoutPriority

  private val forceRender = renderWait >= maxRenderWait.U
  private val readPreference = Mux(io.adaptiveEnable && scanoutPriority, !forceRender, nextReadOwner)

  private def choose(renderValid: Bool, scanoutValid: Bool, preferScanout: Bool): Bool =
    Mux(renderValid && scanoutValid, preferScanout, scanoutValid)

  when(readState === readIdle && (io.render.ar.valid || io.scanout.ar.valid)) {
    readOwner := choose(io.render.ar.valid, io.scanout.ar.valid, readPreference)
    readState := readAddress
  }
  when(writeState === writeIdle && (io.render.aw.valid || io.scanout.aw.valid)) {
    writeOwner := choose(io.render.aw.valid, io.scanout.aw.valid, nextWriteOwner)
    writeState := writeAddress
  }

  io.axi.ar.valid := false.B
  io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address)
  io.render.ar.ready := false.B
  io.scanout.ar.ready := false.B
  when(readState === readAddress) {
    io.axi.ar.valid := Mux(readOwner, io.scanout.ar.valid, io.render.ar.valid)
    io.axi.ar.bits := Mux(readOwner, io.scanout.ar.bits, io.render.ar.bits)
    when(readOwner) { io.scanout.ar.ready := io.axi.ar.ready }
      .otherwise { io.render.ar.ready := io.axi.ar.ready }
    when(io.axi.ar.fire) { readState := readData }
  }

  private val renderReadGrant = io.axi.ar.fire && !readOwner
  private val scanoutReadGrant = io.axi.ar.fire && readOwner
  when(!io.render.ar.valid || renderReadGrant) {
    renderWait := 0.U
  }.elsewhen(scanoutReadGrant && renderWait < maxRenderWait.U) {
    renderWait := renderWait + 1.U
  }

  io.render.r.valid := false.B
  io.render.r.bits := io.axi.r.bits
  io.scanout.r.valid := false.B
  io.scanout.r.bits := io.axi.r.bits
  io.axi.r.ready := false.B
  when(readState === readData) {
    when(readOwner) {
      io.scanout.r.valid := io.axi.r.valid
      io.axi.r.ready := io.scanout.r.ready
    }.otherwise {
      io.render.r.valid := io.axi.r.valid
      io.axi.r.ready := io.render.r.ready
    }
    when(io.axi.r.fire && io.axi.r.bits.last) {
      nextReadOwner := !readOwner
      readState := readIdle
    }
  }

  io.axi.aw.valid := false.B
  io.axi.aw.bits := 0.U.asTypeOf(new Axi4Address)
  io.render.aw.ready := false.B
  io.scanout.aw.ready := false.B
  when(writeState === writeAddress) {
    io.axi.aw.valid := Mux(writeOwner, io.scanout.aw.valid, io.render.aw.valid)
    io.axi.aw.bits := Mux(writeOwner, io.scanout.aw.bits, io.render.aw.bits)
    when(writeOwner) { io.scanout.aw.ready := io.axi.aw.ready }
      .otherwise { io.render.aw.ready := io.axi.aw.ready }
    when(io.axi.aw.fire) { writeState := writeData }
  }

  private val renderWriteGrant = io.axi.aw.fire && !writeOwner
  private val scanoutWriteGrant = io.axi.aw.fire && writeOwner
  io.renderGrant := renderReadGrant.asUInt +& renderWriteGrant.asUInt
  io.scanoutGrant := scanoutReadGrant.asUInt +& scanoutWriteGrant.asUInt

  io.axi.w.valid := false.B
  io.axi.w.bits := 0.U.asTypeOf(new Axi4WriteData)
  io.render.w.ready := false.B
  io.scanout.w.ready := false.B
  when(writeState === writeData) {
    io.axi.w.valid := Mux(writeOwner, io.scanout.w.valid, io.render.w.valid)
    io.axi.w.bits := Mux(writeOwner, io.scanout.w.bits, io.render.w.bits)
    when(writeOwner) { io.scanout.w.ready := io.axi.w.ready }
      .otherwise { io.render.w.ready := io.axi.w.ready }
    when(io.axi.w.fire && io.axi.w.bits.last) { writeState := writeResponse }
  }

  io.render.b.valid := false.B
  io.render.b.bits := io.axi.b.bits
  io.scanout.b.valid := false.B
  io.scanout.b.bits := io.axi.b.bits
  io.axi.b.ready := false.B
  when(writeState === writeResponse) {
    when(writeOwner) {
      io.scanout.b.valid := io.axi.b.valid
      io.axi.b.ready := io.scanout.b.ready
    }.otherwise {
      io.render.b.valid := io.axi.b.valid
      io.axi.b.ready := io.render.b.ready
    }
    when(io.axi.b.fire) {
      nextWriteOwner := !writeOwner
      writeState := writeIdle
    }
  }
}
