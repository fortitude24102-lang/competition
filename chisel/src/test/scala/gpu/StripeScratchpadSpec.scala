package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class StripeScratchpadSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("local stripe AXI window") {
    it("keeps byte masks, stalled responses and independent local/external ownership") {
      simulate(new StripeScratchpad) { d =>
        val base = 0x02e00000L
        d.io.in.aw.valid.poke(false); d.io.in.w.valid.poke(false); d.io.in.b.ready.poke(false)
        d.io.in.ar.valid.poke(false); d.io.in.r.ready.poke(false)
        d.io.in.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        d.io.in.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
        d.io.in.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        d.io.ddr.aw.ready.poke(true); d.io.ddr.w.ready.poke(true)
        d.io.ddr.ar.ready.poke(true); d.io.ddr.b.valid.poke(false); d.io.ddr.r.valid.poke(false)
        d.io.ddr.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        d.io.ddr.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        d.reset.poke(true); d.clock.step(2); d.reset.poke(false)
        def address(a: Axi4Address, addr: Long, n: Int, size: Int = 2): Unit = {
          a.poke(0.U.asTypeOf(new Axi4Address)); a.addr.poke(addr); a.len.poke(n-1)
          a.size.poke(size); a.burst.poke(1); a.id.poke(7)
        }
        def write(addr: Long, data: Seq[(Long, Int)], bad: Boolean = false, size: Int = 2, burst: Int = 1): Unit = {
          address(d.io.in.aw.bits, addr, data.size, size); d.io.in.aw.valid.poke(true)
          d.io.in.aw.bits.burst.poke(burst)
          d.io.in.aw.ready.expect(true); d.io.ddr.aw.valid.expect(false); d.clock.step()
          d.io.in.aw.valid.poke(false)
          for (((word, mask), i) <- data.zipWithIndex) {
            d.io.in.w.valid.poke(true); d.io.in.w.bits.data.poke(word)
            d.io.in.w.bits.strb.poke(mask); d.io.in.w.bits.last.poke(i == data.size-1)
            d.io.in.w.ready.expect(true); d.io.ddr.w.valid.expect(false); d.clock.step()
          }
          d.io.in.w.valid.poke(false)
          d.io.in.b.valid.expect(true); d.io.in.b.bits.id.expect(7)
          d.io.in.b.bits.resp.expect(if (bad) 2 else 0)
          d.clock.step(3); d.io.in.b.valid.expect(true)
          d.io.in.b.ready.poke(true); d.clock.step(); d.io.in.b.ready.poke(false)
        }
        def read(addr: Long, n: Int, bad: Boolean = false): Seq[Long] = {
          address(d.io.in.ar.bits, addr, n); d.io.in.ar.valid.poke(true)
          d.io.in.ar.ready.expect(true); d.io.ddr.ar.valid.expect(false); d.clock.step()
          d.io.in.ar.valid.poke(false)
          val result = collection.mutable.ArrayBuffer.empty[Long]
          for (i <- 0 until n) {
            var wait = 0
            while (!d.io.in.r.valid.peek().litToBoolean && wait < 30) {d.clock.step(); wait += 1}
            d.io.in.r.valid.expect(true); d.io.in.r.bits.id.expect(7)
            d.io.in.r.bits.resp.expect(if (bad) 2 else 0); d.io.in.r.bits.last.expect(i == n-1)
            val word = d.io.in.r.bits.data.peek().litValue
            d.clock.step(3); d.io.in.r.bits.data.expect(word); d.io.in.r.valid.expect(true)
            result += word.longValue
            d.io.in.r.ready.poke(true); d.clock.step(); d.io.in.r.ready.poke(false)
          }
          result.toSeq
        }
        write(base, Seq((0x11223344L,15),(0x55667788L,15),(0x99aabbccL,15)))
        write(base+4, Seq((0xff00ee00L,10)))
        read(base,3) shouldBe Seq(0x11223344L,0xff66ee88L,0x99aabbccL)
        write(base+15356,Seq((1L,15),(2L,15)),bad=true)
        read(base+15356,2,bad=true)
        write(base+1,Seq((1L,15)),bad=true)
        write(base,Seq((1L,15)),bad=true,size=1)
        write(base,Seq((1L,15)),bad=true,burst=0)
        write(base+0xf000,Seq((1L,15)),bad=true) // Reserved alias tail cannot escape to DDR.
        write(base+4092,Seq((0x12345678L,15)))
        write(base+4092,Seq((1L,15),(2L,15)),bad=true) // Illegal4KiB crossing, no partial writes.
        read(base+4092,1) shouldBe Seq(0x12345678L)
        read(base+4092,2,bad=true)
        read(base,1) shouldBe Seq(0x11223344L)
        // External AW can be backpressured, then owns W/B while local reads proceed.
        address(d.io.in.aw.bits,0x02000000L,1); d.io.in.aw.valid.poke(true)
        d.io.ddr.aw.ready.poke(false); d.io.in.aw.ready.expect(false)
        d.io.ddr.aw.bits.addr.expect(0x02000000L); d.clock.step(3)
        d.io.ddr.aw.ready.poke(true); d.clock.step(); d.io.in.aw.valid.poke(false)
        read(base,1) shouldBe Seq(0x11223344L)
        d.io.in.w.valid.poke(true); d.io.in.w.bits.data.poke(42); d.io.in.w.bits.last.poke(true)
        d.io.ddr.w.valid.expect(true); d.io.ddr.w.bits.data.expect(42); d.clock.step()
        d.io.in.w.valid.poke(false); d.io.ddr.b.valid.poke(true)
        d.io.ddr.b.bits.id.poke(7); d.io.ddr.b.bits.resp.poke(2)
        d.io.in.b.valid.expect(true); d.io.in.b.bits.resp.expect(2)
        d.io.in.b.ready.poke(true); d.clock.step(); d.io.ddr.b.valid.poke(false)
        address(d.io.in.ar.bits,0x02400000L,1); d.io.in.ar.valid.poke(true)
        d.io.ddr.ar.valid.expect(true); d.clock.step(); d.io.in.ar.valid.poke(false)
        d.io.ddr.r.valid.poke(true); d.io.ddr.r.bits.id.poke(7)
        d.io.ddr.r.bits.data.poke(123); d.io.ddr.r.bits.last.poke(true)
        d.io.in.r.valid.expect(true); d.io.in.r.bits.data.expect(123)
        d.io.in.r.ready.poke(true); d.clock.step(); d.io.ddr.r.valid.poke(false)
      }
    }
  }
}
