package gpu

import chisel3._
import chisel3.util._

/** Ordered nearest-neighbor RGB565 rasterizer. Commands are validated upstream. */
class TransformBlitEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val completion = Decoupled(new GpuCompletion)
    val axi = new Axi4MasterPort
    val pixelDone = Output(Bool())
  })

  private val reader = Module(new AxiReadEngine)
  private val writer = Module(new AxiWriteEngine)
  private val idle :: issueRead :: waitRead :: issueWrite :: waitWrite :: advance :: stepX :: stepY :: finish :: Nil = Enum(9)
  private val state = RegInit(idle)
  private val command = Reg(new GpuCommand)
  private val error = RegInit(GpuError.None.U(8.W))
  private val x = RegInit(0.U(16.W))
  private val y = RegInit(0.U(16.W))
  private val sx = RegInit(0.U(16.W))
  private val sy = RegInit(0.U(16.W))
  private val remainderX = RegInit(0.U(17.W))
  private val remainderY = RegInit(0.U(17.W))
  private val pixel = Reg(UInt(16.W))

  io.command.ready := state === idle
  when(io.command.fire) {
    command := io.command.bits
    x := 0.U
    y := 0.U
    sx := 0.U
    sy := 0.U
    remainderX := 0.U
    remainderY := 0.U
    error := GpuError.None.U
    state := issueRead
  }

  private val sourceX = Mux(command.flags(0), command.srcWidthPixels - 1.U - sx, sx)
  private val sourceY = Mux(command.flags(1), command.srcHeightPixels - 1.U - sy, sy)
  private val sourceAddress = command.srcAddr + (sourceY * command.srcStride)(31, 0) + (sourceX << 1)
  private val destinationAddress = command.dstAddr + (y * command.dstStride)(31, 0) + (x << 1)
  reader.io.request.valid := state === issueRead
  reader.io.request.bits.address := sourceAddress
  reader.io.request.bits.bytes := 2.U
  reader.io.data.ready := state === waitRead
  when(reader.io.request.fire) { state := waitRead }
  when(reader.io.data.fire) {
    pixel := Mux(sourceAddress(1), reader.io.data.bits.data(31, 16), reader.io.data.bits.data(15, 0))
  }
  when(state === waitRead && reader.io.done) {
    when(reader.io.error) {
      error := GpuError.AxiResponse.U
      state := finish
    }.elsewhen(command.flags(4) && pixel === command.colorKey) {
      state := advance
    }.otherwise {
      state := issueWrite
    }
  }

  writer.io.request.valid := state === issueWrite
  writer.io.request.bits.address := destinationAddress
  writer.io.request.bits.beats := 1.U
  writer.io.data.valid := state === waitWrite
  writer.io.data.bits.data := Cat(pixel, pixel)
  writer.io.data.bits.strb := Mux(destinationAddress(1), "hc".U, "h3".U)
  when(writer.io.request.fire) { state := waitWrite }
  when(state === waitWrite && writer.io.done) {
    when(writer.io.error) {
      error := GpuError.AxiResponse.U
      state := finish
    }.otherwise {
      state := advance
    }
  }

  // Count each successful pixel once, including pixels suppressed by Key.
  io.pixelDone := state === advance
  when(state === advance) {
    when(x === command.widthPixels - 1.U) {
      when(y === command.heightPixels - 1.U) {
        state := finish
      }.otherwise {
        x := 0.U
        sx := 0.U
        remainderX := 0.U
        y := y + 1.U
        remainderY := remainderY + command.srcHeightPixels
        state := stepY
      }
    }.otherwise {
      x := x + 1.U
      remainderX := remainderX + command.srcWidthPixels
      state := stepX
    }
  }
  // Exact floor(x*srcWidth/dstWidth), with the same recurrence for Y.
  // ponytail: severe shrinking costs source-step cycles; add a setup quotient
  // only if measured workloads need it. No divider or texture cache here.
  when(state === stepX) {
    when(remainderX >= command.widthPixels) {
      remainderX := remainderX - command.widthPixels
      sx := sx + 1.U
    }.otherwise { state := issueRead }
  }
  when(state === stepY) {
    when(remainderY >= command.heightPixels) {
      remainderY := remainderY - command.heightPixels
      sy := sy + 1.U
    }.otherwise { state := issueRead }
  }

  // Each read/write is one beat. Its engine reports done only after the R/B
  // handshake, so even failures reach finish with no promised traffic left.
  io.completion.valid := state === finish
  io.completion.bits.tag := command.tag
  io.completion.bits.error := error
  when(io.completion.fire) { state := idle }

  io.axi.ar <> reader.io.axiAr
  reader.io.axiR <> io.axi.r
  io.axi.aw <> writer.io.axiAw
  io.axi.w <> writer.io.axiW
  writer.io.axiB <> io.axi.b
}
