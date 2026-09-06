package gpu

import chisel3._
import chisel3.util._

class PixelWriteInput extends Bundle {
  val address = UInt(32.W)
  val pixel = UInt(16.W)
  val writeEnable = Bool()
  val rowLast = Bool()
}

class PackedPixelWrite extends Bundle {
  val address = UInt(32.W)
  val data = UInt(32.W)
  val strb = UInt(4.W)
  val rowLast = Bool()
}

class PixelWritePacker extends Module {
  val io = IO(new Bundle {
    val input = Flipped(Decoupled(new PixelWriteInput))
    val output = Decoupled(new PackedPixelWrite)
  })

  private val openValid = RegInit(false.B)
  private val openAddress = Reg(UInt(32.W))
  private val openData = Reg(UInt(32.W))
  private val openStrb = Reg(UInt(4.W))
  private val openRowLast = Reg(Bool())

  private val outputValid = RegInit(false.B)
  private val outputBits = Reg(new PackedPixelWrite)

  io.output.valid := outputValid
  io.output.bits := outputBits
  io.input.ready := false.B

  when(io.output.fire) {
    outputValid := false.B
  }

  when(!outputValid) {
    when(openValid) {
      when(io.input.valid) {
        val alignedAddress = Cat(io.input.bits.address(31, 2), 0.U(2.W))
        when(alignedAddress === openAddress) {
          io.input.ready := true.B
          when(io.input.fire) {
            outputBits.address := openAddress
            outputBits.data := Mux(
              io.input.bits.writeEnable,
              Cat(io.input.bits.pixel, openData(15, 0)),
              openData
            )
            outputBits.strb := Mux(io.input.bits.writeEnable, openStrb | "hc".U, openStrb)
            outputBits.rowLast := io.input.bits.rowLast
            outputValid := true.B
            openValid := false.B
          }
        }.otherwise {
          outputBits.address := openAddress
          outputBits.data := openData
          outputBits.strb := openStrb
          outputBits.rowLast := openRowLast
          outputValid := true.B
          openValid := false.B
        }
      }
    }.otherwise {
      io.input.ready := true.B
      when(io.input.fire && io.input.bits.writeEnable) {
        val alignedAddress = Cat(io.input.bits.address(31, 2), 0.U(2.W))
        val upper = io.input.bits.address(1)
        val packedData = Mux(upper, Cat(io.input.bits.pixel, 0.U(16.W)), io.input.bits.pixel)
        val packedStrb = Mux(upper, "hc".U, "h3".U)
        when(upper || io.input.bits.rowLast) {
          outputBits.address := alignedAddress
          outputBits.data := packedData
          outputBits.strb := packedStrb
          outputBits.rowLast := io.input.bits.rowLast
          outputValid := true.B
        }.otherwise {
          openAddress := alignedAddress
          openData := packedData
          openStrb := packedStrb
          openRowLast := io.input.bits.rowLast
          openValid := true.B
        }
      }
    }
  }
}
