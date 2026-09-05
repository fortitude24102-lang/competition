package gpu

object GpuMemoryMap {
  val ApbBase: BigInt = BigInt("f8100000", 16)
  val ApbBytes: BigInt = 0x10000

  val FramebufferA: BigInt = BigInt("02000000", 16)
  val FramebufferB: BigInt = BigInt("02200000", 16)
  val DenseAssets: BigInt = BigInt("02400000", 16)
  val SparseAssets: BigInt = BigInt("06000000", 16)
  val DdrEndExclusive: BigInt = BigInt("10000000", 16)

  val FrameWidth = 640
  val FrameHeight = 480
  val BytesPerPixel = 2
  val FrameBytes: BigInt = FrameWidth * FrameHeight * BytesPerPixel
}

object GpuRegisterMap {
  val Id = 0x0000
  val Version = 0x0004
  val Status = 0x0008
  val Control = 0x000c
  val Op = 0x0010
  val SrcAddr = 0x0014
  val DstAddr = 0x0018
  val Size = 0x001c
  val SrcStride = 0x0020
  val DstStride = 0x0024
  val ColorKey = 0x0028
  val AlphaFlags = 0x002c
  val Tag = 0x0030
  val LastDone = 0x0034
  val Error = 0x0038
  val QueueLevel = 0x003c
  val FrontBuffer = 0x0040
  val BackBuffer = 0x0044
  val QosWatermarks = 0x0048
  val PerfControl = 0x004c
  val PerfCyclesLo = 0x0050
  val PerfCyclesHi = 0x0054
  val PerfPixelsLo = 0x0058
  val PerfPixelsHi = 0x005c
  val PerfReadBytesLo = 0x0060
  val PerfReadBytesHi = 0x0064
  val PerfWriteBytesLo = 0x0068
  val PerfWriteBytesHi = 0x006c
  val PerfStallsLo = 0x0070
  val PerfStallsHi = 0x0074

  val All: Seq[Int] = Seq(
    Id, Version, Status, Control, Op, SrcAddr, DstAddr, Size, SrcStride,
    DstStride, ColorKey, AlphaFlags, Tag, LastDone, Error, QueueLevel,
    FrontBuffer, BackBuffer, QosWatermarks, PerfControl, PerfCyclesLo,
    PerfCyclesHi, PerfPixelsLo, PerfPixelsHi, PerfReadBytesLo,
    PerfReadBytesHi, PerfWriteBytesLo, PerfWriteBytesHi, PerfStallsLo,
    PerfStallsHi
  )
}
