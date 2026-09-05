package gpu

import chisel3._

object GpuOpcode {
  val Nop = 0
  val Fill = 1
  val Copy = 2
  val ColorKey = 3
  val Alpha = 4
  val Sparse = 5
  val Present = 6
  val Max = Present
}

object GpuError {
  val None = 0
  val InvalidOpcode = 1
  val ZeroSize = 2
  val MisalignedAddress = 3
  val StrideTooSmall = 4
  val AddressRange = 5
  val OverlappingCopy = 6
  val QueueFull = 7
  val SparseFormat = 8
  val AxiResponse = 9
}

class GpuCommand extends Bundle {
  val op = UInt(4.W)
  val srcAddr = UInt(32.W)
  val dstAddr = UInt(32.W)
  val widthPixels = UInt(16.W)
  val heightPixels = UInt(16.W)
  val srcStride = UInt(32.W)
  val dstStride = UInt(32.W)
  val color = UInt(16.W)
  val colorKey = UInt(16.W)
  val alpha = UInt(8.W)
  val flags = UInt(16.W)
  val tag = UInt(16.W)
}

class GpuCompletion extends Bundle {
  val tag = UInt(16.W)
  val error = UInt(8.W)
}

class PixelTransaction extends Bundle {
  val op = UInt(3.W)
  val foreground = UInt(16.W)
  val background = UInt(16.W)
  val fillColor = UInt(16.W)
  val colorKey = UInt(16.W)
  val alpha = UInt(8.W)
}

class PixelResult extends Bundle {
  val pixel = UInt(16.W)
  val writeEnable = Bool()
}
