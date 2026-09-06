package gpu

import chisel3._

class ApbSlavePort extends Bundle {
  val paddr = Input(UInt(16.W))
  val psel = Input(Bool())
  val penable = Input(Bool())
  val pwrite = Input(Bool())
  val pwdata = Input(UInt(32.W))
  val prdata = Output(UInt(32.W))
  val pready = Output(Bool())
  val pslverror = Output(Bool())
}

class Efinix2dGpuTop extends Module {
  val io = IO(new Bundle {
    val apb = new ApbSlavePort
    val axi = new Axi4MasterPort
    val vblank = Input(Bool())
    val scanoutLevel = Input(UInt(12.W))
    val displayReady = Input(Bool())
    val displayPixel = Output(UInt(16.W))
    val displayValid = Output(Bool())
    val irq = Output(Bool())
  })

  io.apb.prdata := 0.U
  io.apb.pready := true.B
  io.apb.pslverror := false.B

  io.axi.aw.valid := false.B
  io.axi.aw.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.w.valid := false.B
  io.axi.w.bits := 0.U.asTypeOf(new Axi4WriteData)
  io.axi.b.ready := false.B
  io.axi.ar.valid := false.B
  io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.r.ready := false.B

  io.displayPixel := 0.U
  io.displayValid := false.B
  io.irq := false.B
}
