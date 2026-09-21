package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class AssetDmaRegsSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def initialize(dut: AssetDmaRegs): Unit = {
    dut.io.paddr.poke(0)
    dut.io.psel.poke(false)
    dut.io.penable.poke(false)
    dut.io.pwrite.poke(false)
    dut.io.pwdata.poke(0)
    dut.io.metaIn.valid.poke(false)
    dut.io.metaIn.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
    dut.io.metaOut.ready.poke(false)
    dut.io.packetCommitted.poke(false)
    dut.io.packetBytes.poke(0)
    dut.io.packetLast.poke(false)
    dut.io.packetFailed.poke(false)
    dut.io.packetError.poke(0)
    dut.io.abortDone.poke(false)
    dut.reset.poke(true)
    dut.clock.step(2)
    dut.reset.poke(false)
  }

  private def transfer(dut: AssetDmaRegs, offset: Int, write: Boolean,
                       data: BigInt = 0): (BigInt, Boolean) = {
    dut.io.paddr.poke(offset)
    dut.io.pwrite.poke(write)
    dut.io.pwdata.poke(data)
    dut.io.psel.poke(true)
    dut.io.penable.poke(false)
    dut.clock.step()
    dut.io.penable.poke(true)
    dut.io.pready.expect(true)
    val result = dut.io.prdata.peek().litValue -> dut.io.pslverror.peek().litToBoolean
    dut.clock.step()
    dut.io.psel.poke(false)
    dut.io.penable.poke(false)
    result
  }

  private def program(dut: AssetDmaRegs, session: BigInt = 0x12345678L,
                      destination: BigInt = GpuMemoryMap.DenseAssets,
                      assetId: BigInt = 7, offset: BigInt = 0,
                      sequence: BigInt = 0, maxLength: BigInt = 2048): Unit = {
    transfer(dut, AssetDmaRegisterMap.Session, write = true, session)._2 shouldBe false
    transfer(dut, AssetDmaRegisterMap.DstAddr, write = true, destination)._2 shouldBe false
    transfer(dut, AssetDmaRegisterMap.AssetId, write = true, assetId)._2 shouldBe false
    transfer(dut, AssetDmaRegisterMap.ExpectedOffset, write = true, offset)._2 shouldBe false
    transfer(dut, AssetDmaRegisterMap.ExpectedSequence, write = true, sequence)._2 shouldBe false
    transfer(dut, AssetDmaRegisterMap.MaxLength, write = true, maxLength)._2 shouldBe false
  }

  private def pokeMeta(dut: AssetDmaRegs, session: BigInt = 0x12345678L,
                       assetId: BigInt = 7, offset: BigInt = 0,
                       length: Int = 64, flags: Int = 0,
                       sequence: BigInt = 0, crc: BigInt = 0x89abcdefL): Unit = {
    dut.io.metaIn.bits.session.poke(session)
    dut.io.metaIn.bits.assetId.poke(assetId)
    dut.io.metaIn.bits.offset.poke(offset)
    dut.io.metaIn.bits.length.poke(length)
    dut.io.metaIn.bits.flags.poke(flags)
    dut.io.metaIn.bits.sequence.poke(sequence)
    dut.io.metaIn.bits.crc32.poke(crc)
  }

  describe("AssetDmaRegs") {
    it("atomically starts a valid descriptor without changing any V1 register offset") {
      simulate(new AssetDmaRegs) { dut =>
        initialize(dut)
        program(dut)
        transfer(dut, AssetDmaRegisterMap.Control, write = true, 1)._2 shouldBe false

        dut.io.active.expect(true)
        dut.io.start.expect(true)
        dut.clock.step()
        dut.io.start.expect(false)
        dut.io.descriptor.session.expect(0x12345678L)
        dut.io.descriptor.dstAddr.expect(GpuMemoryMap.DenseAssets)
        dut.io.descriptor.assetId.expect(7)
        dut.io.descriptor.expectedOffset.expect(0)
        dut.io.descriptor.expectedSequence.expect(0)
        dut.io.descriptor.maxLength.expect(2048)
        transfer(dut, AssetDmaRegisterMap.Status, write = false)._1 shouldBe 1
        GpuRegisterMap.All.max shouldBe 0x008c
        AssetDmaRegisterMap.All.min shouldBe 0x0100
      }
    }

    it("holds valid metadata under backpressure, commits once, and drops duplicates once") {
      simulate(new AssetDmaRegs) { dut =>
        initialize(dut)
        program(dut)
        transfer(dut, AssetDmaRegisterMap.Control, write = true, 1)

        pokeMeta(dut)
        dut.io.metaIn.valid.poke(true)
        dut.io.metaOut.ready.poke(false)
        dut.io.metaOut.valid.expect(true)
        dut.io.metaIn.ready.expect(false)
        dut.clock.step(3)
        dut.io.metaOut.bits.crc32.expect(0x89abcdefL)

        dut.io.metaOut.ready.poke(true)
        dut.io.metaIn.ready.expect(true)
        dut.clock.step()
        dut.io.metaIn.valid.poke(false)

        dut.io.packetBytes.poke(64)
        dut.io.packetCommitted.poke(true)
        dut.clock.step()
        dut.io.packetCommitted.poke(false)
        dut.io.committedOffset.expect(64)
        dut.io.committedSequence.expect(1)
        dut.io.committedBytes.expect(64)
        transfer(dut, AssetDmaRegisterMap.PacketCount, write = false)._1 shouldBe 1

        pokeMeta(dut, offset = 0, sequence = 0)
        dut.io.metaIn.valid.poke(true)
        dut.io.metaOut.valid.expect(false)
        dut.io.metaIn.ready.expect(true)
        dut.io.dropPacket.expect(true)
        dut.clock.step()
        dut.io.metaIn.valid.poke(false)
        transfer(dut, AssetDmaRegisterMap.DuplicateCount, write = false)._1 shouldBe 1
        transfer(dut, AssetDmaRegisterMap.PacketCount, write = false)._1 shouldBe 1

        pokeMeta(dut, offset = 64, sequence = 1)
        dut.io.metaIn.valid.poke(true)
        dut.io.metaOut.valid.expect(true)
        dut.io.metaOut.bits.offset.expect(64)
        dut.io.metaOut.bits.sequence.expect(1)
      }
    }

    it("rejects wrong metadata and address overflow without losing the active descriptor") {
      simulate(new AssetDmaRegs) { dut =>
        initialize(dut)
        program(dut, maxLength = 1024)
        transfer(dut, AssetDmaRegisterMap.Control, write = true, 1)

        pokeMeta(dut, session = 0x11111111L)
        dut.io.metaIn.valid.poke(true)
        dut.io.metaIn.ready.expect(true)
        dut.io.metaOut.valid.expect(false)
        dut.io.dropPacket.expect(true)
        dut.clock.step()
        dut.io.metaIn.valid.poke(false)
        dut.io.active.expect(true)
        transfer(dut, AssetDmaRegisterMap.ErrorCount, write = false)._1 shouldBe 1
        (transfer(dut, AssetDmaRegisterMap.Status, write = false)._1 & 0xff05) shouldBe 0x0205

        pokeMeta(dut, length = 3, flags = 0)
        dut.io.metaIn.valid.poke(true)
        dut.io.dropPacket.expect(true)
        dut.clock.step()
        dut.io.metaIn.valid.poke(false)
        transfer(dut, AssetDmaRegisterMap.ErrorCount, write = false)._1 shouldBe 2

        pokeMeta(dut, offset = 1024, length = 1, sequence = 0)
        dut.io.metaIn.valid.poke(true)
        dut.io.dropPacket.expect(true)
        dut.clock.step()
        dut.io.metaIn.valid.poke(false)
        transfer(dut, AssetDmaRegisterMap.ErrorCount, write = false)._1 shouldBe 3

        dut.io.abortDone.poke(false)
        transfer(dut, AssetDmaRegisterMap.Control, write = true, 2)._2 shouldBe false
        dut.io.active.expect(true)
        dut.io.abortDone.poke(true)
        dut.clock.step()
        dut.io.abortDone.poke(false)
        dut.io.active.expect(false)
        dut.io.aborted.expect(true)

        program(dut, destination = GpuMemoryMap.DdrEndExclusive - 1020, maxLength = 1024)
        transfer(dut, AssetDmaRegisterMap.Control, write = true, 1)._2 shouldBe true
        dut.io.active.expect(false)
      }
    }
  }
}
