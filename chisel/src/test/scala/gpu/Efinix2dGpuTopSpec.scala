package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Efinix2dGpuTopSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def apbWrite(dut: Efinix2dGpuTop, offset: Int, data: BigInt): Unit = {
    dut.io.apb.paddr.poke(offset)
    dut.io.apb.pwrite.poke(true.B)
    dut.io.apb.pwdata.poke(data)
    dut.io.apb.psel.poke(true.B)
    dut.io.apb.penable.poke(false.B)
    dut.clock.step()
    dut.io.apb.penable.poke(true.B)
    dut.io.apb.pready.expect(true.B)
    dut.io.apb.pslverror.expect(false.B)
    dut.clock.step()
    dut.io.apb.psel.poke(false.B)
    dut.io.apb.penable.poke(false.B)
  }

  private def apbRead(dut: Efinix2dGpuTop, offset: Int): BigInt = {
    dut.io.apb.paddr.poke(offset)
    dut.io.apb.pwrite.poke(false.B)
    dut.io.apb.pwdata.poke(0.U)
    dut.io.apb.psel.poke(true.B)
    dut.io.apb.penable.poke(false.B)
    dut.clock.step()
    dut.io.apb.penable.poke(true.B)
    dut.io.apb.pready.expect(true.B)
    dut.io.apb.pslverror.expect(false.B)
    val result = dut.io.apb.prdata.peek().litValue
    dut.clock.step()
    dut.io.apb.psel.poke(false.B)
    dut.io.apb.penable.poke(false.B)
    result
  }

  private def waitIdle(dut: Efinix2dGpuTop): Unit = {
    var idle = false
    var polls = 0
    while (!idle && polls < 1000) {
      val status = apbRead(dut, GpuRegisterMap.Status)
      idle = (status & 0xa0) == 0x20
      polls += 1
    }
    assert(idle, "GPU did not drain the submitted stress tier")
  }

  private def initialize(dut: Efinix2dGpuTop): Unit = {
    dut.io.apb.paddr.poke(0.U)
    dut.io.apb.psel.poke(false.B)
    dut.io.apb.penable.poke(false.B)
    dut.io.apb.pwrite.poke(false.B)
    dut.io.apb.pwdata.poke(0.U)
    dut.io.vblank.poke(false.B)
    dut.io.scanoutLevel.poke(2048.U)
    dut.io.underflow_pulse_gpu.poke(false.B)
    dut.io.displayReady.poke(true.B)
    dut.io.assetMeta.valid.poke(false.B)
    dut.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
    dut.io.assetPayload.valid.poke(false.B)
    dut.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte))
    dut.io.assetStreamError.poke(false.B)
    dut.io.axi.aw.ready.poke(true.B)
    dut.io.axi.w.ready.poke(true.B)
    dut.io.axi.b.valid.poke(true.B)
    dut.io.axi.b.bits.id.poke(0.U)
    dut.io.axi.b.bits.resp.poke(Axi4.Okay.U)
    dut.io.axi.ar.ready.poke(true.B)
    dut.io.axi.r.valid.poke(false.B)
    dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    dut.reset.poke(true.B)
    dut.clock.step(2)
    dut.reset.poke(false.B)
  }

  describe("Efinix2dGpuTop") {
    it("refills through the high watermark while Render, Scanout and Asset share DDR") {
      simulate(new Efinix2dGpuTop) { dut =>
        initialize(dut)
        val memory = collection.mutable.Map.empty[BigInt, Int]
        val source = (0 until 512).map(_ & 255)
        val payload = (0 until 1024).map(i => (i * 13 + 7) & 255)
        val assetBase = GpuMemoryMap.DenseAssets + 0x1000
        source.zipWithIndex.foreach { case (byte, i) => memory(GpuMemoryMap.DenseAssets + i) = byte }
        def byteAt(address: BigInt): Int = memory.getOrElse(address, if (address.testBit(0)) 0x12 else 0x34)
        var cycle = 0
        var level = 0
        var displayStarted = false
        var pixels = 0
        var readAddress = BigInt(0)
        var readBeats = 0
        var readId = BigInt(0)
        var writeAddress = BigInt(0)
        var writeBeats = 0
        var responsePending = false
        var heldRead = false
        var preferWrite = false
        var overlappingTraffic = false

        def tick(count: Int = 1): Unit = for (_ <- 0 until count) {
          dut.io.scanoutLevel.poke(level)
          dut.io.displayReady.poke(level < 2048)
          dut.io.axi.ar.ready.poke(readBeats == 0 && cycle % 5 != 0)
          dut.io.axi.aw.ready.poke(writeBeats == 0 && !responsePending && cycle % 7 != 0)
          val writeSlot = !heldRead && cycle % 2 == 0 && writeBeats > 0 &&
            dut.io.axi.w.valid.peek().litToBoolean &&
            (readBeats == 0 || preferWrite)
          val readSlot = heldRead || (cycle % 2 == 0 && readBeats > 0 && !writeSlot)
          dut.io.axi.r.valid.poke(readSlot)
          dut.io.axi.r.bits.id.poke(readId)
          dut.io.axi.r.bits.last.poke(readBeats == 1)
          dut.io.axi.r.bits.data.poke((0 until 4).map(i => BigInt(byteAt(readAddress + i)) << (i * 8)).reduce(_ | _))
          dut.io.axi.w.ready.poke(writeSlot)
          dut.io.axi.b.valid.poke(responsePending)
          val ar = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val aw = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val r = readSlot && dut.io.axi.r.ready.peek().litToBoolean
          val w = writeSlot && dut.io.axi.w.valid.peek().litToBoolean
          val b = responsePending && dut.io.axi.b.ready.peek().litToBoolean
          val pixel = dut.io.displayValid.peek().litToBoolean && level < 2048
          val nextReadAddress = dut.io.axi.ar.bits.addr.peek().litValue
          val nextReadBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
          val nextReadId = dut.io.axi.ar.bits.id.peek().litValue
          val nextWriteAddress = dut.io.axi.aw.bits.addr.peek().litValue
          val nextWriteBeats = dut.io.axi.aw.bits.len.peek().litValue.toInt + 1
          if (readBeats > 0 && writeBeats > 0 && readAddress >= GpuMemoryMap.FramebufferB &&
              readAddress < GpuMemoryMap.DenseAssets) overlappingTraffic = true
          if (w) {
            dut.io.axi.w.bits.last.expect(writeBeats == 1)
            val data = dut.io.axi.w.bits.data.peek().litValue
            val strb = dut.io.axi.w.bits.strb.peek().litValue
            for (i <- 0 until 4 if strb.testBit(i)) memory(writeAddress + i) = ((data >> (8 * i)) & 255).toInt
          }
          if (pixel) {
            dut.io.displayPixel.expect(0x1234)
            dut.io.displayLineLast.expect(pixels % 960 == 959)
            dut.io.displayFrameLast.expect(false)
          }
          dut.clock.step()
          if (displayStarted && cycle % 4 == 0) {
            withClue(s"display FIFO underflow at cycle $cycle, read=0x${readAddress.toString(16)}/$readBeats, write=0x${writeAddress.toString(16)}/$writeBeats, B=$responsePending, heldR=$heldRead, pixels=$pixels: ") {
              level should be > 0
            }
            level -= 1
          }
          if (pixel) { level += 1; pixels += 1 }
          if (level >= 1536) displayStarted = true
          level should be <= 2048
          heldRead = readSlot && !r
          if (r) { readAddress += 4; readBeats -= 1; preferWrite = true }
          if (w) { writeAddress += 4; writeBeats -= 1; preferWrite = false }
          if (b) responsePending = false
          if (w && writeBeats == 0) responsePending = true
          if (ar) { readAddress = nextReadAddress; readBeats = nextReadBeats; readId = nextReadId }
          if (aw) { writeAddress = nextWriteAddress; writeBeats = nextWriteBeats }
          cycle += 1
        }
        def transfer(offset: Int, write: Boolean, data: BigInt = 0): BigInt = {
          dut.io.apb.paddr.poke(offset)
          dut.io.apb.pwrite.poke(write)
          dut.io.apb.pwdata.poke(data)
          dut.io.apb.psel.poke(true)
          dut.io.apb.penable.poke(false)
          tick()
          dut.io.apb.penable.poke(true)
          dut.io.apb.pslverror.expect(false)
          val result = dut.io.apb.prdata.peek().litValue
          tick()
          dut.io.apb.psel.poke(false)
          dut.io.apb.penable.poke(false)
          result
        }
        transfer(GpuRegisterMap.Op, true, GpuOpcode.Present)
        transfer(GpuRegisterMap.Size, true, 0x00010001L)
        transfer(GpuRegisterMap.DstStride, true, 2)
        transfer(GpuRegisterMap.DstAddr, true, GpuMemoryMap.FramebufferB)
        transfer(GpuRegisterMap.Control, true, 1)
        tick(10)
        dut.io.vblank.poke(true)
        tick()
        dut.io.vblank.poke(false)
        transfer(AssetDmaRegisterMap.Session, true, 9)
        transfer(AssetDmaRegisterMap.DstAddr, true, assetBase)
        transfer(AssetDmaRegisterMap.AssetId, true, 7)
        transfer(AssetDmaRegisterMap.MaxLength, true, 1024)
        transfer(AssetDmaRegisterMap.Control, true, 1)
        dut.io.assetMeta.bits.session.poke(9)
        dut.io.assetMeta.bits.assetId.poke(7)
        dut.io.assetMeta.bits.length.poke(1024)
        dut.io.assetMeta.bits.flags.poke(1)
        dut.io.assetMeta.valid.poke(true)
        dut.io.assetMeta.ready.expect(true)
        tick()
        dut.io.assetMeta.valid.poke(false)
        for ((byte, index) <- payload.zipWithIndex) {
          dut.io.assetPayload.valid.poke(true)
          dut.io.assetPayload.bits.data.poke(byte)
          dut.io.assetPayload.bits.last.poke(index == payload.size - 1)
          dut.io.assetPayload.ready.expect(true)
          tick()
        }
        dut.io.assetPayload.valid.poke(false)
        transfer(GpuRegisterMap.Op, true, GpuOpcode.Copy)
        transfer(GpuRegisterMap.SrcAddr, true, GpuMemoryMap.DenseAssets)
        transfer(GpuRegisterMap.DstAddr, true, GpuMemoryMap.FramebufferA)
        transfer(GpuRegisterMap.Size, true, (4L << 16) | 64L)
        transfer(GpuRegisterMap.SrcStride, true, 128)
        transfer(GpuRegisterMap.DstStride, true, 128)
        transfer(GpuRegisterMap.Tag, true, 99)
        transfer(GpuRegisterMap.Control, true, 1)
        var complete = false
        for (_ <- 0 until 200 if !complete) {
          tick(50)
          val renderDone = transfer(GpuRegisterMap.LastDone, false) == 99
          val assetDone = transfer(AssetDmaRegisterMap.CommittedBytes, false) == 1024
          complete = renderDone && assetDone
        }
        withClue(s"completion stalled with FIFO=$level, scanout pixels=$pixels: ") {
          complete shouldBe true
        }
        displayStarted shouldBe true
        overlappingTraffic shouldBe true
        pixels should be >= 1536
        transfer(GpuRegisterMap.Error, false) shouldBe 0
        transfer(AssetDmaRegisterMap.ErrorCount, false) shouldBe 0
        source.indices.map(i => memory(GpuMemoryMap.FramebufferA + i)) shouldBe source
        payload.indices.map(i => memory(assetBase + i)) shouldBe payload
        transfer(GpuRegisterMap.PerfControl, true, 1)
        transfer(GpuRegisterMap.PerfPixelsLo, false) shouldBe 256
      }
    }

    it("keeps emergency QoS enabled during a later pending frame swap") {
      simulate(new Efinix2dGpuTop) { dut =>
        initialize(dut)
        apbWrite(dut, GpuRegisterMap.Op, GpuOpcode.Present)
        apbWrite(dut, GpuRegisterMap.Size, 0x00010001L)
        apbWrite(dut, GpuRegisterMap.DstStride, 2)
        apbWrite(dut, GpuRegisterMap.DstAddr, GpuMemoryMap.FramebufferB)
        apbWrite(dut, GpuRegisterMap.Control, 1)
        dut.clock.step(10)
        dut.io.vblank.poke(true.B)
        dut.clock.step()
        dut.io.vblank.poke(false.B)
        dut.clock.step(4) // Scanout has been enabled for the first frame.

        apbWrite(dut, GpuRegisterMap.DstAddr, GpuMemoryMap.FramebufferA)
        apbWrite(dut, GpuRegisterMap.Control, 1)
        dut.clock.step(10) // Second PRESENT is now pending without vblank.
        dut.io.scanoutLevel.poke(0)

        apbWrite(dut, AssetDmaRegisterMap.Session, 1)
        apbWrite(dut, AssetDmaRegisterMap.DstAddr, GpuMemoryMap.DenseAssets)
        apbWrite(dut, AssetDmaRegisterMap.AssetId, 2)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedOffset, 0)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedSequence, 0)
        apbWrite(dut, AssetDmaRegisterMap.MaxLength, 4)
        apbWrite(dut, AssetDmaRegisterMap.Control, 1)
        dut.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
        dut.io.assetMeta.bits.session.poke(1)
        dut.io.assetMeta.bits.assetId.poke(2)
        dut.io.assetMeta.bits.length.poke(4)
        dut.io.assetMeta.bits.flags.poke(1)
        dut.io.assetMeta.valid.poke(true.B)
        dut.io.assetMeta.ready.expect(true.B)
        dut.clock.step()
        dut.io.assetMeta.valid.poke(false.B)
        for (index <- 0 until 4) {
          dut.io.assetPayload.bits.data.poke(index + 1)
          dut.io.assetPayload.bits.last.poke(index == 3)
          dut.io.assetPayload.valid.poke(true.B)
          dut.io.assetPayload.ready.expect(true.B)
          dut.clock.step()
        }
        dut.io.assetPayload.valid.poke(false.B)
        for (_ <- 0 until 20) {
          dut.io.axi.aw.valid.expect(false.B)
          dut.clock.step()
        }
      }
    }

    it("keeps scanout off until software requests the first frame swap") {
      simulate(new Efinix2dGpuTop) { dut =>
        dut.io.apb.paddr.poke(0.U)
        dut.io.apb.psel.poke(false.B)
        dut.io.apb.penable.poke(false.B)
        dut.io.apb.pwrite.poke(false.B)
        dut.io.apb.pwdata.poke(0.U)
        dut.io.vblank.poke(false.B)
        dut.io.scanoutLevel.poke(0.U)
        dut.io.underflow_pulse_gpu.poke(false.B)
        dut.io.displayReady.poke(true.B)
        dut.io.assetMeta.valid.poke(false.B)
        dut.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
        dut.io.assetPayload.valid.poke(false.B)
        dut.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte))
        dut.io.assetStreamError.poke(false.B)
        dut.io.axi.aw.ready.poke(true.B)
        dut.io.axi.w.ready.poke(true.B)
        dut.io.axi.b.valid.poke(false.B)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.axi.ar.ready.poke(true.B)
        dut.io.axi.r.valid.poke(false.B)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))

        dut.reset.poke(true.B)
        dut.clock.step(2)
        dut.reset.poke(false.B)
        for (_ <- 0 until 12) {
          dut.io.axi.ar.valid.expect(false.B)
          dut.clock.step()
        }
      }
    }

    it("drains the frozen 16/32/64/96/128 Sprite-equivalent tiers without losing commands or counters") {
      simulate(new Efinix2dGpuTop) { dut =>
        initialize(dut)
        apbWrite(dut, GpuRegisterMap.Op, GpuOpcode.Fill)
        apbWrite(dut, GpuRegisterMap.DstAddr, GpuMemoryMap.FramebufferB)
        apbWrite(dut, GpuRegisterMap.Size, 0x00010001L)
        apbWrite(dut, GpuRegisterMap.DstStride, 2)
        apbWrite(dut, GpuRegisterMap.ColorKey, 0x07e0)

        val tiers = Seq(16, 32, 64, 96, 128)
        for ((spriteCount, tierIndex) <- tiers.zipWithIndex) {
          apbWrite(dut, GpuRegisterMap.PerfControl, 2)
          val firstTag = 0x1000 + tierIndex * 0x100

          for (chunkStart <- 0 until spriteCount by 16) {
            val chunkCount = math.min(16, spriteCount - chunkStart)
            dut.io.axi.aw.ready.poke(false.B)
            dut.io.axi.w.ready.poke(false.B)
            for (index <- 0 until chunkCount) {
              val tag = firstTag + chunkStart + index
              apbWrite(dut, GpuRegisterMap.Tag, tag)
              apbWrite(dut, GpuRegisterMap.Control, 1)
            }

            dut.io.axi.aw.ready.poke(true.B)
            dut.io.axi.w.ready.poke(true.B)
            waitIdle(dut)
            apbRead(dut, GpuRegisterMap.LastDone) shouldBe
              BigInt(firstTag + chunkStart + chunkCount - 1)
            apbRead(dut, GpuRegisterMap.Error) shouldBe BigInt(GpuError.None)
          }

          apbWrite(dut, GpuRegisterMap.PerfControl, 1)
          val pixelCount = apbRead(dut, GpuRegisterMap.PerfPixelsLo) |
            (apbRead(dut, GpuRegisterMap.PerfPixelsHi) << 32)
          pixelCount shouldBe BigInt(spriteCount)
          apbRead(dut, GpuRegisterMap.LastDone) shouldBe BigInt(firstTag + spriteCount - 1)
        }
      }
    }

    it("routes Asset APB and commits a three-byte network packet through the third DDR client") {
      simulate(new Efinix2dGpuTop) { dut =>
        initialize(dut)
        apbWrite(dut, AssetDmaRegisterMap.Session, 0x1234)
        apbWrite(dut, AssetDmaRegisterMap.DstAddr, GpuMemoryMap.DenseAssets)
        apbWrite(dut, AssetDmaRegisterMap.AssetId, 7)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedOffset, 0)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedSequence, 0)
        apbWrite(dut, AssetDmaRegisterMap.MaxLength, 4096)
        apbWrite(dut, AssetDmaRegisterMap.Control, 1)
        dut.io.assetSession.expect(0x1234)
        dut.io.assetMeta.bits.session.poke(0x1234)
        dut.io.assetMeta.bits.assetId.poke(7)
        dut.io.assetMeta.bits.offset.poke(0)
        dut.io.assetMeta.bits.length.poke(3)
        dut.io.assetMeta.bits.flags.poke(1)
        dut.io.assetMeta.bits.sequence.poke(0)
        dut.io.assetMeta.bits.crc32.poke(0)
        dut.io.assetMeta.valid.poke(true.B)
        dut.io.assetMeta.ready.expect(true.B)
        dut.clock.step()
        dut.io.assetMeta.valid.poke(false.B)

        for ((byte, index) <- Seq(0x11, 0x22, 0x33).zipWithIndex) {
          dut.io.assetPayload.bits.data.poke(byte)
          dut.io.assetPayload.bits.last.poke(index == 2)
          dut.io.assetPayload.valid.poke(true.B)
          dut.io.assetPayload.ready.expect(true.B)
          dut.clock.step()
        }
        dut.io.assetPayload.valid.poke(false.B)

        var sawAddress = false
        var sawData = false
        for (_ <- 0 until 40) {
          if (dut.io.axi.aw.valid.peek().litToBoolean) {
            dut.io.axi.aw.bits.addr.expect(GpuMemoryMap.DenseAssets)
            sawAddress = true
          }
          if (dut.io.axi.w.valid.peek().litToBoolean) {
            dut.io.axi.w.bits.data.expect(0x00332211)
            dut.io.axi.w.bits.strb.expect(7)
            dut.io.axi.w.bits.last.expect(true.B)
            sawData = true
          }
          dut.clock.step()
        }
        sawAddress shouldBe true
        sawData shouldBe true
        apbRead(dut, AssetDmaRegisterMap.CommittedBytes) shouldBe 3
        apbRead(dut, AssetDmaRegisterMap.PacketCount) shouldBe 1
        apbRead(dut, AssetDmaRegisterMap.Status) & 2 shouldBe 2
      }
    }

    it("reports a guard truncation without issuing an Asset DDR address") {
      simulate(new Efinix2dGpuTop) { dut =>
        initialize(dut)
        apbWrite(dut, AssetDmaRegisterMap.Session, 1)
        apbWrite(dut, AssetDmaRegisterMap.DstAddr, GpuMemoryMap.DenseAssets)
        apbWrite(dut, AssetDmaRegisterMap.AssetId, 2)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedOffset, 0)
        apbWrite(dut, AssetDmaRegisterMap.ExpectedSequence, 0)
        apbWrite(dut, AssetDmaRegisterMap.MaxLength, 1024)
        apbWrite(dut, AssetDmaRegisterMap.Control, 1)
        dut.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
        dut.io.assetMeta.bits.session.poke(1)
        dut.io.assetMeta.bits.assetId.poke(2)
        dut.io.assetMeta.bits.length.poke(8)
        dut.io.assetMeta.bits.flags.poke(1)
        dut.io.assetMeta.valid.poke(true.B)
        dut.io.assetMeta.ready.expect(true.B)
        dut.clock.step()
        dut.io.assetMeta.valid.poke(false.B)
        dut.io.assetPayload.bits.data.poke(0x55)
        dut.io.assetPayload.bits.last.poke(false.B)
        dut.io.assetPayload.valid.poke(true.B)
        dut.clock.step()
        dut.io.assetPayload.valid.poke(false.B)
        dut.io.assetStreamError.poke(true.B)
        dut.io.axi.aw.valid.expect(false.B)
        dut.clock.step()
        dut.io.assetStreamError.poke(false.B)
        dut.io.assetAbort.expect(true.B)
        dut.clock.step()
        dut.io.axi.aw.valid.expect(false.B)
        apbRead(dut, AssetDmaRegisterMap.ErrorCount) shouldBe 1
        apbRead(dut, AssetDmaRegisterMap.CommittedBytes) shouldBe 0
      }
    }
  }
}
