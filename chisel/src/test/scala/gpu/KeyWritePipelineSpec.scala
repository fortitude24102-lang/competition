package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class KeyWritePipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Key-only two-burst writer") {
    it("issues two ordered rows before B without retiring either early or accepting a third") {
      simulate(new AxiWritePipeline) { d =>
        d.io.request.valid.poke(false); d.io.request.bits.address.poke(0); d.io.request.bits.beats.poke(0)
        d.io.data.valid.poke(false); d.io.data.bits.data.poke(0); d.io.data.bits.strb.poke(0)
        d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
        d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        def request(a: Int): Unit = {
          d.io.request.bits.address.poke(a); d.io.request.bits.beats.poke(4); d.io.request.valid.poke(true)
          d.io.request.ready.expect(true); d.clock.step(); d.io.request.valid.poke(false)
          d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(a); d.io.axiAw.bits.len.expect(3)
          d.clock.step()
        }
        def row(seed: Int): Unit = {
          for(i <- 0 until 4) {
            d.io.data.valid.poke(true); d.io.data.bits.data.poke(seed+i); d.io.data.bits.strb.poke(if(i==1)0 else 15)
            d.io.axiW.valid.expect(true); d.io.axiW.bits.data.expect(seed+i)
            d.io.axiW.bits.strb.expect(if(i==1)0 else 15); d.io.axiW.bits.last.expect(i==3)
            d.io.done.expect(false); d.clock.step()
          }
          d.io.data.valid.poke(false)
        }
        request(0x1000); row(16); request(0x1800); row(32)
        d.io.request.valid.poke(true); d.io.request.bits.address.poke(0x2000)
        d.io.request.ready.expect(false); d.clock.step(5); d.io.done.expect(false)
        d.io.request.valid.poke(false)
        d.io.axiB.valid.poke(true); d.io.axiB.ready.expect(true); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(false); d.clock.step()
        d.io.done.expect(false)
        d.io.axiB.valid.poke(true); d.clock.step(); d.io.axiB.valid.poke(false)
        d.io.done.expect(true); d.io.error.expect(false); d.clock.step(); d.io.done.expect(false)
        d.io.request.ready.expect(true)
      }
    }

    it("splits at 4KiB and aggregates the first B error only at final request retirement") {
      simulate(new AxiWritePipeline) { d =>
        d.io.request.valid.poke(true); d.io.request.bits.address.poke(0xff8); d.io.request.bits.beats.poke(4)
        d.io.data.valid.poke(false); d.io.data.bits.data.poke(0); d.io.data.bits.strb.poke(15)
        d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
        d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse)); d.clock.step()
        d.io.request.valid.poke(false)
        for (a <- Seq(0xff8,0x1000)) {
          d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(a); d.io.axiAw.bits.len.expect(1)
          d.clock.step(); d.io.data.valid.poke(true)
          for(i <- 0 until 2) { d.io.axiW.bits.last.expect(i==1); d.clock.step() }
          d.io.data.valid.poke(false)
        }
        d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(2); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(false); d.io.request.ready.expect(false)
        d.clock.step(3); d.io.axiB.bits.resp.poke(0); d.io.axiB.valid.poke(true); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(true); d.clock.step(2)
        d.io.done.expect(false); d.io.request.ready.expect(true)
      }
    }
  }
}
