package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class RenderEngineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("official Sapphire external AXI boundary") {
    it("matches the 32-bit data, 32-bit address, 4-bit ID and 8-bit burst contract") {
      val address = new Axi4Address
      val writeData = new Axi4WriteData
      val writeResponse = new Axi4WriteResponse
      val readData = new Axi4ReadData

      address.addr.getWidth shouldBe 32
      address.id.getWidth shouldBe 4
      address.len.getWidth shouldBe 8
      writeData.data.getWidth shouldBe 32
      writeData.strb.getWidth shouldBe 4
      writeResponse.id.getWidth shouldBe 4
      readData.data.getWidth shouldBe 32
      readData.id.getWidth shouldBe 4
    }

    it("keeps every AXI request inactive after reset until a GPU command exists") {
      simulate(new Efinix2dGpuTop) { dut =>
        dut.io.apb.psel.poke(false)
        dut.io.apb.penable.poke(false)
        dut.io.apb.pwrite.poke(false)
        dut.io.apb.paddr.poke(0)
        dut.io.apb.pwdata.poke(0)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.vblank.poke(false)
        dut.io.displayReady.poke(false)
        dut.io.scanoutLevel.poke(0)
        dut.clock.step()

        dut.io.axi.aw.valid.expect(false)
        dut.io.axi.w.valid.expect(false)
        dut.io.axi.ar.valid.expect(false)
        dut.io.axi.b.ready.expect(false)
        dut.io.axi.r.ready.expect(false)
        dut.io.irq.expect(false)
        dut.io.displayValid.expect(false)
        dut.io.displayLineLast.expect(false)
        dut.io.displayFrameLast.expect(false)
      }
    }

    it("executes an APB-submitted Fill through the real pixel pipe and reports completion") {
      simulate(new Efinix2dGpuTop) { dut =>
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        var writeAddress = 0L
        var responsePending = false
        var sawIrq = false

        dut.io.apb.psel.poke(false)
        dut.io.apb.penable.poke(false)
        dut.io.apb.pwrite.poke(false)
        dut.io.apb.paddr.poke(0)
        dut.io.apb.pwdata.poke(0)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.vblank.poke(false)
        dut.io.scanoutLevel.poke(0)
        dut.io.displayReady.poke(false)
        dut.clock.step()

        def apbWrite(offset: Int, data: BigInt): Unit = {
          dut.io.apb.paddr.poke(offset)
          dut.io.apb.pwrite.poke(true)
          dut.io.apb.pwdata.poke(data)
          dut.io.apb.psel.poke(true)
          dut.io.apb.penable.poke(true)
          dut.io.apb.pslverror.expect(false)
          dut.clock.step()
          dut.io.apb.psel.poke(false)
          dut.io.apb.penable.poke(false)
        }

        apbWrite(GpuRegisterMap.Op, GpuOpcode.Fill)
        apbWrite(GpuRegisterMap.DstAddr, GpuMemoryMap.FramebufferA + 2)
        apbWrite(GpuRegisterMap.Size, (2L << 16) | 3L)
        apbWrite(GpuRegisterMap.DstStride, 12)
        apbWrite(GpuRegisterMap.ColorKey, 0x5aa5)
        apbWrite(GpuRegisterMap.Tag, 0x1234)
        apbWrite(GpuRegisterMap.Control, 1)

        for (_ <- 0 until 300 if !sawIrq) {
          dut.io.axi.b.valid.poke(responsePending)
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = responsePending && dut.io.axi.b.ready.peek().litToBoolean

          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            }
            writeAddress += 4
          }
          sawIrq ||= dut.io.irq.peek().litToBoolean
          dut.clock.step()
          if (bFire) responsePending = false
          if (wLast) responsePending = true
        }

        sawIrq shouldBe true
        def halfWord(address: Long): Int = memory(address) | (memory(address + 1) << 8)
        Seq(
          GpuMemoryMap.FramebufferA.longValue + 2,
          GpuMemoryMap.FramebufferA.longValue + 4,
          GpuMemoryMap.FramebufferA.longValue + 6,
          GpuMemoryMap.FramebufferA.longValue + 14,
          GpuMemoryMap.FramebufferA.longValue + 16,
          GpuMemoryMap.FramebufferA.longValue + 18
        ).foreach(address => halfWord(address) shouldBe 0x5aa5)

        dut.io.apb.paddr.poke(GpuRegisterMap.LastDone)
        dut.io.apb.pwrite.poke(false)
        dut.io.apb.psel.poke(true)
        dut.io.apb.penable.poke(true)
        dut.io.apb.prdata.expect(0x1234)
        dut.io.apb.paddr.poke(GpuRegisterMap.Error)
        dut.io.apb.prdata.expect(GpuError.None)
      }
    }
  }

  describe("RenderEngine completion order") {
    it("does not let a rejected queued command complete ahead of an active Fill") {
      simulate(new RenderEngine) { dut =>
        val completionTags = collection.mutable.ArrayBuffer.empty[BigInt]
        val completionCycles = collection.mutable.ArrayBuffer.empty[Int]
        var commandIndex = 0
        var responsePending = false

        dut.io.completion.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)

        for (cycle <- 0 until 150 if completionTags.size < 2) {
          dut.io.command.valid.poke(commandIndex < 2)
          dut.io.command.bits.op.poke(if (commandIndex == 0) GpuOpcode.Fill else 15)
          dut.io.command.bits.srcAddr.poke(0)
          dut.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferA)
          dut.io.command.bits.widthPixels.poke(1)
          dut.io.command.bits.heightPixels.poke(1)
          dut.io.command.bits.srcStride.poke(0)
          dut.io.command.bits.dstStride.poke(2)
          dut.io.command.bits.color.poke(0x1234)
          dut.io.command.bits.colorKey.poke(0)
          dut.io.command.bits.alpha.poke(255)
          dut.io.command.bits.flags.poke(0)
          dut.io.command.bits.tag.poke(commandIndex + 1)
          dut.io.axi.b.valid.poke(responsePending)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val writeLast = dut.io.axi.w.valid.peek().litToBoolean &&
            dut.io.axi.w.ready.peek().litToBoolean && dut.io.axi.w.bits.last.peek().litToBoolean
          val responseFire = responsePending && dut.io.axi.b.ready.peek().litToBoolean
          if (dut.io.completion.valid.peek().litToBoolean) {
            completionTags += dut.io.completion.bits.tag.peek().litValue
            completionCycles += cycle
          }
          dut.clock.step()
          if (commandFire) commandIndex += 1
          if (responseFire) responsePending = false
          if (writeLast) responsePending = true
        }

        completionTags.toSeq shouldBe Seq(BigInt(1), BigInt(2))
        completionCycles(1) - completionCycles(0) should be >= 2
      }
    }
  }

  describe("AxiReadEngine") {
    it("splits at 4 KB and preserves every beat while the consumer applies backpressure") {
      simulate(new AxiReadEngine) { dut =>
        dut.io.request.valid.poke(false)
        dut.io.request.bits.address.poke(0)
        dut.io.request.bits.bytes.poke(0)
        dut.io.data.ready.poke(false)
        dut.io.axiAr.ready.poke(false)
        dut.io.axiR.valid.poke(false)
        dut.io.axiR.bits.id.poke(0)
        dut.io.axiR.bits.data.poke(0)
        dut.io.axiR.bits.resp.poke(0)
        dut.io.axiR.bits.last.poke(false)
        dut.clock.step()

        dut.io.request.valid.poke(true)
        dut.io.request.bits.address.poke(0x0ff8)
        dut.io.request.bits.bytes.poke(20)
        dut.io.request.ready.expect(true)
        dut.clock.step()
        dut.io.request.valid.poke(false)

        dut.io.axiAr.valid.expect(true)
        dut.io.axiAr.bits.addr.expect(0x0ff8)
        dut.io.axiAr.bits.len.expect(1)
        dut.io.axiAr.bits.size.expect(Axi4.WordSize)
        dut.io.axiAr.bits.burst.expect(Axi4.Incrementing)
        dut.clock.step(2)
        dut.io.axiAr.valid.expect(true)
        dut.io.axiAr.bits.addr.expect(0x0ff8)
        dut.io.axiAr.ready.poke(true)
        dut.clock.step()
        dut.io.axiAr.ready.poke(false)

        dut.io.axiR.valid.poke(true)
        dut.io.axiR.bits.data.poke(0x11111111L)
        dut.io.axiR.bits.last.poke(false)
        dut.io.data.valid.expect(true)
        dut.io.axiR.ready.expect(false)
        dut.clock.step(2)
        dut.io.data.ready.poke(true)
        dut.io.data.bits.data.expect(0x11111111L)
        dut.io.data.bits.address.expect(0x0ff8)
        dut.clock.step()

        dut.io.axiR.bits.data.poke(0x22222222L)
        dut.io.axiR.bits.last.poke(true)
        dut.io.data.bits.data.expect(0x22222222L)
        dut.io.data.bits.address.expect(0x0ffc)
        dut.clock.step()
        dut.io.axiR.valid.poke(false)

        dut.io.axiAr.valid.expect(true)
        dut.io.axiAr.bits.addr.expect(0x1000)
        dut.io.axiAr.bits.len.expect(2)
        dut.io.axiAr.ready.poke(true)
        dut.clock.step()
        dut.io.axiAr.ready.poke(false)

        for (index <- 0 until 3) {
          dut.io.axiR.valid.poke(true)
          dut.io.axiR.bits.data.poke(0x33333333L + index)
          dut.io.axiR.bits.last.poke(index == 2)
          dut.io.data.bits.address.expect(0x1000 + index * 4)
          dut.io.data.bits.last.expect(index == 2)
          dut.clock.step()
        }
        dut.io.axiR.valid.poke(false)
        dut.io.done.expect(true)
        dut.io.error.expect(false)
        dut.clock.step()
        dut.io.done.expect(false)
      }
    }

    it("reports a non-OKAY read response when the request completes") {
      simulate(new AxiReadEngine) { dut =>
        dut.io.request.valid.poke(true)
        dut.io.request.bits.address.poke(0x2000)
        dut.io.request.bits.bytes.poke(4)
        dut.io.data.ready.poke(true)
        dut.io.axiAr.ready.poke(true)
        dut.io.axiR.valid.poke(false)
        dut.io.axiR.bits.id.poke(0)
        dut.io.axiR.bits.data.poke(0)
        dut.io.axiR.bits.resp.poke(0)
        dut.io.axiR.bits.last.poke(false)
        dut.clock.step()
        dut.io.request.valid.poke(false)
        dut.clock.step()

        dut.io.axiR.valid.poke(true)
        dut.io.axiR.bits.resp.poke(2)
        dut.io.axiR.bits.last.poke(true)
        dut.clock.step()
        dut.io.axiR.valid.poke(false)
        dut.io.done.expect(true)
        dut.io.error.expect(true)
      }
    }
  }

  describe("AxiWriteEngine") {
    it("splits at 4 KB and preserves data and half-word strobes under backpressure") {
      simulate(new AxiWriteEngine) { dut =>
        dut.io.request.valid.poke(false)
        dut.io.request.bits.address.poke(0)
        dut.io.request.bits.beats.poke(0)
        dut.io.data.valid.poke(false)
        dut.io.data.bits.data.poke(0)
        dut.io.data.bits.strb.poke(0)
        dut.io.axiAw.ready.poke(false)
        dut.io.axiW.ready.poke(false)
        dut.io.axiB.valid.poke(false)
        dut.io.axiB.bits.id.poke(0)
        dut.io.axiB.bits.resp.poke(0)
        dut.clock.step()

        dut.io.request.valid.poke(true)
        dut.io.request.bits.address.poke(0x0ffc)
        dut.io.request.bits.beats.poke(3)
        dut.io.request.ready.expect(true)
        dut.clock.step()
        dut.io.request.valid.poke(false)

        dut.io.axiAw.valid.expect(true)
        dut.io.axiAw.bits.addr.expect(0x0ffc)
        dut.io.axiAw.bits.len.expect(0)
        dut.io.axiAw.ready.poke(true)
        dut.clock.step()
        dut.io.axiAw.ready.poke(false)

        dut.io.data.valid.poke(true)
        dut.io.data.bits.data.poke(0xaaaabbbbL)
        dut.io.data.bits.strb.poke(0xc)
        dut.io.axiW.valid.expect(true)
        dut.io.axiW.bits.data.expect(0xaaaabbbbL)
        dut.io.axiW.bits.strb.expect(0xc)
        dut.io.axiW.bits.last.expect(true)
        dut.io.axiW.ready.poke(false)
        dut.clock.step(2)
        dut.io.data.ready.expect(false)
        dut.io.axiW.ready.poke(true)
        dut.clock.step()
        dut.io.data.valid.poke(false)
        dut.io.axiW.ready.poke(false)

        dut.io.axiB.valid.poke(true)
        dut.io.axiB.ready.expect(true)
        dut.clock.step()
        dut.io.axiB.valid.poke(false)

        dut.io.axiAw.valid.expect(true)
        dut.io.axiAw.bits.addr.expect(0x1000)
        dut.io.axiAw.bits.len.expect(1)
        dut.io.axiAw.ready.poke(true)
        dut.clock.step()
        dut.io.axiAw.ready.poke(false)

        for ((data, strobe, last) <- Seq(
          (0x11112222L, 0xf, false),
          (0x33334444L, 0x3, true)
        )) {
          dut.io.data.valid.poke(true)
          dut.io.data.bits.data.poke(data)
          dut.io.data.bits.strb.poke(strobe)
          dut.io.axiW.ready.poke(true)
          dut.io.axiW.bits.data.expect(data)
          dut.io.axiW.bits.strb.expect(strobe)
          dut.io.axiW.bits.last.expect(last)
          dut.clock.step()
        }
        dut.io.data.valid.poke(false)
        dut.io.axiW.ready.poke(false)
        dut.io.axiB.valid.poke(true)
        dut.clock.step()
        dut.io.axiB.valid.poke(false)
        dut.io.done.expect(true)
        dut.io.error.expect(false)
      }
    }

    it("reports a non-OKAY write response when the request completes") {
      simulate(new AxiWriteEngine) { dut =>
        dut.io.request.valid.poke(true)
        dut.io.request.bits.address.poke(0x2000)
        dut.io.request.bits.beats.poke(1)
        dut.io.data.valid.poke(true)
        dut.io.data.bits.data.poke(0x12345678L)
        dut.io.data.bits.strb.poke(0xf)
        dut.io.axiAw.ready.poke(true)
        dut.io.axiW.ready.poke(true)
        dut.io.axiB.valid.poke(false)
        dut.io.axiB.bits.id.poke(0)
        dut.io.axiB.bits.resp.poke(0)
        dut.clock.step()
        dut.io.request.valid.poke(false)
        dut.clock.step()
        dut.clock.step()
        dut.io.data.valid.poke(false)

        dut.io.axiB.valid.poke(true)
        dut.io.axiB.bits.resp.poke(2)
        dut.clock.step()
        dut.io.axiB.valid.poke(false)
        dut.io.done.expect(true)
        dut.io.error.expect(true)
      }
    }
  }

  describe("Solid Fill path") {
    it("generates every RGB565 address in a strided rectangle") {
      simulate(new RectAddressGen) { dut =>
        dut.io.start.valid.poke(true)
        dut.io.start.bits.base.poke(0x2002)
        dut.io.start.bits.widthPixels.poke(3)
        dut.io.start.bits.heightPixels.poke(2)
        dut.io.start.bits.stride.poke(12)
        dut.io.address.ready.poke(false)
        dut.clock.step()
        dut.io.start.valid.poke(false)

        val observed = collection.mutable.ArrayBuffer.empty[(BigInt, Boolean, Boolean)]
        for (cycle <- 0 until 20 if observed.size < 6) {
          dut.io.address.ready.poke(cycle % 3 != 0)
          if (dut.io.address.valid.peek().litToBoolean && dut.io.address.ready.peek().litToBoolean) {
            observed += ((
              dut.io.address.bits.address.peek().litValue,
              dut.io.address.bits.rowLast.peek().litToBoolean,
              dut.io.address.bits.last.peek().litToBoolean
            ))
          }
          dut.clock.step()
        }

        observed.toSeq shouldBe Seq(
          (BigInt(0x2002), false, false),
          (BigInt(0x2004), false, false),
          (BigInt(0x2006), true, false),
          (BigInt(0x200e), false, false),
          (BigInt(0x2010), false, false),
          (BigInt(0x2012), true, true)
        )
      }
    }

    it("packs adjacent RGB565 pixels and flushes half words at row boundaries") {
      simulate(new PixelWritePacker) { dut =>
        val pixels = Seq(
          (0x2002, 0x1000, false),
          (0x2004, 0x1001, false),
          (0x2006, 0x1002, true),
          (0x200e, 0x1003, false),
          (0x2010, 0x1004, false),
          (0x2012, 0x1005, true)
        )
        val observed = collection.mutable.ArrayBuffer.empty[(BigInt, BigInt, BigInt, Boolean)]
        var inputIndex = 0
        dut.io.output.ready.poke(true)

        for (_ <- 0 until 40 if observed.size < 4) {
          if (inputIndex < pixels.size) {
            val (address, pixel, rowLast) = pixels(inputIndex)
            dut.io.input.valid.poke(true)
            dut.io.input.bits.address.poke(address)
            dut.io.input.bits.pixel.poke(pixel)
            dut.io.input.bits.writeEnable.poke(true)
            dut.io.input.bits.rowLast.poke(rowLast)
          } else {
            dut.io.input.valid.poke(false)
          }

          val inputFire = dut.io.input.valid.peek().litToBoolean && dut.io.input.ready.peek().litToBoolean
          if (dut.io.output.valid.peek().litToBoolean) {
            observed += ((
              dut.io.output.bits.address.peek().litValue,
              dut.io.output.bits.data.peek().litValue,
              dut.io.output.bits.strb.peek().litValue,
              dut.io.output.bits.rowLast.peek().litToBoolean
            ))
          }
          dut.clock.step()
          if (inputFire) inputIndex += 1
        }

        observed.toSeq shouldBe Seq(
          (BigInt(0x2000), BigInt("10000000", 16), BigInt(0xc), false),
          (BigInt(0x2004), BigInt("10021001", 16), BigInt(0xf), true),
          (BigInt(0x200c), BigInt("10030000", 16), BigInt(0xc), false),
          (BigInt(0x2010), BigInt("10051004", 16), BigInt(0xf), true)
        )
      }
    }

    it("fills a strided rectangle through the pixel-pipe and AXI handshakes") {
      simulate(new DenseBlitEngine) { dut =>
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        var submitted = false
        var completed = false
        var pixelPending = false
        var responsePending = false
        var writeAddress = 0L

        dut.io.completion.ready.poke(true)
        dut.io.pixelRequest.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)

        for (_ <- 0 until 300 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.op.poke(GpuOpcode.Fill)
          dut.io.command.bits.srcAddr.poke(0)
          dut.io.command.bits.dstAddr.poke(0x2002)
          dut.io.command.bits.widthPixels.poke(3)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.srcStride.poke(0)
          dut.io.command.bits.dstStride.poke(12)
          dut.io.command.bits.color.poke(0xabcd)
          dut.io.command.bits.colorKey.poke(0)
          dut.io.command.bits.alpha.poke(255)
          dut.io.command.bits.flags.poke(0)
          dut.io.command.bits.tag.poke(0x55aa)

          dut.io.pixelResult.valid.poke(pixelPending)
          dut.io.pixelResult.bits.pixel.poke(0xabcd)
          dut.io.pixelResult.bits.writeEnable.poke(true)
          dut.io.axi.b.valid.poke(responsePending)
          dut.io.axi.b.bits.id.poke(0)
          dut.io.axi.b.bits.resp.poke(0)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val requestFire = dut.io.pixelRequest.valid.peek().litToBoolean && dut.io.pixelRequest.ready.peek().litToBoolean
          val resultFire = dut.io.pixelResult.valid.peek().litToBoolean && dut.io.pixelResult.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            }
            writeAddress += 4
          }
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0x55aa)
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (resultFire) pixelPending = false
          if (requestFire) pixelPending = true
          if (bFire) responsePending = false
          if (wLast) responsePending = true
        }

        completed shouldBe true
        def halfWord(address: Long): Int = memory(address) | (memory(address + 1) << 8)
        Seq(0x2002L, 0x2004L, 0x2006L, 0x200eL, 0x2010L, 0x2012L).foreach { address =>
          halfWord(address) shouldBe 0xabcd
        }
        halfWord(0x2008) shouldBe 0
        halfWord(0x200c) shouldBe 0
      }
    }

    it("copies an odd-width strided rectangle from an upper-halfword source") {
      simulate(new DenseBlitEngine) { dut =>
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        val sourcePixels = Seq(0x1111, 0x2222, 0x3333, 0x4444, 0x5555, 0x6666)
        val sourceAddresses = Seq(0x2400002L, 0x2400004L, 0x2400006L, 0x2400012L, 0x2400014L, 0x2400016L)
        for ((pixel, address) <- sourcePixels.zip(sourceAddresses)) {
          memory(address) = pixel & 0xff
          memory(address + 1) = pixel >> 8
        }

        def word(address: Long): Long = (0 until 4).map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
        var submitted = false
        var completed = false
        var pixelPending = false
        var pendingPixel = 0
        var readAddress = 0L
        var readBeats = 0
        var writeAddress = 0L
        var responsePending = false

        dut.io.completion.ready.poke(true)
        dut.io.pixelRequest.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(0)

        for (_ <- 0 until 500 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.op.poke(GpuOpcode.Copy)
          dut.io.command.bits.srcAddr.poke(0x2400002L)
          dut.io.command.bits.dstAddr.poke(0x2000002L)
          dut.io.command.bits.widthPixels.poke(3)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.srcStride.poke(16)
          dut.io.command.bits.dstStride.poke(12)
          dut.io.command.bits.color.poke(0)
          dut.io.command.bits.colorKey.poke(0)
          dut.io.command.bits.alpha.poke(255)
          dut.io.command.bits.flags.poke(0)
          dut.io.command.bits.tag.poke(0xcafe)

          dut.io.pixelResult.valid.poke(pixelPending)
          dut.io.pixelResult.bits.pixel.poke(pendingPixel)
          dut.io.pixelResult.bits.writeEnable.poke(true)
          dut.io.axi.b.valid.poke(responsePending)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(if (readBeats > 0) word(readAddress) else 0)
          dut.io.axi.r.bits.last.poke(readBeats == 1)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val pixelRequestFire = dut.io.pixelRequest.valid.peek().litToBoolean && dut.io.pixelRequest.ready.peek().litToBoolean
          val pixelResultFire = dut.io.pixelResult.valid.peek().litToBoolean && dut.io.pixelResult.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (pixelRequestFire) pendingPixel = dut.io.pixelRequest.bits.foreground.peek().litValue.toInt
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
          }
          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            }
            writeAddress += 4
          }
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0xcafe)
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (pixelResultFire) pixelPending = false
          if (pixelRequestFire) pixelPending = true
          if (rFire) {
            readAddress += 4
            readBeats -= 1
          }
          if (bFire) responsePending = false
          if (wLast) responsePending = true
        }

        completed shouldBe true
        def halfWord(address: Long): Int = memory(address) | (memory(address + 1) << 8)
        val destinationAddresses = Seq(0x2000002L, 0x2000004L, 0x2000006L, 0x200000eL, 0x2000010L, 0x2000012L)
        destinationAddresses.map(halfWord) shouldBe sourcePixels
      }
    }
  }

  describe("Color Key path") {
    it("routes a valid Color Key command to the dense engine instead of rejecting it") {
      simulate(new RenderEngine) { dut =>
        dut.io.command.valid.poke(true)
        dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
        dut.io.command.bits.op.poke(GpuOpcode.ColorKey)
        dut.io.command.bits.srcAddr.poke(GpuMemoryMap.DenseAssets)
        dut.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferA)
        dut.io.command.bits.widthPixels.poke(2)
        dut.io.command.bits.heightPixels.poke(1)
        dut.io.command.bits.srcStride.poke(4)
        dut.io.command.bits.dstStride.poke(4)
        dut.io.command.bits.tag.poke(0x15)
        dut.io.vblank.poke(false)
        dut.io.completion.ready.poke(true)
        dut.io.axi.aw.ready.poke(false)
        dut.io.axi.w.ready.poke(false)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))

        while (!dut.io.command.ready.peek().litToBoolean) dut.clock.step()
        dut.clock.step()
        dut.io.command.valid.poke(false)
        dut.clock.step(8)
        dut.io.completion.valid.expect(false)
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(GpuMemoryMap.DenseAssets)
      }
    }

    it("reads only the source and suppresses transparent byte lanes and an all-transparent row") {
      simulate(new DenseBlitEngine) { dut =>
        val key = 0xbeef
        val srcBase = 0x02400000L
        val dstBase = 0x02000000L
        val source = Seq(key, 0x1111, key, 0x2222, key, key, key, key)
        val initial = Seq(0xaaaa, 0xbbbb, 0xcccc, 0xdddd, 1, 2, 3, 4)
        val expected = Seq(0xaaaa, 0x1111, 0xcccc, 0x2222, 1, 2, 3, 4)
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        for ((pixel, index) <- source.zipWithIndex) {
          memory(srcBase + index * 2) = pixel & 0xff
          memory(srcBase + index * 2 + 1) = pixel >> 8
        }
        for ((pixel, index) <- initial.zipWithIndex) {
          memory(dstBase + index * 2) = pixel & 0xff
          memory(dstBase + index * 2 + 1) = pixel >> 8
        }

        def word(address: Long): Long =
          (0 until 4).map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
        def halfWord(address: Long): Int = memory(address) | (memory(address + 1) << 8)

        var submitted = false
        var completed = false
        var pixelPending = false
        var pendingPixel = 0
        var pendingWrite = false
        var readAddress = 0L
        var readBeats = 0
        var writeAddress = 0L
        var responsePending = false
        val readRequests = collection.mutable.ArrayBuffer.empty[Long]
        val writeRequests = collection.mutable.ArrayBuffer.empty[Long]
        val writeStrobes = collection.mutable.ArrayBuffer.empty[Int]

        dut.io.completion.ready.poke(true)
        dut.io.pixelRequest.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(0)

        for (_ <- 0 until 1500 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.ColorKey)
          dut.io.command.bits.srcAddr.poke(srcBase)
          dut.io.command.bits.dstAddr.poke(dstBase)
          dut.io.command.bits.widthPixels.poke(4)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.srcStride.poke(8)
          dut.io.command.bits.dstStride.poke(8)
          dut.io.command.bits.colorKey.poke(key)
          dut.io.command.bits.tag.poke(0x1515)

          dut.io.pixelResult.valid.poke(pixelPending)
          dut.io.pixelResult.bits.pixel.poke(pendingPixel)
          dut.io.pixelResult.bits.writeEnable.poke(pendingWrite)
          dut.io.axi.b.valid.poke(responsePending)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(BigInt(if (readBeats > 0) word(readAddress) else 0L))
          dut.io.axi.r.bits.last.poke(readBeats == 1)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val requestFire = dut.io.pixelRequest.valid.peek().litToBoolean && dut.io.pixelRequest.ready.peek().litToBoolean
          val resultFire = dut.io.pixelResult.valid.peek().litToBoolean && dut.io.pixelResult.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (requestFire) {
            pendingPixel = dut.io.pixelRequest.bits.foreground.peek().litValue.toInt
            pendingWrite = pendingPixel != key
          }
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
            readRequests += readAddress
          }
          if (awFire) {
            writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
            writeRequests += writeAddress
          }
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            writeStrobes += strobe
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            }
            writeAddress += 4
          }
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0x1515)
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (resultFire) pixelPending = false
          if (requestFire) pixelPending = true
          if (rFire) {
            readAddress += 4
            readBeats -= 1
          }
          if (bFire) responsePending = false
          if (wLast) responsePending = true
        }

        completed shouldBe true
        (0 until 8).map(index => halfWord(dstBase + index * 2)) shouldBe expected
        readRequests.toSeq shouldBe Seq(srcBase, srcBase + 8)
        writeRequests.toSeq shouldBe Seq(dstBase, dstBase + 4)
        writeStrobes.toSeq shouldBe Seq(0xc, 0xc)
      }
    }
  }

  describe("Global Alpha path") {
    it("pairs foreground and background pixels under random AXI delays") {
      simulate(new DenseBlitEngine) { dut =>
        val srcBase = 0x02400000L
        val dstBase = 0x02000000L
        // Row 0 begins in the low halfword and covers the two-pixel chunk path;
        // the 10-byte stride makes row 1 upper-first and covers single-pixel chunks.
        val stride = 10
        val width = 3
        val height = 2
        val alpha = 128
        val foreground = Seq(0xf800, 0x07e0, 0x001f, 0xffff, 0x0000, 0x1234)
        val background = Seq(0x001f, 0xf800, 0x07e0, 0x0000, 0xffff, 0xabcd)
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)

        def pixelAddress(base: Long, index: Int): Long =
          base + (index / width) * stride + (index % width) * 2
        def storeHalf(address: Long, value: Int): Unit = {
          memory(address) = value & 0xff
          memory(address + 1) = value >> 8
        }
        def loadHalf(address: Long): Int = memory(address) | (memory(address + 1) << 8)
        def word(address: Long): Long =
          (0 until 4).map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
        def blend(fg: Int, bg: Int): Int = {
          def channel(f: Int, b: Int): Int = (f * alpha + b * (255 - alpha) + 127) / 255
          val r = channel((fg >> 11) & 0x1f, (bg >> 11) & 0x1f)
          val g = channel((fg >> 5) & 0x3f, (bg >> 5) & 0x3f)
          val b = channel(fg & 0x1f, bg & 0x1f)
          (r << 11) | (g << 5) | b
        }

        foreground.indices.foreach { index =>
          storeHalf(pixelAddress(srcBase, index), foreground(index))
          storeHalf(pixelAddress(dstBase, index), background(index))
        }

        final case class ReadBurst(id: Int, var address: Long, var beats: Int)
        val reads = collection.mutable.Queue.empty[ReadBurst]
        val readAddresses = collection.mutable.ArrayBuffer.empty[Long]
        val observedPairs = collection.mutable.ArrayBuffer.empty[(Int, Int)]
        val random = new scala.util.Random(0x16a17L)
        var submitted = false
        var completed = false
        var resultPending = false
        var pendingResult = 0
        var writeAddress = 0L
        var responsePending = false
        var writeTransactionOpen = false

        dut.io.completion.ready.poke(true)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(Axi4.Okay)
        dut.io.axi.r.bits.resp.poke(Axi4.Okay)

        for (_ <- 0 until 10000 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.Alpha)
          dut.io.command.bits.srcAddr.poke(srcBase)
          dut.io.command.bits.dstAddr.poke(dstBase)
          dut.io.command.bits.widthPixels.poke(width)
          dut.io.command.bits.heightPixels.poke(height)
          dut.io.command.bits.srcStride.poke(stride)
          dut.io.command.bits.dstStride.poke(stride)
          dut.io.command.bits.alpha.poke(alpha)
          dut.io.command.bits.tag.poke(0x1617)

          dut.io.axi.aw.ready.poke(!writeTransactionOpen && random.nextBoolean())
          dut.io.axi.w.ready.poke(random.nextBoolean())
          // Legal conservative slave: once AW is accepted, it does not accept a
          // same-address read until WLAST. The renderer must issue read-before-write.
          dut.io.axi.ar.ready.poke(!writeTransactionOpen && random.nextBoolean())
          dut.io.axi.b.valid.poke(responsePending && random.nextBoolean())

          val offerRead = reads.nonEmpty && random.nextBoolean()
          dut.io.axi.r.valid.poke(offerRead)
          dut.io.axi.r.bits.id.poke(if (reads.nonEmpty) reads.front.id else 0)
          dut.io.axi.r.bits.data.poke(BigInt(if (reads.nonEmpty) word(reads.front.address) else 0L))
          dut.io.axi.r.bits.last.poke(reads.nonEmpty && reads.front.beats == 1)

          dut.io.pixelResult.valid.poke(resultPending && random.nextBoolean())
          dut.io.pixelResult.bits.pixel.poke(pendingResult)
          dut.io.pixelResult.bits.writeEnable.poke(true)
          dut.io.pixelRequest.ready.poke(random.nextBoolean())

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val requestFire = dut.io.pixelRequest.valid.peek().litToBoolean && dut.io.pixelRequest.ready.peek().litToBoolean
          val resultFire = dut.io.pixelResult.valid.peek().litToBoolean && dut.io.pixelResult.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (requestFire) {
            val fg = dut.io.pixelRequest.bits.foreground.peek().litValue.toInt
            val bg = dut.io.pixelRequest.bits.background.peek().litValue.toInt
            observedPairs += fg -> bg
            pendingResult = blend(fg, bg)
          }
          if (arFire) {
            val address = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            reads.enqueue(ReadBurst(
              dut.io.axi.ar.bits.id.peek().litValue.toInt,
              address,
              dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
            ))
            readAddresses += address
          }
          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            }
            writeAddress += 4
          }
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0x1617)
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (resultFire) resultPending = false
          if (requestFire) resultPending = true
          if (rFire) {
            if (reads.front.beats == 1) reads.dequeue()
            else {
              reads.front.address += 4
              reads.front.beats -= 1
            }
          }
          if (bFire) responsePending = false
          if (wLast) {
            responsePending = true
            writeTransactionOpen = false
          }
          if (awFire) writeTransactionOpen = true
        }

        completed shouldBe true
        observedPairs.toSeq shouldBe foreground.zip(background)
        foreground.indices.map(index => loadHalf(pixelAddress(dstBase, index))) shouldBe
          foreground.zip(background).map { case (fg, bg) => blend(fg, bg) }
        readAddresses.exists(address => address >= srcBase && address < srcBase + height * stride) shouldBe true
        readAddresses.exists(address => address >= dstBase && address < dstBase + height * stride) shouldBe true
      }
    }

    it("does not leak an Alpha background read error into the following Fill") {
      simulate(new DenseBlitEngine) { dut =>
        final case class ReadBeat(id: Int, data: Long)
        val reads = collection.mutable.Queue.empty[ReadBeat]
        val completions = collection.mutable.ArrayBuffer.empty[(Int, Int)]
        var commandIndex = 0
        var resultPending = false
        var pendingPixel = 0
        var responsePending = false
        var backgroundErrorSent = false

        dut.io.completion.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(Axi4.Okay)
        dut.io.pixelRequest.ready.poke(true)

        for (_ <- 0 until 300 if completions.size < 2) {
          dut.io.command.valid.poke(commandIndex < 2)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          if (commandIndex == 0) {
            dut.io.command.bits.op.poke(GpuOpcode.Alpha)
            dut.io.command.bits.srcAddr.poke(GpuMemoryMap.DenseAssets)
            dut.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferA)
            dut.io.command.bits.srcStride.poke(2)
            dut.io.command.bits.dstStride.poke(2)
            dut.io.command.bits.alpha.poke(128)
            dut.io.command.bits.tag.poke(0xa001)
          } else {
            dut.io.command.bits.op.poke(GpuOpcode.Fill)
            dut.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferA + 4)
            dut.io.command.bits.dstStride.poke(2)
            dut.io.command.bits.color.poke(0x07e0)
            dut.io.command.bits.tag.poke(0xf001)
          }
          dut.io.command.bits.widthPixels.poke(1)
          dut.io.command.bits.heightPixels.poke(1)

          dut.io.axi.r.valid.poke(reads.nonEmpty)
          dut.io.axi.r.bits.id.poke(if (reads.nonEmpty) reads.front.id else 0)
          dut.io.axi.r.bits.data.poke(BigInt(if (reads.nonEmpty) reads.front.data else 0L))
          dut.io.axi.r.bits.last.poke(true)
          dut.io.axi.r.bits.resp.poke(
            if (reads.nonEmpty && reads.front.id == 1 && !backgroundErrorSent) 2 else Axi4.Okay
          )
          dut.io.axi.b.valid.poke(responsePending)
          dut.io.pixelResult.valid.poke(resultPending)
          dut.io.pixelResult.bits.pixel.poke(pendingPixel)
          dut.io.pixelResult.bits.writeEnable.poke(true)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val requestFire = dut.io.pixelRequest.valid.peek().litToBoolean && dut.io.pixelRequest.ready.peek().litToBoolean
          val resultFire = dut.io.pixelResult.valid.peek().litToBoolean && dut.io.pixelResult.ready.peek().litToBoolean
          val wLast = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean &&
            dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (arFire) {
            val id = dut.io.axi.ar.bits.id.peek().litValue.toInt
            reads.enqueue(ReadBeat(id, if (id == 0) 0x0000f800L else 0x0000001fL))
          }
          if (requestFire) {
            val op = dut.io.pixelRequest.bits.op.peek().litValue.toInt
            pendingPixel = if (op == GpuOpcode.Alpha) 0x800f else 0x07e0
          }
          if (completionFire) {
            completions += dut.io.completion.bits.tag.peek().litValue.toInt ->
              dut.io.completion.bits.error.peek().litValue.toInt
          }

          dut.clock.step()
          if (commandFire) commandIndex += 1
          if (rFire) {
            if (reads.front.id == 1) backgroundErrorSent = true
            reads.dequeue()
          }
          if (resultFire) resultPending = false
          if (requestFire) resultPending = true
          if (bFire) responsePending = false
          if (wLast) responsePending = true
        }

        completions.toSeq shouldBe Seq(
          0xa001 -> GpuError.AxiResponse,
          0xf001 -> GpuError.None
        )
      }
    }
  }

  describe("PixelReadAligner") {
    it("selects the upper first pixel and stops after an odd pixel count under backpressure") {
      simulate(new PixelReadAligner) { dut =>
        dut.io.start.valid.poke(true)
        dut.io.start.bits.upperFirst.poke(true)
        dut.io.start.bits.pixels.poke(3)
        dut.io.input.valid.poke(false)
        dut.io.input.bits.poke(0)
        dut.io.output.ready.poke(false)
        dut.clock.step()
        dut.io.start.valid.poke(false)

        val words = Seq(BigInt("22221111", 16), BigInt("44443333", 16))
        val observed = collection.mutable.ArrayBuffer.empty[(BigInt, Boolean)]
        var wordIndex = 0
        for (cycle <- 0 until 30 if observed.size < 3) {
          dut.io.output.ready.poke(cycle % 3 != 1)
          if (wordIndex < words.size) {
            dut.io.input.valid.poke(true)
            dut.io.input.bits.poke(words(wordIndex))
          } else {
            dut.io.input.valid.poke(false)
          }

          val inputFire = dut.io.input.valid.peek().litToBoolean && dut.io.input.ready.peek().litToBoolean
          if (dut.io.output.valid.peek().litToBoolean && dut.io.output.ready.peek().litToBoolean) {
            observed += ((dut.io.output.bits.pixel.peek().litValue, dut.io.output.bits.last.peek().litToBoolean))
          }
          dut.clock.step()
          if (inputFire) wordIndex += 1
        }

        observed.toSeq shouldBe Seq(
          (BigInt(0x2222), false),
          (BigInt(0x3333), false),
          (BigInt(0x4444), true)
        )
        dut.io.busy.expect(false)
      }
    }

    it("handles lower-first even widths and can restart on a strided next row") {
      simulate(new PixelReadAligner) { dut =>
        dut.io.start.valid.poke(false)
        dut.io.input.valid.poke(false)
        dut.io.input.bits.poke(0)
        dut.io.output.ready.poke(true)
        dut.clock.step()

        def readRow(upperFirst: Boolean, pixels: Int, words: Seq[BigInt]): Seq[BigInt] = {
          dut.io.start.valid.poke(true)
          dut.io.start.bits.upperFirst.poke(upperFirst)
          dut.io.start.bits.pixels.poke(pixels)
          dut.clock.step()
          dut.io.start.valid.poke(false)

          val result = collection.mutable.ArrayBuffer.empty[BigInt]
          var wordIndex = 0
          for (_ <- 0 until 30 if result.size < pixels) {
            dut.io.input.valid.poke(wordIndex < words.size)
            if (wordIndex < words.size) dut.io.input.bits.poke(words(wordIndex))
            val inputFire = dut.io.input.valid.peek().litToBoolean && dut.io.input.ready.peek().litToBoolean
            if (dut.io.output.valid.peek().litToBoolean) result += dut.io.output.bits.pixel.peek().litValue
            dut.clock.step()
            if (inputFire) wordIndex += 1
          }
          result.toSeq
        }

        readRow(upperFirst = false, 4, Seq(BigInt("22221111", 16), BigInt("44443333", 16))) shouldBe
          Seq(0x1111, 0x2222, 0x3333, 0x4444).map(BigInt(_))
        readRow(upperFirst = true, 2, Seq(BigInt("66665555", 16), BigInt("88887777", 16))) shouldBe
          Seq(0x6666, 0x7777).map(BigInt(_))
      }
    }
  }
}
