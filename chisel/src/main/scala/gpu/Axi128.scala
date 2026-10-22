package gpu

import chisel3._
import chisel3.util._

/** Native DDR shape; deliberately separate from the existing 32-bit GPU bus. */
class Axi128Address extends Bundle {
  val addr = UInt(32.W)
  val id = UInt(8.W)
  val len = UInt(8.W)
  val size = UInt(3.W)
  val burst = UInt(2.W)
  val lock = Bool()
  val cache = UInt(4.W)
  val prot = UInt(3.W)
  val qos = UInt(4.W)
  val region = UInt(4.W)
}
class Axi128WriteData extends Bundle {
  val data = UInt(128.W)
  val strb = UInt(16.W)
  val last = Bool()
}
class Axi128WriteResponse extends Bundle {
  val id = UInt(8.W)
  val resp = UInt(2.W)
}
class Axi128ReadData extends Bundle {
  val id = UInt(8.W)
  val data = UInt(128.W)
  val resp = UInt(2.W)
  val last = Bool()
}
class Axi128MasterPort extends Bundle {
  val aw = Decoupled(new Axi128Address)
  val w = Decoupled(new Axi128WriteData)
  val b = Flipped(Decoupled(new Axi128WriteResponse))
  val ar = Decoupled(new Axi128Address)
  val r = Flipped(Decoupled(new Axi128ReadData))
}
class WideCopyRequest extends Bundle {
  val srcAddr = UInt(32.W)
  val dstAddr = UInt(32.W)
  val bytes = UInt(32.W)
  val tag = UInt(16.W)
}
