package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import testutil.StableChiselSim

/** Breaks caught: per-row AR instead of packed read; Key masking on Copy;
  * wrong halfword strobes; two engines claiming contiguous Copy; early retirement
  * or deadlock on failed reads/B; consuming DDR beats through cache-only mux. */
class SmallCopyPrefetchSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private case class Shape(w:Int=14,h:Int=18,stride:Int=1920,src:Long=0x02400000L,dst:Long=0x02000100L)
  private case class Result(cycles:Int,reads:Int,writes:Int,overlap:Boolean,peakWrites:Int)
  private def init(d:RenderEngine):Unit = {
    d.io.command.valid.poke(false);d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
    d.io.completion.ready.poke(true);d.io.vblank.poke(false);d.io.perfClear.poke(false)
    d.io.underflowPulse.poke(false);d.io.renderGrant.poke(0);d.io.scanoutGrant.poke(0)
    d.io.textureCacheLoad.valid.poke(false);d.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
    d.io.textureCacheInvalidate.poke(false)
    d.io.axi.ar.ready.poke(false);d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false)
    d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
    d.clock.step()
  }
  private def run(d:RenderEngine,s:Shape,tag:Int,fault:Int=0,cached:Boolean=false,bDelay:Int=80):Result = {
    val mem=mutable.Map.empty[Long,Int].withDefaultValue(0x5a)
    // Deliberately includes transparent-key magenta: Copy MUST still write it.
    val pixels=Vector.tabulate(s.w*s.h)(i=>if(i%5==0)0xf81f else (i*37+0x1234)&65535)
    for(i<-pixels.indices;l<-0 until 2)mem(s.src+i*2+l)=(pixels(i)>>(8*l))&255
    val beforePixels=d.io.perfPixels.peek().litValue
    if(cached) {
      d.io.textureCacheLoad.valid.poke(true);d.io.textureCacheLoad.bits.base.poke(s.src)
      d.io.textureCacheLoad.bits.bytes.poke(s.w*s.h*2);d.clock.step()
      d.io.textureCacheLoad.valid.poke(false)
    }
    val writes=mutable.Queue.empty[(Long,Int)]
    val replies=mutable.Queue.empty[Int]
    var ra=0L;var rLeft=0;var rId=0;var wOffset=0
    var submitted=0;var completed=0;var cycles=0;var arCount=0;var awCount=0
    var bCount=0;var rCount=0;var copyReads=0;var copyWrites=0;var overlap=false
    var peakWrites=0
    while(completed<4 && cycles<16000) {
      d.io.command.valid.poke(submitted<4 && (!cached || d.io.textureCacheValid.peek().litToBoolean))
      d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
      d.io.command.bits.op.poke(Seq(GpuOpcode.Copy,GpuOpcode.Fill,GpuOpcode.ColorKey,GpuOpcode.Alpha)(submitted.min(3)))
      d.io.command.bits.tag.poke(tag+submitted)
      d.io.command.bits.srcAddr.poke(if(submitted==0)s.src else if(submitted==1)0L else s.src)
      d.io.command.bits.dstAddr.poke(if(submitted==0)s.dst else 0x02100000L+submitted*0x100L)
      val followingWidth=if(cached && submitted==2)2 else 1
      d.io.command.bits.widthPixels.poke(if(submitted==0)s.w else followingWidth)
      d.io.command.bits.heightPixels.poke(if(submitted==0)s.h else 1)
      d.io.command.bits.srcStride.poke(if(submitted==0)s.w*2 else followingWidth*2)
      d.io.command.bits.dstStride.poke(if(submitted==0)s.stride else followingWidth*2)
      d.io.command.bits.colorKey.poke(0xf81f);d.io.command.bits.color.poke(0xf800);d.io.command.bits.alpha.poke(255)
      d.io.axi.ar.ready.poke(rLeft==0 && cycles%5!=2)
      d.io.axi.r.valid.poke(rLeft>0 && cycles%3!=1)
      d.io.axi.r.bits.id.poke(if(fault==2 && completed==0)1 else rId)
      d.io.axi.r.bits.resp.poke(if(fault==1 && completed==0 && rCount==3)2 else 0)
      val early=fault==5 && completed==0 && rCount==3
      d.io.axi.r.bits.last.poke(rLeft==1 || early)
      d.io.axi.r.bits.data.poke((0 until 4).foldLeft(BigInt(0))((v,l)=>v|(BigInt(mem(ra+l))<<(8*l))))
      d.io.axi.aw.ready.poke(cycles%7!=3);d.io.axi.w.ready.poke(cycles%5!=1)
      val bv=replies.headOption.exists(_<=cycles)
      d.io.axi.b.valid.poke(bv);d.io.axi.b.bits.id.poke(if(fault==6 && bCount==0)1 else 0)
      d.io.axi.b.bits.resp.poke(if((fault==3 && bCount==0)||(fault==4 && bCount==1))2 else 0)
      def fire(v:Bool,r:Bool):Boolean=v.peek().litToBoolean && r.peek().litToBoolean
      val cf=fire(d.io.command.valid,d.io.command.ready)
      val rf=fire(d.io.axi.r.valid,d.io.axi.r.ready)
      if(fire(d.io.axi.ar.valid,d.io.axi.ar.ready)) {
        ra=d.io.axi.ar.bits.addr.peek().litValue.longValue
        rLeft=d.io.axi.ar.bits.len.peek().litValue.toInt+1;rId=d.io.axi.ar.bits.id.peek().litValue.toInt
        arCount+=1;if(completed==0 && (!cached || d.io.textureCacheValid.peek().litToBoolean))copyReads+=1
      }
      if(fire(d.io.axi.aw.valid,d.io.axi.aw.ready)) {
        val a=d.io.axi.aw.bits.addr.peek().litValue.longValue
        val n=d.io.axi.aw.bits.len.peek().litValue.toInt+1
        assert((a&4095L)+4*n<=4096,"AW crossed 4KiB")
        if(a>=0x02100100L)assert(completed>0 && rLeft==0 && writes.isEmpty && replies.isEmpty,"following command before drain")
        if(completed==0){copyWrites+=1;if(awCount>bCount)overlap=true}
        awCount+=1;peakWrites=math.max(peakWrites,awCount-bCount);writes.enqueue((a,n))
      }
      if(fire(d.io.axi.w.valid,d.io.axi.w.ready)) {
        assert(writes.nonEmpty);val(a,n)=writes.head
        val word=d.io.axi.w.bits.data.peek().litValue;val strb=d.io.axi.w.bits.strb.peek().litValue.toInt
        for(l<-0 until 4 if (strb&(1<<l))!=0)mem(a+4*wOffset+l)=((word>>(8*l))&255).toInt
        d.io.axi.w.bits.last.expect(wOffset==n-1);wOffset+=1
        if(wOffset==n){writes.dequeue();wOffset=0;replies.enqueue(cycles+bDelay)}
      }
      if(bv && d.io.axi.b.ready.peek().litToBoolean){replies.dequeue();bCount+=1}
      if(d.io.completion.valid.peek().litToBoolean) {
        d.io.completion.bits.tag.expect(tag+completed)
        d.io.completion.bits.error.expect(if(fault!=0 && completed==0)GpuError.AxiResponse else GpuError.None)
        assert(writes.isEmpty && replies.isEmpty && rLeft==0 && bCount==awCount,"completion before all channels drained")
        completed+=1
      }
      d.clock.step();if(cf)submitted+=1
      if(rf){ra+=4;rLeft-=1;rCount+=1}
      cycles+=1
    }
    completed shouldBe 4
    if(fault==0) {
      for(y<-0 until s.h;b<- -2 until s.w*2+2) {
        val want=if(b<0 || b>=s.w*2)0x5a else (pixels(y*s.w+b/2)>>((b&1)*8))&255
        // In contiguous Copy, neighboring rows occupy the nominal guard.
        if(s.stride>s.w*2 || (y==0 && b<0) || (y==s.h-1 && b>=s.w*2) || (b>=0 && b<s.w*2))
          mem(s.dst+y*s.stride+b) shouldBe want
      }
      (d.io.perfPixels.peek().litValue-beforePixels) shouldBe BigInt(s.w*s.h+(if(cached)4 else 3))
    }
    mem(0x02100100L) shouldBe 0;mem(0x02100101L) shouldBe 0xf8
    mem(0x02100200L) shouldBe 0x5a;mem(0x02100201L) shouldBe 0x5a // Key skips magenta
    if(cached) {mem(0x02100202L) shouldBe 0x59;mem(0x02100203L) shouldBe 0x12}
    mem(0x02100300L) shouldBe 0x1f;mem(0x02100301L) shouldBe 0xf8 // Alpha255 copies magenta
    Result(cycles,copyReads,copyWrites,overlap,peakWrites)
  }
  it("copies packed strided glyphs once, preserves every lane and beats legacy retirement") {
    val cycles=Seq(false,true).map { enabled =>
      var result:Result=null
      simulate(new RenderEngine(enableKeyPrefetch=true,enableKeyWritePipeline=true,enableSmallCopyPrefetch=enabled)) { d =>
        init(d);result=run(d,Shape(),10)
        result.reads shouldBe (if(enabled)1 else 18);result.writes shouldBe 18
        if(enabled)assert(result.overlap)
        run(d,Shape(8,32,1922,dst=0x02000ffeL),20).reads shouldBe (if(enabled)1 else 32)
        run(d,Shape(src=0x02400ffcL),30).reads shouldBe (if(enabled)2 else 19)
        run(d,Shape(h=33),40).reads shouldBe 33
        run(d,Shape(src=0x02400002L),50).reads shouldBe 18
        run(d,Shape(w=13),60).reads shouldBe 18
        val contiguous=run(d,Shape(stride=28),70)
        contiguous.reads shouldBe 1;contiguous.writes shouldBe 1
      }
      result.cycles
    }
    cycles(1) should be < cycles(0)
    info(s"14x18 Copy with delayed B: legacy=${cycles(0)}, prefetch=${cycles(1)}")
  }
  it("drains failed DDR reads and both outstanding writes before the next Fill, Key and Alpha") {
    simulate(new RenderEngine(enableKeyPrefetch=true,enableKeyWritePipeline=true,enableSmallCopyPrefetch=true)) { d =>
      init(d)
      for(fault<-1 to 6)run(d,Shape(),100+fault*10,fault)
      run(d,Shape(),200).reads shouldBe 1
    }
  }
  it("keeps cached Key and Alpha reads exclusive from the new DDR Copy path") {
    simulate(new RenderEngine(enableKeyPrefetch=true,enableKeyWritePipeline=true,enableSmallCopyPrefetch=true)) { d =>
      init(d);run(d,Shape(),220,cached=true).reads shouldBe 1
      d.io.perfCacheBytes.expect(8) // One 32-bit cache word for Key, one for Alpha.
    }
  }
  it("uses four credits without early retirement across Copy, cached Key, Alpha and response faults") {
    val results=Seq(2,4).map { credits =>
      var result:Result=null
      simulate(new RenderEngine(enableKeyPrefetch=true,enableKeyWritePipeline=true,
        enableSmallCopyPrefetch=true,writeCredits=credits)) { d =>
        init(d);result=run(d,Shape(),300,cached=true,bDelay=180)
        result.peakWrites shouldBe credits; result.reads shouldBe 1
        if(credits==4) {
          run(d,Shape(8,32,1922,dst=0x02000ffeL),310,bDelay=180)
          for(fault<-1 to 6)run(d,Shape(),320+fault*10,fault,bDelay=180)
          run(d,Shape(),400,cached=true,bDelay=180)
        }
      }
      result.cycles
    }
    results(1) should be < results(0)
    info(s"same delayed-B Copy: two=${results(0)}, four=${results(1)}")
  }
}
