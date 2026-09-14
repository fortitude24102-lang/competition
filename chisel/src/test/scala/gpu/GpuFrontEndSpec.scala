package gpu

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class GpuFrontEndSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def pokeCommand(dut: CommandValidator, op: Int, src: BigInt, dst: BigInt,
                          width: Int, height: Int, srcStride: Int, dstStride: Int): Unit = {
    dut.io.command.op.poke(op)
    dut.io.command.srcAddr.poke(src)
    dut.io.command.dstAddr.poke(dst)
    dut.io.command.widthPixels.poke(width)
    dut.io.command.heightPixels.poke(height)
    dut.io.command.srcStride.poke(srcStride)
    dut.io.command.dstStride.poke(dstStride)
    dut.io.command.color.poke(0x1234)
    dut.io.command.colorKey.poke(0)
    dut.io.command.alpha.poke(255)
    dut.io.command.flags.poke(0)
    dut.io.command.tag.poke(7)
  }

  describe("official Sapphire GPU contract") {
    it("uses the APB and DDR addresses frozen by the official demo plan") {
      GpuMemoryMap.ApbBase shouldBe BigInt("f8100000", 16)
      GpuMemoryMap.FramebufferA shouldBe BigInt("02000000", 16)
      GpuMemoryMap.FramebufferB shouldBe BigInt("02200000", 16)
      GpuMemoryMap.DenseAssets shouldBe BigInt("02400000", 16)
      GpuMemoryMap.SparseAssets shouldBe BigInt("06000000", 16)
      GpuMemoryMap.DdrEndExclusive shouldBe BigInt("10000000", 16)
      (new GpuCommand).getWidth shouldBe 236
    }
  }

  describe("CommandQueue") {
    it("stores exactly sixteen commands and preserves order across simultaneous dequeue and enqueue") {
      simulate(new CommandQueue(16)) { dut =>
        dut.io.enq.valid.poke(false)
        dut.io.deq.ready.poke(false)
        dut.clock.step()

        for (tag <- 0 until 16) {
          dut.io.enq.valid.poke(true)
          dut.io.enq.bits.tag.poke(tag)
          dut.io.enq.ready.expect(true)
          dut.clock.step()
        }
        dut.io.enq.valid.poke(false)
        dut.io.level.expect(16)
        dut.io.full.expect(true)
        dut.io.empty.expect(false)
        dut.io.enq.ready.expect(false)

        dut.io.deq.ready.poke(true)
        dut.io.enq.valid.poke(true)
        dut.io.enq.bits.tag.poke(16)
        dut.io.deq.valid.expect(true)
        dut.io.deq.bits.tag.expect(0)
        dut.clock.step()
        dut.io.enq.valid.poke(false)

        for (tag <- 1 to 16) {
          dut.io.deq.valid.expect(true)
          dut.io.deq.bits.tag.expect(tag)
          dut.clock.step()
        }
        dut.io.deq.valid.expect(false)
        dut.io.empty.expect(true)
        dut.io.highWater.expect(16)
      }
    }
  }

  describe("CommandValidator") {
    it("rejects malformed commands before they can reach DDR") {
      simulate(new CommandValidator) { dut =>
        pokeCommand(dut, GpuOpcode.Fill, 0, GpuMemoryMap.FramebufferA, 8, 4, 0, 16)
        dut.io.valid.expect(true)
        dut.io.error.expect(GpuError.None)

        pokeCommand(dut, 15, 0, GpuMemoryMap.FramebufferA, 8, 4, 0, 16)
        dut.io.valid.expect(false)
        dut.io.error.expect(GpuError.InvalidOpcode)

        pokeCommand(dut, GpuOpcode.Fill, 0, GpuMemoryMap.FramebufferA, 0, 4, 0, 16)
        dut.io.error.expect(GpuError.ZeroSize)

        pokeCommand(dut, GpuOpcode.Copy, GpuMemoryMap.DenseAssets + 1, GpuMemoryMap.FramebufferA, 8, 4, 16, 16)
        dut.io.error.expect(GpuError.MisalignedAddress)

        pokeCommand(dut, GpuOpcode.Copy, GpuMemoryMap.DenseAssets, GpuMemoryMap.FramebufferA, 1, 2, 3, 2)
        dut.io.error.expect(GpuError.MisalignedAddress)

        pokeCommand(dut, GpuOpcode.Copy, GpuMemoryMap.DenseAssets, GpuMemoryMap.FramebufferA, 8, 4, 14, 16)
        dut.io.error.expect(GpuError.StrideTooSmall)

        pokeCommand(dut, GpuOpcode.Fill, 0, GpuMemoryMap.DdrEndExclusive - 4, 8, 1, 0, 16)
        dut.io.error.expect(GpuError.AddressRange)

        pokeCommand(dut, GpuOpcode.Copy, GpuMemoryMap.FramebufferA, GpuMemoryMap.FramebufferA + 4, 8, 2, 16, 16)
        dut.io.error.expect(GpuError.OverlappingCopy)

        pokeCommand(dut, GpuOpcode.Alpha, GpuMemoryMap.FramebufferA, GpuMemoryMap.FramebufferA + 2, 8, 1, 16, 16)
        dut.io.error.expect(GpuError.OverlappingCopy)

        pokeCommand(dut, GpuOpcode.Alpha, GpuMemoryMap.FramebufferA, GpuMemoryMap.FramebufferA, 8, 2, 16, 16)
        dut.io.valid.expect(true)

        pokeCommand(dut, GpuOpcode.Sparse, GpuMemoryMap.SparseAssets, GpuMemoryMap.FramebufferA, 8, 2, 0, 16)
        dut.io.valid.expect(true)

        pokeCommand(dut, GpuOpcode.Sparse, GpuMemoryMap.SparseAssets + 2, GpuMemoryMap.FramebufferA, 8, 2, 0, 16)
        dut.io.error.expect(GpuError.MisalignedAddress)

        pokeCommand(dut, GpuOpcode.Present, 0, GpuMemoryMap.FramebufferA + 4096, 1, 1, 0, 2)
        dut.io.error.expect(GpuError.AddressRange)

        pokeCommand(dut, GpuOpcode.Present, 0, GpuMemoryMap.FramebufferB, 1, 1, 0, 2)
        dut.io.valid.expect(true)
      }
    }
  }

  describe("GpuApbRegs") {
    it("returns read data only in the APB access phase after a setup phase") {
      simulate(new GpuApbRegs) { dut =>
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.pwrite.poke(false)
        dut.io.paddr.poke(0)
        dut.io.pwdata.poke(0)
        dut.io.command.ready.poke(true)
        dut.io.queueLevel.poke(0)
        dut.io.queueHighWater.poke(0)
        dut.io.queueFull.poke(false)
        dut.io.queueEmpty.poke(true)
        dut.io.engineBusy.poke(false)
        dut.io.irqPending.poke(false)
        dut.io.lastDoneTag.poke(0)
        dut.io.lastError.poke(0)
        dut.io.frontBuffer.poke(GpuMemoryMap.FramebufferA)
        dut.io.backBuffer.poke(GpuMemoryMap.FramebufferB)
        dut.io.perfCycles.poke(0)
        dut.io.perfPixels.poke(0)
        dut.io.perfReadBytes.poke(0)
        dut.io.perfWriteBytes.poke(0)
        dut.io.perfStalls.poke(0)
        dut.io.perfUnderflows.poke(0)
        dut.io.perfRenderGrants.poke(0)
        dut.io.perfScanoutGrants.poke(0)
        dut.clock.step()

        dut.io.paddr.poke(GpuRegisterMap.Id)
        dut.io.psel.poke(true)
        dut.io.penable.poke(false)
        dut.io.pready.expect(false)
        dut.clock.step()

        dut.io.penable.poke(true)
        dut.io.pready.expect(true)
        dut.io.prdata.expect(BigInt("32444750", 16))
        dut.io.pslverror.expect(false)
      }
    }

    it("programs valid QoS hysteresis thresholds and rejects invalid writes without changing them") {
      simulate(new GpuApbRegs) { dut =>
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.pwrite.poke(false)
        dut.io.paddr.poke(0)
        dut.io.pwdata.poke(0)
        dut.io.command.ready.poke(true)
        dut.io.queueLevel.poke(0)
        dut.io.queueHighWater.poke(0)
        dut.io.queueFull.poke(false)
        dut.io.queueEmpty.poke(true)
        dut.io.engineBusy.poke(false)
        dut.io.irqPending.poke(false)
        dut.io.lastDoneTag.poke(0)
        dut.io.lastError.poke(0)
        dut.io.frontBuffer.poke(GpuMemoryMap.FramebufferA)
        dut.io.backBuffer.poke(GpuMemoryMap.FramebufferB)
        dut.io.perfCycles.poke(0)
        dut.io.perfPixels.poke(0)
        dut.io.perfReadBytes.poke(0)
        dut.io.perfWriteBytes.poke(0)
        dut.io.perfStalls.poke(0)
        dut.io.perfUnderflows.poke(0)
        dut.io.perfRenderGrants.poke(0)
        dut.io.perfScanoutGrants.poke(0)

        def transfer(write: Boolean, data: BigInt = 0): (BigInt, Boolean) = {
          dut.io.paddr.poke(GpuRegisterMap.QosWatermarks)
          dut.io.pwrite.poke(write)
          dut.io.pwdata.poke(data)
          dut.io.psel.poke(true)
          dut.io.penable.poke(false)
          dut.clock.step()
          dut.io.penable.poke(true)
          val result = dut.io.prdata.peek().litValue -> dut.io.pslverror.peek().litToBoolean
          dut.clock.step()
          dut.io.psel.poke(false)
          dut.io.penable.poke(false)
          result
        }

        transfer(write = false)._1 shouldBe BigInt("86000100", 16)
        transfer(write = true, BigInt("05000064", 16))._2 shouldBe false
        dut.io.qosLowWatermark.expect(100)
        dut.io.qosHighWatermark.expect(0x500)
        dut.io.qosAdaptiveEnable.expect(false)
        transfer(write = true, BigInt("00320064", 16))._2 shouldBe true
        transfer(write = false)._1 shouldBe BigInt("05000064", 16)
      }
    }

    it("reads identity, writes staging fields, submits atomically, and errors on invalid offsets or a full queue") {
      simulate(new GpuApbRegs) { dut =>
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.pwrite.poke(false)
        dut.io.paddr.poke(0)
        dut.io.pwdata.poke(0)
        dut.io.command.ready.poke(true)
        dut.io.queueLevel.poke(0)
        dut.io.queueHighWater.poke(0)
        dut.io.queueFull.poke(false)
        dut.io.queueEmpty.poke(true)
        dut.io.engineBusy.poke(false)
        dut.io.irqPending.poke(false)
        dut.io.lastDoneTag.poke(0)
        dut.io.lastError.poke(0)
        dut.io.frontBuffer.poke(GpuMemoryMap.FramebufferA)
        dut.io.backBuffer.poke(GpuMemoryMap.FramebufferB)
        dut.io.perfCycles.poke(0)
        dut.io.perfPixels.poke(0)
        dut.io.perfReadBytes.poke(0)
        dut.io.perfWriteBytes.poke(0)
        dut.io.perfStalls.poke(0)
        dut.io.perfUnderflows.poke(0)
        dut.io.perfRenderGrants.poke(0)
        dut.io.perfScanoutGrants.poke(0)
        dut.clock.step()

        def transfer(offset: Int, write: Boolean, data: BigInt = 0): (BigInt, Boolean) = {
          dut.io.paddr.poke(offset)
          dut.io.pwrite.poke(write)
          dut.io.pwdata.poke(data)
          dut.io.psel.poke(true)
          dut.io.penable.poke(false)
          dut.clock.step()
          dut.io.penable.poke(true)
          dut.io.pready.expect(true)
          val result = (dut.io.prdata.peek().litValue, dut.io.pslverror.peek().litToBoolean)
          dut.clock.step()
          dut.io.psel.poke(false)
          dut.io.penable.poke(false)
          result
        }

        transfer(GpuRegisterMap.Id, write = false)._1 shouldBe BigInt("32444750", 16)
        transfer(GpuRegisterMap.Op, write = true, GpuOpcode.Fill)
        transfer(GpuRegisterMap.DstAddr, write = true, GpuMemoryMap.FramebufferA)
        transfer(GpuRegisterMap.Size, write = true, (4L << 16) | 8L)
        transfer(GpuRegisterMap.DstStride, write = true, 16)
        transfer(GpuRegisterMap.ColorKey, write = true, 0xabcd)
        transfer(GpuRegisterMap.Tag, write = true, 0x55aa)

        dut.io.paddr.poke(GpuRegisterMap.Control)
        dut.io.pwrite.poke(true)
        dut.io.pwdata.poke(1)
        dut.io.psel.poke(true)
        dut.io.penable.poke(false)
        dut.clock.step()
        dut.io.penable.poke(true)
        dut.io.command.valid.expect(true)
        dut.io.command.bits.op.expect(GpuOpcode.Fill)
        dut.io.command.bits.dstAddr.expect(GpuMemoryMap.FramebufferA)
        dut.io.command.bits.widthPixels.expect(8)
        dut.io.command.bits.heightPixels.expect(4)
        dut.io.command.bits.color.expect(0xabcd)
        dut.io.command.bits.tag.expect(0x55aa)
        dut.io.pslverror.expect(false)
        dut.clock.step()
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)

        transfer(0xfffc, write = false)._2 shouldBe true
        dut.io.command.ready.poke(false)
        transfer(GpuRegisterMap.Control, write = true, 1)._2 shouldBe true
      }
    }

    it("holds a coherent performance snapshot and emits one-cycle clear requests") {
      simulate(new GpuApbRegs) { dut =>
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.pwrite.poke(false)
        dut.io.paddr.poke(0)
        dut.io.pwdata.poke(0)
        dut.io.command.ready.poke(true)
        dut.io.queueLevel.poke(3)
        dut.io.queueHighWater.poke(16)
        dut.io.queueFull.poke(false)
        dut.io.queueEmpty.poke(false)
        dut.io.engineBusy.poke(true)
        dut.io.irqPending.poke(true)
        dut.io.lastDoneTag.poke(0x1234)
        dut.io.lastError.poke(0)
        dut.io.frontBuffer.poke(GpuMemoryMap.FramebufferA)
        dut.io.backBuffer.poke(GpuMemoryMap.FramebufferB)
        dut.io.perfCycles.poke(BigInt("1122334455667788", 16))
        dut.io.perfPixels.poke(BigInt("0123456789abcdef", 16))
        dut.io.perfReadBytes.poke(BigInt("0102030405060708", 16))
        dut.io.perfWriteBytes.poke(BigInt("1020304050607080", 16))
        dut.io.perfStalls.poke(BigInt("8877665544332211", 16))
        dut.io.perfUnderflows.poke(BigInt("1111222233334444", 16))
        dut.io.perfRenderGrants.poke(BigInt("5555666677778888", 16))
        dut.io.perfScanoutGrants.poke(BigInt("9999aaaabbbbcccc", 16))
        dut.clock.step()

        def transfer(offset: Int, write: Boolean, data: BigInt = 0): BigInt = {
          dut.io.paddr.poke(offset)
          dut.io.pwrite.poke(write)
          dut.io.pwdata.poke(data)
          dut.io.psel.poke(true)
          dut.io.penable.poke(false)
          dut.clock.step()
          dut.io.penable.poke(true)
          val result = dut.io.prdata.peek().litValue
          dut.clock.step()
          dut.io.psel.poke(false)
          dut.io.penable.poke(false)
          result
        }

        transfer(GpuRegisterMap.PerfControl, write = true, 1)
        dut.io.perfCycles.poke(0)
        dut.io.perfPixels.poke(0)
        dut.io.perfReadBytes.poke(0)
        dut.io.perfWriteBytes.poke(0)
        dut.io.perfStalls.poke(0)
        dut.io.perfUnderflows.poke(0)
        dut.io.perfRenderGrants.poke(0)
        dut.io.perfScanoutGrants.poke(0)

        transfer(GpuRegisterMap.PerfCyclesLo, write = false) shouldBe BigInt("55667788", 16)
        transfer(GpuRegisterMap.PerfCyclesHi, write = false) shouldBe BigInt("11223344", 16)
        transfer(GpuRegisterMap.PerfPixelsLo, write = false) shouldBe BigInt("89abcdef", 16)
        transfer(GpuRegisterMap.PerfReadBytesHi, write = false) shouldBe BigInt("01020304", 16)
        transfer(GpuRegisterMap.PerfWriteBytesLo, write = false) shouldBe BigInt("50607080", 16)
        transfer(GpuRegisterMap.PerfStallsHi, write = false) shouldBe BigInt("88776655", 16)
        transfer(GpuRegisterMap.PerfUnderflowsLo, write = false) shouldBe BigInt("33334444", 16)
        transfer(GpuRegisterMap.PerfRenderGrantsHi, write = false) shouldBe BigInt("55556666", 16)
        transfer(GpuRegisterMap.PerfScanoutGrantsLo, write = false) shouldBe BigInt("bbbbcccc", 16)

        val status = transfer(GpuRegisterMap.Status, write = false)
        ((status >> 8) & 0x1f) shouldBe 16
        ((status >> 13) & 1) shouldBe 1

        dut.io.paddr.poke(GpuRegisterMap.Control)
        dut.io.pwrite.poke(true)
        dut.io.pwdata.poke(2)
        dut.io.psel.poke(true)
        dut.io.penable.poke(false)
        dut.clock.step()
        dut.io.penable.poke(true)
        dut.io.irqClear.expect(true)
        dut.io.command.valid.expect(false)
        dut.clock.step()
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.irqClear.expect(false)

        dut.io.paddr.poke(GpuRegisterMap.PerfControl)
        dut.io.pwrite.poke(true)
        dut.io.pwdata.poke(2)
        dut.io.psel.poke(true)
        dut.io.penable.poke(false)
        dut.clock.step()
        dut.io.penable.poke(true)
        dut.io.perfClear.expect(true)
        dut.clock.step()
        dut.io.psel.poke(false)
        dut.io.penable.poke(false)
        dut.io.perfClear.expect(false)
      }
    }
  }
}
