package gpu

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
  }
}
