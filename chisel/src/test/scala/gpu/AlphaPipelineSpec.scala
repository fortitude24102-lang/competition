package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Real pixel RTL + AXI byte memory: catches skewed metadata, early completion,
  * lost halfwords/chunk tails and accidental writes beyond the rectangle. */
class AlphaPipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private case class Trace(cycles: Int, reads: Vector[(Int, Long, Int)],
    writes: Vector[(Long, Int)], data: Vector[(BigInt, BigInt, Boolean)])
  private def run(enabled: Boolean, width: Int, phase: Int, stalls: Boolean,
                  fault: Int = 0, cached: Boolean = false): Trace = {
    var elapsed = 0
    var result = Option.empty[Trace]
    simulate(new RenderEngine(enableAlphaPipeline = enabled)) { d =>
      val mem = collection.mutable.Map.empty[Long, Int].withDefaultValue(0x5a)
      val src = GpuMemoryMap.DenseAssets.toLong + phase
      val dst = GpuMemoryMap.FramebufferA.toLong + phase
      val stride = width * 2 + 6
      val height = 2
      val fg = Seq(0xf800, 0x07e0, 0x001f, 0xffff, 0, 0x1234)
      val bg = Seq(0x001f, 0xf800, 0x07e0, 0, 0xffff, 0xabcd)
      // Literal independently hand-checked per-channel alpha=128 / 255 rounded.
      val expected = Seq(0x800f, 0x7c00, 0x03f0, 0x8410, 0x7bef, 0x5af1)
      def put(a: Long, p: Int): Unit = { mem(a) = p & 255; mem(a + 1) = p >> 8 }
      def half(a: Long): Int = mem(a) | mem(a + 1) << 8
      def word(a: Long): Long = (0 until 4).foldLeft(0L)((v, b) => v | mem(a+b).toLong << (8*b))
      for (y <- 0 until height; x <- 0 until width) {
        val i = (y * width + x) % fg.size
        put(src + y*stride + x*2, fg(i)); put(dst + y*stride + x*2, bg(i))
      }
      case class Read(id: Int, var addr: Long, var beats: Int)
      val reads = collection.mutable.Queue.empty[Read]
      val arTrace = collection.mutable.ArrayBuffer.empty[(Int, Long, Int)]
      val awTrace = collection.mutable.ArrayBuffer.empty[(Long, Int)]
      val wTrace = collection.mutable.ArrayBuffer.empty[(BigInt, BigInt, Boolean)]
      var submitted = 0
      var retired = 0
      var writeAddr = 0L
      var writeLeft = 0
      var bPending = false
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
      while (retired < 2 && elapsed < 2000) {
        // Alpha followed by Fill catches stale metadata/error propagation.
        val c = d.io.command.bits
        d.io.textureCacheLoad.valid.poke(cached && !loadSent)
        d.io.textureCacheLoad.bits.base.poke(src & ~3L)
        d.io.textureCacheLoad.bits.bytes.poke(((height*stride+phase+3)/4)*4)
        d.io.command.valid.poke(submitted < 2 && (!cached || d.io.textureCacheValid.peek().litToBoolean))
        c.poke(0.U.asTypeOf(new GpuCommand))
        c.op.poke(if(submitted == 0) GpuOpcode.Alpha else GpuOpcode.Fill)
        c.srcAddr.poke(src); c.dstAddr.poke(if(submitted == 0) dst else dst + 0x1000)
        c.srcStride.poke(stride); c.dstStride.poke(stride)
        c.widthPixels.poke(if(submitted == 0) width else 1)
        c.heightPixels.poke(if(submitted == 0) height else 1)
        c.alpha.poke(128); c.color.poke(0x1357); c.tag.poke(submitted + 1)
        d.io.completion.ready.poke(ready)
        d.io.axi.ar.ready.poke(ready) // Independent of AW/W: do not hide early reads.
        d.io.axi.aw.ready.poke(ready && writeLeft == 0 && !bPending)
        d.io.axi.w.ready.poke(ready)
        val offerR = reads.nonEmpty && ready
        d.io.axi.r.valid.poke(offerR)
        d.io.axi.r.bits.id.poke(reads.headOption.map(_.id).getOrElse(0))
        d.io.axi.r.bits.data.poke(reads.headOption.map(r=>word(r.addr)).getOrElse(0L))
        d.io.axi.r.bits.last.poke(reads.headOption.exists(_.beats == 1))
        val badR = fault == 1 && !readFaultSent && reads.headOption.exists(_.id == 1)
        d.io.axi.r.bits.resp.poke(if(badR) 2 else 0)
        d.io.axi.b.valid.poke(bPending && ready)
        d.io.axi.b.bits.id.poke(0)
        d.io.axi.b.bits.resp.poke(if(fault == 2 && bCount == 0) 2 else 0)
        def fires(p: chisel3.util.DecoupledIO[_]): Boolean = p.valid.peek().litToBoolean && p.ready.peek().litToBoolean
        val cf = fires(d.io.command); val done = fires(d.io.completion)
        val ar = fires(d.io.axi.ar); val rr = fires(d.io.axi.r)
        val aw = fires(d.io.axi.aw); val ww = fires(d.io.axi.w); val bb = fires(d.io.axi.b)
        val w = (d.io.axi.w.bits.data.peek().litValue, d.io.axi.w.bits.strb.peek().litValue,
          d.io.axi.w.bits.last.peek().litToBoolean)
        heldW.foreach { previous => d.io.axi.w.valid.expect(true); w shouldBe previous }
        heldW = if(d.io.axi.w.valid.peek().litToBoolean && !d.io.axi.w.ready.peek().litToBoolean) Some(w) else None
        val nextRead = if(ar) Some(Read(d.io.axi.ar.bits.id.peek().litValue.toInt,
          d.io.axi.ar.bits.addr.peek().litValue.toLong, d.io.axi.ar.bits.len.peek().litValue.toInt + 1)) else None
        val nextWrite = if(aw) Some((d.io.axi.aw.bits.addr.peek().litValue.toLong,
          d.io.axi.aw.bits.len.peek().litValue.toInt + 1)) else None
        if(width > 64 && d.io.axi.ar.valid.peek().litToBoolean) {
          val address = d.io.axi.ar.bits.addr.peek().litValue.toLong
          for(y <- 0 until height; base <- Seq(src,dst)
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
        if(ww) { wCount+=1; writeAddr+=4; writeLeft-=1; if(writeLeft==0) bPending=true }
        nextWrite.foreach { case(a,n) => awCount+=1; writeAddr=a; writeLeft=n }
      }
      withClue(s"pipeline=$enabled width=$width phase=$phase fault=$fault cached=$cached reads=${reads.size} writeLeft=$writeLeft bPending=$bPending elapsed=$elapsed: ") {
        retired shouldBe 2
      }
      if(fault == 0) for(y <- 0 until height; x <- 0 until width)
        half(dst+y*stride+x*2) shouldBe expected((y*width+x)%expected.size)
      for(y <- 0 until height) {
        half(dst+y*stride-2) shouldBe 0x5a5a
        for(x <- 0 until 3) half(dst+y*stride+width*2+x*2) shouldBe 0x5a5a
      }
      half(dst+0x1000) shouldBe 0x1357
      d.io.perfPixels.expect((if(fault == 0) width*height else width) + 1)
      if(cached) d.io.perfCacheBytes.expect(68) // 16x2, stride38, source+2: 36+32.
      if(width == 16 && phase == 0 && fault == 0 && !cached) {
        // Identical work and bus traffic for both sides of the cycle comparison.
        d.io.perfReadBytes.expect(136); d.io.perfWriteBytes.expect(66)
        awCount shouldBe 3; wCount shouldBe 18; bCount shouldBe 3
      }
      result = Some(Trace(elapsed, arTrace.toVector, awTrace.toVector, wTrace.toVector))
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
    for(w <- Seq(1,3,65); phase <- Seq(0,2)) run(true,w,phase,true)
    run(true,16,2,true,cached=true)
  }
  it("matches stalled cross-chunk AXI traces without reading ahead of the prior pixel tail") {
    val old = run(false,65,2,true)
    val candidate = run(true,65,2,true)
    candidate.reads.groupBy(_._1) shouldBe old.reads.groupBy(_._1)
    candidate.writes shouldBe old.writes
    candidate.data shouldBe old.data
  }
  it("drains read/write failures and retires the following Fill without stale metadata") {
    for(enabled <- Seq(false,true); fault <- Seq(1,2)) run(enabled,3,2,true,fault)
  }
}
