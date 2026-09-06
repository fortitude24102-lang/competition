package gpu

import chisel3._
import chisel3.util._

object Axi4 {
  val Okay = 0
  val Incrementing = 1
  val WordSize = 2
}

class Axi4Address extends Bundle {
  val addr = UInt(32.W)
  val id = UInt(4.W)
  val len = UInt(8.W)
  val size = UInt(3.W)
  val burst = UInt(2.W)
  val lock = Bool()
  val cache = UInt(4.W)
  val prot = UInt(3.W)
  val qos = UInt(4.W)
  val region = UInt(4.W)
}

class Axi4WriteData extends Bundle {
  val data = UInt(32.W)
  val strb = UInt(4.W)
  val last = Bool()
}

class Axi4WriteResponse extends Bundle {
  val id = UInt(4.W)
  val resp = UInt(2.W)
}

class Axi4ReadData extends Bundle {
  val id = UInt(4.W)
  val data = UInt(32.W)
  val resp = UInt(2.W)
  val last = Bool()
}

class Axi4MasterPort extends Bundle {
  val aw = Decoupled(new Axi4Address)
  val w = Decoupled(new Axi4WriteData)
  val b = Flipped(Decoupled(new Axi4WriteResponse))
  val ar = Decoupled(new Axi4Address)
  val r = Flipped(Decoupled(new Axi4ReadData))
}
