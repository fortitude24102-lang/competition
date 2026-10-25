package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Real pixel RTL + AXI byte memory: catches skewed metadata, early completion,
  * lost halfwords/chunk tails and accidental writes beyond the rectangle. */
class AlphaPipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private case class Trace(cycles: Int, reads: Vector[(Int, Long, Int)],
    writes: Vector[(Long, Int)], data: Vector[(BigInt, BigInt, Boolean)], prefetchedRows:Int,
    earlyRows:Int)
  private def run(enabled: Boolean, width: Int, phase: Int, stalls: Boolean,
                  fault: Int = 0, cached: Boolean = false, rowPrefetch:Boolean=false,
                  height:Int=2, bDelay:Int=0, sourceStride:Int=0, destinationStride:Int=0,
                  recoverAlpha:Boolean=false, inPlace:Boolean=false,
                  earlyPrefetch:Boolean=false, rDelay:Int=0, reuse:Option[RenderEngine]=None): Trace = {
    var elapsed = 0
    var result = Option.empty[Trace]
    def execute(d:RenderEngine):Unit = withClue(s"width=$width height=$height phase=$phase cached=$cached fault=$fault early=$earlyPrefetch: ") {
      val mem = collection.mutable.Map.empty[Long, Int].withDefaultValue(0x5a)
      val src = GpuMemoryMap.DenseAssets.toLong + phase
      val dst = if(inPlace)src else GpuMemoryMap.FramebufferA.toLong + phase
      val srcStride=if(sourceStride!=0)sourceStride else width*2+6
      val dstStride=if(destinationStride!=0)destinationStride else width*2+6
      val fg = Seq(0xf800, 0x07e0, 0x001f, 0xffff, 0, 0x1234)
      val bg = Seq(0x001f, 0xf800, 0x07e0, 0, 0xffff, 0xabcd)
      // Literal independently hand-checked per-channel alpha=128 / 255 rounded.
      val expected = Seq(0x800f, 0x7c00, 0x03f0, 0x8410, 0x7bef, 0x5af1)
      def put(a: Long, p: Int): Unit = { mem(a) = p & 255; mem(a + 1) = p >> 8 }
      def half(a: Long): Int = mem(a) | mem(a + 1) << 8
      def word(a: Long): Long = (0 until 4).foldLeft(0L)((v, b) => v | mem(a+b).toLong << (8*b))
      for (y <- 0 until height; x <- 0 until width) {
        val i = (y * width + x) % fg.size
        put(src + y*srcStride + x*2, fg(i))
        if(!inPlace)put(dst + y*dstStride + x*2, bg(i))
      }
      if(recoverAlpha)put(dst+0x2000,0x001f)
      case class Read(id: Int, var addr: Long, var beats: Int, due:Int)
      val reads = collection.mutable.Queue.empty[Read]
      val arTrace = collection.mutable.ArrayBuffer.empty[(Int, Long, Int)]
      val awTrace = collection.mutable.ArrayBuffer.empty[(Long, Int)]
      val wTrace = collection.mutable.ArrayBuffer.empty[(BigInt, BigInt, Boolean)]
      var submitted = 0
      var retired = 0
      var writeAddr = 0L
      var writeLeft = 0
      var bPending = false
      var bDue = 0
      var readBlockedUntil = 0
      var prefetchedRows = 0
      var earlyRows = 0
      var earlyBehindPriorB = 0
      var readFaultSent = false
      var bCount = 0
      var awCount = 0
      var wCount = 0
      var loadSent = false
      val random = new scala.util.Random(7471)
      var heldW = Option.empty[(BigInt, BigInt, Boolean)]
      def ready: Boolean = !stalls || random.nextBoolean()
      d.io.perfClear.poke(false); d.io.underflowPulse.poke(false)
      d.io.renderGrant.poke(0); d.io.scanoutGrant.poke(0)
      d.io.textureCacheLoad.valid.poke(false); d.io.textureCacheInvalidate.poke(false)
      d.io.vblank.poke(false)
      val commands=if(recoverAlpha)3 else 2
      while (retired < commands && elapsed < 2000+height*bDelay*4) {
        // Alpha followed by Fill catches stale metadata/error propagation.
        val c = d.io.command.bits
        d.io.textureCacheLoad.valid.poke(cached && !loadSent)
        d.io.textureCacheLoad.bits.base.poke(src & ~3L)
        d.io.textureCacheLoad.bits.bytes.poke(((height*srcStride+(phase&3)+3)/4)*4)
        d.io.command.valid.poke(submitted < commands && (!cached || d.io.textureCacheValid.peek().litToBoolean))
        c.poke(0.U.asTypeOf(new GpuCommand))
        c.op.poke(if(submitted == 1) GpuOpcode.Fill else GpuOpcode.Alpha)
        c.srcAddr.poke(src); c.dstAddr.poke(if(submitted == 0) dst else dst+submitted*0x1000)
        c.srcStride.poke(srcStride); c.dstStride.poke(dstStride)
        c.widthPixels.poke(if(submitted == 0) width else 1)
        c.heightPixels.poke(if(submitted == 0) height else 1)
        c.alpha.poke(128); c.color.poke(0x1357); c.tag.poke(submitted + 1)
        d.io.completion.ready.poke(ready)
        d.io.axi.ar.ready.poke(ready) // Independent of AW/W: do not hide early reads.
        d.io.axi.aw.ready.poke(ready && writeLeft == 0 && !bPending)
        d.io.axi.w.ready.poke(ready)
        val waitForRow1Write = fault==7 && awCount<2 && reads.headOption.exists(r =>
          r.id==1 && r.addr>=((dst+2*dstStride)& ~3L))
        val offerR = reads.nonEmpty && ready && elapsed>=readBlockedUntil && elapsed>=reads.front.due && !waitForRow1Write
        d.io.axi.r.valid.poke(offerR)
        d.io.axi.r.bits.id.poke(reads.headOption.map(_.id).getOrElse(0))
        d.io.axi.r.bits.data.poke(reads.headOption.map(r=>word(r.addr)).getOrElse(0L))
        d.io.axi.r.bits.last.poke(reads.headOption.exists(_.beats == 1))
        val badR = !readFaultSent && reads.headOption.exists { r =>
          (fault==1 && r.id==1) ||
          (fault==5 && r.id==1 && r.addr>=((dst+dstStride)& ~3L)) ||
          (fault==6 && r.id==0 && r.addr>=((src+srcStride)& ~3L)) ||
          (fault==7 && r.id==1 && r.addr>=((dst+2*dstStride)& ~3L))
        }
        d.io.axi.r.bits.resp.poke(if(badR) 2 else 0)
        d.io.axi.b.valid.poke(bPending && ready && elapsed>=bDue)
        d.io.axi.b.bits.id.poke(if(fault==4 && bCount==0)1 else 0)
        d.io.axi.b.bits.resp.poke(if((fault == 2 || fault==3) && bCount == 0) 2 else 0)
        if(bPending)d.io.axi.aw.valid.expect(false) // Still a single-write engine.
        def fires(p: chisel3.util.DecoupledIO[_]): Boolean = p.valid.peek().litToBoolean && p.ready.peek().litToBoolean
        val cf = fires(d.io.command); val done = fires(d.io.completion)
        val ar = fires(d.io.axi.ar); val rr = fires(d.io.axi.r)
        val aw = fires(d.io.axi.aw); val ww = fires(d.io.axi.w); val bb = fires(d.io.axi.b)
        val w = (d.io.axi.w.bits.data.peek().litValue, d.io.axi.w.bits.strb.peek().litValue,
          d.io.axi.w.bits.last.peek().litToBoolean)
        heldW.foreach { previous => d.io.axi.w.valid.expect(true); w shouldBe previous }
        heldW = if(d.io.axi.w.valid.peek().litToBoolean && !d.io.axi.w.ready.peek().litToBoolean) Some(w) else None
        val nextRead = if(ar) Some(Read(d.io.axi.ar.bits.id.peek().litValue.toInt,
          d.io.axi.ar.bits.addr.peek().litValue.toLong, d.io.axi.ar.bits.len.peek().litValue.toInt + 1,
          elapsed+rDelay)) else None
        val nextWrite = if(aw) Some((d.io.axi.aw.bits.addr.peek().litValue.toLong,
          d.io.axi.aw.bits.len.peek().litValue.toInt + 1)) else None
        nextRead.foreach { r =>
          if(r.id==1 && (1 until height).exists(y=>r.addr==((dst+y*dstStride)& ~3L) &&
              d.io.perfPixels.peek().litValue.toInt < y*width))earlyRows+=1
          if(r.id==1 && r.addr==((dst+2*dstStride)& ~3L) && bPending && awCount==1)earlyBehindPriorB+=1
          if(r.id==1 && (1 until height).exists(y=>r.addr==((dst+y*dstStride)& ~3L)) && bPending) {
            prefetchedRows+=1
            if(fault==3)readBlockedUntil=elapsed+80 // Bad previous B arrives before these R beats.
          }
          if(fault==3 && earlyPrefetch && r.id==1 &&
              (1 until height).exists(y=>r.addr==((dst+y*dstStride)& ~3L)))readBlockedUntil=elapsed+80
        }
        if(width > 64 && d.io.axi.ar.valid.peek().litToBoolean) {
          val address = d.io.axi.ar.bits.addr.peek().litValue.toLong
          for(y <- 0 until height; (base,stride) <- Seq((src,srcStride),(dst,dstStride))
              if address == ((base+y*stride+128) & ~3L)) {
            withClue(s"early next-chunk AR at $address: ") {
              d.io.perfPixels.peek().litValue.toInt should be >= (y*width+64)
            }
          }
        }
        nextRead.foreach(r => arTrace += ((r.id,r.addr,r.beats)))
        nextWrite.foreach(awTrace += _)
        if(ww) {
          wTrace += w
          writeLeft should be > 0
          w._3 shouldBe (writeLeft == 1)
          for(b <- 0 until 4 if w._2.testBit(b)) mem(writeAddr+b) = ((w._1 >> (8*b)) & 255).toInt
        }
        if(done) {
          withClue(s"pipeline=$enabled width=$width phase=$phase fault=$fault retiring=$retired cycle=$elapsed: ") {
            reads shouldBe empty; writeLeft shouldBe 0; bPending shouldBe false
          }
          d.io.completion.bits.tag.expect(retired + 1)
          d.io.completion.bits.error.expect(if(retired == 0 && fault != 0) GpuError.AxiResponse else 0)
        }
        d.clock.step(); elapsed += 1
        loadSent = true
        if(cf) submitted += 1
        if(done) retired += 1
        if(rr) { if(badR) readFaultSent=true; val r=reads.front; r.addr+=4; r.beats-=1; if(r.beats==0) reads.dequeue() }
        nextRead.foreach(reads.enqueue(_))
        if(bb) { bPending=false; bCount+=1 }
        if(ww) { wCount+=1; writeAddr+=4; writeLeft-=1; if(writeLeft==0){bPending=true;bDue=elapsed+bDelay} }
        nextWrite.foreach { case(a,n) => awCount+=1; writeAddr=a; writeLeft=n }
      }
      withClue(s"pipeline=$enabled width=$width phase=$phase fault=$fault cached=$cached reads=${reads.size} writeLeft=$writeLeft bPending=$bPending elapsed=$elapsed: ") {
        retired shouldBe commands
      }
      if(fault == 0) for(y <- 0 until height; x <- 0 until width)
        half(dst+y*dstStride+x*2) shouldBe (if(inPlace)fg((y*width+x)%fg.size) else expected((y*width+x)%expected.size))
      for(y <- 0 until height) {
        if(dstStride>width*2) {
          half(dst+y*dstStride-2) shouldBe 0x5a5a
          for(x <- 0 until math.min(3,(dstStride-width*2)/2)) half(dst+y*dstStride+width*2+x*2) shouldBe 0x5a5a
        }
      }
      half(dst+0x1000) shouldBe 0x1357
      if(recoverAlpha)half(dst+0x2000) shouldBe 0x800f
      if(fault==3 && rowPrefetch)readBlockedUntil should be > 0 // Exercise R still stalled when bad B retires.
      if(fault==7) {earlyBehindPriorB should be > 0;readFaultSent shouldBe true}
      if(fault!=0 && rowPrefetch)awCount shouldBe commands+(if(fault==7)1 else 0) // No abandoned lookahead row is written.
      d.io.perfPixels.expect((if(fault == 0) width*height else if(fault==7)width*2 else width) + commands-1)
      if(cached && width==16 && height==2 && !recoverAlpha)d.io.perfCacheBytes.expect(68)
      if(width == 16 && height == 2 && phase == 0 && fault == 0 && !cached) {
        // Identical work and bus traffic for both sides of the cycle comparison.
        d.io.perfReadBytes.expect(136); d.io.perfWriteBytes.expect(66)
        awCount shouldBe 3; wCount shouldBe 18; bCount shouldBe 3
      }
      result = Some(Trace(elapsed, arTrace.toVector, awTrace.toVector, wTrace.toVector,prefetchedRows,earlyRows))
    }
    reuse match {
      case Some(d) =>
        // Each preceding fixture proved all R/W/B drained before retiring.
        // Reuse the compiled circuit, with common reset and fresh byte memory.
        d.reset.poke(true.B);d.clock.step(3);d.reset.poke(false.B);execute(d)
      case None => simulate(new RenderEngine(enableAlphaPipeline=enabled,enableAlphaRowPrefetch=rowPrefetch,
        enableAlphaEarlyPrefetch=earlyPrefetch)) { d => execute(d) }
    }
    result.get
  }

  it("reduces Alpha cycles with identical real-RTL pixels and no transaction reordering") {
    val old = run(false, 16, 0, false)
    val candidate = run(true, 16, 0, false)
    println(s"ALPHA_PIPELINE,legacy=${old.cycles},candidate=${candidate.cycles}")
    // Foreground and background have independent IDs; their relative AR
    // arbitration is not part of the contract. Order within each ID is.
    candidate.reads.groupBy(_._1) shouldBe old.reads.groupBy(_._1)
    candidate.writes shouldBe old.writes
    candidate.data shouldBe old.data
    candidate.cycles should be < old.cycles
  }
  it("keeps odd tails, halfword phases and 64-pixel chunk boundaries under stalls") {
    simulate(new RenderEngine(enableAlphaPipeline=true)) { d =>
      for(w <- Seq(1,3,65); phase <- Seq(0,2)) run(true,w,phase,true,reuse=Some(d))
      run(true,16,2,true,cached=true,reuse=Some(d))
    }
  }
  it("matches stalled cross-chunk AXI traces without reading ahead of the prior pixel tail") {
    val old = run(false,65,2,true)
    val candidate = run(true,65,2,true)
    candidate.reads.groupBy(_._1) shouldBe old.reads.groupBy(_._1)
    candidate.writes shouldBe old.writes
    candidate.data shouldBe old.data
  }
  it("drains read/write failures and retires the following Fill without stale metadata") {
    for(enabled <- Seq(false,true))simulate(new RenderEngine(enableAlphaPipeline=enabled)) { d =>
      for(fault <- Seq(1,2)) run(enabled,3,2,true,fault,reuse=Some(d))
    }
  }
  it("row prefetch overlaps delayed B with next-row reads and preserves the same pixels and traffic") {
    val old=run(true,12,0,false,cached=true,height=12,bDelay=24,sourceStride=24,destinationStride=1920)
    val next=run(true,12,0,false,cached=true,rowPrefetch=true,height=12,bDelay=24,sourceStride=24,destinationStride=1920)
    old.prefetchedRows shouldBe 0; next.prefetchedRows should be > 0
    next.reads.groupBy(_._1) shouldBe old.reads.groupBy(_._1)
    next.writes shouldBe old.writes; next.data shouldBe old.data
    next.cycles should be < old.cycles
    info(s"ALPHA_ROW_PREFETCH,legacy=${old.cycles},prefetch=${next.cycles}")
  }
  it("early row prefetch overlaps next-row latency with current pixels without changing traffic") {
    val old=run(true,12,0,false,cached=true,rowPrefetch=true,height=12,
      sourceStride=24,destinationStride=1920,rDelay=24)
    val next=run(true,12,0,false,cached=true,rowPrefetch=true,height=12,
      sourceStride=24,destinationStride=1920,rDelay=24,earlyPrefetch=true)
    old.earlyRows shouldBe 0; next.earlyRows should be > 0
    next.reads.groupBy(_._1) shouldBe old.reads.groupBy(_._1)
    next.writes shouldBe old.writes; next.data shouldBe old.data
    next.cycles should be < old.cycles
    info(s"ALPHA_EARLY_PREFETCH,old=${old.cycles},early=${next.cycles},rows=${next.earlyRows}")
  }
  it("row prefetch drains failed lookahead and leaves the following Alpha clean") {
    simulate(new RenderEngine(enableAlphaPipeline=true,enableAlphaRowPrefetch=true)) { d =>
      for(fault<-Seq(1,2,3,4,5))run(true,3,2,true,fault,cached=true,rowPrefetch=true,bDelay=24,recoverAlpha=true,reuse=Some(d))
      run(true,3,2,true,6,rowPrefetch=true,bDelay=24,recoverAlpha=true,reuse=Some(d))
      run(true,3,4094,true,rowPrefetch=true,bDelay=24,recoverAlpha=true,reuse=Some(d))
      run(true,12,2,true,cached=true,rowPrefetch=true,height=4,bDelay=24,sourceStride=24,destinationStride=1920,recoverAlpha=true,reuse=Some(d))
    }
  }
  it("row prefetch keeps wide and in-place Alpha on the original row schedule") {
    simulate(new RenderEngine(enableAlphaPipeline=true,enableAlphaRowPrefetch=true)) { d =>
      run(true,65,2,true,rowPrefetch=true,bDelay=24,reuse=Some(d)).prefetchedRows shouldBe 0
      run(true,3,2,true,rowPrefetch=true,bDelay=24,inPlace=true,reuse=Some(d)).prefetchedRows shouldBe 0
    }
  }
  it("row-distinct cached prefetch preserves odd tails in both halfword phases") {
    // Width13 shifts the literal six-color pattern each row; reusing a cached row must fail.
    simulate(new RenderEngine(enableAlphaPipeline=true,enableAlphaRowPrefetch=true)) { d =>
      for(phase<-Seq(0,2))run(true,13,phase,true,cached=true,rowPrefetch=true,height=4,
        bDelay=24,sourceStride=32,destinationStride=1920,recoverAlpha=true,reuse=Some(d))
    }
  }
  it("packed odd rows share edge words without prefetching stale neighboring pixels") {
    simulate(new RenderEngine(enableAlphaPipeline=true,enableAlphaRowPrefetch=true)) { d =>
      for(phase<-Seq(0,2))run(true,13,phase,true,cached=true,rowPrefetch=true,height=4,
        bDelay=24,sourceStride=26,destinationStride=26,recoverAlpha=true,reuse=Some(d))
    }
  }
  it("early prefetch preserves small phased rows, fallback paths and fault recovery under stalls") {
    simulate(new RenderEngine(enableAlphaPipeline=true,enableAlphaRowPrefetch=true,enableAlphaEarlyPrefetch=true)) { d =>
      for(cached<-Seq(false,true);w<-Seq(1,3,12,13,16);phase<-Seq(0,2))
        run(true,w,phase,true,cached=cached,rowPrefetch=true,height=4,bDelay=5,
          destinationStride=1920,earlyPrefetch=true,rDelay=6,reuse=Some(d))
      for(phase<-Seq(0,2))run(true,13,phase,true,cached=true,rowPrefetch=true,height=4,
        sourceStride=26,destinationStride=26,earlyPrefetch=true,reuse=Some(d))
      for(cached<-Seq(false,true))run(true,3,4094,true,cached=cached,rowPrefetch=true,
        earlyPrefetch=true,recoverAlpha=true,reuse=Some(d))
      for(w<-Seq(17,65))run(true,w,2,true,rowPrefetch=true,earlyPrefetch=true,reuse=Some(d)).earlyRows shouldBe 0
      run(true,3,2,true,rowPrefetch=true,inPlace=true,earlyPrefetch=true,reuse=Some(d)).earlyRows shouldBe 0
      run(true,12,2,true,rowPrefetch=true,height=1,earlyPrefetch=true,reuse=Some(d)).earlyRows shouldBe 0
      for(fault<-Seq(1,2,3,4,5))run(true,3,2,true,fault,cached=true,rowPrefetch=true,
        bDelay=24,recoverAlpha=true,earlyPrefetch=true,rDelay=6,reuse=Some(d))
      run(true,3,2,true,6,rowPrefetch=true,bDelay=24,recoverAlpha=true,
        earlyPrefetch=true,rDelay=6,reuse=Some(d))
    }
  }
  it("early prefetch retains failed row2 ownership behind a delayed prior B") {
    run(true,13,2,false,7,cached=true,rowPrefetch=true,height=4,bDelay=80,
      sourceStride=32,destinationStride=1920,recoverAlpha=true,earlyPrefetch=true)
  }
}
