package gpu

import chisel3._
import chisel3.util._

/** Frozen A Day8 interface: one elastic stage, active-high synchronous reset. */
class PixelPipeExt(sourceDirectory: String = "../board/efinix_ti60/rtl/pixel") extends ExtModule {
  override def desiredName: String = "gpu_pixel_pipe"
  val clock = IO(Input(Clock()))
  val reset = IO(Input(Bool()))
  val in_valid = IO(Input(Bool()))
  val in_ready = IO(Output(Bool()))
  val op = IO(Input(UInt(3.W)))
  val foreground = IO(Input(UInt(16.W)))
  val background = IO(Input(UInt(16.W)))
  val fill_color = IO(Input(UInt(16.W)))
  val color_key = IO(Input(UInt(16.W)))
  val alpha = IO(Input(UInt(8.W)))
  val out_valid = IO(Output(Bool()))
  val out_ready = IO(Input(Bool()))
  val result_pixel = IO(Output(UInt(16.W)))
  val write_enable = IO(Output(Bool()))
  Seq("gpu_pixel_contract.vh", "gpu_pixel_copy.v", "gpu_pixel_fill.v", "gpu_pixel_pipe.v")
    .foreach(name => addPath(s"$sourceDirectory/$name"))
}

/** Standalone integration adapter; not yet wired into Efinix2dGpuTop. */
class PixelPipeHarness extends Module {
  val io = IO(new Bundle {
    val input = Flipped(Decoupled(new PixelTransaction))
    val output = Decoupled(new PixelResult)
  })
  private val pixel = Module(new PixelPipeExt)
  pixel.clock := clock
  pixel.reset := reset.asBool
  pixel.in_valid := io.input.valid
  io.input.ready := pixel.in_ready
  pixel.op := io.input.bits.op
  pixel.foreground := io.input.bits.foreground
  pixel.background := io.input.bits.background
  pixel.fill_color := io.input.bits.fillColor
  pixel.color_key := io.input.bits.colorKey
  pixel.alpha := io.input.bits.alpha
  io.output.valid := pixel.out_valid
  pixel.out_ready := io.output.ready
  io.output.bits.pixel := pixel.result_pixel
  io.output.bits.writeEnable := pixel.write_enable
}

