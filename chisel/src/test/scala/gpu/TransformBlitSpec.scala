package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class TransformBlitSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private class Bus(dut: TransformBlitEngine) {
    val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0x5a)
    val reads = collection.mutable.ArrayBuffer.empty[Long]
    val writes = collection.mutable.ArrayBuffer.empty[(Long, Int)]
    var pixels = 0
    var completions = Vector.empty[(Int, Int)]
    var readResp = 0
    var faultRead = 0
    var readId = 0
    var readLast = true
    var writeResp = 0
    var writeId = 0
    private val random = new scala.util.Random(0x7124)
    private var rPending = Option.empty[Long]
    private var bPending = false
    private var delayR = 0
    private var delayB = 0
    private var writeAddress = 0L
    private var cycle = 0
    private var stalledAr = Option.empty[Seq[BigInt]]
    private var stalledAw = Option.empty[Seq[BigInt]]
    private var stalledW = Option.empty[(BigInt, BigInt, Boolean)]

    dut.io.command.valid.poke(false)
    dut.io.completion.ready.poke(false)

    def half(address: Long): Int = memory(address) | (memory(address + 1) << 8)
    def put(address: Long, pixel: Int): Unit = {
      memory(address) = pixel & 255
      memory(address + 1) = pixel >> 8
    }
    def tick(): Unit = {
      val arReady = random.nextBoolean()
      val awReady = random.nextBoolean()
      val wReady = random.nextBoolean()
      dut.io.axi.ar.ready.poke(arReady)
      dut.io.axi.aw.ready.poke(awReady)
      dut.io.axi.w.ready.poke(wReady)
      val rValid = rPending.nonEmpty && delayR == 0
      dut.io.axi.r.valid.poke(rValid)
      dut.io.axi.r.bits.id.poke(readId)
      dut.io.axi.r.bits.resp.poke(if (faultRead == 0 || reads.size == faultRead) readResp else 0)
      dut.io.axi.r.bits.last.poke(readLast)
      val readWord = rPending.map(a => (0 until 4).foldLeft(0L)((word, i) =>
        word | (memory(a + i).toLong << (8 * i)))).getOrElse(0L)
      dut.io.axi.r.bits.data.poke(readWord)
      val bValid = bPending && delayB == 0
      dut.io.axi.b.valid.poke(bValid)
      dut.io.axi.b.bits.id.poke(writeId)
      dut.io.axi.b.bits.resp.poke(writeResp)

      val arValid = dut.io.axi.ar.valid.peek().litToBoolean
      val awValid = dut.io.axi.aw.valid.peek().litToBoolean
      val wValid = dut.io.axi.w.valid.peek().litToBoolean
      def addressBits(a: Axi4Address): Seq[BigInt] = Seq(a.addr, a.id, a.len, a.size,
        a.burst, a.cache, a.prot, a.qos, a.region).map(_.peek().litValue) :+ a.lock.peek().litValue
      val ar = addressBits(dut.io.axi.ar.bits)
      val aw = addressBits(dut.io.axi.aw.bits)
      val w = (dut.io.axi.w.bits.data.peek().litValue,
        dut.io.axi.w.bits.strb.peek().litValue, dut.io.axi.w.bits.last.peek().litToBoolean)
      stalledAr.foreach { previous => arValid shouldBe true; ar shouldBe previous }
      stalledAw.foreach { previous => awValid shouldBe true; aw shouldBe previous }
      stalledW.foreach { previous => wValid shouldBe true; w shouldBe previous }
      stalledAr = if (arValid && !arReady) Some(ar) else None
      stalledAw = if (awValid && !awReady) Some(aw) else None
      stalledW = if (wValid && !wReady) Some(w) else None

      val arFire = arValid && arReady
      val awFire = awValid && awReady
      val wFire = wValid && wReady
      val rFire = rValid && dut.io.axi.r.ready.peek().litToBoolean
      val bFire = bValid && dut.io.axi.b.ready.peek().litToBoolean
      if (arFire) {
        rPending shouldBe None
        dut.io.axi.ar.bits.len.expect(0)
        dut.io.axi.ar.bits.id.expect(0)
        dut.io.axi.ar.bits.size.expect(2)
        dut.io.axi.ar.bits.burst.expect(1)
        reads += dut.io.axi.ar.bits.addr.peek().litValue.toLong
      }
      if (awFire) {
        bPending shouldBe false
        dut.io.axi.aw.bits.len.expect(0)
        dut.io.axi.aw.bits.size.expect(2)
        dut.io.axi.aw.bits.burst.expect(1)
        writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.toLong
      }
      if (wFire) {
        w._3 shouldBe true
        writes += ((writeAddress, w._2.toInt))
        for (i <- 0 until 4 if w._2.testBit(i)) memory(writeAddress + i) = ((w._1 >> (i * 8)) & 255).toInt
      }
      if (dut.io.pixelDone.peek().litToBoolean) pixels += 1
      if (dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean) {
        rPending shouldBe None
        bPending shouldBe false
        completions :+= ((dut.io.completion.bits.tag.peek().litValue.toInt,
          dut.io.completion.bits.error.peek().litValue.toInt))
      }
      dut.clock.step()
      if (rFire) rPending = None
      if (bFire) bPending = false
      if (delayR > 0) delayR -= 1
      if (delayB > 0) delayB -= 1
      if (arFire) { rPending = Some(reads.last); delayR = 1 + cycle % 4 }
      if (wFire) { bPending = true; delayB = 1 + cycle % 5 }
      cycle += 1
    }

    def run(width: Int, height: Int, flags: Int, tag: Int, source: Seq[Seq[Int]],
            expectedError: Int = 0): Unit = {
      reads.clear()
      writes.clear()
      pixels = 0
      memory.clear()
      val src = GpuMemoryMap.DenseAssets.toLong + 2
      val dst = GpuMemoryMap.FramebufferA.toLong + 2
      val srcStride = source.head.size * 2 + 2
      val dstStride = width * 2 + 2
      for ((row, y) <- source.zipWithIndex; (pixel, x) <- row.zipWithIndex)
        put(src + y * srcStride + x * 2, pixel)
      val c = dut.io.command.bits
      c.op.poke(GpuOpcode.Transform)
      c.srcAddr.poke(src)
      c.dstAddr.poke(dst)
      c.widthPixels.poke(width)
      c.heightPixels.poke(height)
      c.srcWidthPixels.poke(source.head.size)
      c.srcHeightPixels.poke(source.size)
      c.srcStride.poke(srcStride)
      c.dstStride.poke(dstStride)
      c.flags.poke(flags)
      c.color.poke(0)
      c.colorKey.poke(0xabcd)
      c.alpha.poke(255)
      c.tag.poke(tag)
      dut.io.command.ready.expect(true)
      dut.io.command.valid.poke(true)
      tick()
      dut.io.command.valid.poke(false)
      dut.io.command.ready.expect(false)
      var count = 0
      while (!dut.io.completion.valid.peek().litToBoolean && count < 4000) { tick(); count += 1 }
      withClue(s"tag $tag did not retire: ") { count should be < 4000 }
      dut.io.completion.bits.tag.expect(tag)
      dut.io.completion.bits.error.expect(expectedError)
      // A waiting next command must not replace a stalled completion.
      c.tag.poke(tag + 100)
      dut.io.command.valid.poke(true)
      for (_ <- 0 until 4) {
        dut.io.command.ready.expect(false)
        dut.io.completion.valid.expect(true)
        dut.io.completion.bits.tag.expect(tag)
        dut.io.completion.bits.error.expect(expectedError)
        dut.io.axi.ar.valid.expect(false)
        dut.io.axi.aw.valid.expect(false)
        dut.io.axi.w.valid.expect(false)
        tick()
      }
      dut.io.completion.ready.poke(true)
      tick()
      dut.io.command.valid.poke(false)
      dut.io.completion.ready.poke(false)
      dut.io.completion.valid.expect(false)
      dut.io.command.ready.expect(true)
      for (_ <- 0 until 3) tick()
      completions.last shouldBe ((tag, expectedError))
    }

    def expectPixels(width: Int, expected: Seq[Int]): Unit = {
      val dst = GpuMemoryMap.FramebufferA.toLong + 2
      val stride = width * 2 + 2
      expected.zipWithIndex.foreach { case (pixel, i) => half(dst + (i / width) * stride + (i % width) * 2) shouldBe pixel }
      pixels shouldBe expected.size
      // Guard bytes before/after every row must survive half-word writes.
      for (row <- 0 until expected.size / width) {
        half(dst + row * stride - 2) shouldBe 0x5a5a
        half(dst + row * stride + width * 2) shouldBe 0x5a5a
      }
      val destinations = expected.indices.filter(i => expected(i) != 0x5a5a).map(i =>
        dst + (i / width) * stride + (i % width) * 2)
      writes.toSeq shouldBe destinations.map(a => (a & ~3L, if ((a & 2) != 0) 12 else 3))
    }
  }

  it("maps asymmetric pixels after scaling, preserves Key holes and half words under backpressure") {
    simulate(new TransformBlitEngine) { dut =>
      val bus = new Bus(dut)
      bus.tick()
      val source = Seq(Seq(0x1234, 0xabcd), Seq(0x5678, 0x9abc))
      bus.run(2, 2, 0, 1, source)
      bus.expectPixels(2, Seq(0x1234, 0xabcd, 0x5678, 0x9abc))
      bus.run(2, 2, GpuTransformFlags.HFlip, 2, source)
      bus.expectPixels(2, Seq(0xabcd, 0x1234, 0x9abc, 0x5678))
      bus.run(2, 2, GpuTransformFlags.VFlip, 3, source)
      bus.expectPixels(2, Seq(0x5678, 0x9abc, 0x1234, 0xabcd))
      bus.run(2, 2, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 4, source)
      bus.expectPixels(2, Seq(0x9abc, 0x5678, 0xabcd, 0x1234))
      bus.run(4, 4, 0, 5, source)
      bus.expectPixels(4, Seq(0x1234, 0x1234, 0xabcd, 0xabcd, 0x1234, 0x1234, 0xabcd, 0xabcd,
        0x5678, 0x5678, 0x9abc, 0x9abc, 0x5678, 0x5678, 0x9abc, 0x9abc))
      bus.run(2, 2, GpuTransformFlags.ColorKey, 6, source)
      bus.expectPixels(2, Seq(0x1234, 0x5a5a, 0x5678, 0x9abc))
      bus.run(2, 2, GpuTransformFlags.ColorKey, 7, Seq.fill(2)(Seq.fill(2)(0xabcd)))
      bus.expectPixels(2, Seq.fill(4)(0x5a5a))
      bus.writes shouldBe empty
      val large = Seq(Seq(1, 2, 3, 4), Seq(5, 6, 7, 8), Seq(9, 10, 11, 12), Seq(13, 14, 15, 16))
      bus.run(2, 2, 0, 8, large)
      bus.expectPixels(2, Seq(1, 3, 9, 11))
      bus.run(2, 2, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 9, large)
      bus.expectPixels(2, Seq(16, 14, 8, 6))
      bus.run(3, 2, GpuTransformFlags.HFlip, 10, Seq(Seq(1, 2, 3), Seq(4, 5, 6)))
      bus.expectPixels(3, Seq(3, 2, 1, 6, 5, 4))
      bus.run(1, 1, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 11, Seq(Seq(0x4321)))
      bus.expectPixels(1, Seq(0x4321))
      val asymmetric = Seq(Seq(0x1234, 0xabcd, 0x5678), Seq(0x9abc, 0x1357, 0x2468))
      bus.run(5, 3, 0, 12, asymmetric)
      bus.expectPixels(5, Seq(0x1234, 0x1234, 0xabcd, 0xabcd, 0x5678,
        0x1234, 0x1234, 0xabcd, 0xabcd, 0x5678, 0x9abc, 0x9abc, 0x1357, 0x1357, 0x2468))
      bus.run(5, 3, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 13, asymmetric)
      bus.expectPixels(5, Seq(0x2468, 0x2468, 0x1357, 0x1357, 0x9abc,
        0x2468, 0x2468, 0x1357, 0x1357, 0x9abc, 0x5678, 0x5678, 0xabcd, 0xabcd, 0x1234))
      val shrink = Seq(Seq(1, 2, 3, 4), Seq(5, 6, 7, 8), Seq(9, 10, 11, 12))
      bus.run(3, 2, 0, 14, shrink)
      bus.expectPixels(3, Seq(1, 2, 3, 5, 6, 7))
      bus.run(3, 2, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 15, shrink)
      bus.expectPixels(3, Seq(12, 11, 10, 8, 7, 6))
      val wide = Seq(Seq(1, 2, 3, 4, 5, 6, 7), Seq(8, 9, 10, 11, 12, 13, 14),
        Seq(15, 16, 17, 18, 19, 20, 21), Seq(22, 23, 24, 25, 26, 27, 28),
        Seq(29, 30, 31, 32, 33, 34, 35))
      bus.run(3, 2, 0, 16, wide)
      bus.expectPixels(3, Seq(1, 3, 5, 15, 17, 19))
      bus.run(3, 2, GpuTransformFlags.HFlip | GpuTransformFlags.VFlip, 17, wide)
      bus.expectPixels(3, Seq(35, 33, 31, 21, 19, 17))
      bus.completions.map(_._1) shouldBe (1 to 17).toVector
    }
  }

  it("retires once after R or B faults and accepts the following command only after retirement") {
    simulate(new TransformBlitEngine) { dut =>
      val bus = new Bus(dut)
      bus.tick()
      val source = Seq(Seq(0x1234, 0xabcd), Seq(0x5678, 0x9abc))
      for ((resp, id, last, tag) <- Seq((2, 0, true, 20), (0, 1, true, 21), (0, 0, false, 22))) {
        bus.readResp = resp; bus.readId = id; bus.readLast = last
        bus.run(2, 2, 0, tag, source, GpuError.AxiResponse)
        bus.reads.size shouldBe 1
        bus.writes shouldBe empty
        bus.pixels shouldBe 0
      }
      bus.readResp = 0; bus.readId = 0; bus.readLast = true
      for ((resp, id, tag) <- Seq((2, 0, 23), (0, 1, 24))) {
        bus.writeResp = resp; bus.writeId = id
        bus.run(2, 2, 0, tag, source, GpuError.AxiResponse)
        bus.reads.size shouldBe 1
        bus.writes.size shouldBe 1
        bus.pixels shouldBe 0
      }
      bus.writeResp = 0; bus.writeId = 0
      bus.run(2, 2, 0, 25, source)
      bus.expectPixels(2, Seq(0x1234, 0xabcd, 0x5678, 0x9abc))
      bus.completions.map(_._1) shouldBe (20 to 25).toVector
    }
  }

  it("preserves the carry of X and Y DDA residuals at the 65535 source-size boundary") {
    simulate(new TransformBlitEngine) { dut =>
      val bus = new Bus(dut)
      bus.tick()
      // Stop after three successful pixels; a fourth R error bounds simulation
      // while checking the 17-bit sum 32767+65535, whose next coordinate is 3.
      bus.readResp = 2
      bus.faultRead = 4
      val source = Seq(1, 2, 3, 4, 5) ++ Seq.fill(65530)(0x7ffe)
      bus.run(32768, 1, 0, 30, Seq(source), GpuError.AxiResponse)
      val dst = GpuMemoryMap.FramebufferA.toLong + 2
      bus.reads.size shouldBe 4
      bus.writes.size shouldBe 3
      bus.pixels shouldBe 3
      Seq(bus.half(dst), bus.half(dst + 2), bus.half(dst + 4), bus.half(dst + 6)) shouldBe
        Seq(1, 2, 4, 0x5a5a)
      bus.run(1, 32768, 0, 31, source.map(pixel => Seq(pixel)), GpuError.AxiResponse)
      bus.reads.size shouldBe 4
      bus.writes.size shouldBe 3
      bus.pixels shouldBe 3
      Seq(bus.half(dst), bus.half(dst + 4), bus.half(dst + 8), bus.half(dst + 12)) shouldBe
        Seq(1, 2, 4, 0x5a5a)
      bus.completions.map(_._1) shouldBe Vector(30, 31)
    }
  }
}
