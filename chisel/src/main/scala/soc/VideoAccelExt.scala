package soc

import chisel3._
import chisel3.experimental.ExtModule

class VideoAccelExt(sourcePath: String) extends ExtModule {
  override def desiredName: String = "VideoAccelTop"

  val clock = IO(Input(Clock()))
  val reset = IO(Input(Bool()))
  val pixel_in = IO(Input(UInt(24.W)))
  val pixel_in_valid = IO(Input(Bool()))
  val pixel_in_ready = IO(Output(Bool()))
  val pixel_in_start_of_frame = IO(Input(Bool()))
  val pixel_in_end_of_line = IO(Input(Bool()))
  val pixel_in_end_of_frame = IO(Input(Bool()))
  val enable = IO(Input(Bool()))
  val mode = IO(Input(UInt(2.W)))
  val threshold = IO(Input(UInt(8.W)))
  val bypass = IO(Input(Bool()))
  val pixel_out = IO(Output(UInt(24.W)))
  val pixel_out_valid = IO(Output(Bool()))
  val pixel_out_ready = IO(Input(Bool()))
  val pixel_out_start_of_frame = IO(Output(Bool()))
  val pixel_out_end_of_line = IO(Output(Bool()))
  val pixel_out_end_of_frame = IO(Output(Bool()))
  val busy = IO(Output(Bool()))
  val frame_done = IO(Output(Bool()))

  addPath(sourcePath)
}
