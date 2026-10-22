package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import testutil.StableChiselSim

class WideCopyRenderSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def yes(b:Bool)=b.peek().litToBoolean
  private def init(d:RenderEngine):Unit = {
    d.io.command.valid.poke(false);d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
    d.io.completion.ready.poke(true);d.io.vblank.poke(true);d.io.perfClear.poke(false)
    d.io.underflowPulse.poke(false);d.io.renderGrant.poke(0);d.io.scanoutGrant.poke(0)
    d.io.textureCacheLoad.valid.poke(false);d.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
    d.io.textureCacheInvalidate.poke(false);d.io.fabricReset.get.poke(true)
    d.io.axi.ar.ready.poke(false);d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false)
    d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
    val w=d.io.wideAxi.get
    w.ar.ready.poke(false);w.aw.ready.poke(false);w.w.ready.poke(false)
    w.r.valid.poke(false);w.r.bits.poke(0.U.asTypeOf(new Axi128ReadData))
    w.b.valid.poke(false);w.b.bits.poke(0.U.asTypeOf(new Axi128WriteResponse))
    d.clock.step(2);d.io.fabricReset.get.poke(false);d.clock.step()
  }
  it("falls back before issue for small/strided/unaligned copies and rejects overflow/IO/overlap") {
    simulate(new RenderEngine(enableWideCopyDma=true)) { d=>
      init(d)
      // width,height,src,dst,srcStride,dstStride,wide?,error
      val cases=Seq(
        (256,8,0x02400000L,0x02000000L,512,512,true,0),
        (255,8,0x02400000L,0x02000000L,510,510,false,0),
        (256,8,0x02400000L,0x02000000L,514,512,false,0),
        (256,8,0x02400002L,0x02000000L,512,512,false,0),
        (256,8,0x02400000L,0x02000002L,512,512,false,0),
        (256,8,0x02400000L,0x02400010L,512,512,false,GpuError.OverlappingCopy),
        (256,8,0x12000000L,0x02000000L,512,512,false,GpuError.AddressRange),
        (65535,65535,0x02400000L,0x02000000L,131070,131070,false,GpuError.AddressRange),
        (0,8,0x02400000L,0x02000000L,512,512,false,GpuError.ZeroSize))
      for((width,height,src,dst,ss,ds,wide,error)<-cases) {
        // Common reset is allowed to cancel bus transactions between shape tests.
        d.reset.poke(true);d.io.fabricReset.get.poke(true);d.clock.step(2)
        d.reset.poke(false);d.io.fabricReset.get.poke(false)
        d.io.command.valid.poke(true);d.io.command.bits.op.poke(GpuOpcode.Copy)
        d.io.command.bits.srcAddr.poke(src);d.io.command.bits.dstAddr.poke(dst)
        d.io.command.bits.widthPixels.poke(width);d.io.command.bits.heightPixels.poke(height)
        d.io.command.bits.srcStride.poke(ss);d.io.command.bits.dstStride.poke(ds)
        d.clock.step();d.io.command.valid.poke(false)
        var found=false;var c=0
        while(!found && c<40) {
          val narrow=yes(d.io.axi.ar.valid);val native=yes(d.io.wideAxi.get.ar.valid)
          if(error!=0) {
            assert(!narrow && !native && !yes(d.io.axi.aw.valid) && !yes(d.io.wideAxi.get.aw.valid))
            if(yes(d.io.completion.valid)){d.io.completion.bits.error.expect(error);found=true}
          } else if(narrow || native){assert(native==wide && narrow!=wide);found=true}
          d.clock.step();c+=1
        }
        assert(found,s"no dispatch/rejection: $width/$height/$src/$ds")
      }
    }
  }
  it("fences Copy then Fill/Key/Alpha/PRESENT at the final wide B and accounts true bytes/pixels") {
    simulate(new RenderEngine(enableWideCopyDma=true)) { d=>
      init(d)
      val wide=d.io.wideAxi.get
      val mem=mutable.Map.empty[Long,Int].withDefaultValue(0x5a)
      val src=0x02400ff0L;val dst=0x02000fe0L
      for(i<-0 until 4096)mem(src+i)=(i*31+7)&255
      mem(0x02500000L)=0x1f;mem(0x02500001L)=0xf8
      mem(0x02500002L)=0x34;mem(0x02500003L)=0x12
      val wr=mutable.Queue.empty[(Long,Int)];val ww=mutable.Queue.empty[(Long,Int)];val wb=mutable.Queue.empty[Int]
      val nr=mutable.Queue.empty[(Long,Int,Int)];val nw=mutable.Queue.empty[(Long,Int,Int)];val nb=mutable.Queue.empty[(Int,Int)]
      var rwi=0;var wwi=0;var nri=0;var nwi=0;var submitted=0;var complete=0;var cycle=0
      var readBytes=0;var writeBytes=0;var wideReads=0;var wideWrites=0
      while(complete<5 && cycle<12000) {
        d.io.command.valid.poke(submitted<5)
        val c=d.io.command.bits;c.poke(0.U.asTypeOf(new GpuCommand))
        c.op.poke(Seq(GpuOpcode.Copy,GpuOpcode.Fill,GpuOpcode.ColorKey,GpuOpcode.Alpha,GpuOpcode.Present)(submitted.min(4)))
        c.tag.poke(100+submitted);c.srcAddr.poke(if(submitted==0)src else 0x02500000L)
        c.dstAddr.poke(if(submitted==0)BigInt(dst) else if(submitted==4)GpuMemoryMap.FramebufferB else BigInt(0x02100000L+submitted*16))
        c.widthPixels.poke(if(submitted==0)256 else 2);c.heightPixels.poke(if(submitted==0)8 else 1)
        c.srcStride.poke(if(submitted==0)512 else 4);c.dstStride.poke(if(submitted==0)512 else 4)
        c.color.poke(0xf800);c.colorKey.poke(0xf81f);c.alpha.poke(255)
        wide.ar.ready.poke(cycle%4!=0);wide.aw.ready.poke(cycle%7!=0);wide.w.ready.poke(cycle%5!=0)
        wide.r.valid.poke(wr.nonEmpty);wide.r.bits.last.poke(wr.headOption.exists(t=>rwi==t._2-1))
        wide.r.bits.data.poke(wr.headOption.map(t=>(0 until 16).foldLeft(BigInt(0))((v,b)=>v|(BigInt(mem(t._1+rwi*16+b))<<(8*b)))).getOrElse(BigInt(0)))
        wide.b.valid.poke(wb.headOption.exists(_<=cycle))
        d.io.axi.ar.ready.poke(nr.isEmpty);d.io.axi.aw.ready.poke(cycle%3!=0);d.io.axi.w.ready.poke(cycle%4!=0)
        d.io.axi.r.valid.poke(nr.nonEmpty);d.io.axi.r.bits.last.poke(nr.headOption.exists(t=>nri==t._2-1))
        d.io.axi.r.bits.id.poke(nr.headOption.map(_._3).getOrElse(0))
        d.io.axi.r.bits.data.poke(nr.headOption.map(t=>(0 until 4).foldLeft(BigInt(0))((v,b)=>v|(BigInt(mem(t._1+nri*4+b))<<(8*b)))).getOrElse(BigInt(0)))
        d.io.axi.b.valid.poke(nb.headOption.exists(_._1<=cycle));d.io.axi.b.bits.id.poke(nb.headOption.map(_._2).getOrElse(0))
        def fire(v:Bool,r:Bool)=yes(v)&&yes(r)
        val cf=fire(d.io.command.valid,d.io.command.ready)
        val wrf=fire(wide.r.valid,wide.r.ready);val nrf=fire(d.io.axi.r.valid,d.io.axi.r.ready)
        if(fire(wide.ar.valid,wide.ar.ready)){wr.enqueue((wide.ar.bits.addr.peek().litValue.longValue,wide.ar.bits.len.peek().litValue.toInt+1));wideReads+=1}
        if(fire(wide.aw.valid,wide.aw.ready)){ww.enqueue((wide.aw.bits.addr.peek().litValue.longValue,wide.aw.bits.len.peek().litValue.toInt+1));wideWrites+=1}
        if(fire(wide.w.valid,wide.w.ready)) {
          val(a,n)=ww.head;val data=wide.w.bits.data.peek().litValue
          for(b<-0 until 16)mem(a+wwi*16+b)=((data>>(8*b))&255).toInt
          writeBytes+=16;wwi+=1;if(wwi==n){ww.dequeue();wwi=0;wb.enqueue(cycle+90)}
        }
        if(fire(wide.b.valid,wide.b.ready))wb.dequeue()
        if(fire(d.io.axi.ar.valid,d.io.axi.ar.ready)) {
          assert(complete>0 && wr.isEmpty && ww.isEmpty && wb.isEmpty,"pixel read before wide Copy completion")
          nr.enqueue((d.io.axi.ar.bits.addr.peek().litValue.longValue,d.io.axi.ar.bits.len.peek().litValue.toInt+1,d.io.axi.ar.bits.id.peek().litValue.toInt))
        }
        if(fire(d.io.axi.aw.valid,d.io.axi.aw.ready)) {
          assert(complete>0 && wr.isEmpty && ww.isEmpty && wb.isEmpty,"pixel write before final wide B")
          nw.enqueue((d.io.axi.aw.bits.addr.peek().litValue.longValue,d.io.axi.aw.bits.len.peek().litValue.toInt+1,d.io.axi.aw.bits.id.peek().litValue.toInt))
        }
        if(fire(d.io.axi.w.valid,d.io.axi.w.ready)) {
          val(a,n,id)=nw.head;val data=d.io.axi.w.bits.data.peek().litValue;val st=d.io.axi.w.bits.strb.peek().litValue.toInt
          for(b<-0 until 4 if (st&(1<<b))!=0){mem(a+nwi*4+b)=((data>>(8*b))&255).toInt;writeBytes+=1}
          nwi+=1;if(nwi==n){nw.dequeue();nwi=0;nb.enqueue((cycle+20,id))}
        }
        if(fire(d.io.axi.b.valid,d.io.axi.b.ready))nb.dequeue()
        if(yes(d.io.completion.valid)) {
          d.io.completion.bits.tag.expect(100+complete);d.io.completion.bits.error.expect(0)
          assert(wr.isEmpty && ww.isEmpty && wb.isEmpty && nr.isEmpty && nw.isEmpty && nb.isEmpty)
          complete+=1
        }
        d.clock.step();if(cf)submitted+=1
        if(wrf){readBytes+=16;rwi+=1;if(rwi==wr.head._2){wr.dequeue();rwi=0}}
        if(nrf){readBytes+=4;nri+=1;if(nri==nr.head._2){nr.dequeue();nri=0}}
        cycle+=1
      }
      complete shouldBe 5;assert(wideReads>=4 && wideWrites==wideReads)
      for(i<-0 until 4096)mem(dst+i) shouldBe mem(src+i)
      mem(dst-1) shouldBe 0x5a;mem(dst+4096) shouldBe 0x5a
      mem(0x02100010L) shouldBe 0;mem(0x02100011L) shouldBe 0xf8
      mem(0x02100020L) shouldBe 0x5a;mem(0x02100022L) shouldBe 0x34
      mem(0x02100030L) shouldBe 0x1f;mem(0x02100032L) shouldBe 0x34
      d.io.perfPixels.expect(2054);d.io.perfReadBytes.expect(readBytes);d.io.perfWriteBytes.expect(writeBytes)
      d.io.frontBase.expect(GpuMemoryMap.FramebufferB)
    }
  }
  it("drains a stalled AW across GPU reset, blocks re-entry until final B and never returns the old tag") {
    simulate(new RenderEngine(enableWideCopyDma=true)) { d=>
      init(d)
      val w=d.io.wideAxi.get
      val reads=mutable.Queue.empty[Int]
      val word=BigInt("fedcba98765432100123456789abcdef",16)
      var ri=0;var wc=0;var wlen=0;var bd= -1;var cycle=0
      var first=false;var restart=false;var resetAt= -1;var completed=false;var lastB=false
      while(!completed && cycle<2200) {
        d.io.command.valid.poke(!first || (resetAt>=0 && cycle>resetAt+3 && !restart))
        val c=d.io.command.bits;c.poke(0.U.asTypeOf(new GpuCommand))
        c.op.poke(if(first)GpuOpcode.Present else GpuOpcode.Copy)
        c.tag.poke(if(first)222 else 111)
        c.srcAddr.poke(0x02400000);c.dstAddr.poke(if(first)GpuMemoryMap.FramebufferB else GpuMemoryMap.FramebufferA)
        c.widthPixels.poke(if(first)1 else 256);c.heightPixels.poke(if(first)1 else 8)
        c.srcStride.poke(if(first)2 else 512);c.dstStride.poke(if(first)2 else 512)
        w.ar.ready.poke(true);w.aw.ready.poke(resetAt>=0 && cycle>resetAt+3);w.w.ready.poke(cycle%4!=0)
        w.r.valid.poke(reads.nonEmpty);w.r.bits.data.poke(word);w.r.bits.last.poke(reads.headOption.exists(_==ri+1))
        w.b.valid.poke(bd>=0 && cycle>=bd)
        if(resetAt<0 && yes(w.aw.valid)){resetAt=cycle}
        d.reset.poke(resetAt>=0 && cycle<resetAt+3)
        if(resetAt>=0 && !lastB && cycle>resetAt+3)d.io.command.ready.expect(false)
        def fire(v:Bool,r:Bool)=yes(v)&&yes(r)
        val rf=fire(w.r.valid,w.r.ready)
        if(fire(d.io.command.valid,d.io.command.ready)){if(!first)first=true else restart=true}
        if(fire(w.ar.valid,w.ar.ready))reads.enqueue(w.ar.bits.len.peek().litValue.toInt+1)
        if(fire(w.aw.valid,w.aw.ready)){assert(wlen==0);wlen=w.aw.bits.len.peek().litValue.toInt+1}
        if(fire(w.w.valid,w.w.ready)){w.w.bits.data.expect(word);wc+=1;w.w.bits.last.expect(wc==wlen);if(wc==wlen)bd=cycle+40}
        if(fire(w.b.valid,w.b.ready)){lastB=true;bd= -1}
        if(yes(d.io.completion.valid)) {
          assert(lastB && restart && reads.isEmpty)
          d.io.completion.bits.tag.expect(222);d.io.completion.bits.error.expect(0);completed=true
        }
        d.clock.step();if(rf){ri+=1;if(ri==reads.head){reads.dequeue();ri=0}}
        cycle+=1
      }
      assert(completed && resetAt>=0);wc shouldBe 64
    }
  }
}
