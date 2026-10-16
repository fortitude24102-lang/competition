package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class ScanoutWordBoundarySpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("conserves words across a supply gap and the terminal high-half handshake") {
    simulate(new PixelReadAligner(continuousWords=true)) { d =>
      d.io.start.valid.poke(true);d.io.start.bits.upperFirst.poke(false);d.io.start.bits.pixels.poke(4)
      d.io.input.valid.poke(false);d.io.output.ready.poke(true);d.clock.step();d.io.start.valid.poke(false)
      d.io.input.valid.poke(true);d.io.input.bits.poke(0x22221111L);d.io.input.ready.expect(true);d.clock.step()
      d.io.input.valid.poke(false)
      d.io.output.bits.pixel.expect(0x1111);d.clock.step()
      d.io.output.bits.pixel.expect(0x2222);d.clock.step()
      // The next DDR word can be arbitrated away for several clocks.
      d.io.output.valid.expect(false);d.io.busy.expect(true);d.clock.step(3);d.io.output.valid.expect(false)
      d.io.input.valid.poke(true);d.io.input.bits.poke(0x44443333L);d.io.input.ready.expect(true);d.clock.step()
      // Extra source data must NOT be consumed by the terminal output handshake.
      d.io.input.bits.poke(0xdeafbeefL)
      d.io.output.bits.pixel.expect(0x3333);d.io.input.ready.expect(false);d.clock.step()
      d.io.output.valid.expect(true);d.io.output.bits.pixel.expect(0x4444);d.io.output.bits.last.expect(true)
      d.io.input.ready.expect(false);d.clock.step()
      d.io.output.valid.expect(false);d.io.busy.expect(false);d.io.input.ready.expect(false)
      d.io.input.valid.poke(false)
      // A one-pixel upper-first row ends on exactly the same guarded phase.
      d.io.start.valid.poke(true);d.io.start.bits.upperFirst.poke(true);d.io.start.bits.pixels.poke(1);d.clock.step()
      d.io.start.valid.poke(false);d.io.input.valid.poke(true);d.io.input.bits.poke(0x66665555L);d.clock.step()
      d.io.input.bits.poke(0xdeadbeefL);d.io.output.bits.pixel.expect(0x6666)
      d.io.output.bits.last.expect(true);d.io.input.ready.expect(false);d.clock.step();d.io.output.valid.expect(false)
    }
  }
  it("retains DDR response faults and drains only the promised row before reporting error") {
    simulate(new ScanoutDma(frameWidth=8,frameHeight=2,strideBytes=20,enableWordPipeline=true)) { d =>
      for(fault <- 0 to 3) {
        d.io.enable.poke(false);d.io.frontBase.poke(0x02001000L);d.io.fifoLevel.poke(0);d.io.refill.poke(false)
        d.io.pixel.ready.poke(true);d.io.axi.ar.ready.poke(true);d.io.axi.r.valid.poke(false)
        d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        d.io.axi.aw.ready.poke(true);d.io.axi.w.ready.poke(true);d.io.axi.b.valid.poke(false)
        d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
        var left=0;var readWords=0;var rows=0;var pixels=0;var errors=0;var frames=0
        for(cycle <- 0 until 100) {
          d.io.enable.poke(cycle<2)
          d.io.axi.r.valid.poke(left>0)
          d.io.axi.r.bits.data.poke(((readWords*2+1L)<<16)|(readWords*2L))
          d.io.axi.r.bits.id.poke(if(fault==2 && readWords==0)7 else 0)
          d.io.axi.r.bits.resp.poke(if(fault==1 && readWords==0)2 else 0)
          d.io.axi.r.bits.last.poke(left==1 || (fault==3 && readWords==0))
          val ar=d.io.axi.ar.valid.peek().litToBoolean
          val r=left>0 && d.io.axi.r.ready.peek().litToBoolean
          if(d.io.pixel.valid.peek().litToBoolean) {
            d.io.pixel.bits.pixel.expect(pixels);d.io.pixel.bits.lineLast.expect(pixels%8==7)
            d.io.pixel.bits.frameLast.expect(pixels==15);pixels+=1
          }
          if(d.io.error.peek().litToBoolean)errors+=1
          if(d.io.frameDone.peek().litToBoolean)frames+=1
          if(ar) {left shouldBe 0;d.io.axi.ar.bits.len.expect(3);rows+=1;left=4}
          d.clock.step();if(r){left-=1;readWords+=1}
        }
        left shouldBe 0
        rows shouldBe (if(fault==0)2 else 1);pixels shouldBe (if(fault==0)16 else 8)
        errors shouldBe (if(fault==0)0 else 1);frames shouldBe (if(fault==0)1 else 0)
      }
    }
  }
}
