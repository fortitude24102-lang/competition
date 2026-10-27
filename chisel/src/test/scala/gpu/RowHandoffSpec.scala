package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class RowHandoffSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("does not hand off at an intermediate 4KiB burst boundary") {
    simulate(new AxiWritePipeline(4)) { d =>
      d.io.request.valid.poke(true);d.io.request.bits.address.poke(0xff8);d.io.request.bits.beats.poke(4)
      d.io.data.valid.poke(false);d.io.data.bits.data.poke(0x12345678L);d.io.data.bits.strb.poke(15)
      d.io.axiAw.ready.poke(true);d.io.axiW.ready.poke(true);d.io.axiB.valid.poke(false)
      d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse));d.clock.step();d.io.request.valid.poke(false)
      for(burst<-0 until 2) {
        d.io.axiAw.valid.expect(true);d.io.axiAw.bits.addr.expect(if(burst==0)0xff8 else 0x1000)
        d.io.axiAw.bits.len.expect(1);d.clock.step();d.io.data.valid.poke(true)
        d.io.request.valid.poke(true);d.io.request.bits.address.poke(0x1800);d.io.request.bits.beats.poke(1)
        for(beat<-0 until 2){d.io.axiW.valid.expect(true);d.io.axiW.bits.last.expect(beat==1);d.io.request.ready.expect(burst==1 && beat==1);d.clock.step()}
        d.io.data.valid.poke(false);d.io.request.valid.poke(false)
      }
      d.io.axiAw.valid.expect(true);d.io.axiAw.bits.addr.expect(0x1800);d.io.axiAw.bits.len.expect(0)
      d.clock.step();d.io.data.valid.poke(true);d.io.axiW.bits.last.expect(true);d.clock.step();d.io.data.valid.poke(false)
      for(last<-Seq(false,true,true)){d.io.axiB.valid.poke(true);d.io.axiB.ready.expect(true);d.clock.step();d.io.axiB.valid.poke(false);d.io.done.expect(last);d.io.error.expect(false);d.clock.step()}
    }
  }

  it("blocks the handoff on a bad B arriving with final W and drains that accepted row") {
    simulate(new AxiWritePipeline) { d =>
      d.io.request.valid.poke(true);d.io.request.bits.address.poke(0x1000);d.io.request.bits.beats.poke(1)
      d.io.data.valid.poke(false);d.io.data.bits.data.poke(0x12345678L);d.io.data.bits.strb.poke(15)
      d.io.axiAw.ready.poke(true);d.io.axiW.ready.poke(true);d.io.axiB.valid.poke(false)
      d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse));d.clock.step();d.io.request.valid.poke(false);d.clock.step()
      d.io.request.valid.poke(true);d.io.request.bits.address.poke(0x1800);d.io.data.valid.poke(true)
      d.io.axiB.valid.poke(true);d.io.axiB.bits.resp.poke(2)
      d.io.axiW.valid.expect(true);d.io.axiW.bits.last.expect(true);d.io.axiB.ready.expect(true);d.io.request.ready.expect(false)
      d.clock.step();d.io.request.valid.poke(false);d.io.data.valid.poke(false);d.io.axiB.valid.poke(false)
      d.io.done.expect(true);d.io.error.expect(true);d.io.axiAw.valid.expect(false);d.clock.step(2)
      d.io.done.expect(false);d.io.request.ready.expect(true)
    }
  }

  for (credits <- Seq(2,4)) {
    it(s"accepts the next request only with final W, preserves its address and retires at B credits=$credits") {
      simulate(new AxiWritePipeline(credits)) { d =>
        d.io.request.valid.poke(true);d.io.request.bits.address.poke(0x1000);d.io.request.bits.beats.poke(1)
        d.io.data.valid.poke(false);d.io.data.bits.data.poke(0x12345678L);d.io.data.bits.strb.poke(15)
        d.io.axiAw.ready.poke(true);d.io.axiW.ready.poke(true);d.io.axiB.valid.poke(false)
        d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse));d.io.request.ready.expect(true);d.clock.step()
        d.io.request.valid.poke(false);d.io.axiAw.valid.expect(true);d.clock.step()
        d.io.data.valid.poke(true);d.io.request.valid.poke(true)
        d.io.request.bits.address.poke(0x1800);d.io.request.bits.beats.poke(2)
        d.io.axiW.ready.poke(false);d.io.request.ready.expect(false);d.clock.step(3)
        d.io.axiW.valid.expect(true);d.io.axiW.bits.data.expect(0x12345678L)
        d.io.axiW.ready.poke(true);d.io.axiW.bits.last.expect(true);d.io.request.ready.expect(true)
        d.clock.step();d.io.request.valid.poke(false);d.io.data.valid.poke(false)
        d.io.axiAw.valid.expect(true);d.io.axiAw.bits.addr.expect(0x1800);d.io.axiAw.bits.len.expect(1)
        d.clock.step();d.io.data.valid.poke(true)
        for(i<-0 until 2){d.io.data.bits.data.poke(32+i);d.io.axiW.valid.expect(true);d.io.axiW.bits.last.expect(i==1);d.clock.step()}
        d.io.data.valid.poke(false);d.io.done.expect(false)
        for(_<-0 until 2){d.io.axiB.valid.poke(true);d.io.axiB.ready.expect(true);d.clock.step();d.io.axiB.valid.poke(false);d.io.done.expect(true);d.io.error.expect(false);d.clock.step()}
        d.io.done.expect(false)
      }
    }
  }

  for (upper <- Seq(false,true)) {
    it(s"restarts the aligner with the final accepted output without stale pixels, upper=$upper") {
      simulate(new Rgb565WordAligner) { d =>
        d.io.start.valid.poke(true);d.io.start.bits.sourceUpper.poke(false)
        d.io.start.bits.destinationUpper.poke(false);d.io.start.bits.pixels.poke(2)
        d.io.input.valid.poke(false);d.io.input.bits.poke(0);d.io.output.ready.poke(false)
        d.clock.step();d.io.start.valid.poke(false);d.io.input.valid.poke(true)
        d.io.input.bits.poke(0x22221111L);d.clock.step();d.io.input.valid.poke(false)
        d.io.output.valid.expect(true);d.io.output.bits.data.expect(0x22221111L)
        d.io.start.valid.poke(true);d.io.start.bits.sourceUpper.poke(upper)
        d.io.start.bits.destinationUpper.poke(upper);d.io.start.bits.pixels.poke(1)
        d.io.start.ready.expect(false);d.clock.step(3);d.io.output.bits.data.expect(0x22221111L)
        d.io.output.ready.poke(true);d.io.start.ready.expect(true);d.clock.step();d.io.start.valid.poke(false)
        d.io.input.valid.poke(true);d.io.input.bits.poke(0x44443333L);d.io.input.ready.expect(true)
        d.clock.step();d.io.input.valid.poke(false);d.io.output.valid.expect(true)
        d.io.output.bits.data.expect(if(upper)0x44440000L else 0x3333L)
        d.io.output.bits.lanes.expect(if(upper)2 else 1);d.io.output.bits.pixels.expect(1)
        d.clock.step();d.io.output.valid.expect(false);d.io.start.ready.expect(true)
      }
    }
  }
}
