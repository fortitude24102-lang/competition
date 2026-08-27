package cpu

import chisel3._
import chisel3.util._

class LoadStoreUnit extends Module {
  val io = IO(new Bundle {
    val addr = Input(UInt(32.W))
    val memWidth = Input(MemWidth())
    val unsignedLoad = Input(Bool())
    val storeData = Input(UInt(32.W))
    val responseData = Input(UInt(32.W))
    val misaligned = Output(Bool())
    val wstrb = Output(UInt(4.W))
    val wdata = Output(UInt(32.W))
    val loadData = Output(UInt(32.W))
  })

  io.misaligned := MuxLookup(io.memWidth, false.B)(Seq(
    MemWidth.Byte -> false.B,
    MemWidth.Half -> io.addr(0),
    MemWidth.Word -> io.addr(1, 0).orR
  ))

  io.wstrb := 0.U
  io.wdata := 0.U
  switch(io.memWidth) {
    is(MemWidth.Byte) {
      switch(io.addr(1, 0)) {
        is(0.U) { io.wstrb := "b0001".U; io.wdata := io.storeData(7, 0) }
        is(1.U) { io.wstrb := "b0010".U; io.wdata := Cat(0.U(16.W), io.storeData(7, 0), 0.U(8.W)) }
        is(2.U) { io.wstrb := "b0100".U; io.wdata := Cat(0.U(8.W), io.storeData(7, 0), 0.U(16.W)) }
        is(3.U) { io.wstrb := "b1000".U; io.wdata := Cat(io.storeData(7, 0), 0.U(24.W)) }
      }
    }
    is(MemWidth.Half) {
      when(io.addr(1)) {
        io.wstrb := "b1100".U
        io.wdata := Cat(io.storeData(15, 0), 0.U(16.W))
      }.otherwise {
        io.wstrb := "b0011".U
        io.wdata := Cat(0.U(16.W), io.storeData(15, 0))
      }
    }
    is(MemWidth.Word) {
      io.wstrb := "b1111".U
      io.wdata := io.storeData
    }
  }

  val selectedByte = MuxLookup(io.addr(1, 0), io.responseData(7, 0))(Seq(
    0.U -> io.responseData(7, 0),
    1.U -> io.responseData(15, 8),
    2.U -> io.responseData(23, 16),
    3.U -> io.responseData(31, 24)
  ))
  val selectedHalf = Mux(io.addr(1), io.responseData(31, 16), io.responseData(15, 0))
  val byteResult = Mux(io.unsignedLoad, Cat(0.U(24.W), selectedByte), Cat(Fill(24, selectedByte(7)), selectedByte))
  val halfResult = Mux(io.unsignedLoad, Cat(0.U(16.W), selectedHalf), Cat(Fill(16, selectedHalf(15)), selectedHalf))

  io.loadData := MuxLookup(io.memWidth, byteResult)(Seq(
    MemWidth.Byte -> byteResult,
    MemWidth.Half -> halfResult,
    MemWidth.Word -> io.responseData
  ))
}
