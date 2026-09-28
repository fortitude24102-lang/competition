package gpu

import chisel3._
import chisel3.util._

class Rgb565WordConfig extends Bundle {
  val sourceUpper = Bool()
  val destinationUpper = Bool()
  val pixels = UInt(16.W)
}

class Rgb565AlignedWord extends Bundle {
  val data = UInt(32.W)
  val lanes = UInt(2.W)
  val pixels = UInt(2.W)
}

/** Small shift/carry reservoir; no background reads and no per-pixel transactions. */
class Rgb565WordAligner extends Module {
  val io = IO(new Bundle {
    val start = Flipped(Decoupled(new Rgb565WordConfig))
    val input = Flipped(Decoupled(UInt(32.W)))
    val output = Decoupled(new Rgb565AlignedWord)
  })
  private val active = RegInit(false.B)
  private val buffer = RegInit(0.U(64.W))
  private val bufferedPixels = RegInit(0.U(3.W))
  private val inputLeft = Reg(UInt(16.W))
  private val outputLeft = Reg(UInt(16.W))
  private val sourceUpper = Reg(Bool())
  private val destinationUpper = Reg(Bool())
  private val inputPixels = Mux(sourceUpper || inputLeft === 1.U, 1.U(2.W), 2.U(2.W))
  private val outputPixels = Mux(destinationUpper || outputLeft === 1.U, 1.U(2.W), 2.U(2.W))

  io.start.ready := !active
  io.input.ready := active && inputLeft =/= 0.U && bufferedPixels <= 2.U
  io.output.valid := active && bufferedPixels >= outputPixels
  io.output.bits.pixels := outputPixels
  io.output.bits.lanes := Mux(destinationUpper, "b10".U, Mux(outputPixels === 1.U, "b01".U, "b11".U))
  io.output.bits.data := Mux(destinationUpper, Cat(buffer(15, 0), 0.U(16.W)),
    Mux(outputPixels === 1.U, Cat(0.U(16.W), buffer(15, 0)), buffer(31, 0)))

  when(io.start.fire) {
    active := io.start.bits.pixels =/= 0.U
    buffer := 0.U
    bufferedPixels := 0.U
    inputLeft := io.start.bits.pixels
    outputLeft := io.start.bits.pixels
    sourceUpper := io.start.bits.sourceUpper
    destinationUpper := io.start.bits.destinationUpper
  }
  private val consumed = Mux(io.output.fire, outputPixels, 0.U)
  private val carriedPixels = bufferedPixels - consumed
  private val carried = Mux(!io.output.fire, buffer,
    Mux(outputPixels === 1.U, Cat(0.U(16.W), buffer(63, 16)), Cat(0.U(32.W), buffer(63, 32))))
  private val incoming = Mux(sourceUpper, Cat(0.U(16.W), io.input.bits(31, 16)),
    Mux(inputPixels === 1.U, Cat(0.U(16.W), io.input.bits(15, 0)), io.input.bits))
  // Fixed 16-bit shifts avoid a general-purpose byte barrel shifter.
  private val appended = Mux(carriedPixels === 0.U, incoming.pad(64),
    Mux(carriedPixels === 1.U, Cat(0.U(16.W), incoming, 0.U(16.W)), Cat(incoming, 0.U(32.W))))
  when(io.input.fire || io.output.fire) {
    buffer := carried | Mux(io.input.fire, appended, 0.U)
    bufferedPixels := carriedPixels + Mux(io.input.fire, inputPixels, 0.U)
  }
  when(io.input.fire) {
    inputLeft := inputLeft - inputPixels
    sourceUpper := false.B
  }
  when(io.output.fire) {
    outputLeft := outputLeft - outputPixels
    destinationUpper := false.B
    when(outputLeft === outputPixels) { active := false.B }
  }
}
