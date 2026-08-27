package cpu

import chisel3._
import chisel3.util._

class CoreBusReq extends Bundle {
  val addr = UInt(32.W)
  val write = Bool()
  val size = UInt(2.W)
  val wdata = UInt(32.W)
  val wstrb = UInt(4.W)
}

class CoreBusResp extends Bundle {
  val rdata = UInt(32.W)
  val error = Bool()
}

class CoreBusIO extends Bundle {
  val req = Decoupled(new CoreBusReq)
  val resp = Flipped(Decoupled(new CoreBusResp))
}

class CommitTrace extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val writeEnable = Bool()
  val rd = UInt(5.W)
  val data = UInt(32.W)
}

class TrapTrace extends Bundle {
  val valid = Bool()
  val cause = UInt(4.W)
  val pc = UInt(32.W)
  val inst = UInt(32.W)
}
