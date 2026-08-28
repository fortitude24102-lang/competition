package soc

import chisel3._
import chisel3.util._
import cpu.{CoreBusReq, CoreBusResp}

class SocBusTargetIO extends Bundle {
  val req = Flipped(Decoupled(new CoreBusReq))
  val resp = Decoupled(new CoreBusResp)
}
