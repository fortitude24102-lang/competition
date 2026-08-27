package soc

import chisel3._

class RegDemo extends Module {
  val io = IO(new Bundle {
    val write_en = Input(Bool())
    val write_data = Input(UInt(8.W))
    val read_data = Output(UInt(8.W))
  })

  val value = RegInit(0.U(8.W))

  when(io.write_en) {
    value := io.write_data
  }

  io.read_data := value
}
