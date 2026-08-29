package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class MemoryMapSpec extends AnyFunSpec with Matchers {
  describe("MemoryMap") {
    it("classifies every boundary without aliasing holes") {
      MemoryMap.regionOf(BigInt("00000000", 16)) shouldBe MemoryRegion.BootRam
      MemoryMap.regionOf(BigInt("0000ffff", 16)) shouldBe MemoryRegion.BootRam
      MemoryMap.regionOf(BigInt("00010000", 16)) shouldBe MemoryRegion.Unmapped
      MemoryMap.regionOf(BigInt("10000000", 16)) shouldBe MemoryRegion.Uart
      MemoryMap.regionOf(BigInt("10000fff", 16)) shouldBe MemoryRegion.Uart
      MemoryMap.regionOf(BigInt("10001000", 16)) shouldBe MemoryRegion.Unmapped
      MemoryMap.regionOf(BigInt("30000000", 16)) shouldBe MemoryRegion.Accelerator
      MemoryMap.regionOf(BigInt("30000fff", 16)) shouldBe MemoryRegion.Accelerator
      MemoryMap.regionOf(BigInt("40000000", 16)) shouldBe MemoryRegion.Unmapped
      MemoryMap.regionOf(BigInt("80000000", 16)) shouldBe MemoryRegion.External
      MemoryMap.regionOf(BigInt("ffffffff", 16)) shouldBe MemoryRegion.External
    }

    it("publishes the frozen peripheral register offsets") {
      MemoryMap.Uart.TxDataOffset shouldBe BigInt(0x00)
      MemoryMap.Uart.StatusOffset shouldBe BigInt(0x04)
      MemoryMap.Uart.RxDataOffset shouldBe BigInt(0x08)
      MemoryMap.Accelerator.ControlOffset shouldBe BigInt(0x00)
      MemoryMap.Accelerator.StatusOffset shouldBe BigInt(0x04)
      MemoryMap.Accelerator.ModeOffset shouldBe BigInt(0x08)
      MemoryMap.Accelerator.ThresholdOffset shouldBe BigInt(0x0c)
      MemoryMap.Accelerator.BypassOffset shouldBe BigInt(0x10)
      MemoryMap.Accelerator.PerfControlOffset shouldBe BigInt(0x14)
      MemoryMap.Accelerator.CycleCountOffset shouldBe BigInt(0x18)
      MemoryMap.Accelerator.InputCountOffset shouldBe BigInt(0x1c)
      MemoryMap.Accelerator.OutputCountOffset shouldBe BigInt(0x20)
      MemoryMap.Accelerator.FrameCountOffset shouldBe BigInt(0x24)
      MemoryMap.Accelerator.StallCountOffset shouldBe BigInt(0x28)
      MemoryMap.Accelerator.BusyCyclesOffset shouldBe BigInt(0x2c)
    }
  }
}
