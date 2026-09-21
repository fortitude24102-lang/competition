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
  }
}
