package gpu

import chisel3._
import chisel3.util._

class RectConfig extends Bundle {
  val base = UInt(32.W)
  val widthPixels = UInt(16.W)
  val heightPixels = UInt(16.W)
  val stride = UInt(32.W)
}

class RectAddress extends Bundle {
  val address = UInt(32.W)
  val rowLast = Bool()
  val last = Bool()
}

class RectAddressGen extends Module {
  val io = IO(new Bundle {
    val start = Flipped(Decoupled(new RectConfig))
    val address = Decoupled(new RectAddress)
    val busy = Output(Bool())
    val done = Output(Bool())
  })

  private val active = RegInit(false.B)
  private val rowBase = Reg(UInt(32.W))
  private val currentAddress = Reg(UInt(32.W))
  private val widthPixels = Reg(UInt(16.W))
  private val heightPixels = Reg(UInt(16.W))
  private val stride = Reg(UInt(32.W))
  private val x = Reg(UInt(16.W))
  private val y = Reg(UInt(16.W))
  private val doneReg = RegInit(false.B)

  doneReg := false.B
  io.start.ready := !active
  io.busy := active
  io.done := doneReg
  io.address.valid := active
  io.address.bits.address := currentAddress
  io.address.bits.rowLast := x === widthPixels - 1.U
  io.address.bits.last := io.address.bits.rowLast && y === heightPixels - 1.U

  when(io.start.fire) {
    rowBase := io.start.bits.base
    currentAddress := io.start.bits.base
    widthPixels := io.start.bits.widthPixels
    heightPixels := io.start.bits.heightPixels
    stride := io.start.bits.stride
    x := 0.U
    y := 0.U
    active := io.start.bits.widthPixels =/= 0.U && io.start.bits.heightPixels =/= 0.U
    when(io.start.bits.widthPixels === 0.U || io.start.bits.heightPixels === 0.U) {
      doneReg := true.B
    }
  }

  when(io.address.fire) {
    when(io.address.bits.last) {
      active := false.B
      doneReg := true.B
    }.elsewhen(io.address.bits.rowLast) {
      x := 0.U
      y := y + 1.U
      rowBase := rowBase + stride
      currentAddress := rowBase + stride
    }.otherwise {
      x := x + 1.U
      currentAddress := currentAddress + 2.U
    }
  }
}
