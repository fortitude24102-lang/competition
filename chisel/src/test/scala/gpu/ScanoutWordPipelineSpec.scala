package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class ScanoutWordPipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("scanout word replacement on the last pixel handshake") {
    it("keeps exact pixels but eliminates between-word bubbles with continuous input") {
      val times = Seq(false,true).map { enabled =>
        var lastCycle=0
        simulate(new PixelReadAligner(continuousWords=enabled)) { d =>
          d.io.start.valid.poke(true);d.io.start.bits.upperFirst.poke(false);d.io.start.bits.pixels.poke(16)
          d.io.input.valid.poke(false);d.io.output.ready.poke(true);d.clock.step();d.io.start.valid.poke(false)
          var word=0;var pixel=0;val cycles=collection.mutable.ArrayBuffer.empty[Int]
          for(cycle <- 0 until 40 if pixel<16) {
            d.io.input.valid.poke(word<8)
            d.io.input.bits.poke((0x1200L+word*2)|((0x1201L+word*2)<<16))
            val take=word<8 && d.io.input.ready.peek().litToBoolean
            val give=d.io.output.valid.peek().litToBoolean
            if(give) {d.io.output.bits.pixel.expect(0x1200+pixel);d.io.output.bits.last.expect(pixel==15);cycles+=cycle}
            d.clock.step();if(take)word+=1;if(give)pixel+=1
          }
          pixel shouldBe 16;word shouldBe 8;d.io.busy.expect(false)
          if(enabled) cycles.toSeq shouldBe (1 to 16)
          lastCycle=cycles.last
        }
        lastCycle
      }
      times(1) should be < times(0)
      info(s"16 pixels: original last=${times(0)}, replacement last=${times(1)} cycles")
    }
    it("preserves halfword starts, odd tails and held output through pauses and row restarts") {
      simulate(new PixelReadAligner(continuousWords=true)) { d =>
        d.io.start.valid.poke(false);d.io.input.valid.poke(false);d.io.output.ready.poke(false);d.clock.step()
        for(upper <- Seq(false,true);size <- Seq(1,2,3,7,12)) {
          d.io.start.ready.expect(true);d.io.start.valid.poke(true)
          d.io.start.bits.upperFirst.poke(upper);d.io.start.bits.pixels.poke(size);d.clock.step()
          d.io.start.valid.poke(false)
          val words=(size+(if(upper)1 else 0)+1)/2;var word=0;var pixel=0
          var held:Option[(BigInt,Boolean)]=None
          for(cycle <- 0 until 100 if pixel<size) {
            val ready=cycle%7>1
            d.io.output.ready.poke(ready);d.io.input.valid.poke(word<words)
            d.io.input.bits.poke((0x3300L+word*2)|((0x3301L+word*2)<<16))
            val take=word<words && d.io.input.ready.peek().litToBoolean
            val valid=d.io.output.valid.peek().litToBoolean
            held.foreach {case(p,last)=>d.io.output.valid.expect(true);d.io.output.bits.pixel.expect(p);d.io.output.bits.last.expect(last)}
            held=if(valid && !ready)Some((d.io.output.bits.pixel.peek().litValue,d.io.output.bits.last.peek().litToBoolean))else None
            if(valid && ready) {d.io.output.bits.pixel.expect(0x3300+(if(upper)1 else 0)+pixel);d.io.output.bits.last.expect(pixel==size-1)}
            d.clock.step();if(take)word+=1;if(valid && ready)pixel+=1
          }
          word shouldBe words;pixel shouldBe size;d.io.busy.expect(false)
          d.io.input.valid.poke(false);d.clock.step();d.io.output.valid.expect(false)
        }
      }
    }
    it("streams the complete production frame with the original CRC inside 600000 cycles") {
      simulate(new ScanoutDmaProductionHarness(enableWordPipeline=true)) { d =>
        d.clock.step(600000)
        d.io.done.expect(true);d.io.mismatch.expect(false)
        d.io.pixelCount.expect(518400);d.io.lineCount.expect(540);d.io.frameLastCount.expect(1)
        d.io.frameCrc.expect(0x954a2475L)
      }
    }
  }
}
