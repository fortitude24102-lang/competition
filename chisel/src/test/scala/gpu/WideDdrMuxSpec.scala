package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import scala.util.Random
import testutil.StableChiselSim

class WideDdrMuxSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def yes(b:Bool)=b.peek().litToBoolean
  private def init(d:WideDdrMux):Unit = {
    for(p<-Seq(d.io.legacy,d.io.native)) {
      p.ar.valid.poke(false);p.ar.bits.poke(0.U.asTypeOf(new Axi128Address))
      p.aw.valid.poke(false);p.aw.bits.poke(0.U.asTypeOf(new Axi128Address))
      p.w.valid.poke(false);p.w.bits.poke(0.U.asTypeOf(new Axi128WriteData))
      p.r.ready.poke(true);p.b.ready.poke(true)
    }
    d.io.ddr.ar.ready.poke(false);d.io.ddr.aw.ready.poke(false);d.io.ddr.w.ready.poke(false)
    d.io.ddr.r.valid.poke(false);d.io.ddr.r.bits.poke(0.U.asTypeOf(new Axi128ReadData))
    d.io.ddr.b.valid.poke(false);d.io.ddr.b.bits.poke(0.U.asTypeOf(new Axi128WriteResponse))
    d.io.emergency.poke(false);d.clock.step()
  }
  private def addr(p:Axi128Address,a:Long,id:Int=0,n:Int=1):Unit = {
    p.poke(0.U.asTypeOf(new Axi128Address));p.addr.poke(a);p.id.poke(id)
    p.len.poke(n-1);p.size.poke(4);p.burst.poke(1)
  }
  it("keeps legacy refill alive when emergency cancels a native handover, including a stalled native address") {
    simulate(new WideDdrMux) { d=>
      init(d);d.io.emergency.poke(true);d.io.ddr.ar.ready.poke(true)
      d.io.legacy.ar.valid.poke(true);addr(d.io.legacy.ar.bits,0x2000000,0x80)
      d.io.legacy.ar.ready.expect(true);d.clock.step() // legacy outstanding
      d.io.native.ar.valid.poke(true);addr(d.io.native.ar.bits,0x2400000)
      d.io.emergency.poke(false);d.clock.step(2)
      d.io.emergency.poke(true)
      d.io.legacy.ar.ready.expect(true);d.io.native.ar.ready.expect(false)
      d.clock.step();d.io.legacy.ar.valid.poke(false)
      d.io.ddr.r.valid.poke(true);d.io.ddr.r.bits.id.poke(0x80);d.io.ddr.r.bits.last.poke(true)
      for(_<-0 until 2) {d.io.legacy.r.valid.expect(true);d.io.native.r.valid.expect(false);d.clock.step()}
      d.io.ddr.r.valid.poke(false);d.io.emergency.poke(false);d.io.ddr.ar.ready.poke(false)
      var c=0;while(!yes(d.io.ddr.ar.valid)&&c<8){d.clock.step();c+=1}
      assert(c<8);d.io.ddr.ar.bits.addr.expect(0x2400000)
      d.clock.step() // capture presented-address lock
      d.io.emergency.poke(true);d.io.legacy.ar.valid.poke(true)
      for(_<-0 until 3){d.io.ddr.ar.valid.expect(true);d.io.ddr.ar.bits.addr.expect(0x2400000);d.clock.step()}
      d.io.ddr.ar.ready.poke(true);d.clock.step();d.io.native.ar.valid.poke(false)
      d.io.ddr.r.valid.poke(true);d.io.ddr.r.bits.id.poke(0);d.io.ddr.r.bits.last.poke(true)
      d.io.native.r.valid.expect(true);d.io.legacy.r.valid.expect(false);d.clock.step()
      d.io.ddr.r.valid.poke(false);d.clock.step(3);d.io.legacy.ar.ready.expect(true)
    }
  }
  it("preserves16 legacy credits, four writes, same IDs and independent directions under random stalls") {
    simulate(new WideDdrMux) { d=>
      init(d)
      case class Tx(owner:Int,addr:Long,id:Int,n:Int)
      val ports=Seq(d.io.legacy,d.io.native)
      val rs=Seq(mutable.Queue.empty[Tx],mutable.Queue.empty[Tx])
      val ws=Seq(mutable.Queue.empty[Tx],mutable.Queue.empty[Tx])
      for(m<-0 to 1;i<-0 until 28) {
        rs(m).enqueue(Tx(m,0x2000000L+m*0x400000+i*64,if(m==0)(i*17)&255 else 0,if(m==0)1 else 2))
        ws(m).enqueue(Tx(m,0x2100000L+m*0x400000+i*64,if(m==0)(i*19)&255 else 0,2))
      }
      val readQ=mutable.Queue.empty[Tx];val writeQ=mutable.Queue.empty[Tx];val bQ=mutable.Queue.empty[Tx]
      var readHead:Option[Tx]=None;var bHead:Option[Tx]=None
      val dataQ=Seq(mutable.Queue.empty[Tx],mutable.Queue.empty[Tx])
      var ri=0;var wi=0;val mi=Array(0,0);var receivedR=0;var receivedB=0
      var ar=0;var aw=0;var cycle=0;var maxRead=0;var maxWrite=0
      var fullReadReplacement=0;var fullWriteReplacement=0
      var previousAR:Option[Long]=None;var previousAW:Option[Long]=None;var previousW:Option[BigInt]=None
      val rnd=new Random(420)
      while((receivedR<56 || receivedB<56)&&cycle<12000) {
        // First responses start at48; keep legacy ownership to96 so that
        // full16-credit retirement + replacement actually occurs in this test.
        val emergency=cycle<96 || cycle%157<27
        d.io.emergency.poke(emergency)
        for(m<-0 to 1) {
          val p=ports(m);p.ar.valid.poke(rs(m).nonEmpty);p.aw.valid.poke(ws(m).nonEmpty)
          rs(m).headOption.foreach(t=>addr(p.ar.bits,t.addr,t.id,t.n))
          ws(m).headOption.foreach(t=>addr(p.aw.bits,t.addr,t.id,t.n))
          p.r.ready.poke(cycle%5!=m);p.b.ready.poke(cycle%7!=m)
          // W data source starts when AW is accepted, ordered per master.
          p.w.valid.poke(dataQ(m).nonEmpty)
          val t=dataQ(m).headOption.getOrElse(Tx(m,0,0,2))
          p.w.bits.data.poke(BigInt(t.addr+mi(m)));p.w.bits.strb.poke(65535);p.w.bits.last.poke(mi(m)==t.n-1)
        }
        d.io.ddr.ar.ready.poke(rnd.nextInt(5)!=0);d.io.ddr.aw.ready.poke(rnd.nextInt(4)!=0)
        d.io.ddr.w.ready.poke(cycle>=48 && rnd.nextInt(4)!=0)
        if(readHead.isEmpty && readQ.nonEmpty && cycle>=48 && rnd.nextInt(3)!=0)readHead=Some(readQ.dequeue())
        if(bHead.isEmpty && bQ.nonEmpty && rnd.nextInt(3)!=0)bHead=Some(bQ.dequeue())
        d.io.ddr.r.valid.poke(readHead.nonEmpty)
        readHead.foreach {t=>d.io.ddr.r.bits.id.poke(t.id);d.io.ddr.r.bits.data.poke(t.addr+ri);d.io.ddr.r.bits.last.poke(ri==t.n-1)}
        d.io.ddr.b.valid.poke(bHead.nonEmpty);bHead.foreach(t=>d.io.ddr.b.bits.id.poke(t.id))
        def fire(v:Bool,r:Bool)=yes(v)&&yes(r)
        previousAR.foreach(a=>{d.io.ddr.ar.valid.expect(true);d.io.ddr.ar.bits.addr.expect(a)})
        previousAW.foreach(a=>{d.io.ddr.aw.valid.expect(true);d.io.ddr.aw.bits.addr.expect(a)})
        previousW.foreach(a=>{d.io.ddr.w.valid.expect(true);d.io.ddr.w.bits.data.expect(a)})
        val rf=fire(d.io.ddr.r.valid,d.io.ddr.r.ready)
        val bf=fire(d.io.ddr.b.valid,d.io.ddr.b.ready)
        val arFire=fire(d.io.ddr.ar.valid,d.io.ddr.ar.ready)
        val awFire=fire(d.io.ddr.aw.valid,d.io.ddr.aw.ready)
        val rRetire=rf && readHead.exists(t=>ri==t.n-1)
        if(readHead.nonEmpty) {
          val t=readHead.get;ports(t.owner).r.valid.expect(true);ports(1-t.owner).r.valid.expect(false)
          ports(t.owner).r.bits.id.expect(t.id);ports(t.owner).r.bits.data.expect(t.addr+ri)
        }
        if(bHead.nonEmpty) {val t=bHead.get;ports(t.owner).b.valid.expect(true);ports(1-t.owner).b.valid.expect(false);ports(t.owner).b.bits.id.expect(t.id)}
        if(fire(d.io.ddr.ar.valid,d.io.ddr.ar.ready)) {
          val a=d.io.ddr.ar.bits.addr.peek().litValue.longValue;val m=if(a<0x2400000)0 else 1
          assert(rs(m).nonEmpty);val t=rs(m).dequeue();a shouldBe t.addr
          d.io.ddr.ar.bits.id.expect(t.id);ports(m).ar.ready.expect(true);ports(1-m).ar.ready.expect(false)
          readQ.enqueue(t);ar+=1
        }
        if(fire(d.io.ddr.aw.valid,d.io.ddr.aw.ready)) {
          val a=d.io.ddr.aw.bits.addr.peek().litValue.longValue;val m=if(a<0x2500000)0 else 1
          assert(ws(m).nonEmpty);val t=ws(m).dequeue();a shouldBe t.addr
          d.io.ddr.aw.bits.id.expect(t.id);writeQ.enqueue(t);dataQ(m).enqueue(t);aw+=1
        }
        if(fire(d.io.ddr.w.valid,d.io.ddr.w.ready)) {
          assert(writeQ.nonEmpty);val t=writeQ.head
          d.io.ddr.w.bits.data.expect(t.addr+wi);d.io.ddr.w.bits.last.expect(wi==t.n-1)
          ports(1-t.owner).w.ready.expect(false);wi+=1;mi(t.owner)+=1
          if(wi==t.n){writeQ.dequeue();dataQ(t.owner).dequeue();bQ.enqueue(t);wi=0;mi(t.owner)=0}
        }
        if(rRetire && arFire && ar-receivedR==17)fullReadReplacement+=1
        if(bf && awFire && aw-receivedB==17)fullWriteReplacement+=1
        val liveReads=ar-receivedR-(if(rRetire)1 else 0)
        val liveWrites=aw-receivedB-(if(bf)1 else 0)
        maxRead=maxRead.max(liveReads);maxWrite=maxWrite.max(liveWrites)
        assert(liveReads<=16 && liveWrites<=16)
        previousAR=if(yes(d.io.ddr.ar.valid)&& !yes(d.io.ddr.ar.ready))Some(d.io.ddr.ar.bits.addr.peek().litValue.longValue)else None
        previousAW=if(yes(d.io.ddr.aw.valid)&& !yes(d.io.ddr.aw.ready))Some(d.io.ddr.aw.bits.addr.peek().litValue.longValue)else None
        previousW=if(yes(d.io.ddr.w.valid)&& !yes(d.io.ddr.w.ready))Some(d.io.ddr.w.bits.data.peek().litValue)else None
        d.clock.step()
        if(rf){ri+=1;if(ri==readHead.get.n){receivedR+=1;readHead=None;ri=0}}
        if(bf){receivedB+=1;bHead=None}
        cycle+=1
      }
      receivedR shouldBe 56;receivedB shouldBe 56
      maxRead shouldBe 16;maxWrite shouldBe 16
      assert(fullReadReplacement>0 && fullWriteReplacement>0,"full-credit same-cycle replacement was not exercised")
      // Both owners empty after the last response; reset discards no live work.
      d.io.ddr.r.valid.poke(false);d.io.ddr.b.valid.poke(false)
      d.reset.poke(true);d.clock.step();d.reset.poke(false);d.clock.step()
      ports.foreach(p=>{p.r.valid.expect(false);p.b.valid.expect(false)})
    }
  }
  it("backpressures W before AW and switches only after final B with both same-ID masters requesting") {
    simulate(new WideDdrMux) { d=>
      init(d)
      val old=d.io.legacy;val next=d.io.native;val bus=d.io.ddr
      bus.ar.ready.poke(true);bus.aw.ready.poke(false);bus.w.ready.poke(true)
      old.w.valid.poke(true);old.w.bits.data.poke(0x1234);old.w.bits.strb.poke(65535);old.w.bits.last.poke(true)
      for(_<-0 until 3){old.w.ready.expect(false);bus.w.valid.expect(false);d.clock.step()}
      old.aw.valid.poke(true);addr(old.aw.bits,0x2000000)
      for(_<-0 until 3){old.w.ready.expect(false);bus.w.valid.expect(false);d.clock.step()}
      bus.aw.ready.poke(true);old.aw.ready.expect(true);old.w.ready.expect(false);d.clock.step()
      old.aw.valid.poke(false);old.w.ready.expect(true);bus.w.bits.data.expect(0x1234);d.clock.step();old.w.valid.poke(false)
      next.aw.valid.poke(true);addr(next.aw.bits,0x2400000)
      next.w.valid.poke(true);next.w.bits.data.poke(0xabcd);next.w.bits.strb.poke(65535);next.w.bits.last.poke(true)
      next.ar.valid.poke(true);addr(next.ar.bits,0x2401000)
      // Read direction can switch to native while legacy still owns outstanding B.
      var ar=false;var c=0
      while(!ar && c<8){next.aw.ready.expect(false);next.w.ready.expect(false);ar=yes(next.ar.ready);d.clock.step();c+=1}
      assert(ar);next.ar.valid.poke(false)
      bus.r.valid.poke(true);bus.r.bits.id.poke(0);bus.r.bits.last.poke(true)
      next.r.valid.expect(true);old.r.valid.expect(false);d.clock.step();bus.r.valid.poke(false)
      old.aw.valid.poke(true);addr(old.aw.bits,0x2001000)
      bus.b.valid.poke(true);bus.b.bits.id.poke(0)
      old.b.valid.expect(true);next.b.valid.expect(false)
      old.aw.ready.expect(false);next.aw.ready.expect(false);next.w.ready.expect(false)
      d.clock.step();bus.b.valid.poke(false)
      c=0;while(!yes(next.aw.ready)&&c<8){old.aw.ready.expect(false);d.clock.step();c+=1}
      assert(c<8);bus.aw.bits.addr.expect(0x2400000)
      d.clock.step();next.aw.valid.poke(false)
      next.w.ready.expect(true);old.w.ready.expect(false);bus.w.bits.data.expect(0xabcd)
      d.clock.step();next.w.valid.poke(false)
      bus.b.valid.poke(true);next.b.valid.expect(true);old.b.valid.expect(false)
      old.aw.ready.expect(false);d.clock.step();bus.b.valid.poke(false)
      old.aw.ready.expect(true);old.aw.valid.poke(false)
    }
  }
}
