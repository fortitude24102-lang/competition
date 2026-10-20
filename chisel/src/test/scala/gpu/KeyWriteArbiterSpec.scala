package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class KeyWriteArbiterSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def init(d: DdrQosArbiter): Unit = {
    d.io.lowWatermark.poke(10); d.io.highWatermark.poke(20)
    d.io.scanoutLevel.poke(30); d.io.adaptiveEnable.poke(true)
    for(p <- Seq(d.io.render,d.io.asset,d.io.scanout)) {
      p.ar.valid.poke(false); p.aw.valid.poke(false); p.w.valid.poke(false)
      p.ar.bits.poke(0.U.asTypeOf(new Axi4Address)); p.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
      p.w.bits.poke(0.U.asTypeOf(new Axi4WriteData)); p.r.ready.poke(true); p.b.ready.poke(true)
    }
    d.io.axi.aw.ready.poke(true); d.io.axi.w.ready.poke(true); d.io.axi.ar.ready.poke(true)
    d.io.axi.r.valid.poke(false); d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    d.io.axi.b.valid.poke(false); d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
  }
  describe("two-response DDR write arbitration") {
    it("routes delayed Render and Asset B by committed W order, not the current AW owner") {
      simulate(new DdrQosArbiter(enableDiagnostics=true,enableWritePipeline=true)) { d =>
        init(d)
        def issue(p: Axi4MasterPort,a:Int): Unit = {
          p.aw.valid.poke(true); p.aw.bits.addr.poke(a); d.clock.step()
          d.io.axi.aw.valid.expect(true); d.io.axi.aw.bits.addr.expect(a); d.clock.step()
          p.aw.valid.poke(false); p.w.valid.poke(true); p.w.bits.last.poke(true); p.w.bits.strb.poke(15)
          d.io.axi.w.valid.expect(true); d.clock.step(); p.w.valid.poke(false)
        }
        issue(d.io.render,0x1000); issue(d.io.asset,0x2000)
        d.io.render.aw.valid.poke(true); d.io.render.aw.bits.addr.poke(0x3000)
        d.clock.step(3); d.io.axi.aw.valid.expect(false)
        d.io.axi.b.valid.poke(true); d.io.axi.b.bits.resp.poke(2); d.io.render.b.ready.poke(false)
        d.io.render.b.valid.expect(true); d.io.render.b.bits.resp.expect(2)
        d.io.asset.b.valid.expect(false); d.io.axi.b.ready.expect(false); d.clock.step(3)
        d.io.render.b.ready.poke(true); d.clock.step()
        d.io.axi.b.valid.poke(false); d.io.axi.b.bits.resp.poke(0); d.clock.step()
        d.io.axi.aw.valid.expect(true); d.io.axi.aw.bits.addr.expect(0x3000)
        d.io.diagnostics.get(3).expect(false) // B head is Asset, even though next W owner is Render.
        d.io.axi.b.valid.poke(true); d.io.asset.b.valid.expect(true); d.io.render.b.valid.expect(false)
        d.clock.step(); d.io.axi.b.valid.poke(false); d.io.render.aw.valid.poke(false)
        d.io.render.w.valid.poke(true); d.io.render.w.bits.last.poke(true); d.clock.step()
        d.io.render.w.valid.poke(false); d.io.diagnostics.get(3).expect(true)
        d.io.axi.b.valid.poke(true); d.io.render.b.valid.expect(true); d.clock.step()
        d.io.axi.b.valid.poke(false); d.io.diagnostics.get(3).expect(false)
      }
    }
    it("holds presented AW through emergency and drains promised W/B while blocking new admissions") {
      simulate(new DdrQosArbiter(enableDiagnostics=true,enableWritePipeline=true)) { d =>
        init(d); d.io.axi.aw.ready.poke(false)
        d.io.render.aw.valid.poke(true); d.io.render.aw.bits.addr.poke(0x1000)
        d.clock.step(); d.io.axi.aw.valid.expect(true); d.clock.step()
        d.io.scanoutLevel.poke(0); d.io.asset.aw.valid.poke(true); d.io.asset.aw.bits.addr.poke(0x2000)
        d.clock.step(3); d.io.axi.aw.valid.expect(true); d.io.axi.aw.bits.addr.expect(0x1000)
        d.io.axi.aw.ready.poke(true); d.clock.step(); d.io.render.aw.valid.poke(false)
        d.io.render.w.valid.poke(true); d.io.render.w.bits.last.poke(true)
        d.io.axi.w.valid.expect(true); d.clock.step(); d.io.render.w.valid.poke(false)
        d.clock.step(3); d.io.axi.aw.valid.expect(false)
        d.io.axi.b.valid.poke(true); d.io.render.b.valid.expect(true); d.clock.step()
        d.io.axi.b.valid.poke(false); d.io.scanoutLevel.poke(20); d.clock.step()
        d.io.axi.aw.valid.expect(true); d.io.axi.aw.bits.addr.expect(0x2000); d.clock.step()
        d.io.asset.aw.valid.poke(false); d.io.asset.w.valid.poke(true); d.io.asset.w.bits.last.poke(true)
        d.clock.step(); d.io.asset.w.valid.poke(false); d.io.axi.b.valid.poke(true)
        d.io.asset.b.valid.expect(true); d.clock.step(); d.io.axi.b.valid.poke(false)
      }
    }
  }
}
