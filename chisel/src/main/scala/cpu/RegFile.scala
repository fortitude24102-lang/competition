package cpu

import chisel3._
import chisel3.util._

class RegFile extends Module {
  val io = IO(new Bundle {
    val rs1 = Input(UInt(5.W))
    val rs2 = Input(UInt(5.W))
    val rd = Input(UInt(5.W))
    val writeEnable = Input(Bool())
    val writeData = Input(UInt(32.W))
    val rs1Data = Output(UInt(32.W))
    val rs2Data = Output(UInt(32.W))
  })

  val registers = RegInit(VecInit(Seq.fill(32)(0.U(32.W))))

  when(io.writeEnable && io.rd =/= 0.U) {
    registers(io.rd) := io.writeData
  }

  private def read(index: UInt): UInt = {
    Mux(
      index === 0.U,
      0.U,
      Mux(io.writeEnable && io.rd === index, io.writeData, registers(index))
    )
  }

  io.rs1Data := read(io.rs1)
  io.rs2Data := read(io.rs2)
}
