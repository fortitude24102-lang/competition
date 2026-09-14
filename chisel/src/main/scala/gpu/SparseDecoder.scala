package gpu

import chisel3._
import chisel3.util._

class SparseDecodeStart extends Bundle {
  val widthPixels = UInt(16.W)
  val heightPixels = UInt(16.W)
}

class SparseDecodeEvent extends Bundle {
  val x = UInt(16.W)
  val y = UInt(16.W)
  val pixel = UInt(16.W)
  val writeEnable = Bool()
  val rowLast = Bool()
}

/** Decodes {runPixels, skipPixels} headers and packed RGB565 literal words. */
class SparseDecoder extends Module {
  val io = IO(new Bundle {
    val start = Flipped(Decoupled(new SparseDecodeStart))
    val input = Flipped(Decoupled(UInt(32.W)))
    val output = Decoupled(new SparseDecodeEvent)
    val abort = Input(Bool())
    val busy = Output(Bool())
    val done = Output(Bool())
    val error = Output(Bool())
  })

  private val idle :: header :: literalWord :: emitLow :: emitHigh :: emitRowEnd :: finished :: Nil = Enum(7)
  private val state = RegInit(idle)
  private val width = Reg(UInt(16.W))
  private val height = Reg(UInt(16.W))
  private val x = RegInit(0.U(16.W))
  private val y = RegInit(0.U(16.W))
  private val runRemaining = Reg(UInt(16.W))
  private val literals = Reg(UInt(32.W))
  private val error = RegInit(false.B)

  io.start.ready := state === idle || state === finished
  io.input.ready := state === header || state === literalWord
  io.output.valid := state === emitLow || state === emitHigh || state === emitRowEnd
  io.output.bits.x := x
  io.output.bits.y := y
  io.output.bits.pixel := Mux(
    state === emitRowEnd,
    0.U,
    Mux(state === emitHigh, literals(31, 16), literals(15, 0))
  )
  io.output.bits.writeEnable := state === emitLow || state === emitHigh
  io.output.bits.rowLast := state === emitRowEnd
  io.busy := state =/= idle && state =/= finished
  io.done := state === finished
  io.error := error

  when(io.abort) {
    state := idle
    error := false.B
  }.otherwise {
    when(io.start.fire) {
      width := io.start.bits.widthPixels
      height := io.start.bits.heightPixels
      x := 0.U
      y := 0.U
      error := false.B
      state := header
    }

    when(state === header && io.input.fire) {
      val skip = io.input.bits(15, 0)
      val run = io.input.bits(31, 16)
      val afterSkip = x.pad(17) + skip
      val afterRun = afterSkip + run
      when(afterSkip > width || afterRun > width) {
        error := true.B
        state := finished
      }.elsewhen(run === 0.U) {
        when(afterSkip =/= width) {
          error := true.B
          state := finished
        }.otherwise {
          x := afterSkip(15, 0)
          state := emitRowEnd
        }
      }.otherwise {
        x := afterSkip(15, 0)
        runRemaining := run
        state := literalWord
      }
    }

    when(state === literalWord && io.input.fire) {
      when(runRemaining === 1.U && io.input.bits(31, 16).orR) {
        error := true.B
        state := finished
      }.otherwise {
        literals := io.input.bits
        state := emitLow
      }
    }

    when(state === emitLow && io.output.fire) {
      x := x + 1.U
      runRemaining := runRemaining - 1.U
      state := Mux(runRemaining === 1.U, header, emitHigh)
    }

    when(state === emitHigh && io.output.fire) {
      x := x + 1.U
      runRemaining := runRemaining - 1.U
      state := Mux(runRemaining === 1.U, header, literalWord)
    }

    when(state === emitRowEnd && io.output.fire) {
      when(y === height - 1.U) {
        state := finished
      }.otherwise {
        x := 0.U
        y := y + 1.U
        state := header
      }
    }
  }
}
