package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class AxiDiagnosticsSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("candidate AXI diagnostics") {
    it("routes the optional page through the real Top APB response stage") {
      for (present <- Seq(false, true)) simulate(new Efinix2dGpuTop(enableFrameLists=true, enableAxiDiagnostics=present)) { dut =>
        dut.io.apb.psel.poke(false); dut.io.apb.penable.poke(false); dut.io.apb.pwrite.poke(false)
        dut.io.apb.paddr.poke(0); dut.io.apb.pwdata.poke(0)
        dut.io.vblank.poke(false); dut.io.scanoutLevel.poke(2048); dut.io.underflow_pulse_gpu.poke(false)
        dut.io.displayReady.poke(true); dut.io.assetMeta.valid.poke(false); dut.io.assetPayload.valid.poke(false)
        dut.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
        dut.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte)); dut.io.assetStreamError.poke(false)
        dut.io.axi.aw.ready.poke(true); dut.io.axi.w.ready.poke(true); dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false); dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false); dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        def access(a: Int, write: Boolean = false, data: Int = 0, error: Boolean = false): BigInt = {
          dut.io.apb.paddr.poke(a); dut.io.apb.pwrite.poke(write); dut.io.apb.pwdata.poke(data)
          dut.io.apb.psel.poke(true); dut.io.apb.penable.poke(false); dut.clock.step()
          dut.io.apb.penable.poke(true)
          var cycles = 0
          while (!dut.io.apb.pready.peek().litToBoolean && cycles < 10) { dut.clock.step(); cycles += 1 }
          dut.io.apb.pready.expect(true); dut.io.apb.pslverror.expect(error)
          val result = dut.io.apb.prdata.peek().litValue
          dut.clock.step(); dut.io.apb.psel.poke(false); dut.io.apb.penable.poke(false); dut.clock.step()
          result
        }
        ((access(0x08) >> 19) & 1) shouldBe (if(present) BigInt(1) else BigInt(0))
        if(present) {
          access(0x600) shouldBe BigInt("41585046",16)
          access(0x604,true,3); dut.clock.step(7); access(0x604,true,0)
          val window = access(0x64c); window should be >= BigInt(7)
          dut.clock.step(5); access(0x64c) shouldBe window
          access(0x604,true,2); access(0x64c) shouldBe 0
        } else access(0x600,error=true) shouldBe 0
      }
    }

    it("counts events only in the enabled window and rejects invalid APB writes without side effects") {
      simulate(new AxiDiagnosticRegs) { dut =>
        dut.io.events.foreach(_.poke(false))
        dut.io.apb.psel.poke(false); dut.io.apb.penable.poke(false)
        dut.io.apb.paddr.poke(0); dut.io.apb.pwrite.poke(false); dut.io.apb.pwdata.poke(0)
        def access(a: Int, write: Boolean = false, data: Int = 0, error: Boolean = false): BigInt = {
          dut.io.apb.paddr.poke(a); dut.io.apb.pwrite.poke(write); dut.io.apb.pwdata.poke(data)
          dut.io.apb.psel.poke(true); dut.io.apb.penable.poke(false); dut.clock.step()
          dut.io.apb.penable.poke(true); dut.io.apb.pready.expect(true); dut.io.apb.pslverror.expect(error)
          val result = dut.io.apb.prdata.peek().litValue
          dut.clock.step(); dut.io.apb.psel.poke(false); dut.io.apb.penable.poke(false); dut.clock.step()
          result
        }
        access(0x600) shouldBe BigInt("41585046", 16)
        access(0x604, true, 3)
        for (i <- 0 until 5) {
          dut.io.events(0).poke(i < 2); dut.io.events(3).poke(true); dut.io.events(7).poke(i < 3)
          dut.clock.step()
        }
        dut.io.events.foreach(_.poke(false))
        access(0x604, true, 4, true) // Must not clear or disable.
        access(0x610, true, 99, true)
        access(0x608, false, 0, true)
        access(0x604) shouldBe 1
        dut.io.events(0).poke(true); dut.clock.step(); dut.io.events(0).poke(false)
        access(0x604, true, 0)
        dut.io.events.foreach(_.poke(true)); dut.clock.step(5); dut.io.events.foreach(_.poke(false))
        access(0x610) shouldBe 3
        access(0x61c) shouldBe 5
        access(0x62c) shouldBe 3
        access(0x604, true, 2)
        for (i <- 0 until 16) access(0x610 + i * 4) shouldBe 0
      }
    }

    it("observes real Render supply gaps and B latency while excluding Asset and Scanout") {
      simulate(new DdrQosArbiter(enableDiagnostics = true)) { dut =>
        dut.io.lowWatermark.poke(10); dut.io.highWatermark.poke(20)
        dut.io.scanoutLevel.poke(30); dut.io.adaptiveEnable.poke(false)
        for (p <- Seq(dut.io.render, dut.io.asset, dut.io.scanout)) {
          p.ar.valid.poke(false); p.aw.valid.poke(false); p.w.valid.poke(false)
          p.ar.bits.poke(0.U.asTypeOf(new Axi4Address)); p.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
          p.w.bits.poke(0.U.asTypeOf(new Axi4WriteData)); p.r.ready.poke(true); p.b.ready.poke(true)
        }
        dut.io.axi.aw.ready.poke(false); dut.io.axi.w.ready.poke(false); dut.io.axi.ar.ready.poke(true)
        dut.io.axi.b.valid.poke(false); dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.axi.r.valid.poke(false); dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        val e = dut.io.diagnostics.get
        dut.io.render.aw.valid.poke(true); dut.clock.step()
        e(4).expect(true); dut.clock.step(2)
        dut.io.axi.aw.ready.poke(true); e(13).expect(true); dut.clock.step()
        dut.io.render.aw.valid.poke(false); e(1).expect(true); dut.clock.step(3)
        dut.io.render.w.valid.poke(true); dut.io.render.w.bits.last.poke(true)
        dut.io.render.w.bits.strb.poke(0) // Zero-strobe beats still occupy the bus.
        e(2).expect(true); dut.clock.step(2)
        dut.io.axi.w.ready.poke(true); e(0).expect(true); dut.clock.step()
        dut.io.render.w.valid.poke(false); e(3).expect(true); dut.clock.step(5)
        dut.io.axi.b.valid.poke(true); e(3).expect(false); e(12).expect(true); dut.clock.step()
        dut.io.axi.b.valid.poke(false)
        dut.io.asset.aw.valid.poke(true); dut.clock.step(2); dut.io.asset.aw.valid.poke(false)
        dut.io.asset.w.valid.poke(true); dut.io.asset.w.bits.last.poke(true)
        e(0).expect(false); e(1).expect(false); e(2).expect(false); dut.clock.step()
        dut.io.asset.w.valid.poke(false); e(3).expect(false); dut.clock.step(3)
        dut.io.axi.b.valid.poke(true); e(12).expect(false); dut.clock.step(); dut.io.axi.b.valid.poke(false)
        dut.io.render.ar.valid.poke(true); dut.clock.step(2); dut.io.render.ar.valid.poke(false)
        e(7).expect(true); dut.clock.step(3)
        dut.io.axi.r.valid.poke(true); dut.io.axi.r.bits.last.poke(true)
        e(6).expect(true); e(7).expect(false); dut.clock.step(); dut.io.axi.r.valid.poke(false)
        dut.io.scanout.ar.valid.poke(true); dut.clock.step(2); dut.io.scanout.ar.valid.poke(false)
        e(7).expect(false); dut.clock.step(3)
        dut.io.axi.r.valid.poke(true); e(6).expect(false); dut.clock.step()
        dut.io.axi.r.valid.poke(false)
        dut.io.adaptiveEnable.poke(true); dut.io.scanoutLevel.poke(0)
        dut.io.render.aw.valid.poke(true); dut.io.render.ar.valid.poke(true)
        e(5).expect(true); e(10).expect(true); dut.io.axi.aw.valid.expect(false); dut.io.axi.ar.valid.expect(false)
      }
    }
  }
}
