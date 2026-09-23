package gpu

import chisel3._
import chisel3.util._

/** Transaction-level arbitration for Render reads/writes, Scanout reads and Asset writes. */
class DdrQosArbiter(maxRenderWait: Int = 8) extends Module {
  require(maxRenderWait > 0)
  val io = IO(new Bundle {
    val render = Flipped(new Axi4MasterPort)
    val scanout = Flipped(new Axi4MasterPort)
    val asset = Flipped(new Axi4MasterPort)
    val axi = new Axi4MasterPort
    val scanoutLevel = Input(UInt(12.W))
    val lowWatermark = Input(UInt(12.W))
    val highWatermark = Input(UInt(12.W))
    val adaptiveEnable = Input(Bool())
    val scanoutPriority = Output(Bool())
    val renderGrant = Output(UInt(2.W))
    val scanoutGrant = Output(UInt(2.W))
    val assetGrant = Output(UInt(2.W))
  })

  private val readIdle :: readAddress :: readData :: Nil = Enum(3)
  private val writeIdle :: writeAddress :: writeData :: writeResponse :: Nil = Enum(4)
  private val readState = RegInit(readIdle)
  private val writeState = RegInit(writeIdle)
  private val readOwner = RegInit(false.B) // false: Render, true: Scanout
  private val writeOwner = RegInit(false.B) // false: Render, true: Asset
  private val readAddressPresented = RegInit(false.B)
  private val writeAddressPresented = RegInit(false.B)
  private val nextReadOwner = RegInit(false.B)
  private val nextWriteOwner = RegInit(false.B)
  private val scanoutPriority = RegInit(false.B)
  private val renderWait = RegInit(0.U(log2Ceil(maxRenderWait + 1).W))
  // Render can stall R while waiting for a new AW, which emergency QoS blocks.
  // Reserve one complete maximum burst so that physical R can always drain
  // and release the read channel to Scanout, independently of Render's sink.
  private val renderResponses = Module(new Queue(new Axi4ReadData, 256, flow = true))
  private val renderResponseSpace = renderResponses.io.count === 0.U

  when(!io.adaptiveEnable || io.scanoutLevel >= io.highWatermark) {
    scanoutPriority := false.B
  }.elsewhen(io.scanoutLevel <= io.lowWatermark) {
    scanoutPriority := true.B
  }
  // Enter immediately at the low mark; the register retains priority through hysteresis.
  private val emergency = io.adaptiveEnable &&
    (io.scanoutLevel <= io.lowWatermark ||
      (scanoutPriority && io.scanoutLevel < io.highWatermark))
  io.scanoutPriority := emergency

  private val renderPending = (io.render.ar.valid && renderResponseSpace) || io.render.aw.valid
  private val repayRender = renderPending && renderWait >= maxRenderWait.U
  private def choose(firstValid: Bool, secondValid: Bool, preferSecond: Bool): Bool =
    Mux(firstValid && secondValid, preferSecond, secondValid)

  when(readState === readIdle) {
    val renderEligible = io.render.ar.valid && renderResponseSpace && !emergency
    val scanoutEligible = io.scanout.ar.valid && (emergency || !repayRender)
    when(renderEligible || scanoutEligible) {
      readOwner := choose(renderEligible, scanoutEligible, emergency || nextReadOwner)
      readState := readAddress
      readAddressPresented := false.B
    }
  }
  when(writeState === writeIdle && !emergency) {
    val renderEligible = io.render.aw.valid
    val assetEligible = io.asset.aw.valid && !repayRender
    when(renderEligible || assetEligible) {
      writeOwner := choose(renderEligible, assetEligible, nextWriteOwner)
      writeState := writeAddress
      writeAddressPresented := false.B
    }
  }

  io.axi.ar.valid := false.B
  io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address)
  io.render.ar.ready := false.B
  io.scanout.ar.ready := false.B
  io.asset.ar.ready := false.B
  // Recheck admission after selection. Once VALID has been presented under
  // backpressure it is an in-flight AXI address and must not be withdrawn.
  private val deferRead = emergency && !readOwner && !readAddressPresented
  when(readState === readAddress && deferRead) { readState := readIdle }
  when(readState === readAddress && !deferRead) {
    io.axi.ar.valid := Mux(readOwner, io.scanout.ar.valid, io.render.ar.valid)
    io.axi.ar.bits := Mux(readOwner, io.scanout.ar.bits, io.render.ar.bits)
    when(readOwner) { io.scanout.ar.ready := io.axi.ar.ready }
      .otherwise { io.render.ar.ready := io.axi.ar.ready }
    when(io.axi.ar.fire) { readState := readData }
    when(io.axi.ar.valid) { readAddressPresented := true.B }
  }

  private val renderReadGrant = io.axi.ar.fire && !readOwner
  private val scanoutReadGrant = io.axi.ar.fire && readOwner

  io.render.r <> renderResponses.io.deq
  renderResponses.io.enq.valid := false.B
  renderResponses.io.enq.bits := io.axi.r.bits
  io.scanout.r.valid := false.B
  io.scanout.r.bits := io.axi.r.bits
  io.asset.r.valid := false.B
  io.asset.r.bits := 0.U.asTypeOf(new Axi4ReadData)
  io.axi.r.ready := false.B
  when(readState === readData) {
    when(readOwner) {
      io.scanout.r.valid := io.axi.r.valid
      io.axi.r.ready := io.scanout.r.ready
    }.otherwise {
      renderResponses.io.enq.valid := io.axi.r.valid
      io.axi.r.ready := renderResponses.io.enq.ready
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
  io.asset.aw.ready := false.B
  private val deferWrite = emergency && !writeAddressPresented
  when(writeState === writeAddress && deferWrite) { writeState := writeIdle }
  when(writeState === writeAddress && !deferWrite) {
    io.axi.aw.valid := Mux(writeOwner, io.asset.aw.valid, io.render.aw.valid)
    io.axi.aw.bits := Mux(writeOwner, io.asset.aw.bits, io.render.aw.bits)
    when(writeOwner) { io.asset.aw.ready := io.axi.aw.ready }
      .otherwise { io.render.aw.ready := io.axi.aw.ready }
    when(io.axi.aw.fire) { writeState := writeData }
    when(io.axi.aw.valid) { writeAddressPresented := true.B }
  }

  private val renderWriteGrant = io.axi.aw.fire && !writeOwner
  private val assetWriteGrant = io.axi.aw.fire && writeOwner
  io.renderGrant := renderReadGrant.asUInt +& renderWriteGrant.asUInt
  io.scanoutGrant := scanoutReadGrant.asUInt
  io.assetGrant := assetWriteGrant.asUInt

  // Count competing admissions, a conservative bound on completed transactions.
  private val competingGrants = scanoutReadGrant.asUInt +& assetWriteGrant.asUInt
  private val nextRenderWait = renderWait +& competingGrants
  when(!renderPending || renderReadGrant || renderWriteGrant) {
    renderWait := 0.U
  }.elsewhen(!emergency && competingGrants =/= 0.U && renderWait < maxRenderWait.U) {
    renderWait := Mux(nextRenderWait >= maxRenderWait.U, maxRenderWait.U, nextRenderWait)
  }

  io.axi.w.valid := false.B
  io.axi.w.bits := 0.U.asTypeOf(new Axi4WriteData)
  io.render.w.ready := false.B
  io.scanout.w.ready := false.B
  io.asset.w.ready := false.B
  when(writeState === writeData) {
    io.axi.w.valid := Mux(writeOwner, io.asset.w.valid, io.render.w.valid)
    io.axi.w.bits := Mux(writeOwner, io.asset.w.bits, io.render.w.bits)
    when(writeOwner) { io.asset.w.ready := io.axi.w.ready }
      .otherwise { io.render.w.ready := io.axi.w.ready }
    when(io.axi.w.fire && io.axi.w.bits.last) { writeState := writeResponse }
  }

  io.render.b.valid := false.B
  io.render.b.bits := io.axi.b.bits
  io.scanout.b.valid := false.B
  io.scanout.b.bits := 0.U.asTypeOf(new Axi4WriteResponse)
  io.asset.b.valid := false.B
  io.asset.b.bits := io.axi.b.bits
  io.axi.b.ready := false.B
  when(writeState === writeResponse) {
    when(writeOwner) {
      io.asset.b.valid := io.axi.b.valid
      io.axi.b.ready := io.asset.b.ready
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
