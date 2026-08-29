package soc

import chisel3._

class StreamBeat(val dataWidth: Int) extends Bundle {
  val data = UInt(dataWidth.W)
  val startOfFrame = Bool()
  val endOfLine = Bool()
  val endOfFrame = Bool()
}
