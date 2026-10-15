package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** The C pixel test cannot establish RTL acceptance of the tall glyph-bank
  * template. Exercise the existing unmodified instance frontend with literal
  * slots12..14, the final green glyph, backpressure, and its rejected end. */
class HudListCompatibilitySpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("expands glyph logo and final HUD Copy in order without changing the RTL ABI") {
    simulate(new InstanceStream(true)) { d =>
      val list=d.io.list.get
      d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
      d.io.apb.paddr.poke(0);d.io.apb.pwdata.poke(0)
      d.io.idle.poke(true);d.io.hardwareError.poke(0);d.io.command.ready.poke(false)
      list.begin.valid.poke(false);list.begin.bits.poke(0);list.end.poke(false);list.owned.poke(false)
      list.descriptor.valid.poke(false);list.descriptor.bits.foreach(_.poke(0))
      d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
      def wr(a:Int,v:BigInt):Unit = {
        d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(true)
        d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);d.clock.step()
        d.io.apb.penable.poke(true);d.io.apb.pready.expect(true)
        d.io.apb.pslverror.expect(false);d.clock.step()
        d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
      }
      val fields=Seq(
        Seq[BigInt](2,0x02c40000,28,1920,14,1404,0),
        Seq[BigInt](2,0x02c10000,1920,1920,960,72,0),
        Seq[BigInt](2,0x02c50000,400,1920,200,70,0))
      for((t,i)<-fields.zipWithIndex) {
        wr(0x40c,12+i);for((v,j)<-t.zipWithIndex)wr(0x410+j*4,v)
      }
      list.owned.poke(true);list.begin.bits.poke(65535);list.begin.valid.poke(true)
      d.clock.step();list.begin.valid.poke(false)
      def send(words:Seq[BigInt]):Unit = {
        words.zipWithIndex.foreach{case(v,i)=>list.descriptor.bits(i).poke(v)}
        list.descriptor.valid.poke(true)
        var n=0;while(!list.descriptor.ready.peek().litToBoolean && n<10){d.clock.step();n+=1}
        list.descriptor.ready.expect(true);d.clock.step();list.descriptor.valid.poke(false)
      }
      val descriptors=Seq(
        Seq[BigInt](12,0x02c29bf4,38808,0x0012000e),
        Seq[BigInt](14,0x02c10d60,0,0x004600c8),
        Seq[BigInt](13,0x02000000,0,0x004803c0))
      val sources=Seq[BigInt](0x02c49798,0x02c50000,0x02c10000)
      val widths=Seq(14,200,960);val heights=Seq(18,70,72);val strides=Seq(28,400,1920)
      for(i<-0 until 3) {
        send(descriptors(i))
        var n=0;while(!d.io.command.valid.peek().litToBoolean && n<10){d.clock.step();n+=1}
        d.io.command.valid.expect(true)
        for(_<-0 until 3) {
          d.io.command.bits.op.expect(2);d.io.command.bits.srcAddr.expect(sources(i))
          d.io.command.bits.dstAddr.expect(descriptors(i)(1))
          d.io.command.bits.srcStride.expect(strides(i));d.io.command.bits.dstStride.expect(1920)
          d.io.command.bits.widthPixels.expect(widths(i));d.io.command.bits.heightPixels.expect(heights(i))
          d.io.command.bits.tag.expect((65535+i)&65535);d.clock.step()
        }
        d.io.command.ready.poke(true);d.clock.step();d.io.command.ready.poke(false)
      }
      list.empty.expect(true);list.error.expect(0);list.end.poke(true);d.clock.step();list.end.poke(false)
      list.begin.valid.poke(true);d.clock.step();list.begin.valid.poke(false)
      send(Seq[BigInt](12,0x02c29bf4,39312,0x0012000e)) // one full cell beyond atlas end
      d.clock.step(5);d.io.command.valid.expect(false);list.error.expect(GpuError.AddressRange)
    }
  }
}
