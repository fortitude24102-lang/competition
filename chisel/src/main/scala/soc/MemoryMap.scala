package soc

import chisel3._

sealed trait MemoryRegion

object MemoryRegion {
  case object BootRam extends MemoryRegion
  case object Uart extends MemoryRegion
  case object Accelerator extends MemoryRegion
  case object External extends MemoryRegion
  case object Unmapped extends MemoryRegion
}

object MemoryMap {
  val BootRamBase: BigInt = BigInt("00000000", 16)
  val BootRamBytes: BigInt = BigInt("00010000", 16)
  val UartBase: BigInt = BigInt("10000000", 16)
  val UartBytes: BigInt = BigInt("00001000", 16)
  val AccelBase: BigInt = BigInt("30000000", 16)
  val AccelBytes: BigInt = BigInt("00001000", 16)
  val ExternalBase: BigInt = BigInt("80000000", 16)

  object Uart {
    val TxDataOffset: BigInt = 0x00
    val StatusOffset: BigInt = 0x04
  }

  object Accelerator {
    val ControlOffset: BigInt = 0x00
    val StatusOffset: BigInt = 0x04
    val ModeOffset: BigInt = 0x08
    val ThresholdOffset: BigInt = 0x0c
    val BypassOffset: BigInt = 0x10
    val PerfControlOffset: BigInt = 0x14
    val CycleCountOffset: BigInt = 0x18
    val InputCountOffset: BigInt = 0x1c
    val OutputCountOffset: BigInt = 0x20
    val FrameCountOffset: BigInt = 0x24
    val StallCountOffset: BigInt = 0x28
    val BusyCyclesOffset: BigInt = 0x2c
  }

  private def contains(address: BigInt, base: BigInt, bytes: BigInt): Boolean =
    address >= base && address < base + bytes

  private def contains(address: UInt, base: BigInt, bytes: BigInt): Bool =
    address >= base.U(32.W) && address < (base + bytes).U(32.W)

  def regionOf(address: BigInt): MemoryRegion = {
    if (contains(address, BootRamBase, BootRamBytes)) MemoryRegion.BootRam
    else if (contains(address, UartBase, UartBytes)) MemoryRegion.Uart
    else if (contains(address, AccelBase, AccelBytes)) MemoryRegion.Accelerator
    else if (address >= ExternalBase && address <= BigInt("ffffffff", 16)) MemoryRegion.External
    else MemoryRegion.Unmapped
  }

  def isBootRam(address: UInt): Bool = contains(address, BootRamBase, BootRamBytes)
  def isUart(address: UInt): Bool = contains(address, UartBase, UartBytes)
  def isAccelerator(address: UInt): Bool = contains(address, AccelBase, AccelBytes)
  def isExternal(address: UInt): Bool = address >= ExternalBase.U(32.W)
}
