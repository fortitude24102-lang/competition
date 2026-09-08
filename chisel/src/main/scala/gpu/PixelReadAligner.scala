package gpu

import chisel3._
import chisel3.util._

class PixelReadConfig extends Bundle {
  val upperFirst = Bool()
  val pixels = UInt(16.W)
}

class AlignedPixel extends Bundle {
  val pixel = UInt(16.W)
  val last = Bool()
}

class PixelReadAligner extends Module {
  val io = IO(new Bundle {
    val start = Flipped(Decoupled(new PixelReadConfig))
    val input = Flipped(Decoupled(UInt(32.W)))
    val output = Decoupled(new AlignedPixel)
    val busy = Output(Bool())
    val done = Output(Bool())
  })

  private val active = RegInit(false.B)
  private val buffered = RegInit(false.B)
  private val word = Reg(UInt(32.W))
  private val upperPhase = Reg(Bool())
  private val upperFirst = Reg(Bool())
  private val remaining = Reg(UInt(16.W))
  private val doneReg = RegInit(false.B)

  doneReg := false.B
  io.start.ready := !active && !buffered
  io.input.ready := active && !buffered
  io.output.valid := active && buffered
  io.output.bits.pixel := Mux(upperPhase, word(31, 16), word(15, 0))
  io.output.bits.last := remaining === 1.U
  io.busy := active
  io.done := doneReg

  when(io.start.fire) {
    active := io.start.bits.pixels =/= 0.U
    upperFirst := io.start.bits.upperFirst
    remaining := io.start.bits.pixels
    when(io.start.bits.pixels === 0.U) {
      doneReg := true.B
    }
  }

  when(io.input.fire) {
    word := io.input.bits
    upperPhase := upperFirst
    upperFirst := false.B
    buffered := true.B
  }

  when(io.output.fire) {
    when(remaining === 1.U) {
      remaining := 0.U
      buffered := false.B
      active := false.B
      doneReg := true.B
    }.otherwise {
      remaining := remaining - 1.U
      when(upperPhase) {
        buffered := false.B
      }.otherwise {
        upperPhase := true.B
      }
    }
  }
}
